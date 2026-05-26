# Chat Session — Bank Rate Collection Solution
**Date:** May 25–26, 2026  
**Session ID:** 6c7315e6-b39e-41f8-9665-017506f451ca  
**Model:** Claude Sonnet 4.6 (GitHub Copilot)

---

## User Request

> Check all files in `/hotel-assets` and `/templates` (CloudFormation).  
> I used the AWS lab at https://catalog.workshops.aws/amazon-connect-ai-agents/en-US/03-self-service-track to create existing AWS resources.  
> I want to create the same solution but instead of hotel industry, create one for **bank rate collection**.  
> Use the prompt in `rate-collection-promt.yaml` but it is very big — create some chunks and use it as MCP tool in Lambda, just like `createBooking` in the hotel.  
> Create a separate folder for CloudFormation templates.  
> **Do not create anything in AWS** — only create the files locally.  
> Use AWS CLI if you need to check anything on the AWS side.

---

## What Was Analyzed

### hotel-assets/ — Key Files Read
| File | Summary |
|---|---|
| `ai-agents/hotel/hotel-self-service-prompt.yaml` | Sunny persona, voice agent for Horizon Hotels; two-message pre-tool latency pattern; tools: searchHotels, createBooking, modifyReservation, cancelReservation, getCustomerReservations, Retrieve, Escalate, Complete |
| `ai-agents/hotel/hotel-agent-assist-prompt.yaml` | Agent-assist version for human agent support; HTML-only output, GenerateNotes + Retrieve tools |
| `ai-agents/common/complete-tool-config.md` | RETURN_TO_CONTROL tool — ends conversation after customer confirms no more questions |
| `ai-agents/common/escalate-tool-config.md` | RETURN_TO_CONTROL tool — transfers to human agent with structured context |
| `ai-agents/common/retrieve-tool-config.md` | MODEL_CONTEXT_PROTOCOL tool — semantic search against Q in Connect Knowledge Base |
| `ai-agents/common/generate-notes-tool-config.md` | MODEL_CONTEXT_PROTOCOL tool — generates call notes for agent-assist mode |
| `ai-agents/defaults/SelfServiceOrchestration.yaml` | Default orchestration prompt template for self-service AI agents |
| `hotel/hotel-api-openapi.yaml` | OpenAPI 3.0 spec for hotel API: searchHotels, createBooking, modifyReservation, cancelReservation, getCustomerReservations |
| `hotel/hotel-seed-data.json` | Hotel records for DynamoDB seeding (New York, LA, Chicago, etc.) |
| `context/aws-resources.json` | Live AWS resource IDs: Connect instance, Lex bot, Q Connect assistant, AI agent, contact flow |
| `context/architecture-overview.txt` | Full call flow: Customer → Connect → Lex (Nova Sonic) → QConnect AI Agent → Hotel API tools |

### templates/ — Key CloudFormation Templates Read
| Template | Purpose |
|---|---|
| `hotel-api.yaml` | API Gateway + Lambda (Node.js) + DynamoDB (HotelsTable, ReservationsTable) + seed data custom resource + API key retrieval custom resource |
| `assistant-setup.yaml` | Wisdom/Q Connect Assistant + S3 KB bucket + Knowledge Base + Connect integration Lambda |
| `ai-agents-setup.yaml` | AI Prompts + AI Agents via Custom Resource Lambda using boto3 / Q Connect API; supports 11 industries |
| `agentcore-gateway.yaml` | AgentCore Gateway + Credential Providers + Gateway Targets via Custom Resource Lambda |
| `unified-workshop-stack.yaml` | Parent stack that deploys all nested stacks |
| `assistant-knowledge-base.yaml` | Knowledge base configuration |
| `connect-instance.yaml` | Connect instance setup |

### rate-collection-promt.yaml — Full Content Analyzed
The original prompt (Ryan, S&P Global Ratewatch) covers:
- **12 Collection Steps**: CD Short/Mid/Long (Steps 1–3), Jumbo CD (4), Standard MM (5), Relationship MM (6), Liquid IRA (7), Fixed IRA (8), Savings (9), Checking (10), Specials (11), Close/Name (12)
- **Rate/APY tracking logic** per product (UNKNOWN → SEPARATE or SAME)
- **Scenarios**: No change, Voicemail, Callback, DNC, M&A, Email (2 sub-cases), Live agent, Refusal, Frustration, Interruption
- **Hard rules**: never output after Complete/Escalate, always collect banker name, wait for goodbye before completing
- **Tools referenced**: Complete, Escalate, ScheduleCallback, RecordMA, MarkDNC

---

## Existing AWS Architecture (Hotel)

