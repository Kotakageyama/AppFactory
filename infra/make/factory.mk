SHELL := /usr/bin/env bash
include infra/make/gcp.mk
include infra/make/neon.mk

APP ?=
DIR ?= ../$(APP)
export APP DIR GCP_PROJECT GCP_REGION ARTIFACT_REPOSITORY NEON_ORG_ID NEON

doctor setup create:
	@bash infra/scripts/factory.sh $@
