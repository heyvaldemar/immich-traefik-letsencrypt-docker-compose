# Immich + Traefik + Let's Encrypt on Docker Compose

[![Deployment Verification](https://github.com/heyvaldemar/immich-traefik-letsencrypt-docker-compose/actions/workflows/deployment-verification.yml/badge.svg?branch=main)](https://github.com/heyvaldemar/immich-traefik-letsencrypt-docker-compose/actions/workflows/deployment-verification.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

This repository deploys Immich (a self-hosted photo and video library with search, face recognition and mobile sync) behind Traefik with automatic Let's Encrypt TLS, backed by PostgreSQL with the vector extensions Immich requires and by Valkey, with scheduled backups of both the database and the library and companion restore scripts.

## Getting started

```bash
# 1. Clone
git clone https://github.com/heyvaldemar/immich-traefik-letsencrypt-docker-compose
cd immich-traefik-letsencrypt-docker-compose

# 2. Create the two Docker networks the stack expects
docker network create traefik-network
docker network create immich-network

# 3. Copy the environment template and fill in required values
cp .env.example .env
$EDITOR .env
# ^ Required: IMMICH_DB_PASSWORD, IMMICH_HOSTNAME,
#   TRAEFIK_HOSTNAME, TRAEFIK_ACME_EMAIL, TRAEFIK_BASIC_AUTH.

# 4. Deploy
docker compose -f immich-traefik-letsencrypt-docker-compose.yml -p immich up -d
```

Immich runs its database migrations on first start and answers nothing until they finish; on a small host that is two to four minutes. The first account registered becomes the administrator, so open the site and register it before anyone else can.

### What success looks like

```bash
docker compose -f immich-traefik-letsencrypt-docker-compose.yml -p immich ps
curl -sk "https://${IMMICH_HOSTNAME}/api/server/ping"
# Expected: {"res":"pong"}
```

`ps` should show `postgres`, `redis`, `immich-server`, `immich-machine-learning` and `traefik` healthy, and `backups` running with no health check of its own.

### Common first-deploy issues

- **`immich-server` restarts before it ever answers.** It is almost always the database: Immich checks the VectorChord version at startup and refuses to run against one it does not support. `docker compose -p immich logs postgres` names it.
- **The machine-learning container exits with code 132 on an older server.** Since Immich 3, the machine-learning image on amd64 requires an `x86-64-v2` CPU. Exit 137 is the other thing: out of memory, so raise `IMMICH_ML_MEMORY_LIMIT`.
- **Cert issuance fails.** DNS has not propagated, or port 80 is not reachable from the internet.
- **Networks not found.** Step 2 was skipped.
- **Uploads from a phone stop part way.** A single large video is one long request; raise `IMMICH_UPLOAD_TIMEOUT`.

## Updating

`./update.sh` moves this checkout to the latest release tag — a combination this repository's CI has booted, upgraded from the previous release on the same volumes, and smoke-tested — and then runs `docker compose up -d`. It refuses to cross a major version unattended, refuses to run over local changes, and names any variable that became required since your version before anything has moved. `./update.sh --dry-run` says what would happen. Every release cut by fleet triage also carries what upstream changed, read from its release notes against this compose file.

Two Immich-specific cautions the upstream release notes are explicit about. Downgrading is not supported, even within a minor version. And the mobile app is compatible with the current and previous major version while the server is only compatible with the matching one, so upgrade the app before the server when a major lands.

## Supply chain trust

Five images pinned to `tag@sha256:<digest>` as interpolation defaults in the compose `x-images` block:

- [`ghcr.io/immich-app/immich-server`](https://github.com/immich-app/immich/pkgs/container/immich-server): the application
- [`ghcr.io/immich-app/immich-machine-learning`](https://github.com/immich-app/immich/pkgs/container/immich-machine-learning): search, face recognition and smart tagging
- [`ghcr.io/immich-app/postgres`](https://github.com/immich-app/immich/pkgs/container/postgres): PostgreSQL 14 with VectorChord and pgvector, built by Immich
- [`valkey/valkey`](https://hub.docker.com/r/valkey/valkey): the job queue
- [`traefik`](https://hub.docker.com/_/traefik): reverse proxy

`git pull` alone delivers the tested combination; an `*_IMAGE_TAG` variable in `.env` overrides deliberately. The server and the machine-learning image are one release split across two containers: Immich supports no combination where they differ, so both version variables carry the same version and CI fails the run if they ever disagree.

Two override levels exist per image. `<PREFIX>_IMAGE_VERSION` in `.env` swaps only the version of that image (Compose then pulls the tag, without a digest) and leaves every other pin as tested; `<PREFIX>_IMAGE_TAG` replaces the whole reference, digest included. The variable names are listed in `.env.example`. Nested defaults need Docker Compose v2.5 or newer (2022); v2.0 to v2.4 leave the inner `${...}` unexpanded and `docker compose up` fails with an invalid reference instead of deploying something unexpected.

The daily `check-pin-freshness` CI job re-resolves each pin against its registry and compares the pinned Immich and Traefik versions against the latest upstream releases. GitHub Actions are pinned by commit SHA; Dependabot keeps those fresh.

## The database is not an ordinary PostgreSQL

Immich does not run stock PostgreSQL. It ships its own image carrying VectorChord and pgvector, and the server reads the VectorChord version at startup and refuses to run against one outside the range it supports. Two consequences for anyone deploying this template:

- **The database pin is not free to move.** It travels with the Immich release, not with the PostgreSQL release calendar. The freshness job watches its digest; the version itself changes when Immich changes it.
- **Older instructions pass `command:` arguments to this container.** They set `shared_preload_libraries` and some tuning by hand. That is no longer correct: those settings live inside the image now, selected between an SSD and an HDD profile by `IMMICH_DB_STORAGE_TYPE`. This compose file passes no `command:` overrides for that reason.

CI asserts both extensions are present in the running database on every push, because a template that pins the wrong database image boots cleanly and fails the first time somebody searches.

## Production checklist

- [ ] **Register the administrator account immediately after deploy.** Until you do, the first stranger who finds the URL can.
- [ ] **Strong `IMMICH_DB_PASSWORD`**: generate it per `.env.example`, letters and digits only.
- [ ] **Regenerate the Traefik dashboard hash.** The one in `.env.example` is a placeholder.
- [ ] **Host-mount the backup volumes.** By default the dumps and archives land in named volumes: if the host dies, they die with it. Bind-mount them to a directory covered by your off-host backup solution.
- [ ] **Size the library volume for growth.** Originals, thumbnails and transcodes live together; thumbnails and transcodes are roughly the size of the originals again.
- [ ] **Know the restore procedure.** Run both restore scripts against a test deployment before you need them in production.
- [ ] **Check the CPU if you use machine learning.** On amd64 the machine-learning image needs `x86-64-v2`; on an older host, remove that service and set the jobs to disabled.

## Backups and restore

The `backups` container runs one loop: `pg_dump --clean --if-exists | gzip` of the database, then a `tar.gz` of the library, then a prune, then sleep. Defaults are a 30-minute warm-up, a 24-hour interval and 7-day retention, all overridable in `.env`.

The library archive deliberately leaves out three directories: `thumbs` and `encoded-video`, which are rebuilt from the originals by a job in the web UI and together are usually larger than the originals themselves, and `backups`, which holds Immich's own nightly dumps that this loop already takes properly. Set `IMMICH_BACKUP_EXCLUDES=` to an empty string to archive everything.

Restore with the interactive scripts, **database first, then the library from the same timestamp**:

```bash
chmod +x ./*.sh
./immich-restore-database.sh
./immich-restore-library.sh
```

The database is the index and the library is what it points at. A library newer than its database holds files no asset row knows about; a database newer than its library holds rows pointing at files that are not there. After restoring the library, run Administration → Jobs → Generate Thumbnails and Transcode Videos to rebuild what the archive leaves out.

Immich's own documentation describes a different restore sequence, with a `search_path` rewrite, for dumps taken by its in-app backup and loaded into a database that still exists. These scripts drop and recreate the database first, which is why no rewrite is needed here — and CI proves the roundtrip, including that Immich comes back up on the restored database, on every run.

## Resource limits

Every service carries memory and CPU limits plus reservations as compose-level defaults: the same values CI boots the stack under. Immich asks for at least 6 GB of RAM across the stack and at least 2 GB for the database alone where limits are in use, and the defaults here reflect that. Override any of them in `.env` (the knobs are listed in `.env.example`) and the override survives every `git pull`. If a service is OOM-killed under real load, `docker inspect <container> --format '{{.State.OOMKilled}}'` says so; raise its `_MEMORY_LIMIT` and recreate.

## Container hardening

Every service runs with `security_opt: no-new-privileges:true`, so a process cannot gain privileges through setuid binaries even if it escapes its initial capability set. Infrastructure containers (the reverse proxy, the database, the cache, the backups sidecar) run with `cap_drop: [ALL]` and add back only what their entrypoints need: `NET_BIND_SERVICE` for Traefik to bind :80/:443, `CHOWN`/`SETUID`/`SETGID` and friends for the data images to own their directories and drop to their service users. The application containers keep the default capability set on purpose: upstream images assume it, and a wrong guess there is a boot loop in production rather than a hardening win. CI boots the stack under exactly these settings on every push, so what ships is what was tested.

## Testing

The [Deployment Verification](https://github.com/heyvaldemar/immich-traefik-letsencrypt-docker-compose/actions/workflows/deployment-verification.yml?query=branch%3Amain) workflow runs on every push, pull request, and every day at 06:00 UTC: shellcheck and actionlint, Trivy scans of all five pinned images, the daily freshness check, and a deploy-and-test job that boots the stack with ephemeral credentials and then requires, in order, that the API answers `{"res":"pong"}` through Traefik, that the machine-learning container answers the server over the internal network, that both vector extensions are present in the running database, that a database dump and a library archive are produced and readable, that the eight backup and restore scenarios pass, and that Immich comes back up on the database the restore test replaced underneath it.

### Backup and restore, proven

`tests/e2e-backup-restore.sh` runs against the live stack and is what CI executes after the HTTPS smoke. The scenario that matters most is the restore roundtrip: insert a marker row, restore the earliest backup, assert the marker is gone. A backup that cannot be restored fails the build. Run it yourself against a running deployment with short intervals in `.env` (`BACKUP_INIT_SLEEP=15s`, `BACKUP_INTERVAL=60s`):

```bash
chmod +x tests/e2e-backup-restore.sh
./tests/e2e-backup-restore.sh
```

It stops the database container briefly to prove failure detection. Run it on a staging copy, not on production.

## Security notes

- Credentials are read from `.env` at deploy time; `.env` is gitignored and compose fails fast on missing required variables.
- PostgreSQL, Valkey and the machine-learning service listen only on the internal network. Nothing but Traefik publishes a port.
- Immich has no registration gate before the first account exists. The first person to reach a fresh deployment becomes its administrator.

---

## About the maintainer

<div align="center">

**Maintained by [Vladimir Mikhalev](https://github.com/heyvaldemar)** · Docker Captain · IBM Champion · AWS Community Builder

[YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1) · [Blog](https://heyvaldemar.com) · [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)

</div>
