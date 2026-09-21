# Agent Pilot Router Evidence

This folder is the evidence store for the Agent Pilot Router prototype.

## Static evidence
- Build plan and architecture: `docs/BUILD_PLAN.md`
- Deployment snapshot: `evidence/2026-09-21-deployment.json`

## Runtime evidence
The website writes runtime evidence to `evidence/runtime/` through `evidence-save.ashx`.

Evidence types:
- build-plan
- task
- final-run
- agent-master

Each record is timestamped and is intended to be used by the next Agent/AI task as a handoff artifact.
