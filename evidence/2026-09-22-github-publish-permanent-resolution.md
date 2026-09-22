# Pilot Router GitHub Publish Failure - Permanent Resolution

Date: 2026-09-22
Version: 0.5.3

## Observed failure
Task 4.2 failed with:
GitHub publish failed: Invalid server response from /github-publish.ashx

## Confirmed root cause
RCA job: 04f4dce9-de82-4745-94e4-3b219e8cd2d6

The failure was NOT caused by GitHub/Azure permission.
The deployed ASP.NET handler contained an invalid C# backslash character literal in the ZIP path normalization code. ASP.NET dynamic compilation failed before ProcessRequest could run, therefore the endpoint returned a non-JSON compiler response and the browser reported Invalid server response.

## Permission checks
- GitHub authenticated account: KirtiBabco.
- KirtiBabco role on KirtiBabco/Hello-8800: admin.
- BABCO_GITHUB_TOKEN is already used by evidence-save.ashx for successful writes into the evidence repository.
- Router managed identity principal: 780414d1-6e8f-47c3-8afb-428f728dca31.
- Router identity has Key Vault Secrets User on kv-babco-github-prod.
- Router identity has Website Contributor on rg-babco-rnd-sandbox.

## Permanent corrections
1. GitHub publisher rewritten without System.IO.Compression dependency.
2. Valid path normalization retained.
3. GET health mode on github-publish.ashx performs live GitHub /user authentication check.
4. Browser preflight now smoke-tests github-publish.ashx before any paid project execution.
5. Non-JSON server responses now display HTTP status + response snippet instead of generic Invalid server response.
6. GitHub Actions workflow .github/workflows/pilot-router-runtime-validation.yml:
   - node --check for JavaScript
   - ASP.NET Web Site precompile using aspnet_compiler.exe
7. Validation workflow run 35714924309 completed SUCCESS for the corrected runtime source.

## Deployment
- Corrected runtime source: 2d17e2adad75c888d46413349ad9ea5a11d7cb4c
- Deployment package commit: 723629731cedacb6155f3a17d17f8d843dbcb80a
- Package: deploy/site-v0.5.3.zip
- Package blob: 5e35520e373cda11c60211c9582829f43d264392
- Azure App Service: app-babco-agent-pilot-router-rnd-260921
- Azure state: Running / Normal

## Permission escalation rule
Do not widen permissions unless the live GitHub health or POST returns a concrete GitHub 401/403.
If repository creation later returns 403, update the GitHub credential itself; do not add Azure permissions.
