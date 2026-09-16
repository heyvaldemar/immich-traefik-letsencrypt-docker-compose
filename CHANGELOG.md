# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **`ghcr.io/immich-app/immich-server:v3.2.1` moved to `ghcr.io/immich-app/immich-server:v3.2.2`.** The freshness check reported the lag; the deploy job booted the stack on the new image before this landed.
- **`ghcr.io/immich-app/immich-machine-learning:v3.2.1` moved to `ghcr.io/immich-app/immich-machine-learning:v3.2.2`.** The freshness check reported the lag; the deploy job booted the stack on the new image before this landed.

## [2.0.3] - 2026-09-15

### Changed

- **`ghcr.io/immich-app/immich-server:v3.2.0` moved to `ghcr.io/immich-app/immich-server:v3.2.1`.** The freshness check reported the lag; the deploy job booted the stack on the new image before this landed.
- **`ghcr.io/immich-app/immich-machine-learning:v3.2.0` moved to `ghcr.io/immich-app/immich-machine-learning:v3.2.1`.** The freshness check reported the lag; the deploy job booted the stack on the new image before this landed.

## [2.0.2] - 2026-09-11

### Changed

- **`ghcr.io/immich-app/immich-server:v3.1.0` moved to `ghcr.io/immich-app/immich-server:v3.2.0`.** The freshness check reported the lag; the deploy job booted the stack on the new image before this landed.
- **`ghcr.io/immich-app/immich-machine-learning:v3.1.0` moved to `ghcr.io/immich-app/immich-machine-learning:v3.2.0`.** The freshness check reported the lag; the deploy job booted the stack on the new image before this landed.

## [2.0.1] - 2026-09-10

### Fixed

- **The archive is read back before it is called a backup.** The library
  tarball was renamed into place on tar's exit code alone. That code has never
  been a statement about whether the file it produced opens, and the gap is not
  theoretical: an archive truncated after tar had already exited still carries
  exit status 0, and the old condition promoted it, logged `Data backup OK`, and
  pruned older archives around it. Measured on a bench in the image this sidecar
  actually runs — a good archive passes, a blocked destination is refused by
  either condition, and a truncated one is caught only by the read-back.

  One `tar -tzf` between the write and the rename now decides it. The database
  dump is untouched: it is written as `pg_dump | gzip` under `set -o pipefail`,
  where a failure at either end of the pipe already fails the pipeline and
  nothing is renamed.

  Found by a new rule in [fleet-ops](https://github.com/heyvaldemar/fleet-ops)
  that asserts this property across every repository, written after one loop
  turned out to be missing it. Eighteen were.

## [2.0.0] - 2026-09-09

### Changed

- **PostgreSQL 14 → 17, which is a migration and not a restart.** Immich's own
  compose file pins PostgreSQL 14, and PostgreSQL 14 goes out of support on 12
  November 2026. Immich publishes the same VectorChord image on 15, 16 and 17,
  and its documentation supports anything from 14 up to 20, so this template
  pins 17: supported until November 2029, and no deployment started from here
  ever has to cross a major it did not choose.

  A data directory belongs to one major, so `docker compose up -d` is not the
  upgrade path. `./immich-upgrade-postgres.sh` dumps the database with the old
  server's own `pg_dump`, refuses to continue unless that dump reads back as a
  valid archive, removes only the PostgreSQL data volume, starts 17 alone,
  loads the dump, and brings the stack back up. VectorChord and pgvector come
  across in the dump as `CREATE EXTENSION` statements and the new image
  supplies them. `./update.sh` calls it when a release moves the major;
  `--dry-run` on either says what would happen. **Take your own copy of the
  dump it leaves behind**: once the old volume is removed it is the only one.
  The library volume is not touched.

### Added

- **The upgrade drill runs the migration.** Where a release changes the
  PostgreSQL major, CI no longer restarts the stack on the previous release's
  volumes — it writes a row into the previous release's database, runs
  `./immich-upgrade-postgres.sh`, and fails the build unless that row reads
  back from the new server. A migration nobody has run is a migration nobody
  should ship.

### Notes

- Verified before release: Immich 3.1.0 on PostgreSQL 17.6 with VectorChord
  0.4.3 and pgvector 0.8.0, sixty-six tables migrated, the eight backup and
  restore scenarios passing, and a marker row written on 14 readable on 17
  with the server healthy and no errors in its log.

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

[Unreleased]: https://github.com/heyvaldemar/immich-traefik-letsencrypt-docker-compose/compare/v2.0.3...HEAD
[2.0.3]: https://github.com/heyvaldemar/immich-traefik-letsencrypt-docker-compose/compare/v2.0.2...v2.0.3
[2.0.2]: https://github.com/heyvaldemar/immich-traefik-letsencrypt-docker-compose/compare/v2.0.1...v2.0.2
[2.0.0]: https://github.com/heyvaldemar/immich-traefik-letsencrypt-docker-compose/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/heyvaldemar/immich-traefik-letsencrypt-docker-compose/releases/tag/v1.0.0
