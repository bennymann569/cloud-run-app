# Cloud Run + Cloud Deploy reference application

This repository contains a Python FastAPI service and the CI/CD automation required to deploy it to Google Cloud Run through Google Cloud Deploy across `dev`, `staging`, and `prod`.

The infrastructure itself is provisioned by the separate `cloud-run-infra` Terraform repository. This repository owns the application, container image, Cloud Run manifests, Skaffold configuration, and GitHub Actions deployment workflows.

## Repository layout

```text
app/                                  Application source code
tests/                                Automated tests
k8s/base/                             Base Cloud Run manifest
k8s/overlays/dev/                     Development overlay
k8s/overlays/staging/                 Staging overlay
k8s/overlays/prod/                    Production overlay
clouddeploy/release.sh                Creates a Cloud Deploy release
.github/workflows/ci.yml              Test and build workflow
.github/workflows/deploy-dev.yml      Automatic deployment to dev
.github/workflows/promote-staging.yml Manual promotion to staging
.github/workflows/promote-prod.yml    Manual promotion to production
Dockerfile                            Production container image
skaffold.yaml                         Cloud Deploy render/deploy configuration
```

## Prerequisites

Install and configure:

- Python 3.12 or later
- Docker with BuildKit enabled
- Google Cloud CLI
- Git
- Access to the GitHub repository
- Access to the Google Cloud project configured by the infrastructure repository

Authenticate locally when testing Google Cloud commands:

```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
```

## Local development

Create and activate a virtual environment:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Run the service locally:

```bash
uvicorn app.main:app --reload
```

Open:

```text
http://127.0.0.1:8000/
http://127.0.0.1:8000/healthz
```

Run tests:

```bash
pytest
```

Build and run the container locally:

```bash
docker build -t cloud-run-app:local .
docker run --rm -p 8080:8080 cloud-run-app:local
```

## GitHub configuration

Create the following repository **variables** in GitHub:

| Name | Example |
|---|---|
| `GCP_PROJECT_ID` | `my-project` |
| `GCP_REGION` | `europe-west2` |
| `ARTIFACT_REGISTRY` | `europe-west2-docker.pkg.dev/my-project/app` |

Create the following repository **secrets**:

| Name | Example |
|---|---|
| `GCP_WIF_PROVIDER` | `projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github/providers/github` |
| `GCP_DEPLOYER_SA` | `github-deployer@my-project.iam.gserviceaccount.com` |

These values are emitted by the infrastructure repository after `terraform apply`.

## Create GitHub environments

Create three GitHub environments:

```text
dev
staging
prod
```

Recommended protection:

| Environment | Protection |
|---|---|
| `dev` | No manual approval required |
| `staging` | Require at least one reviewer |
| `prod` | Require at least one authorised reviewer; restrict deployment to `main` |

The staging and production workflows use `workflow_dispatch`, so they do not run automatically. GitHub environment protection provides an additional approval gate before the workflow job starts.

## Deployment flow

1. A pull request triggers tests.
2. A merge to `main` triggers tests and builds an OCI image.
3. The image is pushed to Artifact Registry using the full commit SHA as its tag.
4. GitHub Actions creates a Cloud Deploy release.
5. Cloud Deploy deploys that release to the `dev` target.
6. An authorised user promotes the same release to `staging`.
7. After staging validation, an authorised user promotes the same release to `prod`.

The same immutable image progresses through all environments. It is not rebuilt for staging or production.

## First deployment

Before the first application deployment, ensure the infrastructure repository has been applied and the initial bootstrap image exists in Artifact Registry.

Build and push the bootstrap image:

```bash
export GCP_PROJECT_ID=your-project-id
export GCP_REGION=europe-west2
export IMAGE="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/app/cloud-run-app:bootstrap"

gcloud auth configure-docker "${GCP_REGION}-docker.pkg.dev"

docker buildx build \
  --platform linux/amd64 \
  --tag "${IMAGE}" \
  --push .
```

