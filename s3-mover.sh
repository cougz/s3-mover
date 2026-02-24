#!/bin/sh
set -eu

log()  { echo "[$(date -u +%H:%M:%S)] [INFO]  $*"; }
warn() { echo "[$(date -u +%H:%M:%S)] [WARN]  $*"; }
die()  { echo "[$(date -u +%H:%M:%S)] [ERROR] $*" >&2; exit 1; }

: "${S3_ENDPOINT:?S3_ENDPOINT is required}"
: "${S3_ACCESS_KEY:?S3_ACCESS_KEY is required}"
: "${S3_SECRET_KEY:?S3_SECRET_KEY is required}"
: "${S3_BUCKET:?S3_BUCKET is required}"
: "${SOURCE_PATH:?SOURCE_PATH is required}"

S3_DESTINATION="${S3_DESTINATION:-}"
FILE_PATTERN="${FILE_PATTERN:-*}"
DELETE_AFTER_UPLOAD="${DELETE_AFTER_UPLOAD:-true}"
MODE="${MODE:-watch}"
CRON_SCHEDULE="${CRON_SCHEDULE:-*/5 * * * *}"
MOVE_SUBDIRS="${MOVE_SUBDIRS:-false}"
MC_EXTRA_ARGS="${MC_EXTRA_ARGS:-}"

s3_dest() {
    local file="$1"
    local dest="s3target/${S3_BUCKET}"
    [ -n "$S3_DESTINATION" ] && dest="${dest}/${S3_DESTINATION}"
    if [ "$MOVE_SUBDIRS" = "true" ]; then
        local rel
        rel=$(dirname "$file" | sed "s|^${SOURCE_PATH}||;s|^/||")
        [ -n "$rel" ] && dest="${dest}/${rel}"
    fi
    echo "${dest}/"
}

upload_file() {
    local file="$1"
    local dest
    dest=$(s3_dest "$file")
    log "Uploading: $file  →  $dest"
    # shellcheck disable=SC2086
    if mc cp $MC_EXTRA_ARGS "$file" "$dest"; then
        log "OK: $(basename "$file")"
        if [ "$DELETE_AFTER_UPLOAD" = "true" ]; then
            if rm -f "$file" 2>/dev/null; then
                log "Deleted local: $file"
            else
                warn "Could not delete $file (permission denied or file removed)"
            fi
        fi
    else
        warn "FAILED: $file — will retry next cycle"
    fi
}

scan_and_upload() {
    local found=0
    while IFS= read -r file; do
        upload_file "$file"
        found=$((found + 1))
    done <<EOF
$(find "$SOURCE_PATH" -type f -name "$FILE_PATTERN" 2>/dev/null)
EOF
    [ "$found" -eq 0 ] && log "No files matching '$FILE_PATTERN' in $SOURCE_PATH"
}

log "Configuring S3 → $S3_ENDPOINT  bucket: $S3_BUCKET"
mc alias set s3target "$S3_ENDPOINT" "$S3_ACCESS_KEY" "$S3_SECRET_KEY" --api S3v4 >/dev/null
mc ls "s3target/${S3_BUCKET}" >/dev/null 2>&1 \
    || die "Cannot reach bucket '${S3_BUCKET}' — check endpoint and credentials"
log "Bucket reachable. Mode: $MODE"

if [ "$MODE" = "once" ]; then
    scan_and_upload
    log "Done."
    exit 0
fi

if [ "$MODE" = "cron" ]; then
    log "Cron schedule: $CRON_SCHEDULE"
    cat > /tmp/s3mover-cron <<EOF
$CRON_SCHEDULE S3_ENDPOINT="$S3_ENDPOINT" S3_ACCESS_KEY="$S3_ACCESS_KEY" S3_SECRET_KEY="$S3_SECRET_KEY" S3_BUCKET="$S3_BUCKET" S3_DESTINATION="$S3_DESTINATION" SOURCE_PATH="$SOURCE_PATH" FILE_PATTERN="$FILE_PATTERN" DELETE_AFTER_UPLOAD="$DELETE_AFTER_UPLOAD" MOVE_SUBDIRS="$MOVE_SUBDIRS" MC_EXTRA_ARGS="$MC_EXTRA_ARGS" MODE=once /app/s3-mover.sh >> /proc/1/fd/1 2>&1
EOF
    crontab /tmp/s3mover-cron && rm /tmp/s3mover-cron
    scan_and_upload
    log "Handing off to crond..."
    exec crond -f -l 6
fi

if [ "$MODE" = "watch" ]; then
    log "Watching $SOURCE_PATH for '$FILE_PATTERN'"
    log "Initial scan skipped in watch mode - only monitoring for new/changed files"
    
    # Startup grace period to ignore initial inotify events from Docker volume mount
    START_TIME=$(date +%s)
    GRACE_SECONDS="${WATCH_GRACE_PERIOD:-10}"
    log "Grace period: ${GRACE_SECONDS}s - ignoring events before"
    
    inotifywait -m -r \
        --event close_write \
        --event moved_to \
        --format '%w%f' \
        "$SOURCE_PATH" | \
    while IFS= read -r file; do
        case "$file" in
            $FILE_PATTERN)
                # Skip files modified during grace period (startup events)
                file_mtime=$(stat -c %Y "$file" 2>/dev/null || echo 0)
                if [ "$file_mtime" -ge "$((START_TIME + GRACE_SECONDS))" ]; then
                    upload_file "$file"
                else
                    log "Skipping: $file (old file from before watch start)"
                fi
                ;;
            *) : ;;
        esac
    done
fi
