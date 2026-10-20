#!/usr/bin/env bash
# railway-start: boots the linuxserver.io webtop desktop when its /init cannot.
#
# Why: Railway runs its own init (podman-init) as PID 1. The image's /init
# (s6-overlay 3.2.1.0) execs s6-overlay-suexec, which exits with "can only run
# as pid 1" in that case, so no desktop, nginx or Selkies would ever start.
# s6-svscan and s6-rc themselves do not need PID 1, so this script does the
# PID 1 part itself and then runs the image's own stage 2 unchanged:
#
#  1. Checks PORT, CUSTOM_USER and PASSWORD. Without a password of at least
#     12 characters it exits: this template never serves an open desktop.
#  2. Writes the nginx login file (SHA-512 crypt) and removes PASSWORD from
#     the environment, so no service, desktop app or terminal can read it.
#  3. Prepares /run like s6-overlay's preinit and saves the environment to
#     /run/s6/container_environment, which the image's with-contenv reads.
#  4. Starts s6-svscan on /run/service with a clean environment.
#  5. Stage 2, as in s6-overlay's rc.init: the S6_STAGE2_HOOK (docker-mods),
#     s6-rc-compile, s6-rc-init and "s6-rc change top". All upstream init
#     steps and services (Xvfb, D-Bus, PulseAudio, nginx, Selkies, XFCE,
#     cron) start in their declared order, and s6-supervise restarts any
#     service that dies.
#  6. Reinstalls requested apt packages in the background.
#  7. SIGTERM: services go down in order, s6-svscan stops, exit 0. If
#     s6-svscan dies on its own, exit 1 so Railway restarts the container.
set -Eeuo pipefail

readonly SCANDIR="/run/service"
readonly S6_RUN_DIR="/run/s6"
readonly ENV_DIR="/run/s6/container_environment"
readonly S6_DB="/run/s6/db"
readonly S6_LIVE="/run/s6-rc"
readonly SITE_SOURCES="/etc/s6-overlay/s6-rc.d"
readonly OVERLAY_SOURCES="/package/admin/s6-overlay/etc/s6-rc/sources"
readonly HTPASSWD_FILE="/etc/nginx/.htpasswd"
readonly CONFIG_DIR="/config"
readonly MIN_PASSWORD_LENGTH=12
readonly DEFAULT_PORT=3000
readonly DEFAULT_HTTPS_PORT=3001
readonly DEFAULT_WS_PORT=8082
readonly DEFAULT_USER="debian"
readonly DEFAULT_SHM_SIZE="1G"
readonly SVSCAN_START_TRIES=100
readonly STOP_TIMEOUT_MS=10000

case ":${PATH}:" in
  *:/command:*) ;;
  *) PATH="/command:${PATH}" ;;
esac
export PATH
readonly S6_PATH="$PATH"

SVSCAN_PID=""
STAGE2_PID=""

