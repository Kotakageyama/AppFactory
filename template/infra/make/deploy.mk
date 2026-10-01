SHELL := /usr/bin/env bash

doctor deploy status logs destroy:
	@bash infra/scripts/cloud-run.sh $@
