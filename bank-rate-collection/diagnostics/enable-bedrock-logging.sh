#!/usr/bin/env bash
# =============================================================================
# Enable Bedrock Model Invocation Logging
# =============================================================================
# Purpose: Bedrock model invocation logging is OFF by default. Without it we
# can't see input/output tokens, cache hits, or latency per invocation — which
# is exactly the data we need to confirm the latency hypothesis.
#
# This script does the following (idempotent — safe to re-run):
#   1. Creates a CloudWatch log group:  /aws/bedrock/modelinvocations
#   2. Creates an IAM role Bedrock can assume to write to that log group
#   3. Turns on model invocation logging at the account+region level
#      with prompt+completion data enabled (we need the .usage block)
#   4. Verifies and prints the resulting configuration
#
# After running this:
#   → Place ONE test call through the hotel solution (any short call is fine,
#     even just 30 seconds — we just need a few Bedrock invocations to land
#     in the log group).
#   → Then run hotel-latency-diagnose-v2.sh to capture the real data.
#
# Output: enable-bedrock-logging-<timestamp>.txt
#
# Usage:
#   chmod +x enable-bedrock-logging.sh
#   ./enable-bedrock-logging.sh
#
# Optional env overrides:
#   AWS_REGION         (default: us-east-1)
#   LOG_GROUP_NAME     (default: /aws/bedrock/modelinvocations)
#   LOG_RETENTION_DAYS (default: 14)
#   ROLE_NAME          (default: BedrockModelInvocationLoggingRole)
#
# IMPORTANT — PII / data sensitivity:
#   This enables text data delivery, so the Ryan AI prompt + banker
#   conversations WILL be written to CloudWatch. Required for token analysis
#   but be aware of the data residency implications. To turn this off later:
#     aws bedrock delete-model-invocation-logging-configuration --region <r>
# =============================================================================

set -u

# ─── Config ──────────────────────────────────────────────────────────────────
AWS_REGION="${AWS_REGION:-us-east-1}"
LOG_GROUP_NAME="${LOG_GROUP_NAME:-/aws/bedrock/modelinvocations}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-14}"
ROLE_NAME="${ROLE_NAME:-BedrockModelInvocationLoggingRole}"

TS=$(date -u +%Y%m%dT%H%M%SZ)
OUT_FILE="enable-bedrock-logging-${TS}.txt"

exec > >(tee -a "$OUT_FILE") 2>&1

section() {
  echo
  echo "================================================================================"
  echo "  $1"
  echo "================================================================================"
}
run() {
  echo
  echo "--- CMD: $* ---"
  "$@" 2>&1 || echo "(command exited $?)"
}

section "ENABLE BEDROCK LOGGING — $TS"
echo "Region:            $AWS_REGION"
echo "Log group:         $LOG_GROUP_NAME"
echo "Log retention:     ${LOG_RETENTION_DAYS} days"
echo "IAM role name:     $ROLE_NAME"
echo
echo "AWS identity:"
run aws sts get-caller-identity --region "$AWS_REGION"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
if [[ -z "$ACCOUNT_ID" || "$ACCOUNT_ID" == "None" ]]; then
  echo "ERROR: could not resolve AWS account ID. Check credentials." ; exit 1
fi
echo "Account ID:        $ACCOUNT_ID"

# ─── 0. Check current Bedrock logging configuration ──────────────────────────
section "0. CURRENT BEDROCK LOGGING CONFIG (before changes)"
run aws bedrock get-model-invocation-logging-configuration --region "$AWS_REGION" --output json

# ─── 1. Create CloudWatch log group ──────────────────────────────────────────
section "1. CREATE CLOUDWATCH LOG GROUP"
echo "If the group already exists, this will error harmlessly (we ignore)."
run aws logs create-log-group \
    --log-group-name "$LOG_GROUP_NAME" \
    --region "$AWS_REGION"

run aws logs put-retention-policy \
    --log-group-name "$LOG_GROUP_NAME" \
    --retention-in-days "$LOG_RETENTION_DAYS" \
    --region "$AWS_REGION"

echo
echo "--- Verify log group exists ---"
run aws logs describe-log-groups \
    --log-group-name-prefix "$LOG_GROUP_NAME" \
    --region "$AWS_REGION" \
    --output json

