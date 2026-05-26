CUSTOM VOICE ARCHITECTURE - Guaranteed Pre-Tool Acknowledgment
Generated: 2026-05-11

Goal
----
Guarantee that the caller hears a short acknowledgment such as "Let me check that"
before any hotel lookup, booking action, retrieval, or other backend tool call starts.

Why the current design cannot guarantee it
------------------------------------------
Current path:

  ConnectParticipantWithLexBot
    -> Lex AmazonQinConnect intent
    -> Q in Connect orchestration agent
    -> tool call
    -> response speech

The silence happens inside one Q in Connect orchestration turn. Neither Connect
flow nor Lex gets a supported mid-turn hook before the tool call begins.

Recommended replacement
-----------------------
Replace the Q in Connect orchestration path with a custom Lex + Lambda turn
orchestrator.

New path:

  Amazon Connect flow
    -> ConnectParticipantWithLexBot
    -> Custom Lex V2 bot intent
    -> Lex fulfillment code hook enabled
    -> Lex fulfillment updates startResponse: "Let me check that"
    -> Orchestrator Lambda / Step Functions
    -> Hotel API / knowledge retrieval / business tools
    -> final response returned to Lex
    -> Nova Sonic streams final speech back to caller

This is the key change: the guaranteed acknowledgment moves from model behavior
to the Lex runtime itself.

Core guarantee
--------------
For every intent that can trigger backend work:

1. `fulfillmentCodeHook.enabled = true`
2. `fulfillmentUpdatesSpecification.active = true`
3. `startResponse.delayInSeconds = 0` or `1`
4. `startResponse.messageGroups[0] = "Let me check that for you."`

Because Lex owns the turn and the fulfillment Lambda is running behind the hook,
Lex can speak the start response immediately and optionally keep speaking update
responses while the backend work continues.

Target architecture
-------------------

1. Amazon Connect
   Keep Connect as the telephony and voice session entry point.
   The contact flow still answers the call, sets the voice, and hands the
   caller to Lex.

2. Custom Lex V2 bot
   Replace `AmazonQinConnect` with a custom bot design.
   Use one of these two patterns:

   Pattern A - Domain intents
   - `SearchHotelsIntent`
   - `CreateBookingIntent`
   - `ModifyReservationIntent`
   - `CancelReservationIntent`
   - `GetReservationsIntent`
   - `FallbackIntent`

   Pattern B - Single router intent
   - `HotelAssistantIntent`
   - fulfillment Lambda classifies the request and decides the tool call

   Recommendation: start with Pattern B for parity with the current free-form
   assistant behavior, then split into domain intents only if you need tighter
   validation and simpler prompts.

3. Orchestrator Lambda
   A Lambda function becomes the turn controller.
   Responsibilities:
   - read the customer utterance and session attributes
   - identify the required operation
   - validate required inputs
   - call the hotel API directly or through a thin internal gateway
   - call knowledge retrieval if needed
   - build a caller-safe final response for Lex
   - set session state for the next turn

4. Optional Step Functions for long-running work
   If any action can take longer than a few seconds, place Step Functions behind
   the fulfillment Lambda.
   Flow:
   - Lambda starts the workflow
   - Lex speaks `startResponse`
   - Lex speaks `updateResponse` every 2-3 seconds while polling continues
   - workflow result is returned to the Lambda
   - Lambda returns final message to Lex

5. Hotel API and knowledge layer
   Preserve the current hotel operations:
   - `searchHotels`
   - `createBooking`
   - `cancelReservation`
   - `getCustomerReservations`
   - `modifyReservation`

   These can remain the same backend APIs. The main change is that the caller
   no longer reaches them through Q in Connect tool invocation.

Reference turn sequence
-----------------------

Caller says: "Can you find hotels in Seattle for next weekend?"

1. Connect sends audio to Lex.
2. Lex resolves the custom intent.
3. Lex immediately plays the configured fulfillment `startResponse`:
   "Let me check that for you."
4. Lex invokes the fulfillment Lambda.
5. Lambda normalizes the request and calls `searchHotels`.
6. If the search is still running, Lex can emit `updateResponse`:
   "Still checking availability."
7. Lambda returns the result text.
8. Lex/Nova Sonic speaks the final answer.

This sequence provides the missing guarantee that the current architecture does
not have.

Recommended per-turn response policy
------------------------------------

Use a small fixed set of runtime-owned filler messages, not model-generated
filler. Examples:

