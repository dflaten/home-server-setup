# Environment Variables

This file describes the `.env` values used by `docker-compose-server.yml` and the ContainerScan launcher script.

Use `.env.example` as the starting point, then copy the values into a local `.env` file. Do not commit `.env`; it contains machine-specific paths and passwords.

## Shared values

### `TZ`

Time zone passed into containers that use local time settings.

Example:

```env
TZ=America/Chicago
```

Use an IANA time zone name. This is safe to change later.

### `PUID`

Numeric user ID used by the LinuxServer containers for Piper and Faster Whisper.

Example:

```env
PUID=1000
```

This should match the host user that should own each service's `/config` files. Changing it after the services have written files can create permission mismatches.

### `PGID`

Numeric group ID used by the LinuxServer containers for Piper and Faster Whisper.

Example:

```env
PGID=1000
```

This should match the host group that should own each service's `/config` files. Changing it after the services have written files can create permission mismatches.

## Immich

### `UPLOAD_LOCATION`

Real host path mounted into Immich at `/usr/src/app/upload`.

Example:

```env
UPLOAD_LOCATION=/mnt/photos
```

Do not change this after deploy unless you are intentionally moving Immich uploads.

### `DB_DATA_LOCATION`

Real host path for the Immich Postgres data directory.

Example:

```env
DB_DATA_LOCATION=/srv/immich/postgres
```

Keep this on the internal disk. Do not change it after first deploy unless you are intentionally migrating the database.

### `IMMICH_VERSION`

Image tag used for both Immich containers.

Example:

```env
IMMICH_VERSION=release
```

Changing this upgrades or downgrades Immich. Treat it as an application version change, not a cosmetic config change.

### `DB_PASSWORD`

Postgres password for the Immich database.

Example:

```env
DB_PASSWORD=changeMeToALongAlphaNumericPassword
```

Set this before first deploy. Changing it later requires updating all Immich database consumers consistently.

### `DB_USERNAME`

Postgres username for Immich.

Example:

```env
DB_USERNAME=postgres
```

This is safe to leave as `postgres` unless you are intentionally managing custom database roles.

### `DB_DATABASE_NAME`

Postgres database name for Immich.

Example:

```env
DB_DATABASE_NAME=immich
```

Usually set this once and leave it alone. Changing it later requires a corresponding database migration or rebuild.

## Jellyfin

### `JELLYFIN_UID`

Numeric user ID Jellyfin runs as.

Example:

```env
JELLYFIN_UID=998
```

This should match the host user that should own Jellyfin's config and state files.

### `JELLYFIN_GID`

Numeric group ID Jellyfin runs as.

Example:

```env
JELLYFIN_GID=998
```

This should match the host group that should own Jellyfin's config and state files.

### `JELLYFIN_CONFIG_DIR`

Host path mounted to `/etc/jellyfin`.

Example:

```env
JELLYFIN_CONFIG_DIR=/etc/jellyfin
```

Create this directory before first start and keep it writable by the Jellyfin user.

### `JELLYFIN_CACHE_DIR`

Host path mounted to `/var/cache/jellyfin`.

Example:

```env
JELLYFIN_CACHE_DIR=/var/cache/jellyfin
```

Create this directory before first start and keep it writable by the Jellyfin user.

### `JELLYFIN_DATA_DIR`

Host path mounted to `/var/lib/jellyfin`.

Example:

```env
JELLYFIN_DATA_DIR=/var/lib/jellyfin
```

This contains Jellyfin state and database files. Back it up if you care about preserving Jellyfin metadata.

### `JELLYFIN_LOG_DIR`

Host path mounted to `/var/log/jellyfin`.

Example:

```env
JELLYFIN_LOG_DIR=/var/log/jellyfin
```

This is safe to relocate if needed, but keep it writable by the Jellyfin user.

### `JELLYFIN_PUBLISHED_SERVER_URL`

Public URL Jellyfin advertises to clients.

Example:

```env
JELLYFIN_PUBLISHED_SERVER_URL=http://192.168.1.10:8096
```

This should match how clients on your network reach Jellyfin.

### `JELLYFIN_MOVIES_SOURCE`

