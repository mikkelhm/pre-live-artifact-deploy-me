# pre-live-artifact-deploy-me — zip-deploy prototype

Public repo: [mikkelhm/pre-live-artifact-deploy-me](https://github.com/mikkelhm/pre-live-artifact-deploy-me). Cloned from a dev-tier Umbraco Cloud project (`scm.rainbowsrock.net`, API base `api.dev-cloud.umbraco.com`).

**Purpose:** end-to-end test of the new **zip-deploy update executor** (currently in `Umbraco.Cloud.Deployment` branch `feature/zip-deploy-update-executor`). Zip-deploy scaffolding landed via PR #4 (merged); `main` now pins `dockerImageTag: 0.3.109-beta` for both pre-live and live jobs.

**Two Cloud environments:** `pre-live` (auto-deploys on push to `main`) and `live` (manually gated by GitHub `environment: live` → Mikkel approves). **No cloud-sync** — GitHub is the source of truth; backoffice schema changes in Cloud don't flow back.

## Platform facts that drive pipeline choices

These are **non-negotiable** — confirmed from the Umbraco.Cloud.* source on disk (`D:\Umbraco\`). Always verify from source before claiming anything else about Cloud.

- **Customer sites run on Windows App Service plans** (IIS + ASP.NET Core Module V2, `hostingModel="inprocess"`). Source: every pricing tier in `Umbraco.Cloud.Hosting\src\AzureWebAppProvisioning\AzureWebAppProvisioning.Worker.Service\appsettings.*.json` sets `"OperatingSystem": "Windows"`.
  - Pipelines that pre-build artifacts should use `--runtime win-x64 --no-self-contained`.
  - `runs-on: windows-latest` matches the target RID and avoids cross-compile oddities.

- **Cloudflare fronts `api.(dev-)cloud.umbraco.com`** and enforces a POST size/reputation gate well below the server's own 256 MB `MultipartBodyLengthLimit`.
  - Observed: ~72 MB zip passes; ~142 MB returns `413 Payload Too Large`; ~150 MB returns a managed-challenge HTML (`Just a moment...`) with 403.
  - Keep uploads under ~100 MB; set a distinctive `User-Agent`; disable `Expect:` header on curl.

- **umbraco-cloud.json is loaded by a *separate* `ConfigurationBuilder`** (not the app's main IConfiguration) with env var prefix `Umbraco:Cloud:` stripped on read.
  - Local env var overrides: `Umbraco:Cloud:Deploy:Settings:ApiKey`, `Umbraco:Cloud:Identity:ClientSecret`.
  - `HMACSecretKey` uses the normal appsettings path: `Umbraco:CMS:Imaging:HMACSecretKey`.
  - **JSON wins over env vars in this loader** — strip secret keys from the committed JSON; inject at artifact time.
  - Sources: `Umbraco.Cloud.Cms/.../UmbracoIdComposer.cs`, `Umbraco-Deploy/.../Umbraco.Deploy.Cloud/Extensions/UmbracoBuilderExtensions.cs`.

## Zip-deploy flow (new)

- Public V2 deployment API: `POST /v2/projects/{projectId}/deployments` — body type `StartProjectDeploymentRequest` at `Umbraco.Cloud.Project\src\Deployment\Deployment.Api.Service\Endpoints\PublicV2\StartProjectDeploymentRequest.cs`.
- Key new input: `DockerImageTag` (string, optional) — selects the update-executor container image. Prototype values: `0.3.101-beta`, `0.3.104-beta`, `0.3.108-beta`, `latest-beta`.
- Artifact upload: `POST /v2/projects/{projectId}/deployments/artifacts` (multipart form: `file`, `description`, `version`).
- Under the hood: executor zip-deploys to Kudu `api/zipdeploy?isAsync=true` (**merge** deploy, not clean — old files linger).
- When shipping a pre-built publish, pass `noBuildAndRestore: "true"` to the start-deployment API.

## Pipeline pattern used here

Canonical layout (from `pre-live-artifact-deploy-me`):

```
.github/
├── workflows/
│   ├── main.yml               # orchestrator (push → pre-live → approve-live → live)
│   ├── cloud-artifact.yml     # publish + zip + upload
│   └── cloud-deployment.yml   # start deployment + wait
└── scripts/
    ├── upload_artifact.sh
    ├── start_deployment.sh    # arg #12 = dockerImageTag (added for zip-deploy)
    └── get_deployment_status.sh
```

- Live promotion gated by a GitHub `environment: live` with Mikkel as required reviewer (needs public repo on free plan).
- **No cloud-sync** — GitHub is the source of truth; backoffice schema changes in Cloud don't flow back.
- Secrets never live in committed config. `launchSettings.json` is gitignored. Secrets are GitHub Actions secrets + injected into JSON files at artifact time (see `cloud-artifact.yml` pwsh step).
- Model classes live in a **sibling class library** (`src/UmbracoProject.Models/`) with `ModelsMode=SourceCodeAuto` + `ModelsDirectory=~/../UmbracoProject.Models/` locally, `ModelsMode=Nothing` on Cloud (Production runtime mode).

## Related skills

- `/setup-cloud-cicd` (`C:\Users\mikke\.claude\skills\setup-cloud-cicd`) scaffolds the original layout. This repo has since been modified — the zip-deploy tweaks (win-x64 publish, DockerImageTag arg, PowerShell steps, no cloud-sync) are bespoke here and haven't been backported into the skill yet.

## When Mikkel asks about Cloud behavior

He's on the Cloud Core Team — answers should cite the actual source at `D:\Umbraco\Umbraco.Cloud.*`, not generic Azure/Umbraco docs. If something isn't obvious from a grep in those repos, ask before inventing.