- Search: "Let me check that for you."
- Reservation lookup: "Let me pull up your reservation."
- Booking change: "Let me review that booking."
- Cancellation: "Let me look into that reservation."
- Fallback long task: "One moment while I check."

Runtime-owned filler is preferable because it is deterministic and testable.

Background noise options
------------------------
If you want something other than silence during longer waits, there are two
safe patterns.

Option 1 - Lex update responses
Use `updateResponse` every 2-3 seconds with short spoken progress messages.
This is the simplest and most robust option.

Option 2 - Short earcon or audio clip in a custom Connect loop
If you truly want ambience rather than words, create a flow-controlled wait loop
outside Q in Connect:
 - play a short prompt or earcon
 - invoke/poll backend status
 - repeat until result is ready

This requires Connect flow ownership of the turn state and is more complex than
Lex update responses. For production voice UX, short spoken updates are usually
better than continuous background noise.

Recommended implementation choice
---------------------------------
Choose this as the primary implementation:

  Connect -> Custom Lex bot -> fulfillment Lambda -> hotel APIs

Reasons:
- preserves Nova Sonic voice experience
- guarantees pre-tool acknowledgment through Lex runtime behavior
- keeps the hotel API surface unchanged
- avoids a full custom telephony loop in Connect
- simpler to test than Q in Connect orchestration

Detailed component design
-------------------------

Connect flow
- Keep the opening greeting and voice selection.
- Replace the current `ConnectParticipantWithLexBot` target bot with a new
  custom Lex bot alias.
- Remove Q in Connect specific wiring from Lex session attributes.
- Keep escalation and disconnect branches in Connect.

Lex bot
- Locale: `en_US`
- Speech model: Nova Sonic
- Intent strategy:
  - start with one router intent plus fallback, or
  - use explicit domain intents if you want tighter slot control
- Enable dialog code hook only if slot validation is needed.
- Enable fulfillment code hook for every action intent.
- Configure `fulfillmentUpdatesSpecification` on every action intent.

Orchestrator Lambda
- Input:
  - utterance text
  - intent name
  - slots
  - session attributes
  - caller identity / customer context
- Processing:
  - classify action
  - resolve parameters
  - fetch customer reservations when required
  - invoke hotel API
  - handle retries, timeouts, and safe caller phrasing
- Output:
  - concise spoken answer
  - next action for Lex
  - updated session attributes

Data contracts
- Preserve current payloads from the hotel API OpenAPI spec where possible.
- Add an internal normalized response contract for Lambda, for example:
  - `status`: success | retryable_error | terminal_error
  - `spokenMessage`: caller-safe text
  - `displayPayload`: optional structured metadata
  - `sessionAttributes`: key/value map

Failure handling
----------------
For backend failures or timeouts:
- start response still plays immediately
- Lambda returns a safe apology and next step
- Connect can transfer to queue for escalation when needed

Examples:
- "I’m still checking, but this is taking longer than expected."
- "I’m sorry, I couldn’t complete that change right now. I can connect you to an agent."

Migration plan
--------------

Phase 1 - Build the custom bot path
- create new Lex bot and alias
- build one router intent with fulfillment code hook
- implement Lambda for `searchHotels` only
- wire a test Connect flow to the new bot

Phase 2 - Add all hotel actions
- `getCustomerReservations`
- `createBooking`
- `modifyReservation`
- `cancelReservation`

Phase 3 - Add progress responses
- configure `startResponse`
- configure `updateResponse`
- add timeout handling and escalation

Phase 4 - Cutover
- point the main Connect flow to the new Lex bot alias
- keep the Q in Connect path as rollback until validation is complete

Acceptance criteria
-------------------

1. After any caller request that triggers backend work, the caller hears a
   spoken acknowledgment within 1 second.
2. No action intent has a silent gap longer than 2 seconds without either a
   start response, update response, or final answer.
3. Hotel API operations produce the same business result as the current tool
   set.
4. Escalation and completion behavior remain available from the Connect flow.

Tradeoffs
---------

Pros
- deterministic filler before backend work
- simpler latency reasoning
- easier observability per turn
- no dependence on model obedience for acknowledgments

Cons
- you lose Q in Connect orchestration convenience
- more custom code in Lambda
- more explicit intent and slot design work
- knowledge-base and action orchestration move into your code

Decision
--------
If guaranteed "let me check that" before every tool call is a hard product
requirement, move off `AmazonQinConnect` for the voice turn path and implement
the custom Lex fulfillment architecture above.