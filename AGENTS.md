# App Factory conventions

- This repository is only an application generator. Do not add central deploy, logs, status, or destroy commands for generated applications.
- Generated repositories are independent Git repositories and own their Cloud Run lifecycle.
- Use `config/app.yaml` in each generated repository as its operational source of truth.
- Keep production database URLs in GCP Secret Manager only; never commit them or place them in `.env`.
- Create exactly one Neon project per application and use its default `main` branch for MVP work.
- Authenticate the Neon CLI with `neon login` or `NEON_API_KEY`; do not store the API key in this repository.
