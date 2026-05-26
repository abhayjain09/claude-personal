# Identity and Authentication Flow

## Short Summary

This deployment uses two layers of authentication:

- Inbound authentication: the caller invokes the gateway with a JWT.
- Outbound authentication: the gateway calls backend APIs with credentials from a credential provider.

## Flow

1. The customer initiates a request through the conversational entry point.
2. The request is routed through the conversational runtime and AI agent.
3. When the agent needs a tool, it calls the gateway with a JWT.
4. The gateway validates the JWT using the configured discovery URL.
5. The gateway checks that the token's `aud` claim matches the gateway's `Allowed Audience`.
6. If valid, the gateway invokes the target.
7. The gateway injects the backend API credential and calls the backend API.
8. The hotel API returns the result through the gateway back to the AI agent.

## Why Allowed Audience Matters

`Allowed Audience` validates the JWT `aud` claim.

In this setup, it is set to the gateway ID after the gateway is created. That ensures a valid JWT cannot be reused against a different gateway, because the audience would not match.

## Inbound Authentication

Inbound authentication is caller to gateway.

- The gateway uses the configured OpenID discovery URL.
- It validates the JWT signature and issuer.
- It checks that `aud` matches the configured gateway ID.
- If validation fails, the request is rejected.

## Outbound Authentication

Outbound authentication is gateway to backend APIs.

- The gateway uses a credential provider.
- The credential provider injects the required backend credential.
- This can be an API key or another supported credential type.

## One-Line Explanation

The caller proves its identity to the gateway with a JWT, and the gateway proves its identity to the backend APIs with the configured backend credential.