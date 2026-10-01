# App Factory

App Factory generates independent application repositories with a minimal Node.js HTTP server, Cloud Run operations, and one Neon project using its default `main` branch. It does not operate already-created apps. Each generated repository owns its Makefile and uses `config/app.yaml` as its operational source of truth.

Applications share **your existing GCP project**, with separate Cloud Run services, runtime service accounts, Neon projects, and database secrets. Production database URLs are sent directly to GCP Secret Manager and never written to files or `.env`. Shared API keys are referenced from Secret Manager without duplication. Only `OPENAI_API_KEY` and `GOOGLE_MAPS_API_KEY` are configured as shared API secrets.

## Prerequisites

- Linux (or WSL), Bash 4+, GNU Make/coreutils, GNU sed, and `flock` (util-linux). Native macOS/Windows execution is not supported.
- Python 3.9+, `jq`, Git, Google Cloud CLI, and Neon CLI. Local Docker, Terraform, and GitHub CLI are not required.
- An existing GCP project with billing enabled and permission to enable APIs, manage Artifact Registry, create runtime service accounts, and create/version secrets and edit their IAM policies.
- Deployment permissions for Cloud Build and Cloud Run, permission to act as the runtime service account, and permission to set service IAM when making a service public. The Cloud Build execution account also needs permission to write images to the chosen Artifact Registry. Ask your GCP administrator to grant the permissions needed for your organization's setup.
- Neon authentication with `neon login` or `NEON_API_KEY` supplied externally. Do not store this key in this repository.
- Git author identity configured for the initial generated commit (`git config --global user.name` and `git config --global user.email`).

The existing CLI integration targets Neon CLI 5.x (`npm install -g neon@5`, with a compatible Node.js version). Run `neon --version` and consult its `--help` before changing major versions. The generated server uses Node.js 22.

## First-time setup

Authenticate and select your project's immutable ID (not its display name):

```sh
gcloud auth login
neon login
export GCP_PROJECT=your-project-id
export GCP_REGION=asia-northeast1
export ARTIFACT_REPOSITORY=apps
make setup
```

`make setup` enables the shared APIs and creates the Docker Artifact Registry if it does not exist. It does not create API keys. Obtain your OpenAI and Google Maps keys, then create each shared secret and add a version. For example, in Bash, repeat the following for `GOOGLE_MAPS_API_KEY` after changing `secret`:

```sh
secret=OPENAI_API_KEY
gcloud secrets create "$secret" --replication-policy=automatic --project="$GCP_PROJECT"
read -r -s -p 'API key: ' api_key
printf '\n'
printf '%s' "$api_key" | gcloud secrets versions add "$secret" --data-file=- --project="$GCP_PROJECT"
unset api_key
```

If the secret already exists, skip `secrets create`. Do not put key values in command arguments, files, or shell tracing. Disable `set -x` before entering keys. After both shared secrets have enabled versions:

```sh
make doctor
make create APP=washspace
cd ../washspace
make doctor
make deploy
```

`make doctor` checks tools, billing, APIs, registry, Neon authentication, and shared secret version metadata. Run it after setup and secret preparation.

## Generation options

`APP` accepts 2–26 lowercase letters, digits, and hyphens, starting with a letter and ending with a letter or digit. The limit accommodates the `APP-run` runtime service account. By default the destination is `../APP`:

```sh
make create APP=washspace DIR=/absolute/path/washspace
make create APP=washspace NEON_ORG_ID=org_xxx
```

The sole Neon organization is selected automatically. Specify `NEON_ORG_ID` when the account has zero or multiple organizations. `GCP_PROJECT`, `GCP_REGION`, and `ARTIFACT_REPOSITORY` are copied into the generated config. Factory variables do not operate on apps after generation. `NEON` may name an executable wrapper; command strings with flags are unsupported.

Existing destinations and existing same-name cloud resources are not adopted during a new generation. Configure the generated app's access policy with `cloud_run.allow_unauthenticated` in `config/app.yaml`; it defaults to public. See its README for the supported YAML format and commands.

## Recovering interrupted generation

Once the scaffold is prepared, the destination remains on failure with a Git-ignored `.factory-state.json` containing the original parameters, Neon project ID, and progress flags. The error reports the failed step and relevant resource identifiers. Existing cloud resources are preserved, and the incomplete app blocks its cloud operations.

Fix the reported cause and rerun **the same `make create` command with the same destination, project, region, registry, and Neon organization**. It reuses the recorded Neon project, skips an already-written database secret, and reapplies secret IAM bindings. If the initial Git commit failed, configure the Git author identity and rerun before any cloud provisioning occurs. Concurrent generation for the same destination is rejected.

If project creation returned an error or was interrupted before its ID was recorded, generation looks up the unique same-name project in the recorded organization on resume. It never blindly creates a second project. If no project is visible, inspect the organization using `neon projects list --org-id org_xxx --output json`. Retry after it appears. Only if you have confirmed that the creation did not produce any project, reset the creation intent and rerun:

```sh
state=../washspace/.factory-state.json
if jq -e '.requested == true and .neon_project == "" and .database_written == false' "$state"; then
  jq '.requested = false' "$state" > "$state.tmp" && mv "$state.tmp" "$state"
fi
```

Do not edit recovery state while generation is running. If abandoning a generation, inspect its state and deliberately remove only its app-specific resources; do not remove shared secrets. An interruption after adding a secret version but before recording completion can add another version on resume; it does not create another Neon project.

## Costs and retirement

`make create` provisions Neon and Secret Manager resources. `make deploy` submits a Cloud Build, stores an image, and deploys Cloud Run. These resources, logs, and storage may incur charges; a minimum instance count of zero does not guarantee a zero bill. Review your providers' billing settings before provisioning.

Generated repositories provide `make status`, `make logs`, and `make destroy`. `destroy` removes only their Cloud Run service. Retire the app's Neon project, database secret, runtime service account, and unused container images separately when appropriate; shared API secrets and the shared registry remain in use by other apps.

## License

[Apache License 2.0](LICENSE).
