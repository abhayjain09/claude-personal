#!/usr/bin/env bash
# =============================================================================
# Hotel Q Connect AI Agent — Latency Diagnostic v2 (READ-ONLY)
# =============================================================================
# What's different from v1:
#   - Auto-discovers the LIVE assistant + KB IDs from Connect integration
#     associations (v1 had stale hardcoded IDs from aws-resources.json that
#     no longer exist).
#   - Pulls real Bedrock model invocation telemetry (requires enable-bedrock-
#     logging.sh to have been run first AND at least one test call placed).
#   - Computes token growth over the most recent calls (input, cache_read,
#     cache_create) — this directly confirms / refutes the caching hypothesis.
#   - Per-Lambda Duration p50/p95/p99 (only Lambdas with actual data).
#   - Captures the full deployed prompt text so we can measure its real
#     token size.
#
# Prerequisite:
#   - enable-bedrock-logging.sh has been run
#   - At least one test call has been placed in the last 24h
#
# Usage:
#   chmod +x hotel-latency-diagnose-v2.sh
#   ./hotel-latency-diagnose-v2.sh
#
# Optional env overrides:
#   AWS_REGION             (default: us-east-1)
#   CONNECT_INSTANCE_ID    (default: 6f93dfc3-9503-4b86-971b-f608ec484e78)
#   ASSISTANT_ID           (default: auto-discover from Connect integrations)
#   AI_AGENT_NAME          (default: auto-discover by name prefix)
#   AI_PROMPT_NAME         (default: auto-discover by name prefix)
#   BEDROCK_LOG_GROUP      (default: /aws/bedrock/modelinvocations)
#   HOURS_BACK             (default: 24)
# =============================================================================

set -u

AWS_REGION="${AWS_REGION:-us-east-1}"
CONNECT_INSTANCE_ID="${CONNECT_INSTANCE_ID:-6f93dfc3-9503-4b86-971b-f608ec484e78}"
BEDROCK_LOG_GROUP="${BEDROCK_LOG_GROUP:-/aws/bedrock/modelinvocations}"
HOURS_BACK="${HOURS_BACK:-24}"

# Cross-platform date for "N hours ago"
if date -v-1H +%s >/dev/null 2>&1; then
  START_TIME_ISO=$(date -u -v-${HOURS_BACK}H +%Y-%m-%dT%H:%M:%SZ)
else
  START_TIME_ISO=$(date -u -d "${HOURS_BACK} hours ago" +%Y-%m-%dT%H:%M:%SZ)
fi
START_MS=$(( ( $(date +%s) - HOURS_BACK*3600 ) * 1000 ))

TS=$(date -u +%Y%m%dT%H%M%SZ)
OUT_FILE="hotel-latency-diagnose-v2-${TS}.txt"

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

# ─── Header ──────────────────────────────────────────────────────────────────
section "DIAGNOSTIC v2 — $TS"
echo "Region:               $AWS_REGION"
echo "ConnectInstanceId:    $CONNECT_INSTANCE_ID"
echo "Bedrock log group:    $BEDROCK_LOG_GROUP"
echo "Looking back:         ${HOURS_BACK}h (since $START_TIME_ISO)"
run aws sts get-caller-identity --region "$AWS_REGION"

# ─── 1. AUTO-DISCOVER live IDs from Connect integration associations ─────────
section "1. AUTO-DISCOVER LIVE ASSISTANT / KB IDs"
echo "Reading integration associations from Connect — these are the only "
echo "guaranteed-current pointers to the live Wisdom assistant and KB."

