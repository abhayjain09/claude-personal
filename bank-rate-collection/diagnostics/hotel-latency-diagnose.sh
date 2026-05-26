#!/usr/bin/env bash
# =============================================================================
# Hotel Q Connect AI Agent — Latency Diagnostic Script (READ-ONLY)
# =============================================================================
# Purpose: Capture the live config of the deployed hotel assistant so we can
# answer:
#   1. Is Anthropic prompt caching enabled / honored?
#   2. How big is the deployed system prompt (tokens)?
#   3. How many tools are registered and how big are their definitions?
#   4. What does Bedrock model invocation logging show for cache_read_input_tokens?
#   5. What is the average / p95 TTFT (time-to-first-token)?
#   6. How does input token count grow turn-by-turn within a single call?
#
# All commands are read-only (Describe / Get / List / FilterLogEvents).
# Output is written to a single file: hotel-latency-diagnose-<timestamp>.txt
# Share that file back and I'll analyze it.
#
# Usage:
#   chmod +x hotel-latency-diagnose.sh
#   ./hotel-latency-diagnose.sh
#
# Optional overrides via env vars:
#   AWS_REGION                (default: us-east-1)
#   ASSISTANT_ID              (default: from aws-resources.json)
#   AI_AGENT_ID               (default: from aws-resources.json)
#   AI_PROMPT_ID              (default: from aws-resources.json)
#   CONNECT_INSTANCE_ID       (default: from aws-resources.json)
#   BEDROCK_LOG_GROUP         (default: /aws/bedrock/modelinvocations)
#   HOURS_BACK                (default: 24 — how far back to scan Bedrock logs)
# =============================================================================

set -u  # error on unset vars; but keep going on individual command failures

# ─── Config ──────────────────────────────────────────────────────────────────
AWS_REGION="${AWS_REGION:-us-east-1}"
ASSISTANT_ID="${ASSISTANT_ID:-d97929ca-a9c3-43ee-8562-c9272acb45e6}"
AI_AGENT_ID="${AI_AGENT_ID:-5b8b33fd-f5f3-4b01-a5bb-7ae9dc69e7c2}"
AI_PROMPT_ID="${AI_PROMPT_ID:-6edfa19f-ebcb-4068-b077-87352e02bf31}"
CONNECT_INSTANCE_ID="${CONNECT_INSTANCE_ID:-6f93dfc3-9503-4b86-971b-f608ec484e78}"
BEDROCK_LOG_GROUP="${BEDROCK_LOG_GROUP:-/aws/bedrock/modelinvocations}"
HOURS_BACK="${HOURS_BACK:-24}"

TS=$(date -u +%Y%m%dT%H%M%SZ)
OUT_FILE="hotel-latency-diagnose-${TS}.txt"
START_MS=$(( ( $(date +%s) - HOURS_BACK*3600 ) * 1000 ))

# ─── Helpers ─────────────────────────────────────────────────────────────────
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
section "DIAGNOSTIC RUN — $TS"
echo "Region:               $AWS_REGION"
echo "AssistantId:          $ASSISTANT_ID"
echo "AIAgentId:            $AI_AGENT_ID"
echo "AIPromptId:           $AI_PROMPT_ID"
echo "ConnectInstanceId:    $CONNECT_INSTANCE_ID"
echo "Bedrock log group:    $BEDROCK_LOG_GROUP"
echo "Looking back:         ${HOURS_BACK}h (since epoch-ms $START_MS)"
echo
echo "AWS identity:"
run aws sts get-caller-identity --region "$AWS_REGION"

# ─── 1. AI Prompt configuration ──────────────────────────────────────────────
section "1. AI PROMPT CONFIG (deployed Hotel-Self-Service-Prompt)"
echo "Looking for cache markers, full template text, model id, and prompt size."
run aws qconnect get-ai-prompt \
    --assistant-id "$ASSISTANT_ID" \
    --ai-prompt-id "$AI_PROMPT_ID" \
    --region "$AWS_REGION" \
    --output json

echo
echo "--- AI Prompt versions (which version is the agent pinned to?) ---"
run aws qconnect list-ai-prompt-versions \
    --assistant-id "$ASSISTANT_ID" \
    --ai-prompt-id "$AI_PROMPT_ID" \
    --region "$AWS_REGION" \
    --output json

