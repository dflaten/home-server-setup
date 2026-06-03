# Environment Variables

This file describes the `.env` values used by `docker-compose-server.yml` and the ContainerScan launcher script.

Use `.env.example` as the starting point, then copy the values into a local `.env` file. Do not commit `.env`; it contains machine-specific paths and passwords.

## Host identity

These values control time zone and file ownership for services that need host-like identity settings.

| Variable | Used by | Example | Notes |
| --- | --- | --- | --- |
| `TZ` | Jellyfin, Piper, Faster Whisper | `America/Chicago` | Use an IANA time zone name. Safe to change later. |
| `PUID` | Piper, Faster Whisper | `1000` | Numeric host user ID that should own each service's `/config` files. Changing after files exist can create permission mismatches. |
| `PGID` | Piper, Faster Whisper | `1000` | Numeric host group ID that should own each service's `/config` files. Changing after files exist can create permission mismatches. |

## Storage paths

These values decide where host data lives and what paths containers see.

| Variable | Used by | Example | Notes |
| --- | --- | --- | --- |
| `UPLOAD_LOCATION` | Immich | `/mnt/photos` | Real host path mounted into Immich at `/usr/src/app/upload`. Do not change after deploy unless you are intentionally moving Immich uploads. |
| `DB_DATA_LOCATION` | Immich Postgres | `/srv/immich/postgres` | Real host path for the Immich Postgres data directory. Keep this on the internal disk. |
| `JELLYFIN_MOVIES_SOURCE` | Jellyfin | `/mnt/media/videos` | Real host path Docker reads movie files from. |
| `JELLYFIN_MOVIES_TARGET` | Jellyfin | `/media/movies` | In-container path where Jellyfin sees the movie library. Use a stable path you are comfortable selecting in Jellyfin libraries. |
| `JELLYFIN_MUSIC_SOURCE` | Jellyfin | `/mnt/music` | Real host path Docker reads music files from. |
| `JELLYFIN_MUSIC_TARGET` | Jellyfin | `/media/music` | In-container path where Jellyfin sees the music library. Use a stable path you are comfortable selecting in Jellyfin libraries. |

## Immich database and version

These values configure the Immich application image tag and Postgres database.

| Variable | Used by | Example | Notes |
| --- | --- | --- | --- |
| `IMMICH_VERSION` | Immich server, Immich machine learning | `release` | Image tag used for both Immich containers. Changing this upgrades or downgrades Immich. |
| `DB_PASSWORD` | Immich Postgres, Immich server | `changeMeToALongAlphaNumericPassword` | Set before first deploy. Changing later requires updating all Immich database consumers consistently. |
| `DB_USERNAME` | Immich Postgres, Immich server | `postgres` | Safe to leave as `postgres` unless you are intentionally managing custom database roles. |
| `DB_DATABASE_NAME` | Immich Postgres, Immich server | `immich` | Usually set once and left alone. Changing later requires a corresponding database migration or rebuild. |

## Jellyfin service state

These values configure the user Jellyfin runs as, the directories that hold Jellyfin state, and the URL advertised to clients.

| Variable | Used by | Example | Notes |
| --- | --- | --- | --- |
| `JELLYFIN_UID` | Jellyfin | `998` | Numeric host user ID that should own Jellyfin's config and state files. |
| `JELLYFIN_GID` | Jellyfin | `998` | Numeric host group ID that should own Jellyfin's config and state files. |
| `JELLYFIN_CONFIG_DIR` | Jellyfin | `/etc/jellyfin` | Host path mounted to `/etc/jellyfin`. Create it before first start and keep it writable by the Jellyfin user. |
| `JELLYFIN_CACHE_DIR` | Jellyfin | `/var/cache/jellyfin` | Host path mounted to `/var/cache/jellyfin`. Create it before first start and keep it writable by the Jellyfin user. |
| `JELLYFIN_DATA_DIR` | Jellyfin | `/var/lib/jellyfin` | Host path mounted to `/var/lib/jellyfin`. Contains Jellyfin state and database files. |
| `JELLYFIN_LOG_DIR` | Jellyfin | `/var/log/jellyfin` | Host path mounted to `/var/log/jellyfin`. Safe to relocate, but keep it writable by the Jellyfin user. |
| `JELLYFIN_PUBLISHED_SERVER_URL` | Jellyfin | `http://192.168.1.10:8096` | Public URL Jellyfin advertises to clients. Match how clients on your network reach Jellyfin. |

## Voice services

These values configure Piper text-to-speech and Faster Whisper speech-to-text.

| Variable | Used by | Example | Notes |
| --- | --- | --- | --- |
| `PIPER_VOICE` | Piper | `en_US-lessac-medium` | Default TTS voice model Piper loads. Availability depends on the image's supported voices. |
| `WHISPER_BEAM` | Faster Whisper | `1` | Beam search width used during transcription. Lower is faster; higher may improve accuracy at higher CPU cost. |
| `WHISPER_LANG` | Faster Whisper | `auto` | Language hint for transcription. Use `auto` for auto-detection, or set a language code for more predictable recognition. |
| `WHISPER_MODEL` | Faster Whisper | `base` | Speech-to-text model size. Larger models are usually more accurate and slower. |

## ContainerScan

These values are configured in `home-server-setup/.env`, even though ContainerScan runs from its own sibling repository.

| Variable | Used by | Example | Notes |
| --- | --- | --- | --- |
| `CONTAINERSCAN_REPO_PATH` | ContainerScan launcher script | `../ContainerScan` | Host path to the local `ContainerScan` repository. The default assumes `home-server-setup` and `ContainerScan` are sibling directories. |
| `CONTAINERSCAN_HTTP_PORT` | ContainerScan nginx | `8088` | Host port exposed for the ContainerScan web UI and scan routes. Must not conflict with another host service. |
| `CONTAINERSCAN_PUBLIC_BASE_URL` | ContainerScan backend, frontend | `http://containerscan.local:8088` | Stable LAN URL encoded into generated QR labels and used by the frontend origin. Treat this as durable. |
| `CONTAINERSCAN_DB_DATA_LOCATION` | ContainerScan Postgres | `/srv/containerscan/postgres` | Host path for the ContainerScan Postgres data directory. Persist this on internal storage. |
| `CONTAINERSCAN_IMAGE_DATA_LOCATION` | ContainerScan backend | `/srv/containerscan/images` | Host path for uploaded container images. Back this up together with the database if you care about recovery. |
| `CONTAINERSCAN_DB_NAME` | ContainerScan Postgres, backend | `containerscan` | Database name for ContainerScan. Usually set once and left alone. |
| `CONTAINERSCAN_DB_USER` | ContainerScan Postgres, backend | `containerscan` | Database role used by ContainerScan. Usually set once and left alone. |
| `CONTAINERSCAN_DB_PASSWORD` | ContainerScan Postgres, backend | `changeMeToALongRandomPassword` | Postgres password for ContainerScan. Set before first deploy. Changing later requires updating all ContainerScan consumers consistently. |