```
Customer (voice)
  → Amazon Connect phone number
  → Contact Flow (Self Service Test Flow)
    → CreateWisdomSession → SetVoice (Nova Sonic / Matthew)
    → ConnectParticipantWithLexBot
  → Lex Bot: hotel-SelfServiceBot (Nova Sonic ASR — speech-to-speech)
    → AmazonQinConnect intent → AI Agent
  → Q Connect AI Agent: Hotel-Self-Service-Agent
    → Prompt: Hotel-Self-Service-Prompt v3 (Claude Haiku 4.5)
    → Tools via AgentCore Gateway:
        Hotel_API_Target___createBooking
        Hotel_API_Target___searchHotels
        Hotel_API_Target___modifyReservation
        Hotel_API_Target___cancelReservation
        Hotel_API_Target___getCustomerReservations
    → MCP Tools: Retrieve (KB search), TellMeAJoke (flow module)
    → RETURN_TO_CONTROL: Escalate, Complete
  → Nova Sonic TTS → Back to customer
```

**Live AWS Resource IDs (from aws-resources.json):**
- Connect Instance: `6f93dfc3-9503-4b86-971b-f608ec484e78`
- Lex Bot: `YBI14PGD3E` (alias: `TSTALIASID`)
- Q Connect Assistant: `d97929ca-a9c3-43ee-8562-c9272acb45e6`
- AI Agent: `5b8b33fd-f5f3-4b01-a5bb-7ae9dc69e7c2`
- AI Prompt: `6edfa19f-ebcb-4068-b077-87352e02bf31:7`
- Contact Flow: `758b182f-afad-4321-acbe-9d8a178c9ae2`

---

## What Was Built

All files created in `/bank-rate-collection/` — **no AWS resources were created**.

### Folder Structure Created

```
bank-rate-collection/
├── cloudformation/
│   ├── bank-rate-api.yaml              ← API Gateway + Lambda + 6 DynamoDB tables
│   ├── bank-assistant-setup.yaml       ← Q Connect Assistant + KB + Connect integration
│   ├── bank-agentcore-gateway.yaml     ← AgentCore Gateway + Target
│   ├── bank-ai-agents-setup.yaml       ← AI Prompt + AI Agent (Custom Resource)
│   └── bank-unified-stack.yaml         ← Parent stack (deploys all 4 above)
├── api/
│   ├── bank-rate-api-openapi.yaml      ← Full OpenAPI 3.0 spec (12 endpoints)
│   └── bank-seed-data.json             ← 10 sample bank records
├── ai-agents/
│   └── bank/
│       ├── bank-rate-collection-prompt.yaml     ← Chunked Ryan agent prompt
│       └── bank-rate-collection-tool-configs.md ← Tool JSON configs + sequence
└── knowledge-base/
    └── bank-rate-collection-faq.md     ← FAQ doc for KB (upload to S3 after deploy)
```

**All 5 CloudFormation YAML files validated ✅** (using CFN-aware YAML parser)

---

## Key Design Decisions

### 1. Prompt Chunking Strategy
The original 250-line monolithic `rate-collection-promt.yaml` was chunked into **12 dedicated API tool calls** — one per product category. This mirrors how `createBooking` in the hotel solution is a Lambda-backed tool the AI agent calls.

| Prompt Step(s) | Lambda Tool Called         | DynamoDB productType      |
|----------------|----------------------------|---------------------------|
| Steps 1–3      | `submitCDRates`            | `cd_standard`             |
| Step 4         | `submitCDRates`            | `cd_jumbo`                |
| Step 5         | `submitMoneyMarketRates`   | `mm_standard`             |
| Step 6         | `submitMoneyMarketRates`   | `mm_relationship`         |
| Step 7         | `submitIRARates`           | `ira_liquid`              |
| Step 8         | `submitIRARates`           | `ira_fixed`               |
| Step 9         | `submitSavingsRates`       | `savings`                 |
| Step 10        | `submitCheckingRates`      | `checking`                |
| Step 11 (each) | `submitSpecial`            | `special_<timestamp>`     |
| Step 12        | `closeCallSession`         | (updates session record)  |

**Analogy:** `submitCDRates` = hotel's `createBooking`. Both are Lambda-backed API Gateway endpoints called by the AI agent to persist data.

### 2. DynamoDB Tables (6 total)
| Table | Primary Key | Purpose |
|---|---|---|
| `BanksTable` | `bankId` | Reference bank data (seeded from bank-seed-data.json) |
| `CallSessionsTable` | `sessionId` | One record per outbound call; TTL 90 days |
| `BankRatesTable` | `sessionId` + `productType` | Rate data per product per call |
| `CallbacksTable` | `sessionId` | Callback requests |
| `DNCTable` | `phoneNumber` | Do Not Call registry |
| `MergerAcquisitionTable` | `sessionId` | M&A event records |

### 3. API Endpoints (12 total)
All routed through a single Lambda function (Node.js 22) behind API Gateway with `x-api-key` auth:

