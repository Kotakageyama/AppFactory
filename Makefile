SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

include infra/make/factory.mk

.PHONY: help doctor setup create

help:
	@printf '%s\n' 'App Factory — create independent Cloud Run application repositories' '' \
	  'Targets:' \
	  'Set GCP_PROJECT to your existing project ID for all operations.' '' \
	  '  make doctor                     Check local tools and shared GCP prerequisites' \
	  '  make setup                      Enable shared GCP services and create Artifact Registry' \
	  '  make create APP=<name>           Generate ../<name> or resume incomplete generation' \
	  '  make create APP=<name> DIR=/path Generate at an explicit new destination'
