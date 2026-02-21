# syntax=docker/dockerfile:1
FROM alpine:3.21 AS base

RUN apk add --no-cache \
    curl \
    inotify-tools \
    ca-certificates \
    tzdata

RUN ARCH="$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')" && \
    curl -fsSL "https://dl.min.io/client/mc/release/linux-${ARCH}/mc" \
         -o /usr/local/bin/mc && \
    chmod +x /usr/local/bin/mc && \
    mc --version

FROM base AS final

RUN addgroup -g 1001 mover && \
    adduser -u 1001 -G mover -s /bin/sh -D mover && \
    mkdir -p /app /data && \
    chown mover:mover /app /data

COPY --chmod=755 s3-mover.sh /app/s3-mover.sh

ENV S3_ENDPOINT="" S3_ACCESS_KEY="" S3_SECRET_KEY="" S3_BUCKET="" \
    S3_DESTINATION="" SOURCE_PATH="/data" FILE_PATTERN="*" \
    DELETE_AFTER_UPLOAD="true" MODE="watch" CRON_SCHEDULE="*/5 * * * *" \
    MOVE_SUBDIRS="false" MC_EXTRA_ARGS=""

WORKDIR /app
VOLUME ["/data"]
USER mover
STOPSIGNAL SIGTERM
ENTRYPOINT ["/app/s3-mover.sh"]
