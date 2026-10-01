SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

include infra/make/deploy.mk

.PHONY: help doctor deploy status logs destroy

help:
	@printf '%s\n' 'Independent Cloud Run application repository' '' \
	  'Targets:' \
	  '  make doctor   Check local prerequisites and this app configuration' \
	  '  make deploy   Build, publish, and deploy this repository' \
	  '  make status   Show this app Cloud Run service' \
	  '  make logs     Read recent Cloud Run logs' \
	  '  make destroy  Delete this Cloud Run service (keeps Neon project and secrets)'
