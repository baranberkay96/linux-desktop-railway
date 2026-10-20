# NOTICE: Debian 13 XFCE Linux Desktop template

## Base image and its components

The service is built `FROM lscr.io/linuxserver/webtop:debian-xfce-eb802092-ls217@sha256:d925f9c84663fe57735be4defe95a338d32bc37f2e12b9e0f0981e91b6bd0a5d`. The image is used as published by linuxserver.io. This repository contains no copy of its source files.

| Component | Source | License | How it is used |
|---|---|---|---|
| linuxserver.io webtop, branch `debian-xfce`, release `eb802092-ls217` | https://github.com/linuxserver/docker-webtop (git revision `721ecb8c708256c9f9cb44dba10d99b8037802d4`) | GPL-3.0 (image label `GPL-3.0-only`) | Base image (`FROM`), unmodified except for the build-time edits listed below |
| linuxserver.io baseimage-selkies (Debian trixie) and baseimage-debian | https://github.com/linuxserver/docker-baseimage-selkies, https://github.com/linuxserver/docker-baseimage-debian | GPL-3.0 | Layers of the base image: the s6 service definitions, `init-nginx`, `/defaults/default.conf` |
| Selkies 2.0.0 | https://github.com/selkies-project/selkies | MPL-2.0 | Streaming server and web client, in the base image |
| pixelflux, pcmflux | https://github.com/thelamer/pixelflux, https://github.com/selkies-project/pcmflux | MPL-2.0 | Capture, video and audio encoding, in the base image |
| s6-overlay 3.2.1.0, s6 2.13.2.0, s6-rc 0.5.6.0 | https://github.com/just-containers/s6-overlay, https://skarnet.org/software/ | ISC | Process supervision. `railway-start` calls `s6-svscan`, `s6-rc-compile`, `s6-rc-init` and `s6-rc` from the image |
| catatonit 0.2.1 | Debian trixie package `catatonit` (in the base image) | GPL-2.0-or-later | Container init and subreaper (`ENTRYPOINT`) |
| proot-apps | https://github.com/linuxserver/proot-apps | GPL-3.0 | In the base image, documented for installing apps into the home directory |
| Xvfb (XLibre xserver 25.2.2 with linuxserver.io patches) | https://github.com/linuxserver/selkies-layers, https://github.com/X11Libre/xserver | MIT/X11-style licenses of the X server | Virtual display, in the base image |
| Debian 13 "trixie" packages: XFCE 4.20, Chromium, nginx 1.26, PulseAudio, Mesa and others | https://sources.debian.org/ and the upstream projects | Each package's own license (see `/usr/share/doc/*/copyright` in the image) | In the base image |

### GPL notes

- The GPL-3.0 parts of the base image (the linuxserver.io image definitions and scripts) and the GPL-2.0 parts (for example XFCE components and catatonit) stay under their licenses. Their complete corresponding source is published by their authors at the repositories above, at the git revision named in the image label, and for Debian packages at https://sources.debian.org/ (versions in the image's `/var/lib/dpkg/status`).
- **Modified file:** at build time, `services/desktop/patch-image.sh` edits two files inside the image: `/defaults/default.conf` (GPL-3.0, from docker-baseimage-selkies) gets basic auth switched on, an Origin check, anti-framing headers and a `/healthz` location; `/etc/nginx/nginx.conf` (Debian nginx package, BSD-2-Clause) gets 2 worker processes and the error log on stderr. The script and the inserted snippets (`nginx-origin-map.conf`, `nginx-server-hardening.conf`) are the complete record of these changes. Anyone who distributes a built image of this template should keep them available with it, as GPL-3.0 section 5 requires for modified versions.
- No license has been attached to this repository yet. Because `patch-image.sh` modifies a GPL-3.0 file, GPL-3.0-or-later is the suggested license for the files written for this template (`Dockerfile`, `railway-start.sh`, `apt-restore.sh`, `patch-image.sh`, the two nginx snippets and the documentation). Confirm this choice before the repository is published.
- No source file of linuxserver.io, Selkies or s6-overlay was copied into this repository. `railway-start` re-implements, in its own code, the order of steps that s6-overlay's `preinit`, `stage0` and `rc.init` perform, and then calls the image's own s6 tools and service definitions.

