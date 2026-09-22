# Final Azure URL Requirement Fix - v0.4.1

## Issue
The prompt could explicitly request the Azure live site URL as the final deliverable, but the planner only created an Azure deployment task and never created a dedicated final URL handoff task.

## Fix
- Detect Azure + URL/link/live/site requirement from the prompt.
- Add final task 6.1: Return verified Azure live site URL.
- Make it the last task after verification/evidence.
- A required URL task cannot become Done unless:
  - real execution proof is complete,
  - actual Azure URL exists,
  - verification is complete,
  - durable evidence exists.
- Task output explicitly displays REQUIRED FINAL OUTPUT MISSING until the URL is available.
