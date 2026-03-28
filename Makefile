.PHONY: help setup run bg-run stop status healthcheck test lint clean

INIT_SCRIPT := scripts/init.sh
LOG_DIR := $(HOME)/logs/keypal
PID_DIR := $(HOME)/.keypal/pids

## help: Show available commands
help:
	@echo "Usage: make <command>"
	@echo ""
	@echo "Setup:"
	@echo "  setup        Install deps, Claude Code CLI, and run pre-flight checks"
	@echo ""
	@echo "Run:"
	@echo "  run          Start bot (foreground)"
	@echo "  bg-run       Start bot (background, with auto-restart + auto-repair)"
	@echo "  stop         Stop background bot"
	@echo "  status       Show running status"
	@echo ""
	@echo "Ops:"
	@echo "  healthcheck  Run service healthcheck now"
	@echo "  clean        Stop all services + clear all schedules"
	@echo ""
	@echo "Dev:"
	@echo "  test         Run tests"
	@echo "  lint         Run linter"

## setup: Install dependencies, Claude Code CLI, and run pre-flight checks
setup:
	uv sync
	uv run pre-commit install
	@command -v claude >/dev/null 2>&1 || curl -fsSL https://claude.ai/install.sh | bash
	@mkdir -p $(LOG_DIR) $(PID_DIR)
	@if [ -f "$(INIT_SCRIPT)" ]; then \
		$(INIT_SCRIPT); \
	else \
		echo '{"status": "error", "errors": ["Init script not found: $(INIT_SCRIPT)"]}'; \
		exit 1; \
	fi

## run: Setup + start bot (foreground)
run: setup
	uv run python -m keypal

## bg-run: Setup + start bot with guardian (background, auto-restart + auto-repair)
bg-run: setup
	@if [ -f "$(PID_DIR)/guardian.pid" ] && kill -0 $$(cat "$(PID_DIR)/guardian.pid") 2>/dev/null; then \
		echo "Already running (PID $$(cat $(PID_DIR)/guardian.pid))"; \
	else \
		nohup $(HOME)/.claude/scripts/guardian.sh --channel all > $(LOG_DIR)/guardian.log 2>&1 & echo $$! > $(PID_DIR)/guardian.pid; \
		echo "Started with guardian (PID $$(cat $(PID_DIR)/guardian.pid), log: $(LOG_DIR)/guardian.log)"; \
	fi

## stop: Stop background bot
stop:
	@for pidfile in $(PID_DIR)/*.pid; do \
		[ -f "$$pidfile" ] || continue; \
		pid=$$(cat "$$pidfile"); \
		name=$$(basename "$$pidfile" .pid); \
		if kill -0 "$$pid" 2>/dev/null; then \
			kill "$$pid" && echo "Stopped $$name (PID $$pid)"; \
		else \
			echo "$$name not running"; \
		fi; \
		rm -f "$$pidfile"; \
	done

## status: Show running status
status:
	@found=false; \
	for pidfile in $(PID_DIR)/*.pid; do \
		[ -f "$$pidfile" ] || continue; \
		found=true; \
		pid=$$(cat "$$pidfile"); \
		name=$$(basename "$$pidfile" .pid); \
		if kill -0 "$$pid" 2>/dev/null; then \
			echo "🟢 $$name (PID $$pid)"; \
		else \
			echo "🔴 $$name (dead)"; \
			rm -f "$$pidfile"; \
		fi; \
	done; \
	[ "$$found" = false ] && echo "No bot running"

## healthcheck: Run service healthcheck now
healthcheck:
	$(HOME)/.claude/scripts/healthcheck.sh --restart --notify

## test: Run tests
test:
	uv run pytest

## lint: Run linter
lint:
	uv run ruff check src/ tests/

## clean: Stop all prototype services and clear schedules
clean:
	@$(HOME)/.claude/scripts/clear-service.sh --all 2>/dev/null || true
	@$(HOME)/.claude/scripts/clear-schedule.sh --all 2>/dev/null || true
	@echo "Cleaned all services and schedules"
