# Temps for Umbrel — native host installer

This Community App Store package deliberately **does not repackage Temps into an
Umbrel container**. The Umbrel app acts as a bootstrapper and UI bridge:

1. A privileged one-shot container downloads the official `https://temps.sh/deploy.sh`.
2. It verifies the installer against the reviewed SHA-256 pinned by the upstream
   Temps platform-setup documentation.
3. It runs the official installer in the Umbrel host namespaces in `local` mode.
4. Temps runs natively under `temps.service` (systemd), exactly as the upstream
   installer expects.
5. A systemd drop-in requests Umbrel-safe ports:
   - `9080` — Temps HTTP/application ingress
   - `9081` — Temps console
6. A tiny nginx bridge lets Umbrel's `app_proxy` open the native console from the
   Umbrel home screen.

## Pinned upstream inputs

- Temps installer SHA-256:
  `49ecd9ce4ee0d4302ae8f11cadbdaa376135800e8f59690ae79c513af762de33`
- Temps release:
  `v0.1.0-nightly.20260930.53d4fb40`
- Admin email:
  `admin@temps.local`

The package intentionally pins these values. If upstream changes `deploy.sh`, the
install fails rather than executing an unreviewed replacement.

## Install / update this repo

Copy the repository contents to your existing GitHub Community App Store repo, then:

```bash
git add .
git commit -m "Use official native Temps host installer"
git push
```

Refresh the Community App Store in Umbrel and install/update **Temps**.

## First login password

The official installer generates the password. It is intentionally **not copied into
Docker logs or the Git repository**.

On the Umbrel host:

```bash
sudo jq -r '.admin_password // .password // .credentials.admin_password // empty'   /root/.temps/setup-result.json
```

If that prints nothing, inspect only the available field names:

```bash
sudo jq 'keys' /root/.temps/setup-result.json
```

Then read the appropriate password field locally on the server.

## Ports

| Port | Purpose |
|---|---|
| `9080/tcp` | Temps HTTP / deployed-app ingress requested by this wrapper |
| `9081/tcp` | Temps console requested by this wrapper |
| `16432/tcp` | Upstream installer TimescaleDB port (normally loopback-only) |
| `39291/tcp` | Umbrel app-proxy entry shown in the app manifest |

Umbrel keeps ownership of its normal `80/443` listeners.

For Cloudflare Tunnel later, route the wildcard application hostname to the Temps
HTTP ingress (normally `http://127.0.0.1:9080` when cloudflared runs on the host).
If cloudflared itself is a container, target the Umbrel host address instead of the
container's own `127.0.0.1`.

## Diagnostics

```bash
sudo systemctl status temps --no-pager
sudo journalctl -u temps -n 100 --no-pager
sudo ss -ltnp | grep -E ':9080|:9081|:3000|:16432'
```

The raw installer transcript is kept root-only at:

```text
/root/temps-install.log
```

It can contain generated credentials, so do not paste it publicly without redacting
secrets.

## Important uninstall behavior

Removing the Umbrel app **does not uninstall the native Temps service or delete its
data**. This is intentional: an Umbrel UI uninstall should not silently destroy
deployment data, databases, keys, or projects.

If you ever want to remove native Temps too, do that separately after backing up and
reviewing the current upstream uninstall procedure.

## Security note

The one-shot installer container is `privileged`, joins the host PID namespace, and
mounts `/` read-write because it must run the upstream installer and manage systemd.
Treat this package as root-equivalent. The long-running nginx bridge itself is not
privileged.
