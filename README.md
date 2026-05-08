# Home Server Setup

This repo is set up to run a small Docker Compose stack on Ubuntu with:

- Immich
- Jellyfin
- Piper
- Faster Whisper

The important constraint is that any USB-backed storage used by the containers must be mounted before the stack starts.

The Immich part of this repo intentionally stays close to your current working Compose file so that the boot automation does not force an Immich migration at the same time.

## Recommended approach

Use two layers:

1. `/etc/fstab` mounts the USB drives by `UUID`, not by `/dev/sdX` names.
2. A `systemd` service starts `docker compose up -d` only after those mount points are available.

This is more stable than manual `mount` commands because `/dev/sdX` names can change between boots.

## 1. Identify the drives

Run:

```bash
lsblk -f
sudo blkid
```

Find the filesystem `UUID` values for the partitions you want Docker services to use.

Pick stable mount points that match the paths you intend to reference in `.env`.

Examples:

- `/media/usb`
- `/mnt/media`
- `/mnt/music`

Create them once:

```bash
sudo mkdir -p /media/usb /mnt/media /mnt/music
```

Note: if Immich already has a working database directory, keep using that exact existing path. Do not invent a new `DB_DATA_LOCATION` unless you are intentionally creating a new database location. In general, keep the database on the internal disk, not on removable USB storage.

## 2. Add `/etc/fstab` entries

Example:

```fstab
UUID=REPLACE_WITH_USB1_UUID  /media/usb  ext4   defaults,nofail,x-systemd.device-timeout=10s  0  2
UUID=REPLACE_WITH_USB2_UUID  /mnt/media  exfat  defaults,nofail,uid=1000,gid=1000,umask=0022,x-systemd.device-timeout=10s  0  0
```

Replace the filesystem type and mount options with the values appropriate for your drives. For example, Linux-native filesystems like `ext4` usually use `defaults`, while `exfat` often needs `uid`, `gid`, and `umask` options.

Then test:

```bash
sudo mount -a
findmnt /media/usb
findmnt /mnt/media
```

If permissions are wrong for non-Linux filesystems such as `ntfs` or `exfat`, use mount options appropriate for that filesystem, for example:

```fstab
UUID=REPLACE_WITH_USB_UUID  /mnt/media  exfat  defaults,nofail,uid=1000,gid=1000,umask=0022,x-systemd.device-timeout=10s  0  0
```

## 3. Configure the Compose stack

Copy the sample env file:

```bash
cp .env.example .env
```

Then set at least:

- `TZ`
- `DB_PASSWORD`
- `JELLYFIN_PUBLISHED_SERVER_URL`

Then update the storage-related variables so they match your existing working setup and your chosen mount points.

For Immich, preserve your current working values:

- `UPLOAD_LOCATION`
- `DB_DATA_LOCATION`
- `DB_PASSWORD`
- `DB_USERNAME`
- `DB_DATABASE_NAME`
- `IMMICH_VERSION`

Do not change `UPLOAD_LOCATION` or `DB_DATA_LOCATION` unless you are intentionally migrating data.

For Jellyfin, configure:

- `JELLYFIN_UID`
- `JELLYFIN_GID`
- `JELLYFIN_CONFIG_DIR`
- `JELLYFIN_CACHE_DIR`
- `JELLYFIN_DATA_DIR`
- `JELLYFIN_LOG_DIR`
- `JELLYFIN_PUBLISHED_SERVER_URL`
- `JELLYFIN_MOVIES_SOURCE`
- `JELLYFIN_MOVIES_TARGET`
- `JELLYFIN_MUSIC_SOURCE`
- `JELLYFIN_MUSIC_TARGET`

For voice services, configure:

- `PUID`
- `PGID`
- `TZ`
- `PIPER_VOICE`
- `WHISPER_BEAM`
- `WHISPER_LANG`
- `WHISPER_MODEL`

For ContainerScan, configure these values directly in `home-server-setup/.env`:

