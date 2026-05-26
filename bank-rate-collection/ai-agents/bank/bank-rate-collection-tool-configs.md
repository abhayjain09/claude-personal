# Bank Rate Collection — Tool Configuration Reference

This document lists all tools used by the **Bank-Rate-Collection AI Agent (Ryan)**.

---

## Two-Message Pre-Tool Latency Pattern

Amazon Nova Sonic streams audio token-by-token. Tool calls take 1–3 seconds — if Ryan goes silent during that window, the banker thinks the line dropped.

For **every** tool call (except the silent `startCallSession` at call connect), Ryan must emit:

1. An **instant ack** `<message>` (3–6 words) — streams in <1s.
2. A silent `<thinking>` block to pick the tool.
3. A **bridging** `<message>` — tool-specific, describes the action.
4. The tool call.
5. A result `<message>`.

This is enforced in the prompt and reinforced in every tool's `instruction` text.

### Per-tool bridging filler reference

The 6 separate submit-tools were consolidated into one `submitRates` tool with a `productCategory` discriminator. This shrinks the AI Agent context window by ~1000 tokens per turn.

| Tool                              | Instant ack example      | Bridging filler example                       |
|-----------------------------------|--------------------------|-----------------------------------------------|
| `startCallSession`                | (silent — pre-greeting)  | (silent — pre-greeting)                       |
| `getCallSession`                  | "One sec."               | "Let me check where we left off."             |
| `closeCallSession`                | "Got it, thanks."        | "Let me wrap up my notes."                    |
| `submitRates` (cd)                | "Got it."                | "Let me log those CD rates now."              |
| `submitRates` (money_market)      | "Perfect."               | "Let me record those Money Market rates."     |
| `submitRates` (ira)               | "Noted."                 | "Let me note that IRA rate."                  |
| `submitRates` (savings)           | "Alright."               | "Let me save that savings rate."              |
| `submitRates` (checking)          | "Sure."                  | "Let me save that checking rate."             |
| `submitRates` (special)           | "Appreciate that."       | "Let me write that special down."             |
| `scheduleCallback`                | "Of course."             | "Let me get that callback on the books."      |
| `markDNC`                         | "Understood, apologies." | "Let me take care of that right away."        |
| `recordMergerAcquisition`         | "Thanks for letting me know." | "Let me note the merger details."        |
| `Retrieve`                        | "Hmm, let me see."       | "Let me look that up for you."                |
| `Escalate`                        | (none — speak final line first) | "I'm connecting you with a specialist now." |
| `Complete`                        | (none — banker has said goodbye) | (no output after Complete)              |

---

## RETURN_TO_CONTROL Tools

### Complete

Ends the call after all data is collected and the banker says goodbye.

```json
{
  "toolName": "Complete",
  "toolType": "RETURN_TO_CONTROL",
  "description": "End the call after all rate collection steps are done and the banker has said goodbye",
  "instruction": {
    "instruction": "Invoke ONLY after: (1) all applicable rate steps 1-11 are complete, (2) closeCallSession API has been called, (3) banker name has been collected, (4) banker has said goodbye. NEVER invoke Complete before the banker's goodbye."
  },
  "inputSchema": {
    "type": "object",
    "properties": {
      "completion_type": {
        "type": "string",
        "enum": ["full", "spot_check", "incomplete", "voicemail", "email"],
        "description": "How the call completed"
      },
      "banker_name": {
        "type": "string",
        "description": "Name of the banker collected at Step 12"
      }
    },
    "required": ["completion_type"]
  },
  "userInteractionConfiguration": {
    "isUserConfirmationRequired": false
  }
}
```

**When to invoke:**
- After full data collection, closeCallSession called, banker name collected, banker says goodbye → `completion_type="full"`
- No-change spot check completed → `completion_type="spot_check"`
- Callback, refusal, incomplete data → `completion_type="incomplete"`
- Voicemail left → `completion_type="voicemail"`
- Email arranged → `completion_type="email"`

**Never invoke when:**
- Banker still has pending questions
- Rate steps are incomplete
- Banker has not said goodbye

---

### Escalate

Transfers the call to a human agent when Ryan cannot resolve the banker's issue.

