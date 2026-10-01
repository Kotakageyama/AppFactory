# __APP_NAME__

This repository independently owns the `__APP_NAME__` Cloud Run service. Its operational configuration is in `config/app.yaml`.

## Commands

```sh
make doctor
make deploy
make status
make logs
make destroy
```

`make deploy` builds an image in the project and Artifact Registry named in `config/app.yaml`, deploys this service, and injects its database URL plus the configured shared secrets from Secret Manager. Production values are never stored in this repository or `.env` files.

Operations require Bash 4+, GNU Make, Python 3.9+, and an authenticated `gcloud` CLI. Deployment also requires Git and a commit (or an explicit `IMAGE_TAG`). Builds run in Cloud Build; local Docker is optional. For local development, run `node app/server.js` with Node.js 22.

## Configuration

`config/app.yaml` is the only operational configuration. Set `cloud_run.allow_unauthenticated` to `false` for an authenticated service; deployment then uses `--no-allow-unauthenticated`. Public access is enabled by default. `make deploy IMAGE_TAG=my-tag` overrides only the image tag.

The validator accepts the template's fixed schema: top-level `name`, two-space nested mappings, four-space `common` list entries, simple scalars (optionally single/double quoted), blank lines, and comments. An empty common list is written `common: []`. It rejects unknown/duplicate/missing keys, tabs, invalid names, and unsupported YAML features such as anchors, multiline values, and flow mappings before any cloud operation. Instance limits must be nonnegative with `min_instances <= max_instances`; `max_instances` must be positive. Fractional CPU must be below 1; other Cloud Run resource compatibility constraints are checked by Cloud Run.

If `.factory-state.json` exists, generation is incomplete and cloud commands are blocked. Resume the original `make create` command from App Factory. The state contains resource identifiers and progress only, never credentials.

`make destroy` only removes the Cloud Run service. When retiring an app, deliberately remove its Neon project, app-specific Secret Manager secret, runtime service account, and unused container images through their consoles/CLIs. Preserve shared API secrets and the shared Artifact Registry. Cloud Run, Cloud Build, image storage, Secret Manager, and Neon may incur charges even when the sample app is idle.
