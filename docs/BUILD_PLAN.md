# Babco Agent Pilot Router - Build Plan

## Purpose
A pilot controller/router that accepts a project prompt plus attachments, produces a build plan, recursively decomposes it into modules/tasks, resolves dependencies, routes each task to a matching Agent or OpenAI fallback, runs ready tasks in sequence/parallel lanes, and preserves evidence for downstream handoff.

## Core flow
1. Project/Prompt Intake
2. Build Plan
3. Recursive Decomposition
4. Dependency Graph Resolver
5. Agent Router
6. Task Runner
7. Evidence Capture
8. Result Handoff

## Initial Agent Registry
- Babco Labs RCA Analysis Agent v5 - root cause analysis and causal diagnosis.
- Babco Labs RCS Solver Agent v2 - verified correction and recurrence prevention.

## Evidence policy
- Build Plan: downloadable PDF + repository JSON evidence.
- Decomposition: downloadable JSON.
- Dependency Graph: downloadable JSON.
- Each completed task: individual repository evidence JSON.
- Final run: repository evidence JSON + downloadable JSON.
- Added Agents: registry evidence JSON.

## Live application
https://app-babco-agent-pilot-router-rnd-260921.azurewebsites.net/
