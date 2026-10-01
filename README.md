# Temps for Umbrel — Community App Store

Unofficial Umbrel Community App Store package for [Temps](https://temps.sh/).

## What this package does

- Opens the Temps dashboard from the Umbrel home screen.
- Keeps Umbrel's host ports 80/443 untouched.
- Exposes Temps' deployed-app HTTP ingress on **port 9080**.
- Exposes the Temps control plane on **port 9081** for Git-provider webhooks and optional external access.
- Persists PostgreSQL, ClickHouse and Temps data under Umbrel's app data directory.
- Gives Temps access to `/var/run/docker.sock` so it can build/run deployments.
- Uses the Umbrel-generated app password as the initial Temps admin password.

## Login

- Username: `admin@umbrel.local`
- Password: the deterministic app password shown by Umbrel for Temps.

## Install through Community App Stores

1. Put the contents of this ZIP in a GitHub repository. The repository root must
   contain `umbrel-app-store.yml` and the `temps-community-temps/` directory.
2. In Umbrel, open **App Store → Community App Stores** and add the GitHub
   repository URL.
3. Refresh the store and install **Temps** from the **Temps Community App Store**.
4. Open Temps from the Umbrel home screen and sign in.

## GitHub commands

```bash
git init
git add .
git commit -m "Add Temps Umbrel app"
git branch -M main
git remote add origin https://github.com/YOUR-USER/umbrel-temps-store.git
git push -u origin main
```

Then add this URL in Umbrel:

```text
https://github.com/YOUR-USER/umbrel-temps-store
```

## Deployed applications

Temps listens for deployed application HTTP traffic on:

```text
http://UMBREL-IP:9080
```

Routing is Host-header based, so normally you should put a reverse proxy or
Cloudflare Tunnel in front of port 9080 and send your app/preview domains to it.
The Temps control plane is also available at `http://UMBREL-IP:9081`; expose that
through a separate hostname if your Git provider needs to deliver webhooks. The
package intentionally does not bind 80 or 443 because Umbrel already uses those
ports.

### Cloudflare Tunnel idea

After Temps itself is working, configure a wildcard hostname such as
`*.apps.example.com` in your Cloudflare setup and forward it to the Umbrel host
on port `9080`. Also route a control-plane hostname such as `temps.example.com`
to port `9081` for Git-provider callbacks/webhooks. Preserve the original Host
header so Temps can select the correct project/environment.

## Important security note

Temps must control Docker to build and launch deployments. This package mounts
`/var/run/docker.sock` into Temps. Docker socket access is effectively root-level
control of the Umbrel host. Only install this package if you trust Temps and the
images/code you deploy through it.

## Updating

The compose file currently uses:

```text
ghcr.io/gotempsh/temps:latest
```

Restarting after a pull can therefore move to a newer Temps build. For a more
conservative setup, replace `latest` with a specific Temps release tag before
publishing your Community App Store repository.

## Troubleshooting

Check the app containers:

```bash
sudo docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep temps-community-temps
```

Temps logs:

```bash
sudo docker logs -f temps-community-temps_server_1
```

PostgreSQL logs:

```bash
sudo docker logs -f temps-community-temps_postgres_1
```

ClickHouse logs:

```bash
sudo docker logs -f temps-community-temps_clickhouse_1
```

If ports `9080` or `9081` are already occupied, change the host side of these lines in
`temps-community-temps/docker-compose.yml`:

```yaml
ports:
  - "9080:3000"
  - "9081:9000"
```

For example `9180:3000` and `9181:9000`.

## Status

This is an unofficial community package adapted from Temps' current Docker
architecture. It has been syntax-checked, but it has not been run on your
specific Umbrel installation yet. Temps is under active development, so upstream
changes can require updates to this package.

## Umbrel.2 database startup fix

This revision adds a one-shot permissions initializer for the TimescaleDB data
bind mount (`1000:1000`) and the upstream-style PostgreSQL socket/password sync.
It also removes the obsolete top-level Compose `version` field.

If an older failed install left the database directory behind, this revision
repairs its ownership automatically before PostgreSQL starts.
