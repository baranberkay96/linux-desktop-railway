# syntax=docker/dockerfile:1
#
# Debian 13 XFCE desktop in the browser, for Railway.
#
# Base: linuxserver.io webtop, branch debian-xfce, release eb802092-ls217
# (built 2026-10-13, git revision 721ecb8c of linuxserver/docker-webtop).
# The digest is the multi-arch index, identical on lscr.io, ghcr.io and
# Docker Hub. To upgrade, replace tag and digest together with a newer
# "debian-xfce-<hash>-ls<n>" release and redeploy.
FROM lscr.io/linuxserver/webtop:debian-xfce-eb802092-ls217@sha256:d925f9c84663fe57735be4defe95a338d32bc37f2e12b9e0f0981e91b6bd0a5d

# Image defaults for Railway. Variables set on the Railway service win.
#  - PUID/PGID 1000: fixed owner of the /config volume. Do not change them
#    after the first boot, because files already on the volume keep the old ids.
#  - START_DOCKER=false: Railway gives no privileged containers, so the
#    bundled Docker daemon can never run there.
#  - SELKIES_ALLOWED_ORIGINS empty: the image ships "*", which lets any
#    website open the desktop's WebSocket with the browser's cached login.
#    Empty is Selkies' own default: same-origin only.
#  - SELKIES_ENABLE_BASIC_AUTH=false: nginx does the login. Selkies listens
#    on loopback only.
ENV PUID=1000 \
    PGID=1000 \
    START_DOCKER=false \
    SELKIES_ALLOWED_ORIGINS="" \
    SELKIES_ENABLE_BASIC_AUTH=false \
    TITLE="Debian 13 XFCE Desktop" \
    CUSTOM_USER=debian \
    PORT=3000

COPY patch-image.sh /tmp/railway-desktop/patch-image.sh
COPY nginx-origin-map.conf nginx-server-hardening.conf /tmp/railway-desktop/
COPY railway-start.sh /usr/local/bin/railway-start
COPY apt-restore.sh /usr/local/bin/railway-apt-restore

# Build-time edits of the image's nginx files. The script checks every
# anchor it edits and fails the build if the upstream files have changed.
RUN bash /tmp/railway-desktop/patch-image.sh \
 && rm -rf /tmp/railway-desktop \
 && chmod 0755 /usr/local/bin/railway-start /usr/local/bin/railway-apt-restore

EXPOSE 3000

# Railway runs its own init (podman-init) as PID 1, and the image's /init
# (s6-overlay 3.2.1.0) refuses to start unless it is PID 1. railway-start
# brings up the same s6 supervision tree without that check. catatonit
# (Debian package, already in the image) reaps zombies and forwards signals,
# as a child subreaper when it is not PID 1 itself.
ENTRYPOINT ["/usr/bin/catatonit", "--", "/usr/local/bin/railway-start"]
