# Repository conventions

- Keep `config/app.yaml` as the source of truth for this application's Cloud Run configuration.
- Do not commit production credentials or copy shared GCP secrets into app-specific secrets.
- Runtime database access uses the `database_secret` named in `config/app.yaml`.
- This repository owns only this app's Cloud Run service; deploy from here with `make deploy`.
