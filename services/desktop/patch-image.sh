#!/usr/bin/env bash
# Build-time edits of the webtop image for Railway. Runs once in the Dockerfile.
#
# /defaults/default.conf is the template that the image's init-nginx step
# copies to /etc/nginx/sites-available/default at every start. It then
# replaces the tokens 3000, 3001, CWS and SUBFOLDER, and removes every "#"
# only when PASSWORD is set (railway-start never passes PASSWORD on, see
# there). The inserted snippets therefore contain no comments, and they use
# CWS and SUBFOLDER on purpose so that they follow CUSTOM_WS_PORT and SUBFOLDER.
#
# Changes:
#  1. Basic auth is always on (the two auth_basic lines are uncommented), so
#     the desktop never serves without a login, whatever the variables say.
#     railway-start writes /etc/nginx/.htpasswd before nginx starts.
#  2. Both server blocks get an Origin check (cross-site requests carrying
#     the browser's cached login are refused), anti-framing headers, and an
#     unauthenticated /healthz that proxies to Selkies' /api/health.
#  3. nginx.conf: 2 workers instead of "auto" (one per host CPU, which on
#     Railway's large hosts means dozens of processes), no CPU pinning, and
#     the error log on stderr so it reaches the Railway logs.
set -Eeuo pipefail

readonly SRC_DIR="/tmp/railway-desktop"
readonly SITE_TEMPLATE="/defaults/default.conf"
readonly NGINX_CONF="/etc/nginx/nginx.conf"
readonly NGINX_WORKERS=2

die() { printf '[patch-image] ERROR: %s\n' "$*" >&2; exit 1; }

# require_count FILE EXTENDED_REGEX EXPECTED: fails the build when the
# upstream file no longer has the line the edit relies on.
require_count() {
  local file="$1" pattern="$2" expected="$3" found
  found="$(grep -c -E -- "$pattern" "$file" || true)"
  if [[ "$found" != "$expected" ]]; then
    die "${file}: expected ${expected} line(s) matching '${pattern}', found ${found}. The base image changed; review this script."
  fi
}

check_snippets() {
  local snippet
  for snippet in nginx-origin-map.conf nginx-server-hardening.conf; do
    [[ -s "${SRC_DIR}/${snippet}" ]] || die "missing ${snippet}"
    # init-nginx would rewrite these characters in the copied template.
    if grep -q -E '#|3000|3001' "${SRC_DIR}/${snippet}"; then
      die "${snippet} must not contain '#', '3000' or '3001'"
    fi
  done
}

patch_site_template() {
  local tmp="${SITE_TEMPLATE}.railway"

  require_count "$SITE_TEMPLATE" '^server \{$' 2
  require_count "$SITE_TEMPLATE" '^  #auth_basic +"Login";$' 2
  require_count "$SITE_TEMPLATE" '^  #auth_basic_user_file +/etc/nginx/\.htpasswd;$' 2
  require_count "$SITE_TEMPLATE" '^  location SUBFOLDER \{$' 2
  require_count "$SITE_TEMPLATE" '^  location SUBFOLDERapi \{$' 2
  require_count "$SITE_TEMPLATE" 'proxy_pass +http://127\.0\.0\.1:CWS;' 2
  if grep -q -E 'healthz|railway_origin' "$SITE_TEMPLATE"; then
    die "${SITE_TEMPLATE} is already patched"
  fi

  {
    cat "${SRC_DIR}/nginx-origin-map.conf"
    awk -v snippet="${SRC_DIR}/nginx-server-hardening.conf" '
      /^  #auth_basic/ { sub(/#/, "") }
      /^  location SUBFOLDER \{$/ {
        while ((getline line < snippet) > 0) print line
        close(snippet)
      }
      { print }
    ' "$SITE_TEMPLATE"
  } > "$tmp"

  require_count "$tmp" '^  auth_basic +"Login";$' 2
  require_count "$tmp" '^  auth_basic_user_file +/etc/nginx/\.htpasswd;$' 2
  require_count "$tmp" '^  location = /healthz \{$' 2
  # shellcheck disable=SC2016 # a literal nginx variable in the pattern
  require_count "$tmp" '^map \$http_origin \$railway_origin_host \{$' 1
  require_count "$tmp" '#' 0

  cat "$tmp" > "$SITE_TEMPLATE"
  rm -f "$tmp"
}

patch_nginx_conf() {
  require_count "$NGINX_CONF" '^worker_processes +[^;]+;$' 1
  sed -i -E "s/^worker_processes +[^;]+;$/worker_processes ${NGINX_WORKERS};/" "$NGINX_CONF"
  sed -i -E '/^worker_cpu_affinity /d' "$NGINX_CONF"
  if grep -q -E '^error_log +[^;]+;$' "$NGINX_CONF"; then
    sed -i -E 's|^error_log +[^;]+;$|error_log stderr crit;|' "$NGINX_CONF"
  else
    printf 'error_log stderr crit;\n' >> "$NGINX_CONF"
  fi
  require_count "$NGINX_CONF" "^worker_processes ${NGINX_WORKERS};$" 1
  require_count "$NGINX_CONF" '^worker_cpu_affinity ' 0
  require_count "$NGINX_CONF" '^error_log stderr crit;$' 1
}

# Renders the patched template the way init-nginx does (default ports,
# CUSTOM_WS_PORT 8082, SUBFOLDER /) and runs "nginx -t" on the patched
# nginx.conf with that site in place of sites-enabled, so a broken edit fails
# the build instead of the first boot. The certificate path of the HTTPS
# server is pointed at a throwaway certificate, since /config/ssl is created
# at runtime.
test_rendered_config() {
  local dir
  dir="$(mktemp -d)"
  require_count "$NGINX_CONF" '^[[:space:]]*include /etc/nginx/sites-enabled/\*;$' 1
  sed -e 's/CWS/8082/g' -e 's|SUBFOLDER|/|g' -e "s|/config/ssl/cert|${dir}/cert|g" \
    "$SITE_TEMPLATE" > "${dir}/site.conf"
  sed -E "s|^([[:space:]]*)include /etc/nginx/sites-enabled/\*;$|\1include ${dir}/site.conf;|" \
    "$NGINX_CONF" > "${dir}/nginx.conf"
  openssl req -new -x509 -days 1 -nodes -subj "/CN=build-test" \
    -out "${dir}/cert.pem" -keyout "${dir}/cert.key" > /dev/null 2>&1 \
    || die "could not create the test certificate"
  nginx -t -q -c "${dir}/nginx.conf" || die "nginx rejected the patched configuration"
  rm -rf "$dir"
}

main() {
  [[ -f "$SITE_TEMPLATE" ]] || die "missing ${SITE_TEMPLATE}"
  [[ -f "$NGINX_CONF" ]] || die "missing ${NGINX_CONF}"
  [[ -x /usr/bin/catatonit ]] || die "missing /usr/bin/catatonit"
  [[ -x /command/s6-svscan && -x /command/s6-rc ]] || die "missing s6 tools in /command"
  check_snippets
  patch_site_template
  patch_nginx_conf
  test_rendered_config
  printf '[patch-image] OK: auth always on, /healthz added, nginx workers=%s\n' "$NGINX_WORKERS"
}

main "$@"