Then push the repository to GitHub. The `Deploy to dev` workflow runs after a successful CI build on `main`.

## Deploy to development

Development deployment is automatic after a successful CI run on `main`.

To inspect the workflow:

```text
GitHub repository -> Actions -> Deploy to dev
```

To deploy manually, run the `Deploy to dev` workflow from the GitHub Actions page.

## Promote to staging

1. Open **Actions**.
2. Select **Promote to staging**.
3. Select **Run workflow**.
4. Enter the Cloud Deploy release name.
5. Approve the GitHub environment deployment if prompted.

Find the latest release name:

```bash
gcloud deploy releases list \
  --delivery-pipeline=cloud-run-app \
  --region="${GCP_REGION}" \
  --project="${GCP_PROJECT_ID}"
```

## Promote to production

1. Validate the staging deployment.
2. Open **Actions**.
3. Select **Promote to production**.
4. Select **Run workflow**.
5. Enter the same Cloud Deploy release name used for staging.
6. Approve the production GitHub environment deployment.

Production promotion is intentionally manual.

## Check rollout status

```bash
gcloud deploy rollouts list \
  --delivery-pipeline=cloud-run-app \
  --region="${GCP_REGION}" \
  --project="${GCP_PROJECT_ID}"
```

View a specific rollout:

```bash
gcloud deploy rollouts describe ROLLOUT_NAME \
  --delivery-pipeline=cloud-run-app \
  --region="${GCP_REGION}" \
  --project="${GCP_PROJECT_ID}"
```

## Roll back a release

Identify the last known-good release:

```bash
gcloud deploy releases list \
  --delivery-pipeline=cloud-run-app \
  --region="${GCP_REGION}" \
  --project="${GCP_PROJECT_ID}"
```

Roll back production:

```bash
gcloud deploy releases rollback \
  --release=KNOWN_GOOD_RELEASE_NAME \
  --delivery-pipeline=cloud-run-app \
  --region="${GCP_REGION}" \
  --project="${GCP_PROJECT_ID}" \
  --target=prod
```

## Monitoring and logs

View Cloud Run logs:

```bash
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="cloud-run-app-prod"' \
  --limit=50 \
  --project="${GCP_PROJECT_ID}"
```

View Cloud Deploy audit logs:

```bash
gcloud logging read \
  'resource.type="clouddeploy.googleapis.com/DeliveryPipeline"' \
  --limit=50 \
  --project="${GCP_PROJECT_ID}"
```

## Troubleshooting

| Symptom | Likely cause | Action |
|---|---|---|
| GitHub Actions cannot authenticate | Incorrect WIF provider or service account secret | Verify `GCP_WIF_PROVIDER` and `GCP_DEPLOYER_SA` |
| `Permission denied` when pushing an image | Deployer lacks Artifact Registry write access | Check Artifact Registry IAM and WIF configuration |
| Cloud Deploy release creation fails | Missing Cloud Deploy permissions or incorrect pipeline/region | Verify Cloud Deploy IAM, pipeline name, region, and project |
| Kustomize render fails | Invalid overlay or manifest | Run `kustomize build k8s/overlays/ENVIRONMENT` locally |
| Cloud Run deployment fails | Runtime service account or image permissions issue | Check Cloud Deploy rollout logs and Cloud Run revision details |
| Application returns errors | Application configuration or dependency issue | Inspect Cloud Run logs and re-run tests locally |

## Security model

- GitHub Actions authenticates through Workload Identity Federation; no service-account key is stored in GitHub.
- The WIF provider restricts authentication to the configured GitHub repository and approved refs.
- The GitHub deployer service account is separate from the Cloud Deploy service account.
- Cloud Run uses a dedicated runtime service account.
- The application container runs as a non-root user.
- Images use immutable commit-SHA tags.
- Do not commit secrets, service-account keys, or `.env` files.

## Destroying application resources

Do not delete Cloud Run services directly if Terraform manages them. Remove the corresponding environment from `cloud_run_services` in the infrastructure repository, plan carefully, and apply the infrastructure change.