## Upstream files checked (2026-10-20)

- `linuxserver/docker-webtop` branch `debian-xfce` at `721ecb8c` (2026-10-13): `Dockerfile` (base `baseimage-selkies:debiantrixie`, XFCE and Chromium packages), `root/defaults/startwm.sh`, `root/usr/local/bin/wrapped-chromium`. Tags on Docker Hub, ghcr.io and lscr.io: `debian-xfce-eb802092-ls217` = `sha256:d925f9c8…` (multi-arch index, amd64 + arm64).
- `linuxserver/docker-baseimage-selkies` `master` (Debian trixie): `Dockerfile` (Selkies 2.0.0, image `ENV` defaults such as `SELKIES_ALLOWED_ORIGINS=*`), `root/defaults/default.conf`, and every `root/etc/s6-overlay/s6-rc.d/*` script (`init-nginx`, `init-selkies-config`, `init-video`, `svc-xorg`, `svc-de`, `svc-selkies`, `svc-nginx`, `svc-pulseaudio`, `svc-dbus`, `svc-xsettingsd`, `svc-watchdog`, `svc-docker`). The same files were extracted from the pinned image's layer `3575691c…` and are byte-identical.
- `linuxserver/docker-baseimage-debian` `master` (trixie): `Dockerfile` (s6-overlay 3.2.1.0, `catatonit`, user `abc`), `init-adduser`, `init-envfile`, `init-custom-files`, `init-migrations`, `init-device-perms`, `init-crontab-config`, `svc-cron`, and `docker-mods.v3` / `with-contenv.v1` / `lsiown.v1` from `linuxserver/docker-mods` branch `mod-scripts`.
- `just-containers/s6-overlay` tag `v3.2.1.0`: `layout/rootfs-overlay/init`, `libexec/preinit`, `libexec/stage0`, `etc/s6-linux-init/skel/rc.init` and `rc.shutdown`, `etc/s6-rc/scripts/*`, `command/with-contenv`, `conf/versions`. `just-containers/s6-overlay-helpers` tag `v0.1.2.0`: `s6-overlay-suexec.c` (`if (getpid() != 1) ... "can only run as pid 1"`). `skarnet/s6-linux-init` tag `v1.1.3.0`: `s6-linux-init.c` (execs `s6-linux-init-telinit` when not PID 1), `s6-linux-init-maker.c`, `s6-linux-init-telinit.c`.
- `selkies-project/selkies` tag `2.0.0`: `src/selkies/settings.py` (environment names, `allowed_origins` default empty = same-origin), `src/selkies/stream_server.py` (`/api/health` unauthenticated 200, Origin check on WebSocket upgrades).
- Debian trixie sources: `chromium` 150.0.7871.181-1~deb13u1 (`debian/scripts/chromium` sources `/etc/chromium.d/*`; `debian/etc/dev-shm` adds `--disable-dev-shm-usage` below 3.8 GB free), `nginx` 1.26.3-3+deb13u7 (`debian/conf/nginx.conf`), `catatonit` 0.2.1-2 (`/usr/bin/catatonit`, subreaper when not PID 1).

## Market templates reviewed

| Template / repo | License | Use |
|---|---|---|
| `linux-desktop-debian` "Linux Desktop \| Debian KDE Plasma in the Cloud" / `two-workspaces/webtop-debian` | none (all rights reserved) | Read for ideas (unauthenticated health location, CPU-only notes). Nothing copied |
| `linux-desktop-alpine` / `two-workspaces/webtop-alpine` (config only), `linux-desktop-lxqt` / `two-workspaces/webtop-lxqt` | none (all rights reserved) | Read for ideas. Nothing copied |
| `debian-desktop-web-gui` "Debian" (`linuxserver/webtop:debian-xfce`, start command) | n/a (template config only) | Read for its healthcheck patch and security notes. Nothing copied |

All files in this package were written for this template. No README text was reused.

Product names belong to their owners. This is a community template, not affiliated with the Debian Project, linuxserver.io, the Selkies project or Railway. "Debian" is a registered trademark of Software in the Public Interest, Inc.