log() { printf '[railway-start] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

is_port() {
  [[ "$1" =~ ^[1-9][0-9]{0,4}$ ]] && (( $1 <= 65535 ))
}

validate_settings() {
  local https_port="${CUSTOM_HTTPS_PORT:-$DEFAULT_HTTPS_PORT}"
  local ws_port="${CUSTOM_WS_PORT:-$DEFAULT_WS_PORT}"

  PORT="${PORT:-$DEFAULT_PORT}"
  is_port "$PORT" || die "PORT must be a number between 1 and 65535 (got '${PORT}')."
  is_port "$https_port" || die "CUSTOM_HTTPS_PORT must be a port number (got '${https_port}')."
  is_port "$ws_port" || die "CUSTOM_WS_PORT must be a port number (got '${ws_port}')."
  if (( PORT == https_port || PORT == ws_port )); then
    die "PORT ${PORT} is used internally (HTTPS ${https_port}, Selkies ${ws_port}). Pick another port."
  fi
  if [[ -n "${CUSTOM_PORT:-}" && "${CUSTOM_PORT}" != "$PORT" ]]; then
    log "CUSTOM_PORT=${CUSTOM_PORT} is ignored: nginx listens on PORT=${PORT}, the port Railway routes to."
  fi
  export PORT CUSTOM_PORT="$PORT"

  CUSTOM_USER="${CUSTOM_USER:-$DEFAULT_USER}"
  if [[ ! "$CUSTOM_USER" =~ ^[A-Za-z0-9._@-]{1,64}$ ]]; then
    die "CUSTOM_USER may only contain letters, digits and . _ @ - (1-64 characters)."
  fi
  export CUSTOM_USER

  PASSWORD="${PASSWORD:-}"
  if (( ${#PASSWORD} < MIN_PASSWORD_LENGTH )); then
    die "PASSWORD is empty or shorter than ${MIN_PASSWORD_LENGTH} characters. Set it in the service Variables. The desktop does not start without a password."
  fi
  if [[ "$PASSWORD" == *$'\n'* ]]; then
    die "PASSWORD must be a single line."
  fi

  # init-nginx removes the IPv6 listener only when DISABLE_IPV6 is set.
  if [[ -z "${DISABLE_IPV6:-}" && ! -s /proc/net/if_inet6 ]]; then
    log "No IPv6 in this container: nginx listens on IPv4 only."
    export DISABLE_IPV6=true
  fi
}

# nginx has basic auth switched on at build time (patch-image.sh), so the
# login file must exist before nginx starts. Only the hash is kept.
write_login_file() {
  local hash tmp="${HTPASSWD_FILE}.tmp"

  hash="$(printf '%s\n' "$PASSWORD" | openssl passwd -6 -stdin)" || die "Could not hash PASSWORD."
  # shellcheck disable=SC2016 # literal "$6$" prefix of a SHA-512 crypt hash
  [[ "$hash" == '$6$'* ]] || die "openssl returned an unexpected password hash format."
  (
    umask 0027
    printf '%s:%s\n' "$CUSTOM_USER" "$hash" > "$tmp"
  )
  chown root:www-data "$tmp"
  chmod 0640 "$tmp"
  mv -f "$tmp" "$HTPASSWD_FILE"
  unset PASSWORD PASSWD SELKIES_BASIC_AUTH_PASSWORD
}

check_volume() {
  if command -v mountpoint > /dev/null 2>&1 && ! mountpoint -q "$CONFIG_DIR"; then
    log "WARNING: ${CONFIG_DIR} is not a mounted volume. The home directory is lost on every redeploy."
  fi
}

# Browsers keep shared memory in /dev/shm. Debian's chromium launcher already
# switches to /tmp (--disable-dev-shm-usage) when /dev/shm has less than
# 3.8 GB free. Growing /dev/shm needs CAP_SYS_ADMIN, which most container
# runtimes withhold: this tries once and only logs the outcome.
report_shared_memory() {
  local want="${DESKTOP_SHM_SIZE:-$DEFAULT_SHM_SIZE}" have_bytes want_bytes

  have_bytes="$(df -P -B1 /dev/shm 2> /dev/null | awk 'NR == 2 { print $2 }')"
  [[ "$have_bytes" =~ ^[0-9]+$ ]] || { log "/dev/shm size unknown."; return 0; }
  case "$(printf '%s' "$want" | tr '[:upper:]' '[:lower:]')" in
    '' | 0 | off | false | no) log "/dev/shm: $(( have_bytes / 1048576 )) MiB."; return 0 ;;
  esac
  want_bytes="$(numfmt --from=iec "$(printf '%s' "$want" | tr '[:lower:]' '[:upper:]')" 2> /dev/null || true)"
  if [[ ! "$want_bytes" =~ ^[0-9]+$ ]]; then
    log "WARNING: DESKTOP_SHM_SIZE '${want}' is not a size like 1G or 512M. Ignored."
  elif (( have_bytes < want_bytes )) && mount -o "remount,size=${want}" /dev/shm 2> /dev/null; then
    log "/dev/shm grown from $(( have_bytes / 1048576 )) MiB to ${want}."
    return 0
  fi
  log "/dev/shm: $(( have_bytes / 1048576 )) MiB. Chromium uses /tmp for shared memory when it is small."
}

# What s6-overlay's preinit does for a root container, minus the PID 1 parts.
prepare_s6_runtime() {
  install -d -m 0755 /run
  if [[ ! -L /var/run ]]; then
    log "WARNING: /var/run is not a symlink to /run."
  fi
  rm -rf "$S6_RUN_DIR" "$SCANDIR" /run/uncaught-logs "$S6_LIVE" "${S6_LIVE}":*
  install -d -m 0755 "$S6_RUN_DIR" "$SCANDIR" "${S6_RUN_DIR}/basedir/bin"
  # Same path as s6-overlay's halt, for scripts that stop the container with it.
  printf '#!/bin/sh\nexec /command/s6-svscanctl -t %s\n' "$SCANDIR" > "${S6_RUN_DIR}/basedir/bin/halt"
  chmod 0755 "${S6_RUN_DIR}/basedir/bin/halt"
}

# s6-linux-init writes one file per variable to this directory, and every
# upstream service script reads it through with-contenv.
dump_environment() {
  local entry name
  install -d -m 0755 "$ENV_DIR"
  while IFS= read -r -d '' entry; do
    name="${entry%%=*}"
    case "$name" in
      _ | SHLVL | PWD | OLDPWD) continue ;;
    esac
    [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    printf '%s' "${entry#*=}" > "${ENV_DIR}/${name}"
  done < <(env -0)
}

start_svscan() {
  local try
  env -i PATH="$S6_PATH" s6-svscan "$SCANDIR" < /dev/null &
  SVSCAN_PID=$!
  for (( try = 0; try < SVSCAN_START_TRIES; try++ )); do
    if s6-svscanctl -a "$SCANDIR" 2> /dev/null; then
      return 0
    fi
    kill -0 "$SVSCAN_PID" 2> /dev/null || die "s6-svscan exited during startup."
    sleep 0.1
  done
  die "s6-svscan did not answer within $(( SVSCAN_START_TRIES / 10 )) seconds."
}

verbosity() {
  local v="${S6_VERBOSITY:-2}"
  [[ "$v" =~ ^[0-9]+$ ]] || v=2
  printf '%s' "$v"
}

run_stage2_hook() {
  local -a hook=()
  local status=0
  [[ -n "${S6_STAGE2_HOOK:-}" ]] || return 0
  read -r -a hook <<< "$S6_STAGE2_HOOK"
  env -i PATH="$S6_PATH" "${hook[@]}" || status=$?
  if (( status != 0 )); then
    log "WARNING: stage 2 hook ${S6_STAGE2_HOOK} exited ${status}."
  fi
}

# Runs in the background so SIGTERM is handled at once, even while init
# steps or docker mods are still running.
stage2() {
  local v cv timeout="${S6_CMD_WAIT_FOR_SERVICES_MAXTIME:-0}"
  local url="the service's public domain"
  if [[ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]]; then
    url="https://${RAILWAY_PUBLIC_DOMAIN}/"
  fi
  v="$(verbosity)"
  cv=$(( v > 0 ? v - 1 : 0 ))
  [[ "$timeout" =~ ^[0-9]+$ ]] || timeout=0

  run_stage2_hook
  if ! s6-rc-compile -v"$cv" "$S6_DB" "$SITE_SOURCES" "$OVERLAY_SOURCES" \
    || ! s6-rc-init -c "$S6_DB" "$SCANDIR"; then
    log "ERROR: could not compile or load the image's s6-rc service database."
    s6-svscanctl -t "$SCANDIR" 2> /dev/null || true
    exit 1
  fi
  if s6-rc -v"$v" -u -t "$timeout" -- change top; then
    log "Desktop services are up. Sign in as '${CUSTOM_USER}' at ${url}"
  else
    log "WARNING: some services did not start (s6-rc exited $?). See the lines above."
  fi
  # Detached, so a slow package mirror never blocks an orderly shutdown.
  nice -n 10 /usr/local/bin/railway-apt-restore &
}

# shellcheck disable=SC2329 # called from the signal trap
stop_services() {
  if [[ -n "$STAGE2_PID" ]] && kill -0 "$STAGE2_PID" 2> /dev/null; then
    log "Startup still running: stopping all supervised processes."
  elif [[ -e "$S6_LIVE" ]]; then
    s6-rc -v1 -bda -t "$STOP_TIMEOUT_MS" change > /dev/null 2>&1 \
      || log "WARNING: not every service stopped cleanly within $(( STOP_TIMEOUT_MS / 1000 )) s."
  fi
  if [[ -n "$SVSCAN_PID" ]]; then
    s6-svscanctl -t "$SCANDIR" 2> /dev/null || kill -TERM "$SVSCAN_PID" 2> /dev/null || true
    wait "$SVSCAN_PID" 2> /dev/null || true
  fi
}

# shellcheck disable=SC2329 # called from the signal trap
on_signal() {
  trap - TERM INT
  log "Received SIG$1: stopping the desktop."
  stop_services
  exit 0
}

supervise() {
  local status=0
  while kill -0 "$SVSCAN_PID" 2> /dev/null; do
    status=0
    wait "$SVSCAN_PID" || status=$?
  done
  log "s6-svscan exited (status ${status}). Stopping the container so Railway restarts it."
  exit 1
}

main() {
  trap 'on_signal TERM' TERM
  trap 'on_signal INT' INT
  validate_settings
  write_login_file
  check_volume
  report_shared_memory
  prepare_s6_runtime
  dump_environment
  start_svscan
  stage2 &
  STAGE2_PID=$!
  supervise
}

main "$@"
