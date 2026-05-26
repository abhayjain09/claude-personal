# Bank Rate Collection — Deployment Guide

S&P Global Ratewatch outbound rate-collection solution built on Amazon Connect
with the same AWS AI-agents architecture as the hotel self-service workshop.

---

## Architecture Overview

```
Outbound Call (Amazon Connect)
  → Contact Flow (Outbound Whisper + Lex Bot)
  → Lex Bot (Nova Sonic — speech↔text)
    → AmazonQinConnect intent
      → Q in Connect AI Agent  (Bank-Rate-Collection-Agent)
        → Ryan prompt (bank-rate-collection-prompt.yaml)
        → Tools:
            startCallSession          → AgentCore Gateway → Lambda → DynamoDB
            submitCDRates             → AgentCore Gateway → Lambda → DynamoDB
            submitMoneyMarketRates    → AgentCore Gateway → Lambda → DynamoDB
            submitIRARates            → AgentCore Gateway → Lambda → DynamoDB
            submitSavingsRates        → AgentCore Gateway → Lambda → DynamoDB
            submitCheckingRates       → AgentCore Gateway → Lambda → DynamoDB
            submitSpecial             → AgentCore Gateway → Lambda → DynamoDB
            closeCallSession          → AgentCore Gateway → Lambda → DynamoDB
            scheduleCallback          → AgentCore Gateway → Lambda → DynamoDB
            markDNC                   → AgentCore Gateway → Lambda → DynamoDB
            recordMergerAcquisition   → AgentCore Gateway → Lambda → DynamoDB
            Retrieve                  → Q in Connect Knowledge Base
            Escalate                  → RETURN_TO_CONTROL (transfer to human)
            Complete                  → RETURN_TO_CONTROL (end call)
```

### Prompt Chunking Strategy

The original rate-collection prompt covers 12 sequential product steps.
Instead of one monolithic prompt, each product category has a **dedicated API tool**:

| Prompt Step(s) | Tool Called              | DynamoDB productType          |
|----------------|--------------------------|-------------------------------|
| 1–3            | `submitCDRates`          | `cd_standard`                 |
| 4              | `submitCDRates`          | `cd_jumbo`                    |
| 5              | `submitMoneyMarketRates` | `mm_standard`                 |
| 6              | `submitMoneyMarketRates` | `mm_relationship`             |
| 7              | `submitIRARates`         | `ira_liquid`                  |
| 8              | `submitIRARates`         | `ira_fixed`                   |
| 9              | `submitSavingsRates`     | `savings`                     |
| 10             | `submitCheckingRates`    | `checking`                    |
| 11 (per item)  | `submitSpecial`          | `special_<timestamp>`         |
| 12             | `closeCallSession`       | (updates session record)      |

This mirrors the hotel architecture where `createBooking`, `cancelReservation`, etc.
are separate Lambda-backed tools.

---

## Folder Structure

```
bank-rate-collection/
├── cloudformation/
│   ├── bank-rate-api.yaml           ← API Gateway + Lambda + DynamoDB
│   ├── bank-assistant-setup.yaml    ← Q Connect Assistant + Knowledge Base
│   ├── bank-agentcore-gateway.yaml  ← AgentCore Gateway + Target
│   ├── bank-ai-agents-setup.yaml    ← AI Prompt + AI Agent
│   └── bank-unified-stack.yaml      ← Parent stack (deploys all above)
├── api/
│   ├── bank-rate-api-openapi.yaml   ← OpenAPI 3.0 spec for all endpoints
│   └── bank-seed-data.json          ← Sample bank records for BanksTable
├── ai-agents/
│   └── bank/
│       ├── bank-rate-collection-prompt.yaml    ← Chunked Ryan agent prompt
│       └── bank-rate-collection-tool-configs.md← Tool reference documentation
└── knowledge-base/
    └── bank-rate-collection-faq.md  ← FAQ document for KB (upload to S3)
```

---

## Prerequisites

Before deploying, ensure these exist in your AWS account:

1. **Amazon Connect instance** — note the Instance ID and ARN
2. **Lex Bot** — Nova Sonic speech model, AmazonQinConnect intent (same as hotel setup)
3. **boto3 Lambda Layer** — updated boto3 ZIP uploaded to S3 (or have the ARN ready)
4. **Assets S3 bucket** — where you upload all template and asset files

