#!/usr/bin/env bash
# railway-apt-restore: reinstalls Debian packages after a redeploy.
#
# Only /config (the home directory) is on the Railway volume. Packages
# installed with apt live in the image and are gone after every redeploy.
# This script, started in the background by railway-start once the desktop
# is up, reinstalls the packages listed in:
#   - the APT_PACKAGES variable (space or comma separated), and
#   - ~/.config/railway-desktop/apt-packages (one or more per line, '#' comments).
# The home-directory list is ignored when HARDEN_DESKTOP or DISABLE_SUDO is
# on, because there the desktop user must not be able to install packages.
set -Eeuo pipefail

readonly LIST_FILE="/config/.config/railway-desktop/apt-packages"
readonly LOG_DIR="/var/log/railway-desktop"
readonly LOG_FILE="${LOG_DIR}/apt-restore.log"
readonly DPKG_LOCK_TIMEOUT=600
readonly NAME_PATTERN='^[a-z0-9][a-z0-9+.-]+(=[A-Za-z0-9.+:~-]+)?$'

log() { printf '[railway-apt-restore] %s\n' "$*" >&2; }

is_true() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    1 | true | yes | on) return 0 ;;
    *) return 1 ;;
  esac
}

# Prints the requested packages, one per line, without duplicates.
collect_packages() {
  local -a words=() parts=()
  local -A seen=()
  local line word

  if [[ -n "${APT_PACKAGES:-}" ]]; then
    read -r -a words <<< "${APT_PACKAGES//,/ }"
  fi
  if is_true "${HARDEN_DESKTOP:-}" || is_true "${DISABLE_SUDO:-}"; then
    if [[ -e "$LIST_FILE" ]]; then
      log "Desktop is hardened: ignoring ${LIST_FILE}."
    fi
  elif [[ -f "$LIST_FILE" && ! -L "$LIST_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%%#*}"
      read -r -a parts <<< "$line"
      words+=("${parts[@]}")
    done < "$LIST_FILE"
  fi

  for word in "${words[@]}"; do
    if [[ ! "$word" =~ $NAME_PATTERN ]]; then
      log "Skipping invalid package name: '${word:0:64}'"
      continue
    fi
    if [[ -z "${seen[$word]:-}" ]]; then
      seen[$word]=1
      printf '%s\n' "$word"
    fi
  done
}

main() {
  local -a pkgs=()
  mapfile -t pkgs < <(collect_packages)
  (( ${#pkgs[@]} > 0 )) || exit 0

  install -d -m 0755 "$LOG_DIR"
  log "Reinstalling ${#pkgs[@]} package(s): ${pkgs[*]} (log: ${LOG_FILE})"
  if {
    DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout="$DPKG_LOCK_TIMEOUT" update &&
      DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout="$DPKG_LOCK_TIMEOUT" \
        install -y --no-install-recommends "${pkgs[@]}"
  } > "$LOG_FILE" 2>&1; then
    log "Packages restored."
  else
    log "WARNING: package restore failed. See ${LOG_FILE} (tail below)."
    tail -n 15 "$LOG_FILE" >&2 || true
  fi
}

main "$@"