- `CONTAINERSCAN_REPO_PATH`
- `CONTAINERSCAN_HTTP_PORT`
- `CONTAINERSCAN_PUBLIC_BASE_URL`
- `CONTAINERSCAN_DB_DATA_LOCATION`
- `CONTAINERSCAN_IMAGE_DATA_LOCATION`
- `CONTAINERSCAN_DB_NAME`
- `CONTAINERSCAN_DB_USER`
- `CONTAINERSCAN_DB_PASSWORD`

`home-server-setup` still does not define the ContainerScan services directly. It starts the separate `ContainerScan` repository's own `docker-compose.yml`, but it now passes the values from `home-server-setup/.env` into that compose project so you only configure ContainerScan in one place. The default `CONTAINERSCAN_REPO_PATH` assumes `home-server-setup` and `ContainerScan` are sibling directories.

Example path mapping:

```env
UPLOAD_LOCATION=/media/usb
DB_DATA_LOCATION=/path/to/your/existing/immich/postgres

JELLYFIN_MOVIES_SOURCE=/mnt/media/videos
JELLYFIN_MOVIES_TARGET=/media/usb2/videos
JELLYFIN_MUSIC_SOURCE=/mnt/music
JELLYFIN_MUSIC_TARGET=/media/music
```

How that works:

- `UPLOAD_LOCATION` is the real host path mounted into Immich at `/usr/src/app/upload`.
- `JELLYFIN_*_SOURCE` is the real host path Docker reads from.
- `JELLYFIN_*_TARGET` is the path Jellyfin sees inside the container and stores in its library database.

Concrete example:

- If your movies are really stored on the host at `/mnt/media/videos`, set `JELLYFIN_MOVIES_SOURCE=/mnt/media/videos`.
- If your existing Jellyfin library already expects those movies at `/media/usb2/videos`, keep `JELLYFIN_MOVIES_TARGET=/media/usb2/videos`.
- The Compose file will bind-mount `/mnt/media/videos` from the host so Jellyfin sees it at `/media/usb2/videos` inside the container.

`.env` is local machine configuration. Do not commit it to Git. Only commit `.env.example`.

Suggested ContainerScan values:

```env
CONTAINERSCAN_REPO_PATH=../ContainerScan
CONTAINERSCAN_HTTP_PORT=8088
CONTAINERSCAN_PUBLIC_BASE_URL=http://containerscan.local:8088
CONTAINERSCAN_DB_DATA_LOCATION=/srv/containerscan/postgres
CONTAINERSCAN_IMAGE_DATA_LOCATION=/srv/containerscan/images
CONTAINERSCAN_DB_NAME=containerscan
CONTAINERSCAN_DB_USER=containerscan
CONTAINERSCAN_DB_PASSWORD=replace-with-a-long-random-password
```

Before first start, create the persistent directories you reference in `.env`, for example:

```bash
sudo mkdir -p /srv/containerscan/postgres /srv/containerscan/images
sudo chown -R 1000:1000 /srv/containerscan/images
```

The Postgres directory will be initialized by the container. The images directory is where uploaded container photos will persist on the host.

## Environment variable reference