---

## Deployment Steps

### Step 1 — Upload assets to S3

```bash
BUCKET="your-assets-bucket-name"
PREFIX="bank-rate-collection"

# Upload CloudFormation templates
aws s3 cp cloudformation/bank-rate-api.yaml         s3://$BUCKET/$PREFIX/cloudformation/
aws s3 cp cloudformation/bank-assistant-setup.yaml  s3://$BUCKET/$PREFIX/cloudformation/
aws s3 cp cloudformation/bank-agentcore-gateway.yaml s3://$BUCKET/$PREFIX/cloudformation/
aws s3 cp cloudformation/bank-ai-agents-setup.yaml  s3://$BUCKET/$PREFIX/cloudformation/
aws s3 cp cloudformation/bank-unified-stack.yaml    s3://$BUCKET/$PREFIX/cloudformation/

# Upload API and AI agent assets
aws s3 cp api/bank-rate-api-openapi.yaml            s3://$BUCKET/$PREFIX/api/
aws s3 cp api/bank-seed-data.json                   s3://$BUCKET/$PREFIX/api/
aws s3 cp ai-agents/bank/bank-rate-collection-prompt.yaml \
                                                    s3://$BUCKET/$PREFIX/ai-agents/bank/
```

### Step 2 — Deploy the unified stack

Using the AWS Console — CloudFormation → Create Stack → Upload template
or using the CLI:

```bash
CONNECT_INSTANCE_ARN="arn:aws:connect:us-east-1:ACCOUNT_ID:instance/INSTANCE-UUID"
CONNECT_INSTANCE_ID="INSTANCE-UUID"
DISCOVERY_URL="https://YOUR-ALIAS.my.connect.aws/.well-known/openid-configuration"
BOTO3_LAYER_ARN="arn:aws:lambda:us-east-1:ACCOUNT_ID:layer:boto3-layer:1"

aws cloudformation deploy \
  --template-file cloudformation/bank-unified-stack.yaml \
  --stack-name bank-rate-collection \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
  --parameter-overrides \
    ConnectInstanceArn="$CONNECT_INSTANCE_ARN" \
    ConnectInstanceId="$CONNECT_INSTANCE_ID" \
    AgentCoreGatewayDiscoveryUrl="$DISCOVERY_URL" \
    Boto3LayerArn="$BOTO3_LAYER_ARN" \
    AssetsBucketName="$BUCKET" \
    SeedDataUrl="s3://$BUCKET/$PREFIX/api/bank-seed-data.json" \
    OpenApiSpecUrl="s3://$BUCKET/$PREFIX/api/bank-rate-api-openapi.yaml" \
    BankRateCollectionPromptUrl="s3://$BUCKET/$PREFIX/ai-agents/bank/bank-rate-collection-prompt.yaml"
```

### Step 3 — Retrieve Stack Outputs

```bash
aws cloudformation describe-stacks \
  --stack-name bank-rate-collection \
  --query 'Stacks[0].Outputs' \
  --output table
```

Key outputs you will need for Step 4:
- `AIAgentArn` — used in the Lex bot session attribute
- `AssistantId` — used in the Connect contact flow
- `KnowledgeBaseBucketName` — upload FAQ docs here

### Step 4 — Upload Knowledge Base documents

```bash
KB_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name bank-rate-collection \
  --query 'Stacks[0].Outputs[?OutputKey==`KnowledgeBaseBucketName`].OutputValue' \
  --output text)

aws s3 cp knowledge-base/bank-rate-collection-faq.md s3://$KB_BUCKET/
```

### Step 5 — Configure Connect Contact Flow

In the Amazon Connect contact flow, set the Lex bot session attribute:

```
x-amz-lex:q-in-connect:ai-agent-arn = <AIAgentArn from stack output>
```

Set the voice to **Amazon Nova Sonic** (speech-to-speech) on the SetVoice block:
```
Voice engine = Generative
Voice ID     = amazon.nova-2-sonic-v1:0   (or Matthew for fallback Generative TTS)
Language     = en-US
```

Latency-tuned Lex session attributes (set on ConnectParticipantWithLexBot block):
```
x-amz-lex:audio:end-timeout-ms:*:*   = 400      # shorter end-of-speech detection
x-amz-lex:audio:start-timeout-ms:*:* = 500      # let banker breathe before barge-in
x-amz-lex:audio:max-length-ms:*:*    = 30000
x-amz-lex:allow-interrupt:*:*        = true     # banker can talk over Ryan
```

