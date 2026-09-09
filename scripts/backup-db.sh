#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

ENV_FILE="$PROJECT_ROOT/.env"
if [ -f "$ENV_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line//[:space:]/}" ]] && continue
        if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
            export "$line"
        fi
    done < "$ENV_FILE"
fi

if [ -z "${POSTGRES_PASSWORD:-}" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Error: POSTGRES_PASSWORD is not set in .env or environment!" >&2
    exit 1
fi

CONTAINER_NAME="traccar-database-1"
DB_USER="traccar"
DB_NAME="traccar"
DB_PASSWORD="$POSTGRES_PASSWORD"

BACKUP_BASE_DIR="$PROJECT_ROOT/backups"
LOG_FILE="$PROJECT_ROOT/logs/backup.log"
LOCK_FILE="/tmp/backup-db.lock"
RETENTION_DAYS=7
JOBS=4

mkdir -p "$BACKUP_BASE_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="traccar_$TIMESTAMP.dump"
FINAL_BACKUP_DIR="$BACKUP_BASE_DIR/$BACKUP_NAME"
HOST_TMP_DIR="$PROJECT_ROOT/data/$BACKUP_NAME"
INTERNAL_TMP_DIR="/var/lib/postgresql/data/$BACKUP_NAME"

exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Another backup is already running. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

if ! docker ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "^$CONTAINER_NAME$"; then
    log "Container $CONTAINER_NAME is not running. Aborting."
    exit 1
fi

DB_SIZE_GB=$(docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT CEIL(pg_database_size('$DB_NAME')/1024.0/1024.0/1024.0);" | xargs)
AVAILABLE_SPACE_GB=$(df -m "$BACKUP_BASE_DIR" | awk 'NR==2 {print int($4/1024)}')

log "Database size: ${DB_SIZE_GB}GB, Available host space: ${AVAILABLE_SPACE_GB}GB"

REQUIRED_SPACE_GB=$((DB_SIZE_GB * 2 + 2))
if [ "$AVAILABLE_SPACE_GB" -lt "$REQUIRED_SPACE_GB" ]; then
    log "Not enough space. Need ${REQUIRED_SPACE_GB}GB, have ${AVAILABLE_SPACE_GB}GB. Aborting."
    exit 1
fi

log "Starting multi-threaded backup of $DB_NAME"

if docker exec -e PGPASSWORD="$DB_PASSWORD" "$CONTAINER_NAME" \
    pg_dump -U "$DB_USER" -Fd -j "$JOBS" --blobs "$DB_NAME" -f "$INTERNAL_TMP_DIR" 2>>"$LOG_FILE"; then

    CURRENT_UID=$(id -u)
    docker exec -u root "$CONTAINER_NAME" chown -R "$CURRENT_UID:$CURRENT_UID" "$INTERNAL_TMP_DIR"

    mv "$HOST_TMP_DIR" "$FINAL_BACKUP_DIR"

    SIZE=$(du -sh "$FINAL_BACKUP_DIR" | cut -f1)
    log "Backup successful: $FINAL_BACKUP_DIR (size: $SIZE)"
else
    log "Backup FAILED"
    rm -rf "$HOST_TMP_DIR" "$FINAL_BACKUP_DIR"
    docker exec -u root "$CONTAINER_NAME" rm -rf "$INTERNAL_TMP_DIR" || true
    exit 1
fi

find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "traccar_*.dump" -mtime +$RETENTION_DAYS -exec rm -rf {} \; -print | while read -r line; do
    log "Removed old backup: $line"
done

log "Backup completed successfully"
exit 0
