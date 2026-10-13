# Postmortem — Fel 1: backend försvann efter fel image-tagg

> Spår A, solo (Tobias-E-E). VM: `devops26a`, 195.148.30.48 (cPouta). Alla tider UTC
> (Discord visar lokal tid, UTC+3).

**Upplägg:** Genrepets Fel 1 (fel image-tagg). Solo: jag injicerade och felsökte
själv och kände alltså till felet, men gick hela vägen via larmet och verktygen.
**Påverkan:** Sidan laddade, men allt under `/api/` svarade `502 Bad Gateway` —
anteckningar gick varken att läsa eller spara. Varaktighet ≈ 1 min 50 s
(11:23:35 → 11:25:25).
**Upptäckt:** `AppDown` i Discord-kanalen 11:24:38 (Firing), 63 s efter injektionen.
Dessutom gick min egen regel `HealthCheckSlow` av (probe-latensen hoppade till 9,5 s
och sedan 3,1 s när nginx väntade på en backend som inte fanns).

**Tidslinje:**

| Tid (UTC) | Vad vi såg | Vad vi gjorde |
|---|---|---|
| 11:23:33 | — | Injektion: `sed` → `template-app-backend:v9.9.9`, `rm -sf backend`, `up -d` → `failed to resolve reference "ghcr.io/tobias-e-e/template-app-backend:v9.9.9": … not found` |
| 11:23:45 | `probe_http_status_code` = 0, `probe_duration_seconds` = 9,5 s | — |
| 11:23:58 | `AppDown` Pending (och `HealthCheckSlow` Pending 11:23:59) | — |
| 11:24:30 | `AppDown` Firing i Prometheus /alerts | — |
| 11:24:38 | Larmet landar i Discord | Skärmdump, börjar felsöka |
| 11:24:4x | Target health: `blackbox-http` UP; `probe_success` 0; status 502 | `sudo docker compose ps` i `/opt/app`: bara `app-frontend-1` — backend saknas |
| 11:24:5x | `grep image: docker-compose.yml` → `:v9.9.9` | Grundorsak hittad |
| 11:25:13 | — | `sed` tillbaka till `:latest`, `sudo docker compose up -d` → `app-backend-1 Started` |
| 11:25:15 | `curl` ger fortfarande 502 (uvicorn startar) | Väntar några sekunder |
| 11:25:26 | `probe_success` = 1, `{"status":"ok"}` på VM:en och utifrån | — |
| 11:25:38 | `AppDown` resolved i Discord | — |
| 11:26:38 | `HealthCheckSlow` resolved i Discord | Klart |

**Grundorsak:** `docker-compose.yml` i `/opt/app` pekade på en image-tagg som inte
finns i GHCR. `up -d` avbröts vid pullen innan någon container rördes, och eftersom
den gamla backend-containern redan var borttagen fanns ingen backend alls. nginx i
frontend kunde inte nå upstream `backend:8000` → 502 på allt under `/api/`.
**Åtgärd:** Taggen tillbaka till `:latest` och `sudo docker compose up -d`, som
skapade backend-containern på nytt från den befintliga imagen.
**Vad som gjorde felsökningen långsam:** Att `curl` direkt efter `up -d` fortfarande
gav 502 — jag trodde ett ögonblick att fixen var fel, men backend behövde några
sekunder att starta. Spåret "frontend är ju UP i Target health" kostar också tid om
man inte vet att `UP` bara betyder att exportern svarade.
**Förebyggande:** En CI-grind/`docker compose config`-kontroll som verifierar att
image-taggen finns innan den rullas ut; `pull` före `rm`. Ett larm på
`probe_http_status_code != 200` hade pekat rakt på 502 i stället för bara "down".
**Vad missade övervakningen?:** `AppDown` larmade 63 s efter injektionen — inom
specifikationen (15 s scrape + 30 s `for:` + 10 s `group_wait`). Den missade *vad*
som var fel: larmet säger bara att proben misslyckas; att backend-containern var
borta syntes först i `docker compose ps`. Min egen regel `HealthCheckSlow` gick av
på riktigt (nginx väntade 3–9 s på en upstream som inte fanns) — ett tecken på att
felet låg bakom nginx, inte i frontend. Fel 2 (503 bara på `/api/health`) fångades
av `AppDown` fast användarna inte märkte något; Fel 3 (backend på port 8001) såg ut
exakt som Fel 1 i larmet, och bara `docker compose config` avslöjade override-filen.
**Bevis (PromQL/panel):** Panelen "Health-check HTTP status (blackbox)" i den nya
dashboarden `observability/grafana/dashboards/spar-a-incident.json` med queryn
`probe_http_status_code{job="blackbox-http"}` — den visar 200 → 0 → 502 → 200 under
incidenten (0 = ingen anslutning alls medan nginx startade om upstream-försöken,
502 därefter) och skiljer därmed "backend borta" från "frontend borta" (bara 0).
Andra panelen lägger `probe_duration_seconds` bredvid antal `app-backend-1`-containrar
(cAdvisor), vilket visar latenstoppen exakt när backend saknades. Rådata i
`fel1-own-query.txt`.

