# lintune-backup — Implementation Context

## What it is
Alpine + openssh-client + cron Docker container. No Laravel inside. Pure bash scripts + crond.
lintune-admin is the control plane: UI, triggering, key management, server registration.

## Container internals

### Entrypoint sequence
1. Read cron schedule: `backup_cron` file in shared volume → `$BACKUP_CRON` env var → hardcoded `0 2 * * *`
2. Write `/etc/crontabs/root`
3. Start `crond`
4. Start `watcher.sh` in foreground

### watcher.sh (polls every 30s)
| File present in shared volume | Action |
|---|---|
| `backup_now` | Remove file → run `backup.sh` |
| `backup_cron` | Read expression → rewrite crontab → `kill -HUP $(pgrep crond)` → remove file |
| *(neither)* | `sleep 30` |

### backup.sh
Orchestrator only. Reads `servers.json` from the shared volume, iterates servers, and for each service pipes the matching script to the remote host via SSH stdin — no pre-copy, no remote cleanup.

```sh
ssh -i $BACKUP_PRIVATE_KEY_PATH lintune-backup@host 'BACKUP_PATH=/backups bash -s' < scripts/backup-mailcow.sh
```

### scripts/ — per-service backup scripts
Each script is self-contained, runs on the remote host, streams output to stdout.
`backup.sh` captures stdout directly to the storage path — no temp file on the remote server.

```sh
ssh -i $KEY lintune-backup@host 'bash -s' < scripts/backup-keycloak.sh \
  > "$BACKUP_STORAGE_PATH/keycloak-$(date +%Y%m%d).tar.gz"
```

| Script | Remote action | Output |
|---|---|---|
| `scripts/backup-keycloak.sh` | `docker exec` MariaDB dump | stdout stream |
| `scripts/backup-mailcow.sh` | Run `backup_and_restore.sh` to temp dir → tar → stdout → cleanup | stdout stream |
| `scripts/backup-nextcloud.sh` | `occ maintenance:mode --on` → tar volume → `occ maintenance:mode --off` | stdout stream |

Mailcow exception: `backup_and_restore.sh` writes to a directory, not stdout. Script runs it to a temp dir on the remote, streams the result back, then cleans up the temp dir.

Variables are injected via the SSH command prefix, not hardcoded in scripts.
Scripts are versioned inside the container image — all servers always get the current version at runtime with no push/sync step needed.

`backup.sh` writes `last_backup.json` to the shared volume on completion:
```json
{ "timestamp": "...", "services": { "mailcow": { "ok": true, "size_mb": 42 }, ... } }
```

## Shared volume (single mount, both containers)
Host path: `/opt/lintune-backup/data`
Mounted as `/backups` in lintune-backup, `/var/lintune-backup` in lintune-admin.

Files written by **lintune-admin**:
- `backup_now` — trigger immediate backup
- `backup_cron` — new cron expression (e.g. `0 3 * * *`)
- `servers.json` — list of servers + services (written at install time and on change)
- `id_backup` — private key file (written at setup, chmod 600 by entrypoint)

Files written by **lintune-backup**:
- `last_backup.json` — status read by lintune-admin UI

## SSH key lifecycle
1. PHP generates RSA keypair at the first install stage IF backup is enabled
2. Private key stored encrypted in `settings` table: `Setting::set('backup.private_key', $key, true)`
3. Private key written to `/opt/lintune-backup/data/id_backup` (the shared volume) at setup
4. Public key pushed to each service server via the SSH connection already open during that stage
5. On each service server: `lintune-backup` system user created, added to `docker` group, public key in `~/.ssh/authorized_keys`

## Cron schedule
- Default: `0 2 * * *`
- Stored in DB: `settings` key `backup.cron` (for UI display and redeploy resilience)
- Written to `.env` as `BACKUP_CRON` at container setup (install.sh / first-time wizard)
- Changing in UI: lintune-admin saves to DB + writes `backup_cron` file to shared volume
- Container startup read order: `backup_cron` file → `$BACKUP_CRON` env var → `0 2 * * *`

## Servers table (lintune-admin DB)
```
servers          — id, label, host, internal_host, ssh_user, ssh_port(22), created_at
server_services  — id, server_id, service ENUM(keycloak|mailcow|nextcloud), service_url, is_default, created_at
```
See root CLAUDE.md "Multi-Instance Architecture" for full schema including the `realms` table.

- `host` — public/external address; used for UI display, service URLs, monitoring
- `internal_host` — private address used for backup SSH; defaults to `host` at insert time
- Backup always SSHes to `internal_host` — when Tailscale/Headscale is added later, just populate `internal_host` with the Tailscale hostname and backup works automatically, no rewrites
- GUI does not expose `internal_host` yet — field is there for forward compatibility

**Written during GUI installer:** each service stage writes the server record with `host = <entered IP/hostname>`, `internal_host = host` (same value, mirroring by default).

**Domain change in lintune-admin settings (MC/NC domain update):**
- Always update `host` to the new domain
- Only update `internal_host` if `internal_host === host` (i.e. it was never explicitly overridden)
- If `internal_host !== host` it was set to a Tailscale hostname — leave it untouched

Written during install stages. `lintune-admin` serialises this to `servers.json` in the shared volume so the backup container can read it without DB access.


## Backup storage
- Default path: `/opt/lintune-backup/backups` (local, created by install.sh)
- Stored in DB: `settings` key `backup.storage_path` (for UI display and container env)
- Written to container env as `BACKUP_STORAGE_PATH`
- NAS support: MSP pre-mounts their NAS at the OS level (e.g. `/mnt/nas`), then sets that path in lintune-admin UI — no install.sh complexity, container is path-agnostic
- Backups land as dated archives: `<service>-YYYYMMDD.tar.gz`

## install.sh responsibilities (additions for backup)
- Always pull and start `lintune-backup` container (even if backup is disabled — container sits idle)
- Create `/opt/lintune-backup/data` on the host (shared volume)
- Create `/opt/lintune-backup/backups` on the host (default storage path)
- Add shared volume to both lintune-admin and lintune-backup compose services

## lintune-admin UI
- Last backup status card (reads `last_backup.json`)
- Backup enable/disable toggle
- Cron schedule input (saved to DB + triggers `backup_cron` file write)
- "Run backup now" button (writes `backup_now` to shared volume)

## Day-2 "Add service" flow
When an MSP adds a new service after initial setup (Settings → "Add new [service]"):
1. MSP enters SSH credentials for the target server
2. Same installer stage logic runs as the wizard (reused, not duplicated)
3. `servers` / `server_services` records written on completion
4. If backup is enabled, backup user creation + key install runs on that server automatically — no separate step

## Open TODOs
- Add **skip** option to the per-service post-install enable flow (currently only retry)
- Manual backup user setup for existing/self-installed services → settings redesign backlog
- Retention policy (keep-last-N) — not yet designed
- Failure notifications (email/webhook) — not yet designed