```json
{
  "toolName": "Escalate",
  "toolType": "RETURN_TO_CONTROL",
  "description": "Escalate to a human agent when Ryan cannot adequately assist",
  "instruction": {
    "instruction": "Escalate when the banker requests a human, or when a technical or policy issue cannot be resolved by the AI. Before escalating, gently confirm with the banker that they still want to speak with someone — they may change their mind."
  },
  "inputSchema": {
    "type": "object",
    "properties": {
      "reason": {
        "type": "string",
        "description": "Reason for escalation"
      },
      "bankerIntent": {
        "type": "string",
        "description": "Brief phrase describing what the banker was trying to accomplish"
      },
      "sentiment": {
        "type": "string",
        "enum": ["positive", "neutral", "frustrated"],
        "description": "Banker emotional state"
      }
    },
    "required": ["reason"]
  },
  "userInteractionConfiguration": {
    "isUserConfirmationRequired": false
  }
}
```

---

## MODEL_CONTEXT_PROTOCOL Tools (MCP)

### Retrieve

Searches the Q in Connect knowledge base for rate collection FAQ and policy information.

```json
{
  "toolName": "Retrieve",
  "toolType": "MODEL_CONTEXT_PROTOCOL",
  "toolId": "aws_service__qconnect_Retrieve",
  "instruction": {
    "instruction": "Search the knowledge base using semantic search to find relevant information about rate collection procedures, product definitions, or bank-specific policies."
  },
  "overrideInputValues": [
    {
      "jsonPath": "$.retrievalConfiguration.knowledgeSource.assistantAssociationIds",
      "value": {
        "constant": {
          "type": "JSON_STRING",
          "value": "[\"<assistantAssociationId>\"]"
        }
      }
    },
    {
      "jsonPath": "$.assistantId",
      "value": {
        "constant": {
          "type": "STRING",
          "value": "{{$.assistantId}}"
        }
      }
    }
  ],
  "userInteractionConfiguration": {
    "isUserConfirmationRequired": false
  }
}
```

---

## AgentCore Gateway Tools (Bank Rate API)

All tools below are routed through the AgentCore Gateway to the Bank Rate Collection Lambda.

### startCallSession
Creates a session record at the start of every call. Returns a `sessionId` used in all subsequent calls.

### getCallSession
Retrieves the current call session state — useful for resuming after interruption.

### closeCallSession
Finalises the session with `completionType` and `bankerName`. Must be called before `Complete`.

### submitRates (UNIFIED)
Single endpoint for all rate submissions. The `productCategory` discriminator selects:
- `cd`           → Steps 1–4 (`tier=standard_10k` or `jumbo_100k`, `termRates[]`)
- `money_market` → Steps 5–6 (`mmType=standard` or `relationship`, `balanceTiers[]`)
- `ira`          → Steps 7–8 (`iraType=liquid` or `fixed_12mo`)
- `savings`      → Step 9 (rate/apy at $2,500)
- `checking`     → Step 10 (rate/apy at $2,500)
- `special`      → Step 11 (full 8-field special record — call once per special)

Set `notOffered: true` when the bank does not offer the product.

### scheduleCallback
Records a callback request when the banker is unavailable.

### markDNC
Adds a phone number to the Do Not Call registry. Use **only** for explicit DNC requests.

### recordMergerAcquisition
Records a bank merger or acquisition event.

---

## Tool Invocation Sequence (Happy Path)

```
Call connects
  → startCallSession                                  (session init)
  → [conversation: Steps 1-3]
  → submitRates(productCategory=cd, tier=standard_10k)
  → [conversation: Step 4]
  → submitRates(productCategory=cd, tier=jumbo_100k)
  → [conversation: Step 5]
  → submitRates(productCategory=money_market, mmType=standard)
  → [conversation: Step 6]
  → submitRates(productCategory=money_market, mmType=relationship)  OR notOffered=true
  → [conversation: Step 7]
  → submitRates(productCategory=ira, iraType=liquid)                OR notOffered=true
  → [conversation: Step 8]
  → submitRates(productCategory=ira, iraType=fixed_12mo)            OR notOffered=true
  → [conversation: Step 9]
  → submitRates(productCategory=savings)                            OR notOffered=true
  → [conversation: Step 10]
  → submitRates(productCategory=checking)                           OR notOffered=true
  → [conversation: Step 11 — per special]
  → submitRates(productCategory=special, ...)                       (repeat for each special)
  → [conversation: Step 12 — collect banker name, say goodbye]
  → closeCallSession(completionType="full", bankerName)
  → Complete(completion_type="full", banker_name)
```