| Variable | Service(s) | Meaning | Example | Notes |
| --- | --- | --- | --- | --- |
| `TZ` | Jellyfin, Piper, Faster Whisper | Time zone passed into containers that use local time settings. | `America/Chicago` | Safe to change. Use an IANA zone name. |
| `PUID` | Piper, Faster Whisper | Numeric user ID the LinuxServer containers run as. | `1000` | Should match the host user that should own `/config` files. Changing later can create permission mismatches. |
| `PGID` | Piper, Faster Whisper | Numeric group ID the LinuxServer containers run as. | `1000` | Should match the host group that should own `/config` files. Changing later can create permission mismatches. |
| `UPLOAD_LOCATION` | Immich | Real host path mounted into Immich at `/usr/src/app/upload`. | `/mnt/photos` | Do not change after deploy unless you are intentionally moving Immich uploads. |
| `JELLYFIN_MOVIES_SOURCE` | Jellyfin | Real host path Docker reads movie files from. | `/mnt/media/videos` | Host-side source of the bind mount. |
| `JELLYFIN_MOVIES_TARGET` | Jellyfin | In-container path where Jellyfin sees the movie library. | `/media/usb2/videos` | If migrating an existing Jellyfin library, keep this aligned with the path already stored in Jellyfin's database. |
| `JELLYFIN_MUSIC_SOURCE` | Jellyfin | Real host path Docker reads music files from. | `/mnt/music` | Host-side source of the bind mount. |
| `JELLYFIN_MUSIC_TARGET` | Jellyfin | In-container path where Jellyfin sees the music library. | `/media/music` | If migrating an existing Jellyfin library, keep this aligned with the path already stored in Jellyfin's database. |
| `DB_DATA_LOCATION` | Immich Postgres | Real host path for the Postgres data directory. | `/srv/immich/postgres` | Keep this on the internal disk. Do not change after first deploy unless you are intentionally migrating the database. |
| `IMMICH_VERSION` | Immich server, Immich machine learning | Image tag used for both Immich containers. | `release` | Changing this upgrades or downgrades Immich. Treat as an application version change, not a cosmetic config change. |
| `DB_PASSWORD` | Immich Postgres, Immich server | Postgres password for the Immich database. | `changeMeToALongAlphaNumericPassword` | Set before first deploy. Changing it later requires updating all consumers consistently. |
| `DB_USERNAME` | Immich Postgres, Immich server | Postgres username for Immich. | `postgres` | Safe to leave as `postgres` unless you are intentionally managing custom DB roles. |
| `DB_DATABASE_NAME` | Immich Postgres, Immich server | Postgres database name for Immich. | `immich` | Usually set once and left alone. Changing later requires a corresponding database migration or rebuild. |
| `JELLYFIN_UID` | Jellyfin | Numeric user ID Jellyfin runs as. | `998` | For native-Ubuntu Jellyfin migrations, this should usually match the existing `jellyfin` account on the host. |
| `JELLYFIN_GID` | Jellyfin | Numeric group ID Jellyfin runs as. | `998` | For native-Ubuntu Jellyfin migrations, this should usually match the existing `jellyfin` group on the host. |
| `JELLYFIN_CONFIG_DIR` | Jellyfin | Host path mounted to `/etc/jellyfin`. | `/etc/jellyfin` | Reuse the existing host path when migrating from a native install. |
| `JELLYFIN_CACHE_DIR` | Jellyfin | Host path mounted to `/var/cache/jellyfin`. | `/var/cache/jellyfin` | Reuse the existing host path when migrating from a native install. |
| `JELLYFIN_DATA_DIR` | Jellyfin | Host path mounted to `/var/lib/jellyfin`. | `/var/lib/jellyfin` | Contains Jellyfin state and database files. Preserve it during migration. |
| `JELLYFIN_LOG_DIR` | Jellyfin | Host path mounted to `/var/log/jellyfin`. | `/var/log/jellyfin` | Safe to relocate if needed, but keep it writable by the Jellyfin user. |
| `JELLYFIN_PUBLISHED_SERVER_URL` | Jellyfin | Public URL Jellyfin advertises to clients. | `http://192.168.1.10:8096` | Should match how clients on your network reach Jellyfin. |
| `PIPER_VOICE` | Piper | Default TTS voice model Piper loads. | `en_US-lessac-medium` | Change this to swap the default voice. Availability depends on the image's supported voices. |
| `WHISPER_BEAM` | Faster Whisper | Beam search width used during transcription. | `1` | Lower is faster; higher may improve accuracy at higher CPU cost. |
| `WHISPER_LANG` | Faster Whisper | Language hint for transcription. | `auto` | Use `auto` for auto-detection or set a language code for more predictable recognition. |
| `WHISPER_MODEL` | Faster Whisper | Speech-to-text model size. | `base` | Larger models are usually more accurate and slower. Pick based on your hardware. |
| `CONTAINERSCAN_REPO_PATH` | ContainerScan launcher script | Host path to the local `ContainerScan` repository whose own `docker-compose.yml` should be started. | `../ContainerScan` | The default assumes the repo is checked out beside `home-server-setup`. Set an absolute path if you clone it elsewhere. |
| `CONTAINERSCAN_HTTP_PORT` | ContainerScan nginx | Host port exposed for the ContainerScan web UI and scan routes. | `8088` | Must not conflict with another host service. If you later put this behind a LAN reverse proxy, you may stop exposing this port directly. |
| `CONTAINERSCAN_PUBLIC_BASE_URL` | ContainerScan backend, frontend | Stable LAN URL encoded into generated QR labels and used by the frontend origin. | `http://containerscan.local:8088` | Treat this as durable. Changing it later means previously printed QR labels point at the wrong address. |
| `CONTAINERSCAN_DB_DATA_LOCATION` | ContainerScan Postgres | Host path for the ContainerScan Postgres data directory. | `/srv/containerscan/postgres` | Persist this on internal storage. Do not put the database on removable media unless you accept the failure mode. |
| `CONTAINERSCAN_IMAGE_DATA_LOCATION` | ContainerScan backend | Host path for uploaded container images. | `/srv/containerscan/images` | Back this up together with the database if you care about recovery. |
| `CONTAINERSCAN_DB_NAME` | ContainerScan Postgres, backend | Database name for ContainerScan. | `containerscan` | Usually set once and left alone. |
| `CONTAINERSCAN_DB_USER` | ContainerScan Postgres, backend | Database role used by ContainerScan. | `containerscan` | Usually set once and left alone. |
| `CONTAINERSCAN_DB_PASSWORD` | ContainerScan Postgres, backend | Postgres password for ContainerScan. | `changeMeToALongRandomPassword` | Set this before first deploy. Changing it later requires updating all ContainerScan consumers consistently. |

