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
	@echo "  make test-fork    Run tests against a mainnet fork (uses FORK_RPC_URL)"
	@echo "  make fork-test    Alias for test-fork"
	@echo ""
	@echo "Environment variables for forked tests (optional):"
	@echo "  MT         Only run tests matching this regex (passed to --match-test / --mt)"
	@echo "  NO_MT      Only run tests NOT matching this regex (passed to --no-match-test / --nmt)"
	@echo "  MC     Only run tests in contracts matching this regex (passed to --match-contract / --mc)"
	@echo "  FORK_BLOCK_NUMBER  Optional: fork block number to use (omit to use latest)"

test:
	forge test -vvv

test-fork:
	@if [ -z "$(FORK_RPC_URL)" ]; then \
		echo "FORK_RPC_URL not set. Set it in .env or pass RPC_URL=..."; \
		exit 1; \
	fi
	# Optional flags (only appended when env vars are set)
	$(eval _MT := $(if $(MT),--match-test "$(MT)",))
	$(eval _MC := $(if $(MC),--match-contract "$(MC)",))
	$(eval _FB := $(if $(FORK_BLOCK_NUMBER),--fork-block-number $(FORK_BLOCK_NUMBER),))
	forge test --fork-url $(FORK_RPC_URL) -vvv $(_FB) $(_MT) $(_MC)

test-fork-verbose:
	@if [ -z "$(FORK_RPC_URL)" ]; then \
		echo "FORK_RPC_URL not set. Set it in .env or pass RPC_URL=..."; \
		exit 1; \
	fi
	# Optional flags (only appended when env vars are set)
	$(eval _MT := $(if $(MT),--match-test "$(MT)",))
	$(eval _MC := $(if $(MC),--match-contract "$(MC)",))
	$(eval _FB := $(if $(FORK_BLOCK_NUMBER),--fork-block-number $(FORK_BLOCK_NUMBER),))
	forge test --fork-url $(FORK_RPC_URL) -vvvvv $(_FB) $(_MT) $(_MC)

fork-test: test-fork
fork-test-verbose: test-fork-verbose


