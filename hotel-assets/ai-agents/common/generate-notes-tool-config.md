# GenerateNotes Tool Configuration

## Overview

The GenerateNotes tool creates conversation summaries for human agents during agent assistance interactions. It helps agents document customer interactions efficiently and accurately.

## Tool Configuration

```json
{
  "toolName": "GenerateNotes",
  "toolType": "MODEL_CONTEXT_PROTOCOL",
  "toolId": "aws_service__qconnect_QueryAssistant",
  "instruction": {
    "instruction": "Generate comprehensive notes summarizing the customer interaction."
  },
  "overrideInputValues": [
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

## CRITICAL: MCP Tool Restrictions

The GenerateNotes tool is a `MODEL_CONTEXT_PROTOCOL` tool. You **CANNOT** override:
- ❌ `inputSchema`
- ❌ `title`
- ❌ `description`

You **CAN** override:
- ✅ `instruction`
- ✅ `overrideInputValues`
- ✅ `userInteractionConfiguration`

## Tool Details

- **Tool Name**: `GenerateNotes`
- **Tool Type**: `MODEL_CONTEXT_PROTOCOL`
- **Tool ID**: `aws_service__qconnect_QueryAssistant`
- **Agent Type**: Agent Assistance only (NOT used in Self-Service)
- **Purpose**: Generate conversation summaries and notes for human agents

## When to Use

Use the GenerateNotes tool when:
1. The human agent requests a summary of the customer conversation
2. The agent needs documentation for the interaction
3. The agent is wrapping up a call and needs notes for the record
4. The agent asks for help capturing key points from the conversation

## When NOT to Use

Do NOT use the GenerateNotes tool when:
1. The agent hasn't requested notes or a summary
2. The conversation is still in early stages with minimal content
3. The agent is asking for information lookup (use Retrieve instead)
4. The agent needs real-time assistance during the conversation

## Good Examples

### Example 1: End-of-Call Summary Request
```
Agent: "Can you generate notes for this call?"

<message>
I'll create a summary of this interaction for you.
</message>

[GenerateNotes tool]

<message>
Here's a summary of the call: The customer called regarding their hotel reservation for next weekend. They requested to change their check-in date from Saturday to Friday and add an extra night. The modification was completed successfully, and the customer was informed of the updated total. No issues or complaints were raised.
</message>
```

### Example 2: Specific Summary Request
```
Agent: "I need notes about what the customer's main concerns were."

<message>
Let me summarize the customer's key concerns from this conversation.
</message>

[GenerateNotes tool]

<message>
The customer's main concerns were: First, they were worried about the cancellation policy for their upcoming reservation due to potential travel changes. Second, they wanted clarification on whether their loyalty points would be affected if they modified the booking. Both concerns were addressed during the call.
</message>
```

### Example 3: Documentation for Follow-up
```
Agent: "Can you create notes I can use for the follow-up ticket?"

<message>
I'll generate notes suitable for your follow-up documentation.
</message>

[GenerateNotes tool]

<message>
Follow-up notes: Customer reported an issue with their billing statement showing a duplicate charge. The charge was verified as a system error. A refund request has been submitted and should process within 3-5 business days. Customer requested email confirmation once the refund is complete. Contact preference: email at the address on file.
</message>
```

## Bad Examples (Avoid These)

### Bad Example 1: Unsolicited Notes
```
[Agent is in the middle of helping customer]

❌ INCORRECT: Using GenerateNotes without agent request.

Why it's wrong: The agent didn't ask for notes. Focus on helping with the current interaction.
```

### Bad Example 2: Using for Information Lookup
```
Agent: "What's our refund policy?"

❌ INCORRECT: Using GenerateNotes to answer policy questions.

Why it's wrong: This is an information request, not a notes request. Use the Retrieve tool instead.
```

### Bad Example 3: Incomplete Conversation
```
Agent: "Generate notes."
[Conversation just started with only a greeting exchanged]

❌ INCORRECT: Generating notes when there's no substantive content.

Why it's wrong: There's nothing meaningful to summarize yet. Wait until there's actual conversation content.
```

## Notes Content Guidelines

Generated notes should include:
1. **Customer's reason for contact**: Why did they reach out?
2. **Key issues or requests**: What did they need help with?
3. **Actions taken**: What was done to help them?
4. **Resolution status**: Was the issue resolved? Any pending items?
5. **Follow-up needed**: Any required next steps?

Notes should be:
- Concise and factual
- Free of personal opinions or judgments
- Professional in tone
- Organized logically
- Easy for other agents to understand

## Formatting Notes

When presenting notes to the agent:
- Use clear, readable formatting
- Organize information logically
- Highlight any action items or follow-ups
- Keep the summary focused and relevant
- Use HTML formatting if structure helps readability (single-line HTML)

## Relationship with Other Tools

- **GenerateNotes**: Creates summaries of conversations (Agent Assistance)
- **Retrieve**: Looks up information from knowledge base (Both agent types)
- **Escalate**: Transfers to human agent (Self-Service only)
- **Complete**: Marks successful resolution (Self-Service only)

GenerateNotes is exclusively for Agent Assistance mode where a human agent is already handling the customer and needs help with documentation.
