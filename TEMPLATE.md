# Debian 13 XFCE Linux Desktop in Your Browser: Railway template spec

## Listing

| Field | Value |
|---|---|
| Name | **Debian 13 XFCE Linux Desktop in Your Browser** (round-5 listing "Debian Linux Desktop in Your Browser" plus the pinned Debian major and the desktop: the image is Debian 13 "trixie" with XFCE 4.20) |
| Description | Full Debian desktop in a browser tab with a persistent home and apps. (69 chars, unchanged) |
| Category | Other |
| Tags | debian, linux-desktop, xfce, remote-desktop, webtop, selkies, chromium, browser |
| Icon | `https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/debian-linux.svg` (200, image/svg+xml) |

How the description is delivered: "Full Debian desktop": XFCE session with Chromium, Thunar, xfce4-terminal, Mousepad, Ristretto, Atril and xarchiver. "Persistent home": `/config` (the home of the desktop user) is a Railway volume. "and apps": the bundled apps keep their settings and profiles in the home directory, apps installed with `proot-apps` live in the home directory, and apt packages listed in `APT_PACKAGES` or `~/.config/railway-desktop/apt-packages` are reinstalled after every redeploy.

## Base market template

- **Base: `linux-desktop-debian` "Linux Desktop | Debian KDE Plasma in the Cloud"** (two-workspaces/webtop-debian, 62 active). Kept: linuxserver.io webtop with Selkies, a generated password, `/config` volume, an unauthenticated health location in front of basic auth, CPU-only notes. Its siblings `linux-desktop-alpine` (58) and `linux-desktop-lxqt` (41) are the same design on other flavours.
- **`debian-desktop-web-gui` "Debian"** (300 active) runs the floating tag `linuxserver/webtop:debian-xfce` with a start command that patches the nginx template and then runs `exec /init`.
- **How the market templates handle Railway's PID 1:** they do not. two-workspaces keeps the image's `ENTRYPOINT ["/init"]` and the "Debian" template ends its start command with `exec /init`. In s6-overlay 3.2.1.0, `/init` execs `s6-overlay-suexec`, whose source (s6-overlay-helpers v0.1.2.0) contains `if (getpid() != 1) strerr_dief1x(100, "can only run as pid 1")`, and `s6-linux-init` (v1.1.3.0) execs `s6-linux-init-telinit` when it is not PID 1. Under podman-init as PID 1 (observed on Railway in round 1, Rule 8.3), `/init` exits 100 before any service starts. If those templates work for their users, those deployments ran with the image entrypoint as PID 1. This could not be verified here, so this template works either way (see "PID 1 design").
- Problems fixed besides PID 1: the "Debian" template ships `PASSWORD` empty by default (blank = no login at all in this image) and a floating tag; two-workspaces pins builds from 2026-09-23 (`debian-kde-6a0b330c-ls197`, four linuxserver releases behind on 2026-10-20) without a digest; every market template keeps Selkies' `SELKIES_ALLOWED_ORIGINS=*` (cross-site WebSocket access with cached basic-auth credentials) and nginx `worker_processes auto` (one worker per host CPU).
- All market repos have **no license**: read for ideas only, nothing copied.

## Pinned versions

| Component | Version | Source | Checked |
|---|---|---|---|
| Base image | `lscr.io/linuxserver/webtop:debian-xfce-eb802092-ls217@sha256:d925f9c84663fe57735be4defe95a338d32bc37f2e12b9e0f0981e91b6bd0a5d` (built 2026-10-13, newest debian-xfce release on 2026-10-20) | Same digest on Docker Hub `linuxserver/webtop`, `ghcr.io/linuxserver/webtop` and `lscr.io` | 2026-10-20 |
| Debian | 13 "trixie" (baseimage-debian `REL=trixie`) | linuxserver/docker-baseimage-debian | 2026-10-20 |
| XFCE | 4.20 (xfce4-session 4.20.2-2) | Debian trixie | 2026-10-20 |
| Selkies | 2.0.0 (2026-09-23) | baseimage-selkies `SELKIES_RELEASE` | 2026-10-20 |
| s6-overlay | 3.2.1.0 (s6 2.13.2.0, s6-rc 0.5.6.0, s6-linux-init 1.1.3.0) | baseimage-debian `S6_OVERLAY_VERSION`, files listed in image layer 0 | 2026-10-20 |
| nginx | 1.26.3 (Debian trixie) | Debian package | 2026-10-20 |

