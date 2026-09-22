# Pilot Router Real Execution RCA - 2026-09-22

RCA job: 4f4c87d4-e360-4519-99ad-43528810aaa4

## Root cause
The Pilot Router was a local progress simulation. Routing labels were selected from capability metadata, but run() advanced task states with timers and did not make authenticated Agent/OpenAI execution calls.

## Permanent rule
A task may be Done only after:
- executor identity
- request receipt
- execution ID
- terminal success
- actual result/artifact
- verification
- durable evidence reference

Missing proof means Blocked/Running, never Done.
