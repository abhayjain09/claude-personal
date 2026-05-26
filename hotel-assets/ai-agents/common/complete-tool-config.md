# Complete Tool Configuration

## Overview

The Complete tool marks a self-service interaction as successfully resolved. It signals that the customer's request has been fully addressed and the conversation can end gracefully.

## Tool Configuration

```json
{
  "toolName": "Complete",
  "toolType": "RETURN_TO_CONTROL",
  "description": "Close conversation when customer has no more questions",
  "instruction": {
    "instruction": "Mark the conversation as complete ONLY after confirming the customer has no additional questions or needs."
  },
  "inputSchema": {
    "type": "object",
    "properties": {
      "reason": {
        "type": "string",
        "description": "Reason of completion"
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

The Complete tool is a `RETURN_TO_CONTROL` tool. You **MUST** provide:
- ✅ `inputSchema` (required)

You **CAN** also set:
- ✅ `description`
- ✅ `instruction`
- ✅ `userInteractionConfiguration`

## Tool Details

- **Tool Name**: `Complete`
- **Tool Type**: `RETURN_TO_CONTROL`
- **Agent Type**: Self-Service only (NOT used in Agent Assistance)
- **Purpose**: Mark successful resolution of customer request

## When to Use

Use the Complete tool when:
1. The customer's original request has been fully resolved
2. All requested actions have been completed successfully
3. The customer has confirmed satisfaction or indicated they have no further questions
4. The conversation has reached a natural conclusion

## When NOT to Use

Do NOT use the Complete tool when:
1. The customer still has pending questions or requests
2. An action is still in progress or awaiting confirmation
3. The customer has expressed dissatisfaction
4. There are unresolved issues from the conversation
5. The customer needs to be transferred to a human agent (use Escalate instead)

## Good Examples

### Example 1: Successful Booking Completion
```
Customer: "Great, that reservation looks perfect. Thank you!"

<message>
Wonderful! Your reservation is all set. You'll receive a confirmation email shortly with all the details. Thank you for choosing us, and we look forward to welcoming you! Have a great day.
</message>

[Complete tool]
```

### Example 2: Information Request Fulfilled
```
Customer: "That answers my question about the cancellation policy. Thanks for your help!"

<message>
You're welcome! I'm glad I could help clarify our cancellation policy for you. If you have any other questions in the future, don't hesitate to reach out. Have a wonderful day!
</message>

[Complete tool]
```

### Example 3: Successful Modification
```
Customer: "Perfect, the date change went through. That's all I needed."

<message>
Excellent! Your reservation has been updated to the new dates. You'll receive an updated confirmation email shortly. Thank you for letting us help you today. Enjoy your stay!
</message>

[Complete tool]
```

### Example 4: Customer Confirms No Further Needs
```
Customer: "No, that's everything. Thanks!"

<message>
You're very welcome! Thank you for reaching out today. If you need anything else before your visit, we're here to help. Take care!
</message>

[Complete tool]
```

## Bad Examples (Avoid These)

### Bad Example 1: Premature Completion
```
Customer: "Can you also check if there's parking available?"

❌ INCORRECT: Using Complete tool when customer has asked another question.

Why it's wrong: The customer has a follow-up question that hasn't been addressed yet.
```

### Bad Example 2: Unconfirmed Action
```
AI: "I've initiated the cancellation. Would you like me to proceed?"
Customer: [No response yet]

❌ INCORRECT: Using Complete tool before customer confirms.

Why it's wrong: The customer hasn't confirmed the action. Wait for explicit confirmation.
```

### Bad Example 3: Dissatisfied Customer
```
Customer: "I guess that will have to do, but I'm not happy about it."

❌ INCORRECT: Using Complete tool when customer expresses dissatisfaction.

Why it's wrong: Customer has indicated dissatisfaction. Consider offering alternatives or escalating to a human agent.
```

### Bad Example 4: Pending Issues
```
Customer: "The booking is done, but I still need to know about the shuttle service."

❌ INCORRECT: Using Complete tool when there's still an open question.

Why it's wrong: Customer has an additional question about shuttle service that needs to be addressed first.
```

## Completion Message Guidelines

When completing a conversation:
1. Confirm what was accomplished
2. Mention any follow-up the customer can expect (confirmation email, etc.)
3. Thank the customer warmly
4. Offer future assistance if needed
5. End with a positive, friendly closing

Keep the closing message:
- Warm and appreciative
- Concise (not overly long)
- Voice-friendly (suitable for speech synthesis)
- Free of technical jargon

## Relationship with Escalate Tool

- **Complete**: Customer's needs were fully met through self-service
- **Escalate**: Customer needs human assistance to resolve their request

If uncertain whether to Complete or Escalate, ask the customer if there's anything else they need help with before making the decision.
