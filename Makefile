.PHONY: help up down restart logs ps build pull clean backup restore

GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
RED    := $(shell tput -Txterm setaf 1)
RESET  := $(shell tput -Txterm sgr0)

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-15s$(RESET) %s\n", $$1, $$2}'

up:
	@if [ ! -f .env ]; then \
		echo "$(RED)Error! .env file is missing!$(RESET)"; \
		echo "$(YELLOW)Please run: cp .env.example .env and configure your variables before startup.$(RESET)"; \
		exit 1; \
	fi
	docker compose up -d

down:
	docker compose down

restart:
	docker compose restart

logs:
	docker compose logs -f

ps:
	docker compose ps

build:
	docker compose build

pull:
	docker compose pull

clean:
	@echo "$(RED)WARNING: This action is destructive and WILL COMPLETELY DESTROY your database volumes!$(RESET)"
	@read -p "Are you absolutely sure you want to proceed? [y/N]: " ans </dev/tty; \
	if [ "$$ans" != "y" ] && [ "$$ans" != "Y" ]; then \
		echo "$(GREEN)Operation aborted. Your data is safe.$(RESET)"; \
		exit 1; \
	fi
	docker compose down -v
	@echo "$(YELLOW)Done. All containers stopped and named volumes completely destroyed.$(RESET)"

backup:
	@echo "$(GREEN)Starting manual backup...$(RESET)"
	docker compose exec backup /backup.sh
	@echo "$(GREEN)Backup completed.$(RESET)"

restore:
	@if [ -z "$(FILE)" ]; then \
		echo "$(RED)Error! Please specify the backup file path.$(RESET)"; \
		echo "$(YELLOW)Example: make restore FILE=daily/traccar-latest.sql.gz$(RESET)"; \
		exit 1; \
	fi
	@CLEAN_FILE=$$(echo "$(FILE)" | sed 's|^backups/||'); \
	HOST_FILE_PATH="backups/$$CLEAN_FILE"; \
	if [ ! -f "$$HOST_FILE_PATH" ]; then \
		echo "$(RED)Error! Backup file not found on host at: $$HOST_FILE_PATH$(RESET)"; \
		exit 1; \
	fi; \
	docker compose exec -T backup /restore.sh /backups/$$CLEAN_FILE
