# Escalate Tool Configuration

## Overview

The Escalate tool transfers self-service conversations to human agents when the AI cannot fully resolve the customer's request. It captures structured context to help the human agent quickly understand the situation.

## Tool Configuration

```json
{
  "toolName": "Escalate",
  "toolType": "RETURN_TO_CONTROL",
  "description": "Escalate to human agent when customer issue cannot be solved",
  "instruction": {
    "instruction": "Escalate the conversation to a human agent when you cannot provide adequate assistance or when the customer request requires human intervention."
  },
  "inputSchema": {
    "type": "object",
    "properties": {
      "reason": {
        "type": "string",
        "description": "Reason of escalation"
      }
    },
    "required": ["reason"]
  },
  "userInteractionConfiguration": {
    "isUserConfirmationRequired": false
  }
}
```

## CRITICAL: RETURN_TO_CONTROL Tool Requirements

The Escalate tool is a `RETURN_TO_CONTROL` tool. You **MUST** provide:
- ✅ `inputSchema` (required)

You **CAN** also set:
- ✅ `description`
- ✅ `instruction`
- ✅ `userInteractionConfiguration`

## Tool Details

- **Tool Name**: `Escalate`
- **Tool Type**: `RETURN_TO_CONTROL`
- **Agent Type**: Self-Service only (NOT used in Agent Assistance)
- **Purpose**: Transfer customer to human agent with context

## Extended Input Schema (Optional)

For more detailed escalation context, you can use an extended schema:

```json
{
  "type": "object",
  "properties": {
    "reason": {
      "type": "string",
      "description": "Reason of escalation"
    },
    "customerIntent": {
      "type": "string",
      "description": "A brief phrase (10-15 words) describing what the customer wants to accomplish"
    },
    "sentiment": {
      "type": "string",
      "description": "Customer's emotional state during the conversation",
      "enum": ["positive", "neutral", "frustrated"]
    },
    "escalationCategory": {
      "type": "string",
      "description": "Category for the escalation reason",
      "enum": [
        "complex_booking",
        "technical_issue",
        "customer_frustration",
        "policy_exception",
        "out_of_scope",
        "other"
      ]
    }
  },
  "required": ["reason"]
}
```

## Field Descriptions

### customerIntent
A concise 10-15 word phrase capturing the customer's goal. This helps the human agent immediately understand what the customer is trying to accomplish.

### sentiment
The customer's emotional state:
- **positive**: Customer is happy, patient, or satisfied with the interaction
- **neutral**: Customer is calm and matter-of-fact
- **frustrated**: Customer has expressed frustration, impatience, or dissatisfaction

### escalationSummary
A detailed summary (max 500 characters) that includes:
- What the customer originally requested
- What actions were attempted by the AI
- Why escalation is necessary
- Any relevant context the human agent needs

### escalationReason
The category that best describes why escalation is needed:
- **complex_booking**: Request requires special handling (group bookings, wedding blocks, corporate accounts)
- **technical_issue**: System errors or technical problems preventing resolution
- **customer_frustration**: Customer has expressed frustration or requested human assistance
- **policy_exception**: Request requires policy override or special authorization
- **out_of_scope**: Request is outside the AI's capabilities
- **other**: Doesn't fit other categories

## When to Use

Use the Escalate tool when:
1. The customer explicitly requests to speak with a human agent
2. The request is too complex for self-service (e.g., wedding blocks, 5+ room bookings)
3. The customer shows signs of frustration after multiple attempts
4. A policy exception or special authorization is required
5. Technical issues prevent completing the request
6. The request is outside the AI's available tools and capabilities

## Good Examples

### Example 1: Complex Request Escalation
```
Customer: "I need to book 15 rooms for a corporate retreat next month."

<message>
I'd be happy to help with your corporate retreat booking. For group reservations of this size, I'll connect you with one of our specialists who can ensure everything is set up perfectly for your team.
</message>

[Escalate tool with:
  customerIntent: "Book 15 hotel rooms for corporate retreat next month"
  sentiment: "positive"
  escalationSummary: "Customer needs to book 15 rooms for a corporate retreat. This exceeds self-service limits for group bookings. Customer is positive and cooperative. Recommend corporate sales team handle for group rates and amenities."
  escalationReason: "complex_booking"
]
```

### Example 2: Customer Frustration Escalation
```
Customer: "This is the third time I've tried to change my reservation and it keeps failing. I just want to talk to someone!"

<message>
I completely understand your frustration, and I apologize for the difficulty you've experienced. Let me connect you with a team member right away who can help resolve this for you.
</message>

[Escalate tool with:
  customerIntent: "Modify existing hotel reservation after multiple failed attempts"
  sentiment: "frustrated"
  escalationSummary: "Customer has attempted to modify reservation multiple times without success. Customer explicitly requested human assistance. Previous attempts encountered errors. Immediate attention recommended."
  escalationReason: "customer_frustration"
]
```

### Example 3: Policy Exception Escalation
```
Customer: "I know check-in is at 3 PM, but my flight lands at 8 AM. Is there any way I can get early check-in?"

<message>
I'd love to help arrange early check-in for you. Let me connect you with our front desk team who can check availability and make special arrangements for your early arrival.
</message>

[Escalate tool with:
  customerIntent: "Request early hotel check-in due to early flight arrival"
  sentiment: "neutral"
  escalationSummary: "Customer's flight arrives at 8 AM, standard check-in is 3 PM. Customer requesting early check-in accommodation. This requires front desk approval based on room availability."
  escalationReason: "policy_exception"
]
```

## Bad Examples (Avoid These)

### Bad Example 1: Vague Summary
```
❌ INCORRECT:
[Escalate tool with:
  customerIntent: "Help with booking"
  sentiment: "neutral"
  escalationSummary: "Customer needs help."
  escalationReason: "other"
]

Why it's wrong: The summary is too vague and doesn't provide actionable context for the human agent.
```

### Bad Example 2: Missing Context
```
❌ INCORRECT:
[Escalate tool with:
  customerIntent: "Change reservation"
  sentiment: "frustrated"
  escalationSummary: "Customer is frustrated."
  escalationReason: "customer_frustration"
]

Why it's wrong: Doesn't explain what the customer tried to change, what went wrong, or what specific help is needed.
```

### Bad Example 3: Wrong Sentiment Assessment
```
Customer: "No problem, I understand you can't help with this. Can you transfer me to someone who can?"

❌ INCORRECT:
[Escalate tool with:
  sentiment: "frustrated"
  ...
]

Why it's wrong: Customer is being understanding and polite, not frustrated. Sentiment should be "neutral" or "positive".
```

### Bad Example 4: Unnecessary Escalation
```
Customer: "What time is check-out?"

❌ INCORRECT: Using Escalate tool for a simple FAQ question.

Why it's wrong: This is a simple question that can be answered from the knowledge base. No escalation needed.
```

## Escalation Message Guidelines

When escalating, always:
1. Acknowledge the customer's request
2. Explain that you're connecting them with someone who can help
3. Set positive expectations about the transfer
4. Be warm and reassuring

Do NOT:
1. Apologize excessively or make the customer feel like a burden
2. Promise specific outcomes the human agent may not be able to deliver
3. Blame systems or processes for the escalation
4. Leave the customer without explanation before escalating
