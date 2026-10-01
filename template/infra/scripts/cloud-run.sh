#!/usr/bin/env bash
set -euo pipefail
if [[ -f .factory-state.json ]]; then
  echo 'ERROR: generation is incomplete. Resume make create from App Factory.' >&2
  exit 2
fi
command -v python3 >/dev/null || { echo 'ERROR: Python 3 is required.' >&2; exit 2; }
config=$(python3 infra/scripts/config.py config/app.yaml)
eval "$config"
command -v gcloud >/dev/null || { echo 'ERROR: gcloud is required.' >&2; exit 2; }
service_account="$APP_NAME-run@$GCP_PROJECT.iam.gserviceaccount.com"
secrets="$DATABASE_SECRET=$DATABASE_SECRET:latest"
for secret in $COMMON_SECRETS; do secrets+=",$secret=$secret:latest"; done
case "${1:-}" in
  doctor)
    for tool in git make; do command -v "$tool" >/dev/null || { echo "ERROR: $tool is required." >&2; exit 2; }; done
    gcloud projects describe "$GCP_PROJECT" --format='value(projectId)' | grep -Fxq "$GCP_PROJECT"
    gcloud artifacts repositories describe "$ARTIFACT_REPOSITORY" --location="$GCP_REGION" --project="$GCP_PROJECT" >/dev/null
    for secret in "$DATABASE_SECRET" $COMMON_SECRETS; do gcloud secrets describe "$secret" --project="$GCP_PROJECT" >/dev/null; done
    gcloud iam service-accounts describe "$service_account" --project="$GCP_PROJECT" >/dev/null
    echo 'OK   app configuration and cloud prerequisites'
    ;;
  deploy)
    command -v git >/dev/null || { echo 'ERROR: git is required.' >&2; exit 2; }
    image_tag=${IMAGE_TAG:-$(git rev-parse --short HEAD)}
    [[ "$image_tag" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || { echo 'ERROR: invalid IMAGE_TAG' >&2; exit 2; }
    image="$GCP_REGION-docker.pkg.dev/$GCP_PROJECT/$ARTIFACT_REPOSITORY/$APP_NAME:$image_tag"
    auth_flag=--no-allow-unauthenticated
    if [[ "$ALLOW_UNAUTHENTICATED" == true ]]; then auth_flag=--allow-unauthenticated; fi
    gcloud builds submit --tag "$image" --project="$GCP_PROJECT" .
    gcloud run deploy "$APP_NAME" --image="$image" --project="$GCP_PROJECT" --region="$GCP_REGION" --platform=managed --service-account="$service_account" --cpu="$CPU" --memory="$MEMORY" --min-instances="$MIN_INSTANCES" --max-instances="$MAX_INSTANCES" --invoker-iam-check "$auth_flag" --update-secrets="$secrets"
    gcloud run services describe "$APP_NAME" --project="$GCP_PROJECT" --region="$GCP_REGION" --format='value(status.url)'
    ;;
  status) gcloud run services describe "$APP_NAME" --project="$GCP_PROJECT" --region="$GCP_REGION" ;;
  logs) gcloud run services logs read "$APP_NAME" --project="$GCP_PROJECT" --region="$GCP_REGION" --limit=100 ;;
  destroy) gcloud run services delete "$APP_NAME" --project="$GCP_PROJECT" --region="$GCP_REGION" ;;
  *) echo 'ERROR: unknown Cloud Run operation' >&2; exit 2 ;;
esac