The tag and digest are on the `FROM` line of `services/desktop/Dockerfile`. If lscr.io is unreachable during a build, `ghcr.io/linuxserver/webtop` with the same tag and digest is equivalent.

## Architecture

```
 Browser ── HTTPS + WebSocket (Railway edge) ──► :3000 nginx (PORT; IPv4, IPv6 if present)
                                                   │ /healthz   no auth ─► Selkies /api/health
                                                   │ everything else: basic auth (SHA-512 crypt),
                                                   │ Origin check, anti-framing headers
                                                   ├─ /        static Selkies dashboard
                                                   └─ /api     ─► 127.0.0.1:8082 Selkies (loopback only)
                                                                  │ WebSocket: H.264/JPEG video (x264, CPU),
                                                                  │ Opus audio, input, clipboard, files
                                                                  ▼
                                   Xvfb :1 ◄── XFCE 4.20 session (user abc, uid 1000, HOME=/config)
 ┌───────────────────────────────────────────────────────────────────────────────────────┐
 │ Desktop service (Dockerfile in services/desktop)                                      │
 │ podman-init (PID 1, Railway) → catatonit (subreaper) → railway-start (root)            │
 │   → s6-svscan /run/service → s6-rc "top": init-* oneshots, then svc-xorg, svc-dbus,     │
 │     svc-pulseaudio, svc-nginx, svc-selkies, svc-de (XFCE), svc-xsettingsd, svc-cron … │
 │ volume /config                                                                         │
 └───────────────────────────────────────────────────────────────────────────────────────┘
```

## Services

### Desktop

| Setting | Value |
|---|---|
| Source | repo `baranberkay96/linux-desktop-railway`, root `/services/desktop` (Dockerfile) |
| Healthcheck | `/healthz` on `PORT=3000`, timeout 600 s (first boot creates the home directory, docker mods can install packages before nginx starts) |
| Public domain | yes, target port 3000 |
| TCP proxy | none |
| Volume | `/config` (home of the desktop user `abc`) |
| Restart policy | ON_FAILURE, 10 retries |
| Replicas | 1 (single-user, volume-backed) |

Files in `services/desktop/`:
- `Dockerfile`: `FROM` the pinned webtop digest; image defaults `PUID/PGID=1000`, `START_DOCKER=false`, `SELKIES_ALLOWED_ORIGINS=""`, `SELKIES_ENABLE_BASIC_AUTH=false`, `TITLE`, `CUSTOM_USER=debian`, `PORT=3000`; runs `patch-image.sh`; `ENTRYPOINT ["/usr/bin/catatonit", "--", "/usr/local/bin/railway-start"]`.
- `patch-image.sh` (build time, fails the build if an anchor is missing): turns basic auth on permanently in `/defaults/default.conf`, inserts the Origin map, the Origin check, anti-framing headers and `/healthz` into both server blocks, sets nginx to 2 workers without CPU pinning and with the error log on stderr, then renders the template as `init-nginx` would and runs `nginx -t` on it.
- `nginx-origin-map.conf`, `nginx-server-hardening.conf`: the inserted snippets (no `#`, `3000` or `3001`, because `init-nginx` rewrites those).
- `railway-start.sh` → `/usr/local/bin/railway-start`: see "PID 1 design".
- `apt-restore.sh` → `/usr/local/bin/railway-apt-restore`: background reinstall of `APT_PACKAGES` and `~/.config/railway-desktop/apt-packages` (names validated, symlinks ignored, dpkg lock timeout 600 s). The home-directory list is ignored when `HARDEN_DESKTOP` or `DISABLE_SUDO` is on.

### Variables

