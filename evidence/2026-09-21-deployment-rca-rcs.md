# Agent Router Deployment RCA / RCS Evidence - 2026-09-21

## Observed failure
Live URL `/agent-master.html` returned the Azure/IIS missing-resource page even though the source branch contained the file.

## RCA
- RCA job: `A171CDF4-0F60-4D7E-8DF0-3471E2C517A2`
- RCA requested Kudu deployment/VFS evidence to distinguish no-sync vs stale deployment.
- The current connector cannot read Kudu VFS directly.
- The prior process incorrectly treated successful `Microsoft.Web/sites/sourcecontrols/web` configuration as proof that site files had actually been deployed.

## RCS
- Durable RCS case: `5a71d154-6db5-46a4-9057-4c2a20648857`
- Initial synchronous RCS call timed out.
- Durable case entered evidence-waiting state.

## Corrective action applied
1. Source control changed from `isManualIntegration=true` to `false`.
2. A deterministic site ZIP was created from the exact required files.
3. ZIP committed at source commit:
   `99b7b009091f186fa705e3129c5bebc1694f6203`
4. ZIP blob SHA:
   `ca44964865ebee387eadb6d99d7765567014baeb`
5. ZIP validation passed with no archive errors.
6. Package root contains:
   - index.html
   - agent-master.html
   - evidence.html
   - site.css
   - shared.js
   - evidence-save.ashx
   - web.config
7. Azure App Setting `WEBSITE_RUN_FROM_PACKAGE` now points to the immutable ZIP URL for commit `99b7b009...`.

## Permanent deployment rule
Never treat source-control configuration success as deployment success.

A release is complete only when all three are true:
1. Source commit exists.
2. Deployable package is validated and immutable.
3. Live endpoint is HTTP-verified externally.

## Live URLs
- Main: https://app-babco-agent-pilot-router-rnd-260921.azurewebsites.net/
- Agent Master: https://app-babco-agent-pilot-router-rnd-260921.azurewebsites.net/agent-master.html
- Evidence Center: https://app-babco-agent-pilot-router-rnd-260921.azurewebsites.net/evidence.html
