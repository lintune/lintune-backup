FROM alpine:3.19

RUN apk add --no-cache bash openssh-client jq dcron

WORKDIR /app
COPY entrypoint.sh watcher.sh backup.sh ./
COPY scripts/ ./scripts/
RUN chmod +x entrypoint.sh watcher.sh backup.sh scripts/*.sh

VOLUME ["/backups", "/storage"]

ENTRYPOINT ["/app/entrypoint.sh"]
