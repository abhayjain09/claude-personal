# Retrieve Tool Configuration

## Overview

The Retrieve tool searches the knowledge base to find relevant information for answering customer questions. It accesses FAQ documents, policies, procedures, and other reference materials.

## Tool Configuration

```json
{
  "toolName": "Retrieve",
  "toolType": "MODEL_CONTEXT_PROTOCOL",
  "toolId": "aws_service__qconnect_Retrieve",
  "instruction": {
    "instruction": "Search the knowledge base using semantic search to find relevant information."
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

## CRITICAL: MCP Tool Restrictions

The Retrieve tool is a `MODEL_CONTEXT_PROTOCOL` tool. You **CANNOT** override:
- ❌ `inputSchema`
- ❌ `title`
- ❌ `description`

You **CAN** override:
- ✅ `instruction`
- ✅ `overrideInputValues`
- ✅ `userInteractionConfiguration`

## Tool Details

- **Tool Name**: `Retrieve`
- **Tool Type**: `MODEL_CONTEXT_PROTOCOL`
- **Tool ID**: `aws_service__qconnect_Retrieve`
- **Agent Type**: Both Self-Service AND Agent Assistance
- **Purpose**: Search knowledge base for relevant information

## When to Use

Use the Retrieve tool when:
1. Customer asks about policies (cancellation, refund, etc.)
2. Customer asks FAQ-type questions
3. Customer needs information about procedures or processes
4. Agent needs to look up reference information
5. Customer asks "how do I..." or "what is..." questions
6. You need factual information not available from other tools

## When NOT to Use

Do NOT use the Retrieve tool when:
1. Customer is asking about their specific account or reservation (use API tools)
2. Customer wants to take an action (book, cancel, modify)
3. The information is already in the conversation history
4. You've already retrieved the same information in this conversation

## Good Examples

### Example 1: Policy Question (Self-Service)
```
Customer: "What's your cancellation policy?"

<message>
Let me look up our cancellation policy for you.
</message>

[Retrieve tool with query: "cancellation policy"]

<message>
Our cancellation policy allows free cancellation up to 24 hours before your check-in date. Cancellations made within 24 hours may be subject to a one-night charge. Would you like me to help you with anything else?
</message>
```

### Example 2: FAQ Question (Self-Service)
```
Customer: "Do you have parking available?"

<message>
Let me check on parking options for you.
</message>

[Retrieve tool with query: "parking availability amenities"]

<message>
Yes, we offer both self-parking and valet parking at most of our locations. Self-parking is typically complimentary for guests, while valet service is available for an additional fee. The specific options may vary by property. Is there a particular location you're asking about?
</message>
```

### Example 3: Procedure Question (Agent Assistance)
```
Agent: "What's the process for handling a disputed charge?"

<message>
Let me find our dispute resolution procedures for you.
</message>

[Retrieve tool with query: "dispute resolution charge dispute process"]

<message>
According to our procedures, disputed charges should be handled as follows: First, verify the charge details with the customer. Second, check if the charge was authorized. If the dispute is valid, submit a refund request through the billing system. For disputes over $100, supervisor approval is required. The customer should receive resolution within 5-7 business days.
</message>
```

### Example 4: Product Information (Self-Service)
```
Customer: "What amenities are included with the premium room?"

<message>
Let me look up the premium room amenities for you.
</message>

[Retrieve tool with query: "premium room amenities included features"]

<message>
Our premium rooms include complimentary breakfast, access to the executive lounge, high-speed WiFi, a mini-bar with select complimentary items, and late checkout upon request. You'll also enjoy upgraded toiletries and a pillow menu. Would you like to book a premium room?
</message>
```

## Bad Examples (Avoid These)

### Bad Example 1: Using for Account-Specific Information
```
Customer: "What's my reservation confirmation number?"

❌ INCORRECT: Using Retrieve tool for customer-specific data.

Why it's wrong: Retrieve searches the knowledge base, not customer records. Use the appropriate API tool (getCustomerReservations) instead.
```

### Bad Example 2: Redundant Retrieval
```
[Already retrieved cancellation policy earlier in conversation]
Customer: "So just to confirm, I can cancel for free?"

❌ INCORRECT: Using Retrieve again for the same information.

Why it's wrong: The information was already retrieved. Reference the previous response instead of making another retrieval call.
```

### Bad Example 3: Action Request
```
Customer: "I want to cancel my reservation."

❌ INCORRECT: Using Retrieve tool for an action request.

Why it's wrong: Customer wants to take an action, not get information. Use the cancelReservation API tool instead.
```

### Bad Example 4: Vague Query
```
Customer: "Tell me about your hotel."

❌ INCORRECT: Using Retrieve with query: "hotel"

Why it's wrong: Query is too vague. Ask the customer what specific information they're looking for, or use a more specific query like "hotel amenities overview" or "hotel location features".
```

## Query Best Practices

When formulating retrieval queries:
1. **Be specific**: Use relevant keywords from the customer's question
2. **Include context**: Add industry-specific terms when helpful
3. **Avoid single words**: Use phrases that capture the intent
4. **Match customer language**: Use terms the customer used when appropriate

Good query examples:
- "cancellation policy refund"
- "check-in time early arrival"
- "pet policy pet-friendly rooms"
- "loyalty program points earning"

Poor query examples:
- "policy" (too vague)
- "help" (not specific)
- "customer question" (not relevant to content)

## Response Guidelines

After retrieving information:
1. Summarize the key points relevant to the customer's question
2. Present information in a conversational, voice-friendly manner
3. Avoid reading verbatim from documents
4. Offer to provide more details if needed
5. Don't mention "knowledge base" or "database" to customers

## Relationship with Other Tools

- **Retrieve**: Gets information from knowledge base (policies, FAQs, procedures)
- **API Tools**: Gets customer-specific data (reservations, accounts, orders)
- **Escalate**: Transfers to human when information isn't sufficient
- **GenerateNotes**: Summarizes conversations (Agent Assistance only)

Use Retrieve for general information, API tools for customer-specific data.