INTEGRATIONS_JSON=$(aws connect list-integration-associations \
    --instance-id "$CONNECT_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --output json 2>&1)
echo "$INTEGRATIONS_JSON"

ASSISTANT_ARN=$(echo "$INTEGRATIONS_JSON" | grep -A1 '"IntegrationType": "WISDOM_ASSISTANT"' | grep IntegrationArn | sed 's/.*"\(arn:aws:wisdom:[^"]*\)".*/\1/' | head -1)
KB_ARN=$(echo "$INTEGRATIONS_JSON" | grep -A1 '"IntegrationType": "WISDOM_KNOWLEDGE_BASE"' | grep IntegrationArn | sed 's/.*"\(arn:aws:wisdom:[^"]*\)".*/\1/' | head -1)

ASSISTANT_ID="${ASSISTANT_ID:-$(echo "$ASSISTANT_ARN" | awk -F/ '{print $NF}')}"
KB_ID="$(echo "$KB_ARN" | awk -F/ '{print $NF}')"

echo
echo "Discovered:"
echo "  ASSISTANT_ARN = $ASSISTANT_ARN"
echo "  ASSISTANT_ID  = $ASSISTANT_ID"
echo "  KB_ARN        = $KB_ARN"
echo "  KB_ID         = $KB_ID"

if [[ -z "$ASSISTANT_ID" ]]; then
  echo "FATAL: could not discover assistant ID from Connect integrations."
  echo "Override via: ASSISTANT_ID=<uuid> ./hotel-latency-diagnose-v2.sh"
  exit 1
fi

# ─── 2. Find ASSISTANT ASSOCIATION (KB <-> assistant link) ────────────────────
section "2. ASSISTANT ASSOCIATION (KB link)"
run aws qconnect list-assistant-associations \
    --assistant-id "$ASSISTANT_ID" \
    --region "$AWS_REGION" \
    --output json

# ─── 3. AI PROMPT — full deployed text + version pinning ─────────────────────
section "3. AI PROMPT — DEPLOYED TEXT"
echo "--- List all AI Prompts under this assistant ---"
PROMPTS_JSON=$(aws qconnect list-ai-prompts \
    --assistant-id "$ASSISTANT_ID" \
    --region "$AWS_REGION" \
    --output json 2>&1)
echo "$PROMPTS_JSON"

# Extract first prompt ID (or override via env var)
AI_PROMPT_ID="${AI_PROMPT_ID:-$(echo "$PROMPTS_JSON" | grep '"aiPromptId"' | head -1 | sed 's/.*"aiPromptId": "\([^"]*\)".*/\1/')}"
echo
echo "Selected AI_PROMPT_ID = $AI_PROMPT_ID"

if [[ -n "$AI_PROMPT_ID" ]]; then
  echo
  echo "--- Get full prompt config (look for cache markers + measure size) ---"
  run aws qconnect get-ai-prompt \
      --assistant-id "$ASSISTANT_ID" \
      --ai-prompt-id "$AI_PROMPT_ID" \
      --region "$AWS_REGION" \
      --output json

  echo
  echo "--- Prompt versions ---"
  run aws qconnect list-ai-prompt-versions \
      --assistant-id "$ASSISTANT_ID" \
      --ai-prompt-id "$AI_PROMPT_ID" \
      --region "$AWS_REGION" \
      --output json
fi

# ─── 4. AI AGENT — tool inventory + KB association config ────────────────────
section "4. AI AGENT — TOOL INVENTORY"
echo "--- List all AI Agents under this assistant ---"
AGENTS_JSON=$(aws qconnect list-ai-agents \
    --assistant-id "$ASSISTANT_ID" \
    --region "$AWS_REGION" \
    --output json 2>&1)
echo "$AGENTS_JSON"

AI_AGENT_ID="${AI_AGENT_ID:-$(echo "$AGENTS_JSON" | grep '"aiAgentId"' | head -1 | sed 's/.*"aiAgentId": "\([^"]*\)".*/\1/')}"
echo
echo "Selected AI_AGENT_ID = $AI_AGENT_ID"

if [[ -n "$AI_AGENT_ID" ]]; then
  echo
  echo "--- Get full agent config (tool list + KB config) ---"
  run aws qconnect get-ai-agent \
      --assistant-id "$ASSISTANT_ID" \
      --ai-agent-id "$AI_AGENT_ID" \
      --region "$AWS_REGION" \
      --output json

  echo
  echo "--- Agent versions ---"
  run aws qconnect list-ai-agent-versions \
      --assistant-id "$ASSISTANT_ID" \
      --ai-agent-id "$AI_AGENT_ID" \
      --region "$AWS_REGION" \
      --output json
fi

# ─── 5. BEDROCK INVOCATION TELEMETRY (the critical section) ──────────────────
section "5. BEDROCK MODEL INVOCATION LOGS — TOKEN + LATENCY DATA"
echo "Look for: cache_read_input_tokens > 0  → caching IS working"
echo "         cache_creation_input_tokens   → cache write events"
echo "         input_tokens growth across turns → confirms context-bloat theory"

echo
echo "--- Log group status ---"
run aws logs describe-log-groups \
    --log-group-name-prefix "$BEDROCK_LOG_GROUP" \
    --region "$AWS_REGION" \
    --output json

echo
echo "--- Recent 30 raw invocations (full payload — heavy but informative) ---"
run aws logs filter-log-events \
    --log-group-name "$BEDROCK_LOG_GROUP" \
    --start-time "$START_MS" \
    --max-items 30 \
    --region "$AWS_REGION" \
    --output json

echo
echo "--- Token usage timeline (CloudWatch Insights query) ---"
QUERY_ID=$(aws logs start-query \
    --log-group-name "$BEDROCK_LOG_GROUP" \
    --start-time $(( START_MS / 1000 )) \
    --end-time $(date +%s) \
    --query-string 'fields @timestamp, input.inputBodyJson.system, output.outputBodyJson.usage.input_tokens as input_tokens, output.outputBodyJson.usage.output_tokens as output_tokens, output.outputBodyJson.usage.cache_read_input_tokens as cache_read, output.outputBodyJson.usage.cache_creation_input_tokens as cache_create | sort @timestamp asc | limit 100' \
    --region "$AWS_REGION" \
    --output text \
    --query 'queryId' 2>/dev/null)

if [[ -n "$QUERY_ID" && "$QUERY_ID" != "None" ]]; then
  echo "Query ID: $QUERY_ID"
  echo "Waiting up to 30s for results..."
  for i in 1 2 3 4 5 6; do
    sleep 5
    STATUS=$(aws logs get-query-results --query-id "$QUERY_ID" --region "$AWS_REGION" --query 'status' --output text 2>/dev/null)
    if [[ "$STATUS" == "Complete" ]]; then break; fi
    echo "  status: $STATUS"
  done
  echo
  echo "--- Insights query results ---"
  run aws logs get-query-results \
      --query-id "$QUERY_ID" \
      --region "$AWS_REGION" \
      --output json
fi

echo
echo "--- Latency timeline (output_token timing if available) ---"
QUERY_ID2=$(aws logs start-query \
    --log-group-name "$BEDROCK_LOG_GROUP" \
    --start-time $(( START_MS / 1000 )) \
    --end-time $(date +%s) \
    --query-string 'fields @timestamp, modelId, output.outputBodyJson.usage.input_tokens, output.outputBodyJson.usage.output_tokens, output.outputBodyJson.usage.cache_read_input_tokens, inferenceRegion | sort @timestamp desc | limit 50' \
    --region "$AWS_REGION" \
    --output text \
    --query 'queryId' 2>/dev/null)

if [[ -n "$QUERY_ID2" && "$QUERY_ID2" != "None" ]]; then
  echo "Query ID: $QUERY_ID2"
  for i in 1 2 3 4 5 6; do
    sleep 5
    STATUS=$(aws logs get-query-results --query-id "$QUERY_ID2" --region "$AWS_REGION" --query 'status' --output text 2>/dev/null)
    if [[ "$STATUS" == "Complete" ]]; then break; fi
  done
  run aws logs get-query-results --query-id "$QUERY_ID2" --region "$AWS_REGION" --output json
fi

# ─── 6. LAMBDA DURATIONS (only Lambdas with actual data) ─────────────────────
section "6. HOTEL API LAMBDA DURATIONS — p50 / p95 / p99"

LAMBDAS=$(aws lambda list-functions \
    --region "$AWS_REGION" \
    --query 'Functions[?contains(FunctionName, `hotel`) || contains(FunctionName, `Hotel`)].FunctionName' \
    --output text 2>/dev/null)

for fn in $LAMBDAS; do
  echo
  echo "--- $fn (last ${HOURS_BACK}h) ---"
  run aws cloudwatch get-metric-statistics \
      --namespace AWS/Lambda \
      --metric-name Duration \
      --dimensions Name=FunctionName,Value="$fn" \
      --start-time "$START_TIME_ISO" \
      --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --period 3600 \
      --statistics Average Maximum SampleCount \
      --extended-statistics p50 p95 p99 \
      --region "$AWS_REGION" \
      --output json
done

# ─── 7. CONTACT RECORDS — call duration + flow path ──────────────────────────
section "7. RECENT CONTACTS"
run aws connect search-contacts \
    --instance-id "$CONNECT_INSTANCE_ID" \
    --time-range "Type=INITIATION_TIMESTAMP,StartTime=$START_TIME_ISO,EndTime=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --max-results 20 \
    --region "$AWS_REGION" \
    --output json

# ─── 8. LEX BOT — locale config + Nova Sonic + intent settings ───────────────
section "8. LEX BOT — hotel-SelfServiceBot details"
BOT_ID="YBI14PGD3E"
run aws lexv2-models describe-bot \
    --bot-id "$BOT_ID" \
    --region "$AWS_REGION" \
    --output json
run aws lexv2-models list-bot-locales \
    --bot-id "$BOT_ID" \
    --bot-version DRAFT \
    --region "$AWS_REGION" \
    --output json
run aws lexv2-models describe-bot-locale \
    --bot-id "$BOT_ID" \
    --bot-version DRAFT \
    --locale-id en_US \
    --region "$AWS_REGION" \
    --output json

# ─── 9. INFERENCE PROFILE — confirm which is being used ──────────────────────
section "9. CURRENT INFERENCE PROFILE FOR PROMPT"
echo "Cross-check: which inference profile is the deployed prompt using?"
echo "(Look back at section 3 output — field is 'modelId')."
echo
echo "--- us. profile details ---"
run aws bedrock get-inference-profile \
    --inference-profile-identifier us.anthropic.claude-haiku-4-5-20251001-v1:0 \
    --region "$AWS_REGION" \
    --output json

# ─── 10. SUMMARY HINTS ───────────────────────────────────────────────────────
section "DIAGNOSTIC COMPLETE — what to look for in this file"
cat <<'EOF'

ANALYSIS CHECKLIST (I'll go through these when you share the file back):

  1. Section 3 — Deployed prompt size
     Look at templateConfiguration.textFullAIPromptEditTemplateConfiguration.text
     Character count tells me actual token cost (≈ chars/4).
     If > 8000 tokens → confirms shrink is high-impact.

  2. Section 4 — Number of tools registered
     Count entries in configuration.orchestrationAIAgentConfiguration.toolConfiguration.tools[]
     If > 8 tools → confirms consolidation impact.

  3. Section 5 — Bedrock cache hits  ⭐ THE BIG ONE
     If ANY invocation shows cache_read_input_tokens > 0 → caching IS working.
     If ALL show cache_read_input_tokens = 0 → caching is OFF.
       If OFF and prompt is large → that's most of your latency growth.

  4. Section 5 — Input token growth
     Plot input_tokens over @timestamp within a single call.
     If it grows ~200-400 tokens per turn → confirms context-bloat (need session
     rotation or smaller history).

  5. Section 6 — Lambda p99 Duration
     If hotel API p99 > 2000ms → backend is contributing to latency, not just LLM.
     If p99 < 500ms → LLM is the bottleneck (where our fixes apply).

  6. Section 3 — modelId
     If 'global.anthropic.claude-haiku-4-5...' → switching to 'us.' saves 100-300ms.
     If already 'us.' → that win is unavailable.

EOF
echo "Output file: $OUT_FILE"
echo
echo "Share this file back and I'll give you the prioritized fix list."
