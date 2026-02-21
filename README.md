# s3-mover

A minimal Docker sidecar that watches a shared volume for files and uploads them to S3-compatible storage.

## Features

- **Multiple modes**: Run once (`once`), watch for changes (`watch`), or scheduled (`cron`)
- **Flexible S3 support**: Works with AWS S3, MinIO, and any S3-compatible storage
- **Multi-architecture**: Builds for both `linux/amd64` and `linux/arm64`
- **Automatic cleanup**: Optionally delete files after successful upload
- **Subdirectory preservation**: Maintain directory structure when uploading

## Quick Start

### Docker Compose

```yaml
version: '3.8'

volumes:
  app-data:

services:
  your-app:
    image: your-app:latest
    volumes:
      - app-data:/app/output

  s3-mover:
    image: ghcr.io/cougz/s3-mover:latest
    restart: unless-stopped
    environment:
      S3_ENDPOINT: "${S3_ENDPOINT}"
      S3_ACCESS_KEY: "${S3_ACCESS_KEY}"
      S3_SECRET_KEY: "${S3_SECRET_KEY}"
      S3_BUCKET: "${S3_BUCKET}"
      SOURCE_PATH: "/data"
      FILE_PATTERN: "*.json"
    volumes:
      - app-data:/data
```

Copy `.env.example` to `.env` and fill in your credentials:
```bash
cp .env.example .env
docker compose up -d
```

### Standalone Docker

```bash
docker run --rm \
  -e S3_ENDPOINT=https://s3.amazonaws.com \
  -e S3_ACCESS_KEY=your-access-key \
  -e S3_SECRET_KEY=your-secret-key \
  -e S3_BUCKET=my-bucket \
  -v /path/to/files:/data \
  ghcr.io/cougz/s3-mover:latest
```

## Configuration

All configuration is done via environment variables:

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `S3_ENDPOINT` | S3-compatible endpoint URL | `https://s3.amazonaws.com` |
| `S3_ACCESS_KEY` | Access key ID | `AKIAIOSFODNN7EXAMPLE` |
| `S3_SECRET_KEY` | Secret access key | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `S3_BUCKET` | Bucket name | `my-backup-bucket` |
| `SOURCE_PATH` | Path to watch for files | `/data` |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `S3_DESTINATION` | `""` | Destination prefix in bucket (e.g., `backups/`) |
| `FILE_PATTERN` | `"*"` | Glob pattern to match files (e.g., `"*.json"`) |
| `DELETE_AFTER_UPLOAD` | `"true"` | Delete local files after successful upload |
| `MODE` | `"watch"` | Operation mode: `once`, `watch`, or `cron` |
| `CRON_SCHEDULE` | `"*/5 * * * *"` | Cron schedule (only in `cron` mode) |
| `MOVE_SUBDIRS` | `"false"` | Preserve subdirectory structure in S3 |
| `MC_EXTRA_ARGS` | `""` | Additional flags to pass to `mc cp` |

## Modes

### `once` (default for non-interactive runs)
Upload all matching files once and exit:
```bash
docker run --rm -e MODE=once ghcr.io/cougz/s3-mover:latest
```

### `watch` (default)
Continuously monitor for new/modified files using inotify:
```bash
docker run -e MODE=watch ghcr.io/cougz/s3-mover:latest
```

### `cron`
Run uploads on a schedule using cron:
```bash
docker run -e MODE=cron -e CRON_SCHEDULE="0 */2 * * *" ghcr.io/cougz/s3-mover:latest
```

## Example Use Cases

### Speedtest Results Backup

Automatically upload speedtest results to S3:

```yaml
services:
  speedtest:
    image: ghcr.io/akvorrat/netzbremse-measurement:latest
    environment:
      NB_SPEEDTEST_JSON_OUT_DIR: '/app/json-results'
    volumes:
      - speedtest-data:/app/json-results

  s3-mover:
    image: ghcr.io/cougz/s3-mover:latest
    environment:
      S3_ENDPOINT: "${S3_ENDPOINT}"
      S3_ACCESS_KEY: "${S3_ACCESS_KEY}"
      S3_SECRET_KEY: "${S3_SECRET_KEY}"
      S3_BUCKET: "${S3_BUCKET}"
      S3_DESTINATION: "speedtest-results"
      SOURCE_PATH: "/data"
      FILE_PATTERN: "*.json"
      MODE: "watch"
    volumes:
      - speedtest-data:/data
```

### Periodic Log Backup

Upload logs every hour:

```yaml
services:
  s3-mover:
    image: ghcr.io/cougz/s3-mover:latest
    environment:
      MODE: "cron"
      CRON_SCHEDULE: "0 * * * *"
      S3_ENDPOINT: "${S3_ENDPOINT}"
      S3_ACCESS_KEY: "${S3_ACCESS_KEY}"
      S3_SECRET_KEY: "${S3_SECRET_KEY}"
      S3_BUCKET: "${S3_BUCKET}"
      SOURCE_PATH: "/data"
      FILE_PATTERN: "*.log"
    volumes:
      - ./logs:/data
```

## Security Notes

- Never commit `.env` files to version control
- Use GitHub Secrets or similar secret management in production
- The Docker image includes `mc` (MinIO client) for S3 operations
- Run containers as non-root (the image uses a dedicated `mover` user with UID 1001)

## Building

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t s3-mover .
```

## License

MIT

## Support

For issues, questions, or contributions, please visit [GitHub](https://github.com/cougz/s3-mover).