# ─── 2. AI Agent configuration ───────────────────────────────────────────────
section "2. AI AGENT CONFIG (tool list, KB association, orchestration template)"
echo "This dumps the full tool inventory and KB association configuration."
run aws qconnect get-ai-agent \
    --assistant-id "$ASSISTANT_ID" \
    --ai-agent-id "$AI_AGENT_ID" \
    --region "$AWS_REGION" \
    --output json

echo
echo "--- AI Agent versions ---"
run aws qconnect list-ai-agent-versions \
    --assistant-id "$ASSISTANT_ID" \
    --ai-agent-id "$AI_AGENT_ID" \
    --region "$AWS_REGION" \
    --output json

# ─── 3. Assistant configuration ──────────────────────────────────────────────
section "3. ASSISTANT CONFIG"
run aws qconnect get-assistant \
    --assistant-id "$ASSISTANT_ID" \
    --region "$AWS_REGION" \
    --output json

echo
echo "--- All AI Agents under this assistant (to spot extra/unused agents) ---"
run aws qconnect list-ai-agents \
    --assistant-id "$ASSISTANT_ID" \
    --region "$AWS_REGION" \
    --output json

echo
echo "--- All AI Prompts under this assistant ---"
run aws qconnect list-ai-prompts \
    --assistant-id "$ASSISTANT_ID" \
    --region "$AWS_REGION" \
    --output json

# ─── 4. Connect instance attributes (voice config, latency settings) ─────────
section "4. CONNECT INSTANCE ATTRIBUTES"
run aws connect describe-instance \
    --instance-id "$CONNECT_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --output json

echo
echo "--- Instance integrations (Wisdom, Lex, Lambda associations) ---"
run aws connect list-integration-associations \
    --instance-id "$CONNECT_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --output json

# ─── 5. Bedrock model invocation logging (cache hit/miss + TTFT) ─────────────
section "5. BEDROCK MODEL INVOCATION LOGS"
echo "Critical: this section answers 'is prompt caching working?'"
echo "Look for: cache_read_input_tokens, cache_creation_input_tokens, input_tokens"
echo
echo "--- Does the log group exist? ---"
run aws logs describe-log-groups \
    --log-group-name-prefix "$BEDROCK_LOG_GROUP" \
    --region "$AWS_REGION" \
    --output json

echo
echo "--- Most recent 20 invocations (raw) ---"
run aws logs filter-log-events \
    --log-group-name "$BEDROCK_LOG_GROUP" \
    --start-time "$START_MS" \
    --max-items 20 \
    --region "$AWS_REGION" \
    --output json

echo
echo "--- Filter: invocations that DID hit the cache (cache_read_input_tokens > 0) ---"
run aws logs filter-log-events \
    --log-group-name "$BEDROCK_LOG_GROUP" \
    --start-time "$START_MS" \
    --filter-pattern '{ $.output.outputBodyJson.usage.cache_read_input_tokens > 0 }' \
    --max-items 10 \
    --region "$AWS_REGION" \
    --output json

echo
echo "--- Filter: invocations that CREATED cache entries (cache_creation_input_tokens > 0) ---"
run aws logs filter-log-events \
    --log-group-name "$BEDROCK_LOG_GROUP" \
    --start-time "$START_MS" \
    --filter-pattern '{ $.output.outputBodyJson.usage.cache_creation_input_tokens > 0 }' \
    --max-items 10 \
    --region "$AWS_REGION" \
    --output json

echo
echo "--- Token usage distribution across recent invocations ---"
echo "(input_tokens, output_tokens, cache_read, cache_create — pulled via CloudWatch Insights)"
run aws logs start-query \
    --log-group-name "$BEDROCK_LOG_GROUP" \
    --start-time $(( START_MS / 1000 )) \
    --end-time $(date +%s) \
    --query-string 'fields @timestamp, output.outputBodyJson.usage.input_tokens, output.outputBodyJson.usage.output_tokens, output.outputBodyJson.usage.cache_read_input_tokens, output.outputBodyJson.usage.cache_creation_input_tokens | sort @timestamp desc | limit 50' \
    --region "$AWS_REGION"
