# Override only when an organization-standard Neon CLI wrapper is required.
NEON ?= neon

# Leave empty when the Neon account has exactly one organization. For accounts
# with multiple organizations, make create requires this explicit ID so the CLI
# never opens an interactive organization picker.
NEON_ORG_ID ?=
