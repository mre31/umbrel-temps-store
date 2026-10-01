#!/bin/sh
set -eu

# Temps Umbrel host bootstrap
#
# This container is intentionally privileged because its only job is to execute
# the official Temps installer in the host namespaces. Temps itself then runs
# natively under systemd on the Umbrel host.
#
# Reviewed installer digest published in the upstream Temps platform-setup skill:
EXPECTED_DEPLOY_SHA256="49ecd9ce4ee0d4302ae8f11cadbdaa376135800e8f59690ae79c513af762de33"

# Pin an immutable upstream release instead of following a moving channel.
TEMPS_VERSION="v0.1.0-nightly.20260930.53d4fb40"
ADMIN_EMAIL="admin@temps.local"

STATE_DIR="/state"
HOST_SCRIPT="/tmp/temps-deploy-umbrel.sh"
LOCAL_SCRIPT="${STATE_DIR}/temps-deploy.sh"

echo "[temps-umbrel] Preparing bootstrap tools..."
apk add --no-cache bash curl coreutils util-linux >/dev/null

mkdir -p "${STATE_DIR}"
chmod 700 "${STATE_DIR}"

host_exec() {
  nsenter -t 1 -m -u -i -n -p -- "$@"
}

temps_exists() {
  host_exec /bin/sh -c 'test -x /usr/local/bin/temps && systemctl list-unit-files temps.service >/dev/null 2>&1'
}

if ! temps_exists; then
  echo "[temps-umbrel] Downloading the official Temps installer..."
  curl --fail --silent --show-error     --proto '=https' --tlsv1.2 --proto-redir '=https' --location     https://temps.sh/deploy.sh     --output "${LOCAL_SCRIPT}"

  echo "${EXPECTED_DEPLOY_SHA256}  ${LOCAL_SCRIPT}" | sha256sum -c -
  bash -n "${LOCAL_SCRIPT}"

  cp "${LOCAL_SCRIPT}" "/host${HOST_SCRIPT}"
  chmod 0700 "/host${HOST_SCRIPT}"

  echo "[temps-umbrel] Running official Temps installer on the Umbrel host..."
  # Installer output may contain generated credentials. Keep it in a root-only
  # file on the host instead of Docker/Umbrel logs.
  host_exec /bin/bash -lc "
    set -euo pipefail
    umask 077
    TERM=xterm bash '${HOST_SCRIPT}'       --mode local       --version '${TEMPS_VERSION}'       --email '${ADMIN_EMAIL}'       --yes       > /root/temps-install.log 2>&1
  "
else
  echo "[temps-umbrel] Existing native Temps installation detected; preserving it."
fi

echo "[temps-umbrel] Applying Umbrel-safe listener ports..."
mkdir -p /host/etc/systemd/system/temps.service.d
cat > /host/etc/systemd/system/temps.service.d/umbrel-ports.conf <<'EOF'
[Service]
Environment="TEMPS_ADDRESS=0.0.0.0:9080"
Environment="TEMPS_CONSOLE_ADDRESS=0.0.0.0:9081"
EOF

host_exec /bin/systemctl daemon-reload
host_exec /bin/systemctl enable temps.service >/dev/null 2>&1 || true
host_exec /bin/systemctl restart temps.service

echo "[temps-umbrel] Waiting for Temps..."
ready=0
i=0
while [ "$i" -lt 90 ]; do
  i=$((i + 1))

  # Preferred Umbrel console listener.
  if host_exec /usr/bin/curl -fsS --max-time 2 http://127.0.0.1:9081/health >/dev/null 2>&1      || host_exec /usr/bin/curl -fsS --max-time 2 http://127.0.0.1:9081/readyz >/dev/null 2>&1      || host_exec /usr/bin/curl -fsS --max-time 2 http://127.0.0.1:9081/ >/dev/null 2>&1; then
    ready=1
    break
  fi

  # Fallback for installer versions whose service CLI flags override env vars.
  if host_exec /usr/bin/curl -fsS --max-time 2 http://127.0.0.1:3000/health >/dev/null 2>&1      || host_exec /usr/bin/curl -fsS --max-time 2 http://127.0.0.1:3000/readyz >/dev/null 2>&1      || host_exec /usr/bin/curl -fsS --max-time 2 http://127.0.0.1:3000/ >/dev/null 2>&1; then
    echo "[temps-umbrel] Warning: Temps is reachable on its default port 3000; 9081 override was not applied."
    ready=1
    break
  fi

  sleep 2
done

if [ "$ready" -ne 1 ]; then
  echo "[temps-umbrel] Temps did not become reachable."
  echo "[temps-umbrel] Inspect on the host with:"
  echo "  sudo systemctl status temps --no-pager"
  echo "  sudo journalctl -u temps -n 100 --no-pager"
  echo "  sudo cat /root/temps-install.log"
  exit 1
fi

touch "${STATE_DIR}/host-install-complete"
chmod 600 "${STATE_DIR}/host-install-complete"

echo "[temps-umbrel] Native Temps installation is ready."
echo "[temps-umbrel] Intended app ingress:  http://HOST:9080"
echo "[temps-umbrel] Intended console:      http://HOST:9081"
echo "[temps-umbrel] Admin email:           ${ADMIN_EMAIL}"
echo "[temps-umbrel] Generated password remains only in /root/.temps/setup-result.json on the host."