echo "(Note: Insights query started. Run 'aws logs get-query-results --query-id <id>' separately if needed.)"

# ─── 6. Lex bot latency settings ─────────────────────────────────────────────
section "6. LEX BOT CONFIG (Nova Sonic + AmazonQinConnect intent)"
echo "--- List Lex bots ---"
run aws lexv2-models list-bots --region "$AWS_REGION" --output json

# ─── 7. Lambda function metrics (hotel API latency) ──────────────────────────
section "7. HOTEL API LAMBDA — recent latency"
echo "--- Hotel API Lambdas ---"
run aws lambda list-functions \
    --region "$AWS_REGION" \
    --query 'Functions[?contains(FunctionName, `hotel`) || contains(FunctionName, `Hotel`)].{Name:FunctionName,Runtime:Runtime,Mem:MemorySize,Timeout:Timeout,LastMod:LastModified}' \
    --output json

echo
echo "--- Duration p50 / p95 / p99 for past ${HOURS_BACK}h (per Lambda) ---"
LAMBDAS=$(aws lambda list-functions \
    --region "$AWS_REGION" \
    --query 'Functions[?contains(FunctionName, `hotel`) || contains(FunctionName, `Hotel`)].FunctionName' \
    --output text 2>/dev/null)
for fn in $LAMBDAS; do
  echo
  echo "--- $fn ---"
  run aws cloudwatch get-metric-statistics \
      --namespace AWS/Lambda \
      --metric-name Duration \
      --dimensions Name=FunctionName,Value="$fn" \
      --start-time "$(date -u -d "${HOURS_BACK} hours ago" +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -v-${HOURS_BACK}H +%Y-%m-%dT%H:%M:%S)" \
      --end-time   "$(date -u +%Y-%m-%dT%H:%M:%S)" \
      --period 3600 \
      --statistics Average Maximum \
      --extended-statistics p50 p95 p99 \
      --region "$AWS_REGION" \
      --output json
done

# ─── 8. Connect contact flow latency (CTRs) ──────────────────────────────────
section "8. RECENT CONTACT TRACE RECORDS (latency in real calls)"
echo "Looking at contact attributes captured during real rate-collection calls."
echo
echo "--- Recent contacts (last ${HOURS_BACK}h) ---"
run aws connect search-contacts \
    --instance-id "$CONNECT_INSTANCE_ID" \
    --time-range "Type=INITIATION_TIMESTAMP,StartTime=$(date -u -d "${HOURS_BACK} hours ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-${HOURS_BACK}H +%Y-%m-%dT%H:%M:%SZ),EndTime=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --max-results 10 \
    --region "$AWS_REGION" \
    --output json

# ─── 9. Bedrock model availability / inference profile ───────────────────────
section "9. BEDROCK MODEL & INFERENCE PROFILE"
echo "--- Inference profile for Haiku 4.5 (cross-region routing affects latency) ---"
run aws bedrock get-inference-profile \
    --inference-profile-identifier global.anthropic.claude-haiku-4-5-20251001-v1:0 \
    --region "$AWS_REGION" \
    --output json
run aws bedrock get-inference-profile \
    --inference-profile-identifier us.anthropic.claude-haiku-4-5-20251001-v1:0 \
    --region "$AWS_REGION" \
    --output json 2>&1 | head -30

# ─── 10. Q Connect session metrics (if accessible) ───────────────────────────
section "10. CONTACT FLOW / SESSION METRICS"
echo "--- Recent CloudWatch metrics for Connect instance ---"
run aws cloudwatch list-metrics \
    --namespace AWS/Connect \
    --dimensions Name=InstanceId,Value="$CONNECT_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --output json

# ─── Done ────────────────────────────────────────────────────────────────────
section "DIAGNOSTIC COMPLETE"
echo "Output file: $OUT_FILE"
echo
echo "Next step: share $OUT_FILE back. I'll analyze:"
echo "  - whether cache_read_input_tokens > 0 anywhere (= caching working)"
echo "  - actual deployed prompt token size"
echo "  - exact tool count and individual tool def sizes"
echo "  - Lambda p95/p99 durations (your hotel API contribution to total latency)"
echo "  - and recommend the precise fixes ordered by impact."