## 4. Start the stack manually

```bash
docker compose -f docker-compose-server.yml --env-file .env up -d
```

ContainerScan launcher notes:

- `home-server-setup` does not start ContainerScan as part of `docker-compose-server.yml`.
- Use `./scripts/containerscan-compose.sh up` to start the sibling `ContainerScan` compose project.
- Use `./scripts/containerscan-compose.sh down` to stop it and `./scripts/containerscan-compose.sh logs` to inspect it.
- The launcher passes `home-server-setup/.env` into the ContainerScan compose project, so you do not need a second `.env` file in the `ContainerScan` repo.

## Migrating Jellyfin from native Ubuntu install to Docker

The safest migration is to reuse your existing Jellyfin state instead of creating a new empty container config.

Jellyfin's official migration guidance says to keep the same paths available inside the container so the existing database and library definitions still point at valid locations.

On Ubuntu package installs, the usual host paths are:

- `/etc/jellyfin`
- `/var/cache/jellyfin`
- `/var/lib/jellyfin`
- `/var/log/jellyfin`

This repo's Compose file is set up for that migration style. In `.env`, set the Jellyfin state directories to the existing host paths from the native install:

```env
JELLYFIN_UID=998
JELLYFIN_GID=998
JELLYFIN_CONFIG_DIR=/etc/jellyfin
JELLYFIN_CACHE_DIR=/var/cache/jellyfin
JELLYFIN_DATA_DIR=/var/lib/jellyfin
JELLYFIN_LOG_DIR=/var/log/jellyfin
JELLYFIN_MOVIES_SOURCE=/path/on/host/for/movies
JELLYFIN_MOVIES_TARGET=/path/jellyfin/already/expects/for/movies
JELLYFIN_MUSIC_SOURCE=/path/on/host/for/music
JELLYFIN_MUSIC_TARGET=/path/jellyfin/already/expects/for/music
```

The `*_SOURCE` values are real host paths. The `*_TARGET` values are the paths visible inside the container. If you are migrating an existing Jellyfin install, keep the `*_TARGET` paths aligned with the paths already stored in Jellyfin's database so library metadata still resolves correctly.

Worked migration example:

```env
JELLYFIN_MOVIES_SOURCE=/mnt/media/videos
JELLYFIN_MOVIES_TARGET=/media/usb2/videos
JELLYFIN_MUSIC_SOURCE=/mnt/music
JELLYFIN_MUSIC_TARGET=/media/music
```