# ─── 2. Create IAM role Bedrock will assume to write logs ────────────────────
section "2. CREATE / VERIFY IAM ROLE"

TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "bedrock.amazonaws.com" },
    "Action": "sts:AssumeRole",
    "Condition": {
      "StringEquals": { "aws:SourceAccount": "$ACCOUNT_ID" },
      "ArnLike":      { "aws:SourceArn":     "arn:aws:bedrock:$AWS_REGION:$ACCOUNT_ID:*" }
    }
  }]
}
EOF
)

PERMISSION_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ],
    "Resource": [
      "arn:aws:logs:$AWS_REGION:$ACCOUNT_ID:log-group:$LOG_GROUP_NAME",
      "arn:aws:logs:$AWS_REGION:$ACCOUNT_ID:log-group:$LOG_GROUP_NAME:*"
    ]
  }]
}
EOF
)

echo "--- Check if role exists ---"
ROLE_EXISTS=$(aws iam get-role --role-name "$ROLE_NAME" --region "$AWS_REGION" --query 'Role.RoleName' --output text 2>/dev/null || echo "")

if [[ -z "$ROLE_EXISTS" ]]; then
  echo "--- Creating role $ROLE_NAME ---"
  run aws iam create-role \
      --role-name "$ROLE_NAME" \
      --assume-role-policy-document "$TRUST_POLICY" \
      --description "Allows Bedrock to write model invocation logs to CloudWatch" \
      --tags Key=Environment,Value=NonProd Key=Purpose,Value=BedrockLogging \
             Key=CreatedBy,Value=Abhay.Lunkad Key=AppID,Value=ASP0017650
else
  echo "--- Role $ROLE_NAME already exists, updating trust policy ---"
  run aws iam update-assume-role-policy \
      --role-name "$ROLE_NAME" \
      --policy-document "$TRUST_POLICY"
fi

echo
echo "--- Attach inline permission policy ---"
run aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name BedrockLoggingPolicy \
    --policy-document "$PERMISSION_POLICY"

# Wait briefly for IAM eventual consistency
echo
echo "Waiting 10s for IAM eventual consistency before attaching role to Bedrock..."
sleep 10

ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME"
echo "ROLE_ARN = $ROLE_ARN"

# ─── 3. Enable Bedrock model invocation logging ──────────────────────────────
section "3. ENABLE BEDROCK MODEL INVOCATION LOGGING"
echo "Turning ON with prompt + completion text capture (needed for usage data)."

LOGGING_CONFIG=$(cat <<EOF
{
  "cloudWatchConfig": {
    "logGroupName": "$LOG_GROUP_NAME",
    "roleArn": "$ROLE_ARN"
  },
  "textDataDeliveryEnabled":      true,
  "imageDataDeliveryEnabled":     false,
  "embeddingDataDeliveryEnabled": false,
  "videoDataDeliveryEnabled":     false
}
EOF
)

run aws bedrock put-model-invocation-logging-configuration \
    --logging-config "$LOGGING_CONFIG" \
    --region "$AWS_REGION"

# ─── 4. Verify ───────────────────────────────────────────────────────────────
section "4. VERIFY CONFIGURATION (after changes)"
run aws bedrock get-model-invocation-logging-configuration --region "$AWS_REGION" --output json

# ─── Done ────────────────────────────────────────────────────────────────────
section "DONE — NEXT STEPS"
cat <<EOF

Bedrock logging is now enabled. To capture real latency data:

  1. Place ONE short test call to the hotel solution.
     - Just say a couple things to trigger 4-6 Bedrock invocations.
     - Doesn't need to be a full call; 30 seconds is enough.

  2. Wait 60 seconds for logs to flush to CloudWatch.

  3. Run the new diagnostic:
        ./hotel-latency-diagnose-v2.sh
     This uses the LIVE assistant ID (auto-discovered from Connect integration
     associations, so it won't fail like the previous run) and pulls the real
     Bedrock token + latency data.

  4. Share both output files back:
        - $OUT_FILE
        - hotel-latency-diagnose-v2-<timestamp>.txt

Then I'll tell you exactly which fixes apply to your bank solution and what
the expected real-world latency improvement is.

To turn logging back OFF later:
  aws bedrock delete-model-invocation-logging-configuration --region $AWS_REGION

EOF
echo "Output file: $OUT_FILE"
