#!/usr/bin/env bash
set -euo pipefail
# Credentials must never appear in shell tracing, even if SHELLOPTS is exported.
set +x
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
project=${GCP_PROJECT:-}
region=${GCP_REGION:-asia-northeast1}
repository=${ARTIFACT_REPOSITORY:-apps}
neon_cli=${NEON:-neon}
[[ "$project" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]] || fail 'GCP_PROJECT must be your existing GCP project ID.'
[[ "$region" =~ ^[a-z]+-[a-z]+[0-9]+$ ]] || fail 'Invalid GCP_REGION.'
[[ "$repository" =~ ^[a-z][a-z0-9_-]{0,62}$ ]] || fail 'Invalid ARTIFACT_REPOSITORY.'
for tool in gcloud "$neon_cli" git make jq python3 flock; do
  command -v "$tool" >/dev/null || fail "Missing tool: $tool"
done
services=(artifactregistry.googleapis.com secretmanager.googleapis.com run.googleapis.com cloudbuild.googleapis.com iam.googleapis.com)
case "${1:-}" in
  doctor)
    failed=0
    check() { if "$@" >/dev/null 2>&1; then printf 'OK   %s\n' "$*"; else printf 'MISS %s\n' "$*"; failed=1; fi; }
    check gcloud projects describe "$project"
    billing=$(gcloud billing projects describe "$project" --format='value(billingEnabled)')
    [[ "$billing" == True ]] || { echo 'MISS Billing'; failed=1; }
    for service in "${services[@]}"; do
      enabled=$(gcloud services list --enabled --project="$project" --filter="config.name=$service" --format='value(config.name)')
      [[ "$enabled" == "$service" ]] || { echo "MISS $service (run make setup)"; failed=1; }
    done
    check gcloud artifacts repositories describe "$repository" --location="$region" --project="$project"
    check "$neon_cli" orgs list --output json
    if [[ -n "${NEON_ORG_ID:-}" ]]; then
      orgs=$("$neon_cli" orgs list --output json)
      printf '%s' "$orgs" | jq -e --arg id "$NEON_ORG_ID" '.[] | select(.id == $id)' >/dev/null || { echo 'MISS Neon organization'; failed=1; }
    fi
    for secret in OPENAI_API_KEY GOOGLE_MAPS_API_KEY; do
      check gcloud secrets describe "$secret" --project="$project"
      version_state=$(gcloud secrets versions describe latest --secret="$secret" --project="$project" --format='value(state)')
      [[ "$version_state" == ENABLED ]] || { echo "MISS enabled latest version for $secret"; failed=1; }
    done
    exit "$failed"
    ;;
  setup)
    gcloud services enable "${services[@]}" --project="$project"
    if ! gcloud artifacts repositories describe "$repository" --location="$region" --project="$project" >/dev/null 2>&1; then
      gcloud artifacts repositories create "$repository" --repository-format=docker --location="$region" --description='Container images for independent applications' --project="$project"
    fi
    echo 'Shared GCP setup complete. Prepare the shared API secrets before make create.'
    exit 0
    ;;
  create) ;;
  *) fail 'Unknown factory operation.' ;;
esac