Set the contact flow greeting (in the Create Wisdom Session block — first thing the banker hears):
```
Hi, this is Ryan calling from S&P Global Ratewatch. May I speak with someone about your current deposit rates?
```

---

## Voice Latency Design

This solution is tuned for low perceived latency on Amazon Nova Sonic (speech-to-speech). End-to-end the realistic minimum is ~1.2–3.5s per turn (Nova Sonic ASR + Claude Haiku inference + tool call + Nova Sonic TTS).

To prevent the banker from hearing silence during tool calls, the Ryan prompt enforces a **two-message pre-tool pattern**:

1. **Instant ack** — `<message>Got it.</message>` streams in <1s while Ryan thinks.
2. **Bridging filler** — `<message>Let me log those CD rates now.</message>` streams while the tool runs.
3. **Tool call** — actual API hit takes 0.5–2s, but is now masked by the bridging audio.
4. **Result** — `<message>Perfect. And for jumbo CDs?</message>` continues the flow.

Each tool has its own bridging phrase. See `ai-agents/bank/bank-rate-collection-tool-configs.md` for the full mapping.

Additional latency wins applied:
- Claude Haiku 4.5 (fastest first-token Anthropic model on Bedrock).
- Knowledge Base `maxResults` lowered to 3 (vs hotel default of 5) — ~200ms saved per Retrieve.
- Lex `end-timeout-ms` set to 400ms (faster end-of-speech detection).
- Single Lambda fronts all 12 API operations (warm container reuse across calls).
- Per-tool instructions in the AI Agent config explicitly remind the LLM to emit the bridging filler before each call.

What we deliberately did NOT do (and why):
- **Lex `fulfillmentUpdates` filler** — architecturally blocked for AMAZON.QInConnectIntent (returns ValidationException). Prompt-side filler is the only working path.
- **Lex `initialResponseSetting`** — rejected by Lex build validation for QInConnectIntent.
- **Connect flow per-turn filler** — `ConnectParticipantWithLexBot` does not expose a mid-turn hook.

See `hotel-assets/context/latency-diagnosis.txt` for the full investigation of why these don't work.

---

## DynamoDB Table Structure

| Table              | PK          | SK (if any)     | Purpose                         |
|--------------------|-------------|-----------------|----------------------------------|
| BanksTable         | bankId      | —               | Reference bank data (seeded)     |
| CallSessionsTable  | sessionId   | —               | One record per outbound call     |
| BankRatesTable     | sessionId   | productType     | Rate data per product per call   |
| CallbacksTable     | sessionId   | —               | Callback requests                |
| DNCTable           | phoneNumber | —               | Do Not Call registry             |
| MergerAcquisitionTable | sessionId | —             | M&A event records                |

---

## Querying Collected Rates (AWS CLI examples)

```bash
# Get all rates for a specific session
aws dynamodb query \
  --table-name bank-rate-collection-BankRatesTable \
  --key-condition-expression "sessionId = :sid" \
  --expression-attribute-values '{":sid": {"S": "YOUR-SESSION-ID"}}'

# Check DNC list
aws dynamodb scan --table-name bank-rate-collection-DNCTable

# List recent call sessions
aws dynamodb scan \
  --table-name bank-rate-collection-CallSessionsTable \
  --filter-expression "#s = :s" \
  --expression-attribute-names '{"#s":"status"}' \
  --expression-attribute-values '{":s":{"S":"in-progress"}}'
```

---

## Stack Dependencies

```
bank-unified-stack
├── bank-assistant-setup     (no deps)
├── bank-rate-api            (no deps)
├── bank-agentcore-gateway   (depends on: bank-rate-api)
└── bank-ai-agents-setup     (depends on: bank-assistant-setup, bank-agentcore-gateway)
```

---

## Tear Down

```bash
# Delete unified stack (deletes all nested stacks)
aws cloudformation delete-stack --stack-name bank-rate-collection

# Wait for deletion
aws cloudformation wait stack-delete-complete --stack-name bank-rate-collection
```

Note: S3 buckets with content must be emptied before CloudFormation can delete them.

```bash
# Empty KB bucket before deletion
aws s3 rm s3://$KB_BUCKET --recursive
```