| Variable | Default | Notes |
|---|---|---|
| `PASSWORD` | `${{secret(32)}}` | Browser login. At least 12 characters and one line, otherwise the service exits with a clear log message. Only its SHA-512 crypt hash is kept; the variable is removed before any service starts. |
| `CUSTOM_USER` | `debian` | Browser login name, `[A-Za-z0-9._@-]{1,64}`. The Linux account is always `abc`. |
| `PORT` | `3000` | nginx listen port (copied to the image's `CUSTOM_PORT`). Rule 8.1: Railway's healthcheck probes it. Must differ from 3001 (internal HTTPS) and 8082 (Selkies). |
| `TZ` | `Etc/UTC` | Time zone. |
| `TITLE` | `Debian 13 XFCE Desktop` | Browser tab title. |
| `APT_PACKAGES` | empty | Optional packages reinstalled in the background after each start. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `15` | Time for the ordered shutdown. |

Optional upstream variables that work unchanged (documented in README): `HARDEN_DESKTOP`, `SELKIES_FRAMERATE`, `SELKIES_MICROPHONE_ENABLED`, `SELKIES_ENABLE_CLIPBOARD`, `LC_ALL`, `DOCKER_MODS`, `DESKTOP_SHM_SIZE` (this template; default `1G`, see shared memory). No required inputs.

## PID 1 design

`railway-start` does what the PID 1 parts of s6-overlay would have done, then hands over to the image's own stage 2. Every upstream service definition, dependency and readiness rule is kept.

1. **Validate** `PORT` (numeric, not 3001/8082), `CUSTOM_USER`, `PASSWORD` (≥ 12 characters, one line). Fail closed.
2. **Login file:** `openssl passwd -6 -stdin` → `/etc/nginx/.htpasswd` (root:www-data 0640). `PASSWORD`, `PASSWD` and `SELKIES_BASIC_AUTH_PASSWORD` are unset. Because the env dump below has no `PASSWORD`, `init-nginx` neither rewrites the login file nor strips `#` from the template.
3. **Checks:** warns if `/config` is not a mounted volume; logs `/dev/shm` and tries to grow it to `DESKTOP_SHM_SIZE`; sets `DISABLE_IPV6=true` when the container has no IPv6 (otherwise nginx's `[::]` listener would fail).
4. **preinit equivalent:** clears `/run/s6`, `/run/service`, `/run/s6-rc*`; creates them; adds `/run/s6/basedir/bin/halt` (→ `s6-svscanctl -t`) for scripts that stop the container the s6-overlay way.
5. **Environment dump** to `/run/s6/container_environment` (one file per variable, as `s6-linux-init -s` does), which every upstream `with-contenv` script reads.
6. **`s6-svscan /run/service`** in the background with only `PATH` in its environment (as s6-linux-init starts it), waiting until `s6-svscanctl -a` answers.
7. **Stage 2 (background job, as in s6-overlay `rc.init`):** `S6_STAGE2_HOOK` (`/docker-mods`: custom services, docker mods), `s6-rc-compile /run/s6/db /etc/s6-overlay/s6-rc.d /package/admin/s6-overlay/etc/s6-rc/sources`, `s6-rc-init`, `s6-rc -u change top`. A compile/init failure stops the container; a service that fails to come up is logged (upstream's default `S6_BEHAVIOUR_IF_STAGE2_FAILS=0`), and the healthcheck catches a missing nginx or Selkies.
8. **Supervision:** s6-supervise restarts any service that dies. If s6-svscan itself exits, `railway-start` exits 1 and Railway restarts the container.
9. **SIGTERM** (catatonit forwards it): `s6-rc -bda change` (services down in reverse order, 10 s limit; skipped if stage 2 is still running), `s6-svscanctl -t`, exit 0.

The same path runs when the container's entrypoint is PID 1 (local `docker run` without `--init`): catatonit is then PID 1 instead of a subreaper.

## Healthcheck and auth design

- Basic auth is part of the image template (uncommented at build), so no variable combination can produce an open desktop. Without the login file nginx would answer 500, not serve the desktop.
- `/healthz` (exact match, GET/HEAD only, no auth, no access log) proxies to Selkies' `GET /api/health` on loopback, which Selkies 2.0.0 answers `200 OK` without credentials. It passes only when nginx and Selkies both run, and it shows no desktop content. Its upstream URL is written with the `CWS` and `SUBFOLDER` tokens, so it follows `CUSTOM_WS_PORT` and `SUBFOLDER`.
- **Origin check** (server level, both servers): a request with an `Origin` header must come from the same host name (`$host`); a missing `Origin` (navigations, CLI clients) is allowed. This stops cross-site POSTs to `/api/upload` and WebSocket hijacking with the browser's cached basic-auth credentials. Selkies' own WebSocket check is back on same-origin because the Dockerfile resets `SELKIES_ALLOWED_ORIGINS` from `*` to empty (Selkies' default).
- `X-Frame-Options: SAMEORIGIN` and `frame-ancestors 'self'` against clickjacking.
- Selkies listens on `localhost` only (`--addr=localhost` in `svc-selkies`), the internal HTTPS port 3001 is not routed by Railway, and the bundled Docker daemon is off.

## First login

1. Wait for the deployment to be healthy. The first build pulls about 1.3 GB.
2. Open the public URL and sign in with `debian` / `PASSWORD`.
3. The XFCE desktop opens at the browser window's size. The Selkies side menu has clipboard, file transfer, audio, keyboard, display and stream settings.
4. Terminal: `sudo apt update && sudo apt install {package}`. For packages that should come back after redeploys, add them to `APT_PACKAGES` or `~/.config/railway-desktop/apt-packages`, or install apps into the home directory with `proot-apps install {app}`.

## Improvements over market templates

1. **Starts under Railway's PID 1.** The image's `/init` refuses to run when it is not PID 1 (source-verified); `railway-start` runs the same s6 tree without that check. Market templates run `/init` unchanged.
2. **Never an open desktop:** generated `secret(32)` password, minimum length check, and basic auth compiled into the nginx template. The "Debian" market template defaults to an empty password, which disables the login entirely.
3. **Cross-site protection:** Selkies back to same-origin WebSockets (market images keep `*`), plus an nginx Origin check that also covers uploads, and anti-framing headers.
4. **Password hygiene:** only a SHA-512 crypt hash on disk; the password is not in the environment of any service, desktop app or terminal (upstream keeps `PASSWORD` in the container environment and hashes it with apr1-MD5 on the command line).
5. **Pinned, current and reproducible image:** release tag plus multi-arch digest from 2026-10-13 (Debian 13, Selkies 2.0.0). The "Debian" template uses a floating tag; two-workspaces pins 2026-09-23 builds by tag only.
6. **Healthcheck that tests the stream server** (`/healthz` → Selkies `/api/health`), with `PORT` set and a 600 s window.
7. **Right-sized nginx:** 2 workers instead of one per host CPU, error log in the Railway logs.
8. **apt packages come back after redeploys** (`APT_PACKAGES` / home list, in the background so boot is not delayed), with a hardening guard.
9. **Shared memory handled and reported:** Debian's Chromium launcher falls back to `/tmp` below 3.8 GB of `/dev/shm` (verified in the trixie package), and the start log reports the size and tries to grow it.
10. **Clean shutdown** in dependency order within `RAILWAY_DEPLOYMENT_DRAINING_SECONDS=15`; Docker daemon disabled (it cannot run on Railway); IPv6 listener dropped automatically if the container has no IPv6; fixed uid 1000 for the volume.
11. Honest documentation of CPU-only rendering, audio, microphone, clipboard and file transfer, and a Fair Use note.

## Resource estimate

Railway prices: RAM $10/GB-month, vCPU $20/vCPU-month, volume $0.15/GB-month. Estimates, not measured.

| State | RAM | CPU | Notes |
|---|---|---|---|
| Idle (no browser tab connected) | ~0.45 GB | ~0.03 vCPU | Xvfb, XFCE session, Selkies (Python), PulseAudio, nginx |
| Active session, office/dev work | 0.8-1.5 GB | 0.3-1.0 vCPU while the screen changes | x264 software encoding of the stream at up to 60 fps |
| Active with Chromium and several tabs | 1.5-3 GB | 0.5-1.5 vCPU | |
| Volume `/config` | 1 GB at start | | Chromium cache and user files grow it |

Monthly cost: **idle 24/7 ≈ $5.25** (0.45 GB × $10 + 0.03 vCPU × $20 + 1 GB × $0.15). **Typical ≈ $13** (always on, about 3 hours of active use a day: ~1.0 GB average RAM, ~0.13 vCPU average, 3 GB volume). Heavy daily use (8 h/day, 2 GB, 0.35 vCPU average, 5 GB) ≈ $28.

Minimum plan: **Hobby.** Trial's 1 GB per service boots the desktop but Chromium will run out of memory. Hobby's 5 GB volume cap per service bounds `/config`; Pro allows more. Railway's app sleeping can cut idle cost, but it stops the desktop session and only triggers when the desktop makes no outbound traffic.

## Verification checklist

- [ ] Build log: `[patch-image] OK: auth always on, /healthz added, nginx workers=2`. A failing build here means the base image changed: read the `[patch-image] ERROR` line.
- [ ] Deploy log: `[railway-start]` lines for `/dev/shm`, then the s6 init output (`[ls.io-init] done.`), then `Desktop services are up. Sign in as 'debian' …`. No `can only run as pid 1` line, and no password anywhere in the log.
- [ ] `curl -i https://{domain}/healthz` → `200` `OK`. `curl -i https://{domain}/` → `401` with `WWW-Authenticate: Basic`. Wrong password → `401`.
- [ ] Browser login with `debian` / `PASSWORD`: XFCE desktop appears, resizes with the window, mouse and keyboard work, the panel and Chromium start.
- [ ] Cross-site: `curl -i -u debian:PASS -H 'Origin: https://evil.example' https://{domain}/` → `403`; the same with `Origin: https://{domain}` → `200`.
- [ ] In the desktop terminal: `echo "${PASSWORD:-unset}"` → `unset`; `id` → `uid=1000(abc)`; `sudo -n true` works; `ps -C nginx` shows 1 master + 2 workers; `cat /proc/1/comm` → `podman-init` (or `catatonit` locally).
- [ ] Audio: play a sound in Chromium after clicking the page; clipboard: copy text both ways; upload a file through the side menu (lands in `~/Desktop`).
- [ ] Chromium runs several tabs without "Aw, Snap!" (shared memory fallback). Note the `/dev/shm` size from the start log.
- [ ] Persistence: create `~/Desktop/test.txt`, set a wallpaper, add `gimp` to `APT_PACKAGES`, redeploy. The file and wallpaper remain, and the log shows `Packages restored.`
- [ ] Redeploy log shows `Received SIGTERM: stopping the desktop.` and the old deployment stops within 15 s.
- [ ] Set `PASSWORD` to `short` and redeploy: the deploy fails with the "PASSWORD is empty or shorter than 12 characters" line and nothing listens.

## Open questions

- Nothing was built or run (Docker was off-limits). The first Railway build is the first build of this Dockerfile; `patch-image.sh` runs `nginx -t` on the patched config there.
- `railway-start` reproduces s6-overlay's boot order from source; it has not been executed. Specific unknowns: `s6-svscanctl -a` as the readiness probe for s6-svscan, `env -0`-based env dump vs. `s6-linux-init`'s, and SIGTERM handling end to end.
- Whether Railway's runtime grants the image what `init-selkies-config` tries (`mknod` for gamepad/webcam devices falls back to plain files, upstream behaviour) and whether `sudo` (setuid) works.
- `/dev/shm` size on Railway and whether the remount works (needs CAP_SYS_ADMIN; expected to fail harmlessly).
- Railway's edge: `Host` kept as the public domain (needed by both Origin checks) and long-lived WebSockets (Selkies reconnects if the edge closes them).
- Software-encoding CPU cost at Railway's shared vCPUs; the frame-rate default (60) may need lowering for some users.
- The README Deploy button code `debian-13-xfce-linux-desktop-in-your-browser` is predicted from earlier publishes. Confirm after publishing.