## Skärmdumpar (placeholders — läggs in av Tobi efter testet)

- `[SCREENSHOT provlarm-discord.png]` — provlarmet `TestChannel` i Discord, 14:15:26 lokal tid.
- `[SCREENSHOT egenregel-firing.png]` — `HealthCheckSlow` som Firing på `http://localhost:9090/alerts` (sänkt tröskel, 14:18 lokal tid).
- `[SCREENSHOT fel1-discord.png]` — `AppDown` Firing i Discord 14:24:38 och resolved 14:25:38.
- `[SCREENSHOT fel1-panel.png]` — panelen ovan med tidsintervallet 11:20–11:30 UTC.
- `[SCREENSHOT fel2-discord.png]` — Firing 14:37:23 / resolved 14:38:23.
- `[SCREENSHOT fel3-discord.png]` — Firing 14:40:38 / resolved 14:41:38.

## Terminalutdrag (alla tre felen)

Före/efter för varje fel ligger som textfiler i den här katalogen:
`fel1-before.txt`, `fel1-inject.txt`, `fel1-alert-timeline.txt`, `fel1-restore.txt`,
samma för `fel2-*` (inkl. `fel2-diagnose.txt` — det ursprungliga kommandot med `-u root`
faller på `open() "/tmp/nginx.pid" failed (13: Permission denied)`, felet injicerades utan
`-u root`) och `fel3-*`. Återställningen slutar i alla tre med `{"status":"ok"}`.

## Frågor att besvara i inlämningen (en rad var — placeholders för testkörningen)

- **Tid fel → larm:** 46–63 s; styrs av `scrape_interval` 15 s, `for: 30s` och `group_wait: 10s`.
- **Vad mäter AppDown:** att blackbox-proben mot `/api/health` ger 2xx — appen kan fungera medan den larmar (Fel 2) och vara trasig utan larm (t.ex. bara `/api/items` trasig).
- **Varför UP när appen är nere:** Target health mäter att *exportern* svarade på scrapen, inte att proben lyckades.
- **Vem gör vad:** Prometheus utvärderar och äger status, Alertmanager grupperar/skickar, kanalen visar; letar först i Prometheus /alerts, sedan `logs alertmanager` (`Notify … failed`).
- **Egen regel:** `avg_over_time(probe_duration_seconds[1m]) > 0.5` i 1 min — gauge utan brus, `for: 0s` hade larmat på en enda långsam probe.
- **Varför tunnel:** varje öppen port är en attackyta; SSH-tunneln ger samma åtkomst krypterat utan nytt hål i security groupen.
- **Var ligger hemligheten:** i `alertmanager/.env` på VM:en (gitignorad), monterad som fil; aldrig i `alertmanager.yml` eftersom den är committad.
- **Lasttestet:** p95 38–81 ms över nätet, SLO:t höll; backend (FastAPI) tog mest CPU/minne av appens två.
- **rate() på probe_duration_seconds:** det är en gauge, `rate()` räknar ökningstakt för counters — Prometheus varnar "metric might not be a counter".
- **Annorlunda nästa gång:** vänta några sekunder efter `up -d` innan `curl`, och kör `docker compose config` tidigt.
- **Fel 2:** `restart` behåller containerns skrivbara lager (den ändrade `default.conf`); `--force-recreate` skapar en ny container från imagen.
- **Fel 3:** `docker compose config` visar den sammanslagna konfigurationen inklusive `docker-compose.override.yml`, som compose läser automatiskt.
