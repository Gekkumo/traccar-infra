#!/bin/bash
set -euo pipefail

CONTAINER_NAME="traccar-database-1"
DB_USER="traccar"
DB_NAME="traccar"
BACKUP_DIR="./backups"
LOG_FILE="./logs/backup.log"
RETENTION_DAYS=7

mkdir -p "$BACKUP_DIR"

BACKUP_FILE="$BACKUP_DIR/traccar_$(date +%Y%m%d_%H%M%S).dump"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "🚀 Starting backup of database $DB_NAME"

if docker exec "$CONTAINER_NAME" pg_dump -U "$DB_USER" -Fc -j 4 --blobs "$DB_NAME" > "$BACKUP_FILE"; then
    SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    log "Backup successful: $BACKUP_FILE (size: $SIZE)"
else
    log "Backup FAILED for $DB_NAME"
    exit 1
fi

log "Cleaning up backups older than $RETENTION_DAYS days"
find "$BACKUP_DIR" -name "traccar_*.dump" -type f -mtime +$RETENTION_DAYS -delete

log "Backup process completed"