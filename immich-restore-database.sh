#!/bin/bash

# Restore the Immich database from one of the backups the `backups` container
# has taken.
#
# 1. Finds the server and backups containers through compose, not by name: a
#    container_name override, or another stack whose containers share a prefix,
#    defeats a `docker ps` name filter.
# 2. Lists what is available and asks which one.
# 3. Stops the server, so nothing writes while the database is being replaced
#    and so Immich re-reads the schema when it comes back.
# 4. Drops the database, recreates it, and loads the dump.
# 5. Starts the server again.
#
#     chmod +x immich-restore-database.sh
#     ./immich-restore-database.sh
#
# The dump the backups container writes is a plain `pg_dump --clean --if-exists`
# of the Immich database, so it carries the VectorChord and pgvector extensions
# and the vector indexes with it. Immich's own documentation describes a
# different sequence, with a search_path rewrite, for dumps taken by Immich's
# in-app backup and restored into a database that already exists. This script
# recreates the database first, which is why no rewrite is needed here — and
# the deploy job proves the roundtrip on every run.
set -euo pipefail
cd "$(dirname "$0")"

COMPOSE_FILE="${DOCKER_COMPOSE_FILE:-immich-traefik-letsencrypt-docker-compose.yml}"
PROJECT="${COMPOSE_PROJECT_NAME:-immich}"
DB_NAME="${IMMICH_DB_NAME:-immich}"
DB_USER="${IMMICH_DB_USER:-immichdbuser}"
BACKUP_PATH="${POSTGRES_BACKUPS_PATH:-/srv/immich-postgres/backups}"

dc() { docker compose -f "$COMPOSE_FILE" -p "$PROJECT" "$@"; }

SERVER_CONTAINER="$(dc ps -aq immich-server | head -n 1)"
BACKUPS_CONTAINER="$(dc ps -aq backups | head -n 1)"
[ -n "$SERVER_CONTAINER" ] || { echo "the immich-server container was not found — is the stack up?" >&2; exit 1; }
[ -n "$BACKUPS_CONTAINER" ] || { echo "the backups container was not found — is the stack up?" >&2; exit 1; }

echo "--> All available database backups:"
docker exec "$BACKUPS_CONTAINER" sh -c "ls -1 $BACKUP_PATH" || true

echo "--> Copy and paste the backup name from the list above to restore the database and press [ENTER]
--> Example: immich-postgres-backup-YYYY-MM-DD_hh-mm.gz"
echo -n "--> "
read -r SELECTED_DATABASE_BACKUP
[ -n "$SELECTED_DATABASE_BACKUP" ] || { echo "nothing selected, nothing restored" >&2; exit 1; }

if ! docker exec "$BACKUPS_CONTAINER" sh -c "gzip -t '${BACKUP_PATH}/${SELECTED_DATABASE_BACKUP}'"; then
  echo "that file is not a readable gzip archive — nothing has been stopped or dropped" >&2
  exit 1
fi
echo "--> $SELECTED_DATABASE_BACKUP was selected and reads as a valid archive"

echo "--> Stopping the server..."
docker stop "$SERVER_CONTAINER" > /dev/null

echo "--> Restoring the database..."
docker exec "$BACKUPS_CONTAINER" bash -c "set -o pipefail
  dropdb --force -h postgres -p 5432 -U '$DB_USER' '$DB_NAME' \
  && createdb -h postgres -p 5432 -U '$DB_USER' '$DB_NAME' \
  && gzip -dc '${BACKUP_PATH}/${SELECTED_DATABASE_BACKUP}' \
     | psql -q -o /dev/null -v ON_ERROR_STOP=1 -h postgres -p 5432 -U '$DB_USER' -d '$DB_NAME'"
echo "--> Database recovery completed."

echo "--> Starting the server..."
docker start "$SERVER_CONTAINER" > /dev/null
echo "--> Immich is starting on the restored database; it runs its migrations before it answers."
