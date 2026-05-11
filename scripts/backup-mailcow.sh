#!/bin/bash
set -euo pipefail

# The wrapper script runs everything as root (needed to read mailcow.conf and
# clean up root-owned backup files). See SshInstaller::setupBackupUser().
if [[ ! -f /usr/local/sbin/lintune-mailcow-backup.sh ]]; then
    echo "mailcow backup wrapper not found at /usr/local/sbin/lintune-mailcow-backup.sh" >&2
    exit 1
fi

sudo -n /usr/local/sbin/lintune-mailcow-backup.sh