```
POST /sessions                      → startCallSession
GET  /sessions/{sessionId}          → getCallSession
POST /sessions/{sessionId}/close    → closeCallSession
POST /rates/cd                      → submitCDRates
POST /rates/money-market            → submitMoneyMarketRates
POST /rates/ira                     → submitIRARates
POST /rates/savings                 → submitSavingsRates
POST /rates/checking                → submitCheckingRates
POST /rates/specials                → submitSpecial
POST /callbacks                     → scheduleCallback
POST /dnc                           → markDNC
POST /merger-acquisition            → recordMergerAcquisition
```

### 4. Tool Types (same pattern as hotel)
| Tool | Type | Notes |
|---|---|---|
| `startCallSession`, `submitCDRates`, etc. | AgentCore Gateway → Lambda | Like hotel's `createBooking` |
| `Retrieve` | MODEL_CONTEXT_PROTOCOL | Q in Connect KB search |
| `Escalate` | RETURN_TO_CONTROL | Transfer to human |
| `Complete` | RETURN_TO_CONTROL | End call (completion_type: full/spot_check/incomplete/voicemail/email) |

### 5. Stack Deployment Order
```
bank-unified-stack (parent)
  ├── bank-assistant-setup      [no deps] → AssistantId, AssistantAssociationId
  ├── bank-rate-api             [no deps] → ApiEndpoint, ApiKeyValue
  ├── bank-agentcore-gateway    [needs: bank-rate-api] → GatewayArn
  └── bank-ai-agents-setup      [needs: bank-assistant-setup + bank-agentcore-gateway]
```

---

## New Architecture (Bank Rate Collection)

```
Outbound Call (Amazon Connect)
  → Contact Flow (outbound whisper + Lex Bot session)
  → Lex Bot (Nova Sonic — speech↔text)
    → AmazonQinConnect intent
      → Q in Connect AI Agent (Bank-Rate-Collection-Agent)
        → Ryan prompt (bank-rate-collection-prompt.yaml)
        → Tools:
            startCallSession       → AgentCore GW → Lambda → DynamoDB (CallSessionsTable)
            submitCDRates          → AgentCore GW → Lambda → DynamoDB (BankRatesTable)
            submitMoneyMarketRates → AgentCore GW → Lambda → DynamoDB (BankRatesTable)
            submitIRARates         → AgentCore GW → Lambda → DynamoDB (BankRatesTable)
            submitSavingsRates     → AgentCore GW → Lambda → DynamoDB (BankRatesTable)
            submitCheckingRates    → AgentCore GW → Lambda → DynamoDB (BankRatesTable)
            submitSpecial          → AgentCore GW → Lambda → DynamoDB (BankRatesTable)
            closeCallSession       → AgentCore GW → Lambda → DynamoDB (CallSessionsTable)
            scheduleCallback       → AgentCore GW → Lambda → DynamoDB (CallbacksTable)
            markDNC                → AgentCore GW → Lambda → DynamoDB (DNCTable)
            recordMergerAcquisition→ AgentCore GW → Lambda → DynamoDB (MergerAcquisitionTable)
            Retrieve               → Q in Connect Knowledge Base
            Escalate               → RETURN_TO_CONTROL → human agent transfer
            Complete               → RETURN_TO_CONTROL → end call
  → Nova Sonic TTS → Back to banker
```

---

## Deployment Steps (Summary)

1. **Upload assets to S3** — all CFN templates, openapi spec, seed data, prompt YAML
2. **Deploy `bank-unified-stack.yaml`** — creates all resources (Assistant, API, Gateway, AI Agent)
3. **Retrieve outputs** — `AIAgentArn`, `AssistantId`, `KnowledgeBaseBucketName`
4. **Upload KB docs** — copy `knowledge-base/bank-rate-collection-faq.md` to KB S3 bucket
5. **Configure Connect contact flow** — set `x-amz-lex:q-in-connect:ai-agent-arn` session attribute

Full CLI commands are in [README.md](README.md).

---

## Tags Applied to All AWS Resources
```yaml
Environment: NonProd
Name: BankRateCollection
contact: askdevopscloud@spglobal.com
AppID: ASP0017650
CreatedBy: Abhay.Lunkad
Owner: anuthama.c@spglobal.com
```

---

## Validation Results
```
cloudformation/bank-agentcore-gateway.yaml   ✅ OK
cloudformation/bank-ai-agents-setup.yaml     ✅ OK
cloudformation/bank-assistant-setup.yaml     ✅ OK
cloudformation/bank-rate-api.yaml            ✅ OK
cloudformation/bank-unified-stack.yaml       ✅ OK
api/bank-rate-api-openapi.yaml               ✅ OK
api/bank-seed-data.json                      ✅ OK
ai-agents/bank/bank-rate-collection-prompt.yaml  ✅ OK
```
