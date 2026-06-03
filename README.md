# Home Server Setup

This repo is set up to run a small Docker Compose stack on Ubuntu with:

- Immich
- Jellyfin
- Piper
- Faster Whisper

The important constraint is that any USB-backed storage used by the containers must be mounted before the stack starts.

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

If permissions are wrong for non-Linux filesystems such as `ntfs` or `exfat`, adjust the `uid`, `gid`, and `umask` options for the user that should read and write those files.

## 3. Configure the Compose stack

Copy the sample env file:

```bash
cp .env.example .env
```

Then set at least:

- `TZ`
- `DB_PASSWORD`
- `JELLYFIN_PUBLISHED_SERVER_URL`

Then update the storage-related variables so they match your chosen mount points. See [ENVIRONMENT_VARIABLES.md](ENVIRONMENT_VARIABLES.md) for the full `.env` reference.

For Immich, keep the database on the internal disk. Do not change `UPLOAD_LOCATION` or `DB_DATA_LOCATION` after first deploy unless you are intentionally moving Immich data.

Example path mapping:

```env
UPLOAD_LOCATION=/media/usb
DB_DATA_LOCATION=/srv/immich/postgres

JELLYFIN_MOVIES_SOURCE=/mnt/media/videos
JELLYFIN_MOVIES_TARGET=/media/movies
JELLYFIN_MUSIC_SOURCE=/mnt/music
JELLYFIN_MUSIC_TARGET=/media/music
```

How that works:

- `UPLOAD_LOCATION` is the real host path mounted into Immich at `/usr/src/app/upload`.
- `JELLYFIN_*_SOURCE` is the real host path Docker reads from.
- `JELLYFIN_*_TARGET` is the path Jellyfin sees inside the container and stores in its library database.

`.env` is local machine configuration. Do not commit it to Git. Only commit `.env.example`.

ContainerScan is configured in `home-server-setup/.env`, but it still runs from the separate `ContainerScan` repository's own `docker-compose.yml`. The default `CONTAINERSCAN_REPO_PATH` assumes `home-server-setup` and `ContainerScan` are sibling directories.

Before first start, create the persistent directories you reference in `.env`, for example:

```bash
sudo mkdir -p /srv/containerscan/postgres /srv/containerscan/images
sudo chown -R 1000:1000 /srv/containerscan/images
```

The Postgres directory will be initialized by the container. The images directory is where uploaded container photos will persist on the host.

## 4. Start the stack manually

```bash
docker compose -f docker-compose-server.yml --env-file .env up -d
```

ContainerScan launcher notes:

- `home-server-setup` does not start ContainerScan as part of `docker-compose-server.yml`.
- Use `./scripts/containerscan-compose.sh up` to start the sibling `ContainerScan` compose project. This also applies the backend database migration during startup before the API server begins serving traffic.
- Use `./scripts/containerscan-compose.sh down` to stop it and `./scripts/containerscan-compose.sh logs` to inspect it.
- The launcher passes `home-server-setup/.env` into the ContainerScan compose project, so you do not need a second `.env` file in the `ContainerScan` repo.

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

## Things to verify on the host

Before relying on boot automation, verify the host can see the drives, Docker Compose can parse the stack, and the systemd unit starts cleanly:

```bash
lsblk -f
docker compose version
docker compose -f docker-compose-server.yml --env-file .env config
sudo systemctl status home-server-compose.service
```