app=${APP:-}
# The runtime service account appends -run and has a 30-character ID limit.
[[ "$app" =~ ^[a-z][a-z0-9-]{0,24}[a-z0-9]$ ]] || fail 'APP must be 2-26 lowercase letters/digits/hyphens, start with a letter and end with a letter or digit.'
dir=${DIR:-../$app}
prefix=${app^^}; prefix=${prefix//-/_}
secret=${prefix}_DATABASE_URL
sa="$app-run@$project.iam.gserviceaccount.com"
neon_org=${NEON_ORG_ID:-}
for shared in OPENAI_API_KEY GOOGLE_MAPS_API_KEY; do
  gcloud secrets describe "$shared" --project="$project" >/dev/null || fail "Required shared secret missing: $shared"
  version_state=$(gcloud secrets versions describe latest --secret="$shared" --project="$project" --format='value(state)')
  [[ "$version_state" == ENABLED ]] || fail "Shared secret has no enabled latest version: $shared"
done
orgs_json=$("$neon_cli" orgs list --output json)
if [[ -z "$neon_org" ]]; then neon_org=$(printf '%s' "$orgs_json" | jq -r 'if length == 1 then .[0].id else empty end'); fi
[[ -n "$neon_org" ]] || fail 'Specify NEON_ORG_ID when there is not exactly one organization.'
printf '%s' "$orgs_json" | jq -e --arg id "$neon_org" '.[] | select(.id == $id)' >/dev/null || fail 'Neon organization not found.'
projects_json=$("$neon_cli" projects list --org-id "$neon_org" --output json)
printf '%s' "$projects_json" | jq -e 'type == "array"' >/dev/null || fail 'Unexpected Neon project list format.'

state="$dir/.factory-state.json"
if [[ -e "$dir" || -L "$dir" ]]; then
  [[ -d "$dir" && ! -L "$dir" && -f "$state" ]] || fail "Destination exists and is not an incomplete generation: $dir"
else
  # Refuse to adopt or overwrite resources that predate this generation.
  if printf '%s' "$projects_json" | jq -e --arg name "$app" '.[] | select(.name == $name)' >/dev/null; then fail 'A same-name Neon project already exists.'; fi
  if gcloud secrets describe "$secret" --project="$project" >/dev/null 2>&1; then fail "App secret already exists: $secret"; fi
  if gcloud iam service-accounts describe "$sa" --project="$project" >/dev/null 2>&1; then fail "Runtime service account already exists: $sa"; fi
  parent=$(dirname "$dir"); mkdir -p "$parent"
  staging=$(mktemp -d "$parent/.$app.tmp.XXXXXX")
  trap 'rm -rf -- "$staging"' EXIT
  cp -R template/. "$staging"
  sed -e "s|__APP_NAME__|$app|g" -e "s|__GCP_PROJECT__|$project|g" -e "s|__GCP_REGION__|$region|g" -e "s|__ARTIFACT_REPOSITORY__|$repository|g" -e "s|__DATABASE_SECRET__|$secret|g" "$staging/config/app.yaml.template" > "$staging/config/app.yaml"
  rm -- "$staging/config/app.yaml.template"
  sed -i -e "s|__APP_NAME__|$app|g" "$staging/README.md"
  python3 "$staging/infra/scripts/config.py" "$staging/config/app.yaml" >/dev/null
  jq -n --arg app "$app" --arg project "$project" --arg region "$region" --arg repository "$repository" --arg org "$neon_org" '{version:1, app:$app, project:$project, region:$region, repository:$repository, org:$org, requested:false, neon_project:"", database_written:false}' > "$staging/.factory-state.json"
  # -T prevents nesting the scaffold if another process creates the destination.
  mv -T -- "$staging" "$dir"
  trap - EXIT
fi
exec 9>"$dir/.factory.lock"
flock -n 9 || fail 'Another generation is running for this destination.'
[[ -f "$state" ]] || fail 'This generation has already completed.'
jq -e --arg app "$app" --arg project "$project" --arg region "$region" --arg repository "$repository" --arg org "$neon_org" '.version == 1 and .app == $app and .project == $project and .region == $region and .repository == $repository and .org == $org and (.requested | type == "boolean") and (.database_written | type == "boolean") and (.neon_project | type == "string")' "$state" >/dev/null || fail 'Resume arguments differ from the original generation or state is invalid.'
stage='local scaffold'
neon_project=$(jq -r '.neon_project' "$state")
report_failure() {
  result=$?
  if (( result != 0 )); then
    printf '\nGeneration incomplete at: %s\nRepository/state: %s\nNeon organization: %s\nNeon project: %s\nDatabase secret: %s\nRuntime account: %s\nResume with the same make create arguments. Existing cloud resources were preserved.\n' "$stage" "$dir" "$neon_org" "${neon_project:-not yet identified}" "$secret" "$sa" >&2
  fi
}
trap report_failure EXIT
save_state() { jq "$@" "$state" > "$state.tmp"; mv -- "$state.tmp" "$state"; }
config=$(python3 "$dir/infra/scripts/config.py" "$dir/config/app.yaml")
eval "$config"
[[ "$APP_NAME" == "$app" && "$GCP_PROJECT" == "$project" && "$GCP_REGION" == "$region" && "$ARTIFACT_REPOSITORY" == "$repository" && "$DATABASE_SECRET" == "$secret" && "$COMMON_SECRETS" == 'OPENAI_API_KEY GOOGLE_MAPS_API_KEY' ]] || fail 'Resource names in config/app.yaml differ from the generation state. Restore the original values before resuming.'
git -C "$dir" init -q
if ! git -C "$dir" rev-parse --verify HEAD >/dev/null 2>&1; then
  git -C "$dir" add .
  git -C "$dir" commit -qm 'Initial app scaffold' || fail 'Initial Git commit failed. Configure git user.name/user.email, then resume.'
fi
stage='Neon project creation/identification'
if [[ -z "$neon_project" ]]; then
  if [[ $(jq -r '.requested' "$state") == false ]]; then
    save_state '.requested = true'
    "$neon_cli" projects create --name "$app" --org-id "$neon_org" --no-secrets --no-color >/dev/null
  fi
  projects_json=$("$neon_cli" projects list --org-id "$neon_org" --output json)
  neon_project=$(printf '%s' "$projects_json" | jq -r --arg name "$app" '[.[] | select(.name == $name)] | if length == 1 then .[0].id else empty end')
  [[ -n "$neon_project" ]] || fail 'Creation result is uncertain. Inspect Neon projects; retry once the project is visible. Do not create another project blindly. See README recovery instructions.'
  save_state --arg id "$neon_project" '.neon_project = $id'
fi
stage='Neon main connection and database secret'
branches_json=$("$neon_cli" branches list --project-id "$neon_project" --output json)
printf '%s' "$branches_json" | jq -e '.. | objects | select(.name? == "main")' >/dev/null || fail 'Neon project has no main branch.'
if [[ $(jq -r '.database_written' "$state") == false ]]; then
  connection_output=$("$neon_cli" connection-string main --project-id "$neon_project" --output json --no-color)
  db_url=$(printf '%s\n' "$connection_output" | awk '/^postgres(ql)?:\/\// {print; exit}')
  if [[ -z "$db_url" && "$connection_output" == \{* ]]; then db_url=$(printf '%s' "$connection_output" | jq -r '.connection_string // .connectionString // .uri // .data.connection_string // empty' 2>/dev/null) || fail 'Invalid connection response (content suppressed).'; fi
  [[ "$db_url" =~ ^postgres(ql)?://[^[:space:]]+$ ]] || fail 'Could not read a valid Neon connection string (content suppressed).'
  if ! gcloud secrets describe "$secret" --project="$project" >/dev/null 2>&1; then gcloud secrets create "$secret" --replication-policy=automatic --project="$project"; fi
  printf '%s' "$db_url" | gcloud secrets versions add "$secret" --data-file=- --project="$project"
  unset connection_output db_url
  save_state '.database_written = true'
fi
stage='runtime account and secret access'
if ! gcloud iam service-accounts describe "$sa" --project="$project" >/dev/null 2>&1; then gcloud iam service-accounts create "$app-run" --display-name="Cloud Run runtime for $app" --project="$project"; fi
for entry in "$secret" OPENAI_API_KEY GOOGLE_MAPS_API_KEY; do
  gcloud secrets add-iam-policy-binding "$entry" --member="serviceAccount:$sa" --role=roles/secretmanager.secretAccessor --project="$project" >/dev/null
done
stage='completion'
rm -- "$state"
trap - EXIT
printf '\nApplication created successfully.\nRepository: %s\nGCP project: %s\nNeon project: %s\nDatabase secret: %s\n\nNext: cd %q && make deploy\n' "$dir" "$project" "$neon_project" "$secret" "$dir"
