#!/bin/bash

# Restore the Immich library — originals, uploads and profile images — from one
# of the archives the `backups` container has taken.
#
# The archive deliberately leaves out `thumbs`, `encoded-video` and Immich's own
# `backups` directory: all three are rebuilt from the originals, and together
# they are usually larger than the originals themselves. After a restore, run
# the "Generate Thumbnails" and "Transcode Videos" jobs from the web UI's
# Administration → Jobs page to rebuild what was left out.
#
#     chmod +x immich-restore-library.sh
#     ./immich-restore-library.sh
#
# Restore the DATABASE FIRST, with immich-restore-database.sh, and then the
# library from the same timestamp. The database is the index; a library newer
# than its database has files no asset row points at, and a database newer than
# its library has rows pointing at files that are not there.
set -euo pipefail
cd "$(dirname "$0")"

COMPOSE_FILE="${DOCKER_COMPOSE_FILE:-immich-traefik-letsencrypt-docker-compose.yml}"
PROJECT="${COMPOSE_PROJECT_NAME:-immich}"

dc() { docker compose -f "$COMPOSE_FILE" -p "$PROJECT" "$@"; }

SERVER_CONTAINER="$(dc ps -aq immich-server | head -n 1)"
BACKUPS_CONTAINER="$(dc ps -aq backups | head -n 1)"
[ -n "$SERVER_CONTAINER" ] || { echo "the immich-server container was not found — is the stack up?" >&2; exit 1; }
[ -n "$BACKUPS_CONTAINER" ] || { echo "the backups container was not found — is the stack up?" >&2; exit 1; }

# Every value from the backups container: the environment its loop reads, so
# a path or name set in .env is the one used here too. This used to read the
# shell that ran it, which has none of them unless someone exported them.
env_of() { docker exec "$BACKUPS_CONTAINER" printenv "$1"; }
BACKUP_PATH="$(env_of DATA_BACKUPS_PATH)"; RESTORE_PATH="$(env_of DATA_PATH)"
case "$RESTORE_PATH" in ""|/) echo "DATA_PATH is '$RESTORE_PATH'; refusing to clear under it" >&2; exit 1 ;; esac

SELECTED_LIBRARY_BACKUP="${1:-}"
if [ -z "$SELECTED_LIBRARY_BACKUP" ]; then
  echo "--> All available library backups:"
  docker exec "$BACKUPS_CONTAINER" sh -c "ls -1 $BACKUP_PATH" || true

  echo "--> Copy and paste the backup name from the list above to restore the library and press [ENTER]
  --> Example: immich-library-backup-YYYY-MM-DD_hh-mm.tar.gz"
  echo -n "--> "
  read -r SELECTED_LIBRARY_BACKUP
fi
[ -n "$SELECTED_LIBRARY_BACKUP" ] || { echo "nothing selected, nothing restored" >&2; exit 1; }

if ! docker exec "$BACKUPS_CONTAINER" sh -c "tar -tzf '${BACKUP_PATH}/${SELECTED_LIBRARY_BACKUP}' > /dev/null"; then
  echo "that file is not a readable tar archive — nothing has been stopped or deleted" >&2
  exit 1
fi
echo "--> $SELECTED_LIBRARY_BACKUP was selected and reads as a valid archive"

echo "--> Stopping the server..."
docker stop "$SERVER_CONTAINER" > /dev/null
trap 'docker start "$SERVER_CONTAINER" > /dev/null' EXIT  # started again whatever happens

echo "--> Restoring the library..."
# The archive stores paths relative to /, so it extracts there. Only the
# directories the archive carries are cleared: wiping all of RESTORE_PATH would
# also delete the thumbnails and transcodes of assets this archive still holds,
# and those take hours to rebuild.
docker exec "$BACKUPS_CONTAINER" bash -c "set -o pipefail
  for d in library upload profile; do rm -rf '${RESTORE_PATH}'/\$d; done
  tar -zxpf '${BACKUP_PATH}/${SELECTED_LIBRARY_BACKUP}' -C /"
echo "--> Library recovery completed."

echo "--> Starting the server..."
docker start "$SERVER_CONTAINER" > /dev/null
echo "--> Run Administration -> Jobs -> Generate Thumbnails and Transcode Videos to rebuild what the archive leaves out."
