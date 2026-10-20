# Rizzo Flow API in Docker — shortcuts. `make` alone shows this list.
SHELL := /bin/bash
COMPOSE ?= docker compose
REPO ?= https://github.com/Rizzo-AI-Academy/rizzo-flow
PORT ?= 8017
URL := http://127.0.0.1:$(PORT)

# Add the Vulkan overlay only when the host exposes a GPU render node.
GPU := $(if $(wildcard /dev/dri/renderD*),-f docker-compose.gpu.yml,)
FILES := -f docker-compose.yml $(GPU)

.DEFAULT_GOAL := help
.PHONY: help up up-cpu down logs ps shell health build update clean-data

help:
	@echo "make up          start (GPU/Vulkan when /dev/dri exists, else CPU) and build if needed"
	@echo "make up-cpu      start forced to CPU, no device passthrough"
	@echo "make down        stop and remove the container (keeps ./data)"
	@echo "make logs        follow the API log"
	@echo "make ps          container state + health"
	@echo "make health      GET /health (shows the device actually in use)"
	@echo "make shell       bash inside the running container"
	@echo "make build       rebuild the image (reuses the ./data downloads)"
	@echo "make update      rebuild on the latest upstream commit, then restart"
	@echo "make clean-data  delete ./data: the 4.4 GB of weights are downloaded again next start"

up:
	$(COMPOSE) $(FILES) up -d --build

up-cpu:
	$(COMPOSE) -f docker-compose.yml up -d --build

down:
	$(COMPOSE) $(FILES) down

logs:
	$(COMPOSE) $(FILES) logs -f

ps:
	$(COMPOSE) $(FILES) ps

health:
	@curl -fsS $(URL)/health | python3 -m json.tool || \
		echo "not ready yet: first start downloads ~4.4 GB, follow it with 'make logs'"

shell:
	$(COMPOSE) $(FILES) exec rizzo bash

build:
	$(COMPOSE) $(FILES) build

update:
	@sha=$$(git ls-remote $(REPO) HEAD | cut -f1); \
	if [ -z "$$sha" ]; then echo "cannot resolve $(REPO) HEAD"; exit 1; fi; \
	echo "rizzo-flow: building upstream $$sha"; \
	RIZZO_COMMIT=$$sha $(COMPOSE) $(FILES) build && \
	RIZZO_COMMIT=$$sha $(COMPOSE) $(FILES) up -d --force-recreate

clean-data:
	@read -r -p "delete ./data (weights, llama.cpp runtime, HF cache)? [y/N] " a; \
	[[ $$a == [yY] ]] && rm -rf ./data && echo "removed" || echo "kept"
