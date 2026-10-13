# Observability stack (reference, Spar A)

Prometheus + Grafana + node-exporter + cAdvisor + Alertmanager +
blackbox-exporter, wired up to monitor the template app defined in
`../docker-compose.yml`. This is the reference implementation for the
Spar A ("Drift & observability") track - see `kursplan.md` in the repo
root and the student lab guide in `course-material/labs/`.

## Design

This stack is a **separate** docker compose project. It does not edit or
depend on `../docker-compose.yml` - it reaches the app the same way an
external monitor would: over the host network, via
`host.docker.internal:8080/api/health` (through blackbox-exporter). That
keeps the app's compose file untouched and mirrors a realistic setup
where monitoring lives outside the thing it watches.

`host.docker.internal` resolves automatically on Docker Desktop
(macOS/Windows). On a plain Linux Docker Engine - which is what the real
cPouta VM runs - it does **not** resolve unless mapped explicitly. The
`extra_hosts: host.docker.internal:host-gateway` entry on the
`blackbox-exporter` service in `docker-compose.yml` is what makes it work
on Linux too (requires Docker Engine >= 20.10, which the course's
cloud-init installs - see TASK-6).

## Running it

```bash
# 1. Start the app first (from the repo root)
docker compose up -d --build

# 2. Start the observability stack next to it (from this directory)
cd observability
docker compose up -d
```

- Prometheus: http://localhost:9090 (Status -> Targets, Alerts)
- Alertmanager: http://localhost:9093
- Grafana: http://localhost:3000 (admin/admin, or anonymous Viewer access -
  see the security note on the `grafana` service in `docker-compose.yml`)
- cAdvisor UI: http://localhost:8081
- webhook-receiver logs: `docker compose logs -f webhook-receiver`

Tear down: `docker compose down` in both directories.

**Reaching these UIs on the real VM:** the security group from TASK-5 only
opens ports 22 (SSH) and 8080 (the app) - not 9090/3000/9093/etc. Don't
open more inbound ports for this; tunnel over SSH instead, e.g.
`ssh -L 9090:localhost:9090 -L 3000:localhost:3000 -L 9093:localhost:9093 <user>@<floating-ip>`,
then browse to `http://localhost:<port>` on your own machine. Full
walkthrough in the lab guide (`course-material/labs/spar-a-observability.md`).

## The alert

`prometheus/alert.rules.yml` defines one rule, `AppDown`: fires when the
blackbox probe against the app's `/api/health` endpoint fails for more
than 30s (covers both "frontend container stopped" and "backend down but
frontend still proxying to a 502"). Alertmanager routes it to
`webhook-receiver`, a minimal HTTP echo container that logs the alert
payload - a stand-in for a real destination. `alertmanager/alertmanager.yml`
has a commented `email_configs` template showing where real SMTP
credentials would go (never commit real credentials to this repo).

## Resource footprint

Every service has `mem_limit`/`cpus` set, sized for a cPouta
`standard.small` VM running alongside the two app containers:

| Service | mem_limit | cpus |
|---|---|---|
| prometheus | 256m | 0.3 |
| grafana | 256m | 0.3 |
| cadvisor | 128m | 0.2 |
| alertmanager | 64m | 0.1 |
| node-exporter | 64m | 0.1 |
| blackbox-exporter | 64m | 0.1 |
| webhook-receiver | 64m | 0.1 |

Worst case ~900 MB RAM and ~1.2 vCPU across the observability stack, on
top of the app's own two containers. Verified locally (Docker Desktop on
macOS); AC#1 (running within limits on the real VM) still needs
confirming there.

## Known caveat

cAdvisor's host-level metrics (rootfs, disk) are less accurate on Docker
Desktop for macOS than on a native Linux engine, because the bind mounts
it depends on (`/rootfs`, `/var/lib/docker`) don't map to a real Linux
filesystem there. Container-level metrics (CPU/memory per container) and
the rest of the stack are unaffected. The real cPouta VM is native Linux,
so this is a local-testing artifact only.
