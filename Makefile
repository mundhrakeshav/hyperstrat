.PHONY: help test test-fork fork-test

# Default target
.DEFAULT_GOAL := help

# Load environment variables from .env files if present
ifneq (,$(wildcard .env))
include .env
export $(shell sed -n 's/^[A-Za-z_][A-Za-z0-9_]*=.*/\1/p' .env)
endif
ifneq (,$(wildcard .env.local))
include .env.local
export $(shell sed -n 's/^[A-Za-z_][A-Za-z0-9_]*=.*/\1/p' .env.local)
endif

help:
	@echo "Available targets:"
	@echo "  make test         Run all Foundry tests"
	@echo "  make test-fork    Run tests against a mainnet fork (uses MAINNET_RPC_URL)"
	@echo "  make fork-test    Alias for test-fork"

test:
	forge test -vvv

test-fork:
	@if [ -z "$(FORK_RPC_URL)" ]; then \
		echo "FORK_RPC_URL not set. Set it in .env or pass RPC_URL=..."; \
		exit 1; \
	fi
	forge test --fork-url $(FORK_RPC_URL) -vvv

test-fork-verbose:
	@if [ -z "$(FORK_RPC_URL)" ]; then \
		echo "FORK_RPC_URL not set. Set it in .env or pass RPC_URL=..."; \
		exit 1; \
	fi
	forge test --fork-url $(FORK_RPC_URL) -vvvvv

fork-test: test-fork


