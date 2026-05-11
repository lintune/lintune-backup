# lintune-backup

Automated backup service for Lintune-managed servers. Runs as a standalone Docker container — no Laravel, no database, just bash + cron — and is controlled entirely through a shared volume by lintune-admin.

## How it works

The container runs two processes:

- **crond** — executes `backup.sh` on a configurable schedule (default: 02:00 daily)
- **watcher.sh** — polls the shared volume every 30 seconds for trigger files from lintune-admin

### Backup targets

| Service | Method |
|---|---|
| Mailcow | `helper-scripts/backup_and_restore.sh backup all` |
| Keycloak | `docker exec` MariaDB dump |
| Nextcloud | maintenance mode → tar volume → maintenance off |

Backups are written to `/backups/` (the shared volume). After each run, `last_backup.json` is written with per-service status, size, and timestamp — lintune-admin reads this to display backup status in the UI.

## Shared volume

Both `lintune-admin` and `lintune-backup` mount `/opt/lintune-backup/data` on the host:

| File | Written by | Purpose |
|---|---|---|
| `backup_now` | lintune-admin | Trigger an immediate backup run |
| `backup_cron` | lintune-admin | Update the cron schedule (e.g. `0 3 * * *`) |
| `servers.json` | lintune-admin | Server + service list for backup.sh |
| `id_backup` | lintune-admin | SSH private key (chmod 600 by entrypoint) |
| `last_backup.json` | lintune-backup | Last run status, read by lintune-admin UI |

## Setup

Setup is handled automatically by the Lintune web installer. When "Enable backup" is toggled on:

1. An SSH keypair is generated in PHP (first install stage)
2. The private key is stored encrypted in the lintune-admin `settings` table and written to the shared volume
3. During each service install stage (Keycloak, Mailcow, Nextcloud), the existing SSH connection creates a `lintune-backup` system user, adds it to the `docker` group, and installs the public key

If backup is disabled, the container starts but sits idle — no accounts or keys are created on service servers.

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `BACKUP_CRON` | `0 2 * * *` | Initial cron schedule (overridden by `backup_cron` file) |
| `BACKUP_PRIVATE_KEY_PATH` | `/backups/id_backup` | Path to SSH private key |
| `BACKUP_STORAGE_PATH` | `/opt/lintune-backup/backups` | Where backup archives are written. Point at a pre-mounted NAS path to use network storage — the container is path-agnostic. |

The cron schedule is read at startup in this order: `backup_cron` file → `$BACKUP_CRON` env var → `0 2 * * *`. When changed via the lintune-admin UI, the new schedule is saved to the database and a `backup_cron` file is written to the shared volume — no container restart required.

## Docker image

```
ghcr.io/lintune/lintune-backup:latest
```

Built from `Dockerfile` in this directory (Alpine base, openssh-client, bash, dcron).

## Project structure

```
lintune-backup/
├── Dockerfile
├── entrypoint.sh          # reads schedule, writes crontab, starts crond + watcher
├── watcher.sh             # polls shared volume for trigger files
├── backup.sh              # orchestrator: reads servers.json, loops servers, pipes scripts
└── scripts/
    ├── backup-keycloak.sh
    ├── backup-mailcow.sh
    └── backup-nextcloud.sh
```

Each service script is piped to the remote host at runtime (`ssh host 'bash -s' < scripts/backup-mailcow.sh`) — no pre-copy or cleanup needed, and scripts are always the current container version.

## Part of Lintune

lintune-backup is one component of the [Lintune](https://lintune.xyz) open-source MSP platform — a self-hosted alternative to Microsoft 365, providing a single identity, password, and URL for end users.