That means Docker reads the files from `/mnt/media/videos` and `/mnt/music` on the host, but inside the container Jellyfin still sees them at `/media/usb2/videos` and `/media/music`, which preserves the paths already recorded in Jellyfin's database.

Before starting the containerized Jellyfin:

```bash
id jellyfin
sudo systemctl stop jellyfin
sudo systemctl disable jellyfin
```

Then migrate your media to the real USB-backed path if needed, for example:

```bash
sudo mkdir -p /path/on/host/for/movies
rsync -avh --progress /old/media/path/ /path/on/host/for/movies/
```

After that, start only Jellyfin in Docker first:

```bash
docker compose -f docker-compose-server.yml --env-file .env up -d jellyfin
```

If the old package service is no longer needed after you verify the Docker container is working, you can remove it:

```bash
sudo apt remove jellyfin
```

## 5. Start the stack automatically at boot

Create `/etc/systemd/system/home-server-compose.service`:

```ini
[Unit]
Description=Home server Docker Compose stack
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target
RequiresMountsFor=/path/used/by/compose /another/path/used/by/compose

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/home/david/projects/home-server-setup
ExecStart=/usr/bin/docker compose -f /home/david/projects/home-server-setup/docker-compose-server.yml --env-file /home/david/projects/home-server-setup/.env up -d
ExecStop=/usr/bin/docker compose -f /home/david/projects/home-server-setup/docker-compose-server.yml --env-file /home/david/projects/home-server-setup/.env down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
```

If you also want ContainerScan to start at boot, create a second unit such as `/etc/systemd/system/containerscan-compose.service`:

```ini
[Unit]
Description=ContainerScan Docker Compose stack
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target
RequiresMountsFor=/home/david/projects/ContainerScan /srv/containerscan/postgres /srv/containerscan/images

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/home/david/projects/home-server-setup
ExecStart=/home/david/projects/home-server-setup/scripts/containerscan-compose.sh up
ExecStop=/home/david/projects/home-server-setup/scripts/containerscan-compose.sh down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
```

Then enable it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable home-server-compose.service
sudo systemctl start home-server-compose.service

sudo systemctl enable containerscan-compose.service
sudo systemctl start containerscan-compose.service
```

## 6. Run a backup script once a week with cron

If you have a backup script you want to run on a schedule, make sure it is executable and uses absolute paths for any commands or files it depends on.

Example:

```bash
chmod +x /home/david/projects/home-server-setup/scripts/backup.sh
crontab -e
```

Add a weekly cron entry like this to run the script every Sunday at 3:00 AM:

```cron
0 3 * * 0 /bin/bash /home/david/projects/home-server-setup/scripts/backup.sh >> /var/log/home-server-backup.log 2>&1
```

Notes:

- Replace `/home/david/projects/home-server-setup/scripts/backup.sh` with the real path to your backup script.
- `cron` runs with a minimal environment, so avoid relying on shell aliases, relative paths, or environment variables that are only set in your interactive shell.
- The log redirection is optional, but it makes it easier to confirm that the job ran and to inspect failures.

## Notes on the current Compose file

- Immich keeps the same upload mount target as your current setup: `/usr/src/app/upload`.
- The Postgres data path is host-backed and should remain on the internal disk.
- The Immich service definitions are intentionally kept close to your current working stack to reduce upgrade risk.
- Jellyfin is configured to reuse the standard Ubuntu Jellyfin directories so a native install can be migrated into Docker without rebuilding library state from scratch.
- Piper listens on host port `10200`, and Faster Whisper listens on host port `10300` for Wyoming clients such as Home Assistant.
- The `systemd` unit above is what guarantees mount ordering on boot; container restart policies alone do not solve that dependency.

## Things to verify on the host

This sandbox does not currently expose your USB drives or Docker installation, so before relying on boot automation you should verify:

```bash
lsblk -f
docker compose version
docker compose -f docker-compose-server.yml --env-file .env config
sudo systemctl status home-server-compose.service
```
