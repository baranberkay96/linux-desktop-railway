# Deploy and Host Debian 13 XFCE Desktop with Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/debian-13-xfce-linux-desktop-in-your-browser?referralCode=20H68q)

A full Debian 13 (trixie) desktop with XFCE that you open in a browser tab. It comes with Chromium, a file manager, a terminal and a text editor. A generated password protects it, and your home directory (files, settings, browser profile) lives on a persistent volume.

## About Hosting Debian 13 XFCE Desktop

A browser desktop needs a virtual display, a desktop session, a streaming server, a login in front of it, and storage that outlives rebuilds. This community template uses the linuxserver.io webtop image (Debian XFCE, pinned release `eb802092-ls217`), which streams the desktop with Selkies over a single HTTPS WebSocket. Railway runs its own init as PID 1, which the image's s6-overlay init refuses to run under, so a small start script brings up the image's own services under s6 supervision instead. nginx requires a login on every page except `/healthz`. `/config` (the home directory) is a Railway volume.

## Common Use Cases

- Work in a full Linux environment from any device with a browser, including managed work laptops
- Desktop apps you install with apt or proot-apps, such as GIMP, LibreOffice or DBeaver
- Open untrusted links, files or browser extensions in a cloud browser instead of on your own computer
- A ready Linux environment for training sessions, demos and support work

## Dependencies for Debian 13 XFCE Desktop Hosting

- One service built from a small Dockerfile on top of `lscr.io/linuxserver/webtop` (no database, no external API keys)
- A Railway volume mounted at `/config` for the home directory

### Deployment Dependencies

- [linuxserver.io webtop image documentation](https://docs.linuxserver.io/images/docker-webtop/)
- [linuxserver/docker-webtop source (debian-xfce branch)](https://github.com/linuxserver/docker-webtop)
- [linuxserver/docker-baseimage-selkies](https://github.com/linuxserver/docker-baseimage-selkies)
- [Selkies configuration reference](https://docs.linuxserver.io/selkies/user-guide/configuration/)
- [Selkies web client guide (sidebar, clipboard, files)](https://docs.linuxserver.io/selkies/user-guide/web-client/)
- [Debian 13 "trixie"](https://www.debian.org/releases/trixie/)

### Implementation Details

| Service | What runs inside | Volume | Port |
|---|---|---|---|
| Desktop | Xvfb, XFCE, D-Bus, PulseAudio, Selkies (loopback only), nginx (login, `/healthz`), all supervised by s6 | `/config` | 3000 (public HTTPS domain) |

**First login**

1. Wait for the deploy to turn healthy (the first build pulls a 1.3 GB image, so allow a few minutes).
2. Open the public URL. The browser asks for a login.
3. User `debian` (or your `CUSTOM_USER`), password = `PASSWORD` from the service Variables tab.
4. The XFCE desktop appears and resizes to your browser window. The Selkies side menu has the clipboard box, file upload and download, audio, keyboard and display settings.

**Security**

- The desktop never runs without a login. Basic auth is on in nginx at build time, and the service refuses to start if `PASSWORD` is empty or shorter than 12 characters.
- Only a hash of the password is stored, and the password is removed from the environment before any desktop app starts.
- Requests from other websites are refused (Origin check in nginx and Selkies), so a page you visit cannot use your cached login to drive the desktop or upload files.
- The Linux user `abc` has passwordless sudo. Anyone with the password controls the whole container. Set `HARDEN_DESKTOP=true` to disable sudo, terminals and the open-with tools for a locked-down desktop.
- Browsers keep basic-auth logins until they close. Use a private window on shared computers.

**What persists**

Everything in `/config`: documents, `~/Desktop`, XFCE settings, the Chromium profile, and apps installed with `proot-apps install {app}` ([proot-apps](https://github.com/linuxserver/proot-apps) installs into the home directory). Packages installed with `sudo apt install` live in the image and reset on every redeploy. List them in the `APT_PACKAGES` variable or in `~/.config/railway-desktop/apt-packages` (one or more per line) and they are reinstalled in the background after each start (log: `/var/log/railway-desktop/apt-restore.log`).

**No GPU: software rendering**

Railway has no GPUs. The display is a software framebuffer (Xvfb), OpenGL runs on Mesa's CPU renderer, Chromium uses its software path, and Selkies encodes the video stream with x264 on the CPU. Office work, browsing and development tools run well. 3D apps, games and video editing will be slow. A busy screen costs CPU: lower the frame rate in the side menu, or set `SELKIES_FRAMERATE`, to save CPU.

**Audio and clipboard**

- Sound from desktop apps streams to your browser over the same WebSocket. Browsers only play it after you click in the page once.
- The microphone is off by default. Set `SELKIES_MICROPHONE_ENABLED=true` and allow the browser prompt to use it (HTTPS is provided by Railway).
- Text copy and paste works both ways. Chromium-based browsers ask for clipboard permission. In Firefox and Safari, paste through the clipboard box in the side menu. `SELKIES_ENABLE_CLIPBOARD` accepts `true`, `in`, `out` or `false`.

**Shared memory**

Containers often get a small `/dev/shm`, which crashes browsers. Debian's Chromium launcher moves its shared memory to `/tmp` automatically when `/dev/shm` is small, and the start log shows the size. Other Electron or browser apps you install may need `--disable-dev-shm-usage`.

**Scaling and versions**

The desktop is a single-user, volume-backed service: run one replica and scale it vertically (2 GB RAM is comfortable with a browser open). To upgrade, change the `FROM` line in `services/desktop/Dockerfile` to a newer `debian-xfce-{hash}-ls{n}` tag with its digest and redeploy. The home directory is kept.

**Limits**

No Docker inside the desktop (Railway runs no privileged containers), no WebRTC/UDP (the WebSocket stream is used instead), and running apps restart on every redeploy. Railway's app sleeping stops the desktop session as well.

**Fair use**

Use the desktop for your own work. Railway's [Fair Use Policy](https://railway.com/legal/fair-use) forbids cryptocurrency mining, torrenting, reselling compute, operating proxies or anonymization services, and abusive bots or scrapers. Do not run any of these from this desktop.

### Why Deploy Debian 13 XFCE Desktop on Railway?

Railway gives the desktop HTTPS, a persistent volume and usage-based billing without any server to manage. You get a full Linux workstation at a URL in a few minutes, pay for the RAM and CPU it actually uses, and can resize or redeploy it from the dashboard. This is a community template, not affiliated with Debian, linuxserver.io or the Selkies project.
