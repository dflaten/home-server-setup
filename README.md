# Home Server Setup

This repo is set up to run a small Docker Compose stack on Ubuntu with:

- Immich
- Jellyfin
- Piper

The important constraint is that the USB-backed storage must be mounted before the stack starts.

The Immich part of this repo intentionally stays close to your current working Compose file so that the boot automation does not force an Immich migration at the same time.

## Recommended approach

Use two layers:

1. `/etc/fstab` mounts the USB drives by `UUID`, not by `/dev/sda2` or `/dev/sdb1`.
2. A `systemd` service starts `docker compose up -d` only after those mount points are available.

This is more stable than manual `mount` commands because `/dev/sdX` names can change between boots.

## 1. Identify the drives

Run:

```bash
lsblk -f
sudo blkid
```

Find the filesystem `UUID` values for the two partitions you currently mount manually:

- `/dev/sdb1`
- `/dev/sda2`

Pick stable mount points. This repo expects:

- `/mnt/photos` for Immich uploads
- `/mnt/media` for Jellyfin media

Create them once:

```bash
sudo mkdir -p /mnt/photos /mnt/media /srv/immich/postgres
sudo chown -R 1000:1000 /mnt/photos /mnt/media /srv/immich
```

Note: the Immich database should stay on the internal disk. Do not place Postgres data on a removable USB drive.

## 2. Add `/etc/fstab` entries

Example:

```fstab
UUID=REPLACE_WITH_USB1_UUID  /mnt/photos  ext4  defaults,nofail,x-systemd.device-timeout=10s  0  2
UUID=REPLACE_WITH_USB2_UUID  /mnt/media   ext4  defaults,nofail,x-systemd.device-timeout=10s  0  2
```

If one or both USB filesystems are `ntfs`, `exfat`, or something else, replace `ext4` with the actual filesystem type shown by `lsblk -f`.

Then test:

```bash
sudo mount -a
findmnt /mnt/photos
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

The Compose file uses:

- `UPLOAD_LOCATION=/mnt/photos`
- `JELLYFIN_MEDIA_SOURCE=/mnt/media/jellyfin`
- `JELLYFIN_MEDIA_TARGET=/mnt/media/jellyfin`
- `DB_DATA_LOCATION=/srv/immich/postgres`

## 4. Start the stack manually

```bash
docker compose -f docker-compose-server.yml --env-file .env up -d
```

## Migrating Jellyfin from native Ubuntu install to Docker

The safest migration is to reuse your existing Jellyfin state instead of creating a new empty container config.

Jellyfin's official migration guidance says to keep the same paths available inside the container so the existing database and library definitions still point at valid locations.

On Ubuntu package installs, the usual host paths are:

- `/etc/jellyfin`
- `/var/cache/jellyfin`
- `/var/lib/jellyfin`
- `/var/log/jellyfin`

This repo's Compose file is set up for that migration style. In `.env`, set:

```env
JELLYFIN_UID=998
JELLYFIN_GID=998
JELLYFIN_CONFIG_DIR=/etc/jellyfin
JELLYFIN_CACHE_DIR=/var/cache/jellyfin
JELLYFIN_DATA_DIR=/var/lib/jellyfin
JELLYFIN_LOG_DIR=/var/log/jellyfin
JELLYFIN_MEDIA_SOURCE=/mnt/media/jellyfin
JELLYFIN_MEDIA_TARGET=/mnt/media/jellyfin
```

Before starting the containerized Jellyfin:

```bash
id jellyfin
sudo systemctl stop jellyfin
sudo systemctl disable jellyfin
```

Then migrate your media to the real USB-backed path if needed, for example:

```bash
sudo mkdir -p /mnt/media/jellyfin
rsync -avh --progress /old/media/path/ /mnt/media/jellyfin/
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
After=docker.service network-online.target mnt-photos.mount mnt-media.mount
Wants=network-online.target
RequiresMountsFor=/mnt/photos /mnt/media

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

Then enable it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable home-server-compose.service
sudo systemctl start home-server-compose.service
```

## Notes on the current Compose file

- Immich keeps the same upload mount target as your current setup: `/usr/src/app/upload`.
- The Postgres data path is host-backed and should remain on the internal disk.
- The Immich service definitions are intentionally kept close to your current working stack to reduce upgrade risk.
- Jellyfin is configured to reuse the standard Ubuntu Jellyfin directories so a native install can be migrated into Docker without rebuilding library state from scratch.
- The `systemd` unit above is what guarantees mount ordering on boot; container restart policies alone do not solve that dependency.

## Things to verify on the host

This sandbox does not currently expose your USB drives or Docker installation, so before relying on boot automation you should verify:

```bash
lsblk -f
docker compose version
docker compose -f docker-compose-server.yml --env-file .env config
sudo systemctl status home-server-compose.service
```