Real host path Docker reads movie files from.

Example:

```env
JELLYFIN_MOVIES_SOURCE=/mnt/media/videos
```

This is the host-side source of the bind mount.

### `JELLYFIN_MOVIES_TARGET`

In-container path where Jellyfin sees the movie library.

Example:

```env
JELLYFIN_MOVIES_TARGET=/media/movies
```

Use a stable in-container path that you are comfortable selecting in Jellyfin libraries, such as `/media/movies`.

### `JELLYFIN_MUSIC_SOURCE`

Real host path Docker reads music files from.

Example:

```env
JELLYFIN_MUSIC_SOURCE=/mnt/music
```

This is the host-side source of the bind mount.

### `JELLYFIN_MUSIC_TARGET`

In-container path where Jellyfin sees the music library.

Example:

```env
JELLYFIN_MUSIC_TARGET=/media/music
```

Use a stable in-container path that you are comfortable selecting in Jellyfin libraries, such as `/media/music`.

## Piper

### `PIPER_VOICE`

Default TTS voice model Piper loads.

Example:

```env
PIPER_VOICE=en_US-lessac-medium
```

Change this to swap the default voice. Availability depends on the image's supported voices.

## Faster Whisper

### `WHISPER_BEAM`

Beam search width used during transcription.

Example:

```env
WHISPER_BEAM=1
```

Lower is faster. Higher may improve accuracy at higher CPU cost.

### `WHISPER_LANG`

Language hint for transcription.

Example:

```env
WHISPER_LANG=auto
```

Use `auto` for auto-detection, or set a language code for more predictable recognition.

### `WHISPER_MODEL`

Speech-to-text model size.

Example:

```env
WHISPER_MODEL=base
```

Larger models are usually more accurate and slower. Pick based on your hardware.

## ContainerScan

These values are configured in `home-server-setup/.env`, even though ContainerScan runs from its own sibling repository.

### `CONTAINERSCAN_REPO_PATH`

Host path to the local `ContainerScan` repository whose own `docker-compose.yml` should be started.

Example:

```env
CONTAINERSCAN_REPO_PATH=../ContainerScan
```

The default assumes `home-server-setup` and `ContainerScan` are sibling directories. Set an absolute path if you clone it elsewhere.

### `CONTAINERSCAN_HTTP_PORT`

Host port exposed for the ContainerScan web UI and scan routes.

Example:

```env
CONTAINERSCAN_HTTP_PORT=8088
```

This must not conflict with another host service. If you later put this behind a LAN reverse proxy, you may stop exposing this port directly.

### `CONTAINERSCAN_PUBLIC_BASE_URL`

Stable LAN URL encoded into generated QR labels and used by the frontend origin.

Example:

```env
CONTAINERSCAN_PUBLIC_BASE_URL=http://containerscan.local:8088
```

Treat this as durable. Changing it later means previously printed QR labels point at the wrong address.

### `CONTAINERSCAN_DB_DATA_LOCATION`

Host path for the ContainerScan Postgres data directory.

Example:

```env
CONTAINERSCAN_DB_DATA_LOCATION=/srv/containerscan/postgres
```

Persist this on internal storage. Do not put the database on removable media unless you accept that failure mode.

### `CONTAINERSCAN_IMAGE_DATA_LOCATION`

Host path for uploaded container images.

Example:

```env
CONTAINERSCAN_IMAGE_DATA_LOCATION=/srv/containerscan/images
```

Back this up together with the database if you care about recovery.

### `CONTAINERSCAN_DB_NAME`

Database name for ContainerScan.

Example:

```env
CONTAINERSCAN_DB_NAME=containerscan
```

Usually set this once and leave it alone.

### `CONTAINERSCAN_DB_USER`

Database role used by ContainerScan.

Example:

```env
CONTAINERSCAN_DB_USER=containerscan
```

Usually set this once and leave it alone.

### `CONTAINERSCAN_DB_PASSWORD`

Postgres password for ContainerScan.

Example:

```env
CONTAINERSCAN_DB_PASSWORD=changeMeToALongRandomPassword
```

Set this before first deploy. Changing it later requires updating all ContainerScan consumers consistently.
