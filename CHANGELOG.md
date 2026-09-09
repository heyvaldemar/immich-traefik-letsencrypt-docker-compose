# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_(no unreleased changes yet)_

## [1.0.0] - 2026-09-09

First release. A production deployment of Immich behind Traefik, built to the
fleet standard established in
[keycloak-traefik-letsencrypt-docker-compose](https://github.com/heyvaldemar/keycloak-traefik-letsencrypt-docker-compose).

### Added

- **Immich v3.1.0 behind Traefik with Let's Encrypt TLS.** Five images pinned
  by `tag@sha256:<digest>` in the compose `x-images` block: the server, the
  machine-learning service, Immich's own PostgreSQL 14 build carrying
  VectorChord 0.4.3 and pgvector 0.8.1, Valkey 9, and Traefik 3.7. The server
  and machine-learning pins carry the same version and CI fails the run if they
  ever disagree, because Immich ships them as one release.
- **Backups of both halves of the state.** A `pg_dump --clean --if-exists` of
  the database and a `tar.gz` of the library, each written to a `.partial` name
  and renamed only on success, with a `.failed` rename that keeps the evidence
  when a cycle fails. The library archive leaves out `thumbs`,
  `encoded-video` and Immich's own `backups` directory: the first two are
  rebuilt from the originals by a job in the web UI and together are usually
  larger than the originals, and the third holds dumps this loop already takes
  properly. `IMMICH_BACKUP_EXCLUDES=` archives everything.
- **Two restore scripts, database and library**, each of which validates the
  archive it was handed before it stops anything or deletes anything. The
  library script clears only the directories the archive carries, so a restore
  does not throw away thumbnails and transcodes that still belong to assets the
  archive holds.
- **Deployment Verification workflow.** shellcheck and actionlint, Trivy scans
  of all five pinned images, a daily freshness check, and a deploy job that
  requires the API to answer `{"res":"pong"}` through Traefik, the
  machine-learning container to answer the server over the internal network,
  both vector extensions to be present in the running database, a dump and an
  archive to be produced and readable, the eight backup and restore scenarios
  to pass, and Immich to come back up on the database the restore test replaced
  underneath it.
- **`update.sh`** moves between release tags, refuses to cross a major
  unattended, refuses to run over local changes, and names any variable that
  became required since the deployed version before anything moves.
- **Container hardening**: `no-new-privileges` on every service, `cap_drop:
  [ALL]` with a named add-back list on the reverse proxy, the database, the
  cache and the backups sidecar, resource limits and reservations on all six
  services, and a sixty-second `stop_grace_period` on the database and the
  cache so a checkpoint or a save is not cut short by SIGKILL.

### Notes for anyone adapting this from Immich's own compose file

- **No `command:` on the database.** Older instructions pass
  `shared_preload_libraries` and tuning arguments to the PostgreSQL container.
  Those settings live inside Immich's image now, selected between an SSD and an
  HDD profile by `DB_STORAGE_TYPE`, and passing them by hand is how a stack
  ends up with a database that will not start.
- **The cache is Valkey, not Redis**, following upstream. The service is still
  called `redis` because that is the hostname Immich defaults to.
- **The backups sidecar disables the healthcheck it inherits.** It runs the
  database image, whose built-in probe asks a PostgreSQL server that is not
  running in that container whether it is ready. Left inherited, the container
  is unhealthy forever and the upgrade drill waits for it.

[Unreleased]: https://github.com/heyvaldemar/immich-traefik-letsencrypt-docker-compose/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/heyvaldemar/immich-traefik-letsencrypt-docker-compose/releases/tag/v1.0.0
