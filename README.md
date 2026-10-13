# Template App — Från commit till produktion

Det här är startpunkten för ert projekt i DevOps-kursen. Appen är medvetet
enkel — en liten "notes"-app i två delar — så att kursen kan handla om
**processen** (version control, containers, testning, CI/CD, moln) snarare
än om att koda appen från grunden.

## Struktur

```
template-app/
├── backend/     FastAPI REST-API (Python)
│   ├── app/         applikationskod
│   └── tests/       pytest-tester
├── frontend/    Statisk HTML/JS, serverad av nginx
└── docker-compose.yml
```

`frontend` pratar med `backend` via `/api/...` — nginx proxar dessa anrop
vidare till backend-containern, så ni slipper CORS-krångel.

## Kom igång

Kräver Docker + Docker Compose.

```bash
docker compose up --build
```

Appen är nu tillgänglig på <http://localhost:8080>.

Kör backend-testerna:

```bash
docker compose run --rm backend pytest
```

Kör linting (ruff):

```bash
docker compose run --rm backend ruff check .
```

## CI: bygg + push av images till GHCR

Workflowen `.github/workflows/publish-images.yml` körs automatiskt vid varje
push till `main` (dvs. varje mergad pull request). Den bygger både
backend- och frontend-imagen och pushar dem till **GitHub Container
Registry** (GHCR), taggade både med commit-SHA:t och `latest`:

- `ghcr.io/<ägare>/template-app-backend:latest` och `:<sha>`
- `ghcr.io/<ägare>/template-app-frontend:latest` och `:<sha>`

`<sha>`-taggen ger er ett exakt, spårbart bevis på vilken commit som byggde
vilken image — bra att peka på i M6. `latest` pekar alltid på senaste
lyckade bygget från `main`.

### Paket-synlighet (visibility)

Första gången workflowen pushar en image skapas paketet i GHCR som
**privat** som standard. Det betyder att `docker pull` utan autentisering
kommer att svara `denied` — inklusive från en VM i molnet. Ni måste
själva göra paketet publikt: gå till paketets sida på GitHub (**Packages**
på repot eller er profil) → **Package settings** → **Change visibility** →
**Public**. Detta är exakt vad som krävs för att M8:s cloud-init-skript
ska kunna pulla imagen på VM:en utan inloggning — glöm inte bort steget,
annars fastnar ni på ett `denied` som ser ut som ett nätverks- eller
behörighetsfel men faktiskt bara är fel synlighet på paketet.

### Secrets-hygien (M6)

Workflowen loggar in i GHCR med det **inbyggda `GITHUB_TOKEN`** — inte en
Personal Access Token (PAT) sparad som secret. Några saker värda att lyfta:

- **`GITHUB_TOKEN` skapas automatiskt av GitHub för varje workflow-körning
  och förstörs när den är klar.** Ingen risk att den läcker efter jobbet,
  och ingen människa behöver skapa, rotera eller lagra den — till skillnad
  från en PAT som ligger som secret tills någon kommer ihåg att byta ut den.
- **Rättigheterna är minimala och explicita.** `permissions`-blocket i
  workflowen ger tokenen exakt `contents: read` (för att kunna checka ut
  koden) och `packages: write` (för att kunna pusha images) — inget annat.
  Även om ett steg i workflowen skulle vara skadligt eller ha en bugg kan
  tokenen inte röra issues, pull requests eller andra repon.
- **Inga hemligheter checkas in i repot.** Allt som behövs för att logga in
  i GHCR kommer från GitHub Actions körmiljö (`github.actor`,
  `secrets.GITHUB_TOKEN`) — det finns inget lösenord eller nyckel att av
  misstag committa.
## CI: lint + test på varje pull request

Workflowen `.github/workflows/ci.yml` kör automatiskt `ruff check .` och
`pytest` på backend vid varje pull request mot `main`. Den syns som en
check-status ("Lint and test backend") längst ner i pull requesten på
GitHub.

Så länge checken inte är obligatorisk kan en pull request mergas trots att
den är röd. För att låta en röd pipeline **blockera** merge (M5), aktivera
branch protection på `main`:

1. Gå till repot på GitHub → **Settings** → **Branches**.
2. Under **Branch protection rules**, klicka **Add rule** (eller redigera
   regeln för `main`).
3. Ange `main` som branch name pattern.
4. Kryssa i **Require status checks to pass before merging**.
5. Sök upp och kryssa i checken **Lint and test backend** — det är exakt
   namnet på jobbet i `ci.yml` (`jobs.lint-and-test.name`).
6. Spara reglerna.

Testa att det fungerar: skapa en pull request med ett medvetet fel (t.ex. en
`ruff`-varning eller en trasig test). Pipelinen ska bli röd, och GitHub ska
visa att pull requesten inte kan mergas förrän checken är grön.
## Utvecklingsmiljö (devcontainer / Codespaces)

Repot har en färdig **devcontainer** (`.devcontainer/`) med hela kursverktygslådan
förinstallerad: `terraform`, `kubectl`, `oc`, `flux`, `k6`, `ssh` samt Docker
(via docker-in-docker). Den fungerar identiskt oavsett var du kör den:

- **Lokalt i VS Code:** installera tillägget "Dev Containers", öppna repot.
  En notis (toast) dyker då upp automatiskt nere till höger — klicka
  "Reopen in Container". Missar du notisen: öppna Command Palette
  (Cmd+Shift+P på mac, Ctrl+Shift+P på Windows/Linux) och skriv
  "Dev Containers: Reopen in Container". Samma meny nås även via den
  gröna/blå knappen längst ner till vänster i statusfältet (><-symbolen).
- **GitHub Codespaces (bara webbläsare):** öppna repot på GitHub → **Code**
  → **Codespaces** → **Create codespace on main**. Fungerar på skolans låsta
  datorer utan adminrättigheter — inget behöver installeras lokalt.

Verktygen finns på PATH direkt i terminalen inne i containern, t.ex.
`terraform -version`, `kubectl version --client`, `oc version`.
## Cloud-init: automatisk appstart på VM (M7–M8)

`iac/cloud-init/user-data.yaml.tpl` är cloud-init-konfigurationen som gör
att en helt ny cPouta-VM går från "startad" till "appen svarar" utan att
någon loggar in via SSH. Den körs automatiskt av cloud-init vid VM:ens
första uppstart och gör tre saker:

1. Installerar Docker Engine + compose-plugin.
2. Skriver en `docker-compose.yml` som pekar på de färdigbyggda GHCR-
   images:erna (samma images som CI-workflowen ovan publicerar).
3. Hämtar images:erna och startar stacken med `restart: unless-stopped`,
   så den kommer tillbaka av sig själv efter en ombootning.

Filen har `.tpl`-ändelse eftersom den är en Terraform-mall: variabeln
`${ghcr_owner}` sätts in av terraform-modulen (M8) via `templatefile()`
när den skickas som `user_data` till VM:en — se filens egna kommentarer
för hur ni kan rendera och testa den lokalt utan Terraform.

## CD: automatisk deploy till VM (M9)

`.github/workflows/deploy.yml` är M9:s referens-workflow: när workflowen
"Publish images" (M6) har byggt och pushat nya images till GHCR vid en
push till main, loggar denna workflow in på cPouta-VM:en via SSH och kör
`docker compose pull && up -d` mot `/opt/app/docker-compose.yml` — samma
fil som cloud-init (M8, se ovan) skrev vid VM:ens första uppstart.

### Ordningsproblemet: workflow_run i stället för push

Om detta workflow triggades direkt på `push: branches: [main]` skulle det
köra parallellt med "Publish images" — och kunna hinna SSH:a in och köra
`pull` INNAN den nya imagen ens finns i GHCR. Workflowen triggas därför
istället av `workflow_run` på att "Publish images" är **completed**, och
kör bara vidare om den lyckades (`conclusion == 'success'`). Det
garanterar rätt ordning utan att gissa på hur lång tid bygget tar.

### Säkerhet

- **Dedikerad deploy-nyckel:** ett eget SSH-nyckelpar, bara för denna
  workflow, sparat som `secrets.DEPLOY_SSH_KEY` (privat del) i GitHub
  Secrets — inte samma nyckel som Terraform injicerar för admin-åtkomst
  (`ssh_public_key_path`, användaren `ubuntu`, se `iac/terraform/`).
- **Host key-verifiering:** `known_hosts` pinnas i förväg (kör
  `ssh-keyscan -H <floating-ip>` en gång och klistra in resultatet som
  repo-variabeln `DEPLOY_KNOWN_HOSTS`) och skrivs till
  `~/.ssh/known_hosts` innan `ssh` körs med `StrictHostKeyChecking=yes`.
  **Aldrig** `StrictHostKeyChecking=no` — det stänger av
  server-autentiseringen helt och accepterar tyst vilken host som helst.
- **Least-privilege deploy-user:** deployen körs som en egen användare
  (t.ex. `deploy`) som bara är medlem i `docker`-gruppen — inte som
  `root` eller VM:ens admin-användare. Sätt upp den manuellt en gång på
  VM:en: `useradd -m deploy && usermod -aG docker deploy`, och lägg
  `DEPLOY_SSH_KEY`:s publika del i `/home/deploy/.ssh/authorized_keys`.

  **Ärlig brasklapp:** medlemskap i `docker`-gruppen är i praktiken
  root-ekvivalent — en användare som kan prata med Docker-daemonen kan
  starta en container med t.ex. `-v /:/host` och därifrån göra vad den
  vill på värden. "Least privilege" här begränsar alltså vad som krävs
  för att nå den nivån (ingen sudo, inget lösenord, bara den här ena
  SSH-nyckeln) — inte vad ett läckt nyckelinnehav faktiskt ger tillgång
  till. En medveten avvägning för en enkel referens-pipeline, inte något
  att kopiera rakt av till en miljö med känsliga data.

### Secrets & variabler som krävs

| Namn | Typ | Innehåll |
|---|---|---|
| `DEPLOY_SSH_KEY` | Secret | Privat del av deploy-nyckelparet |
| `DEPLOY_USER` | Variable | Deploy-användarens namn på VM:en (t.ex. `deploy`) |
| `DEPLOY_HOST` | Variable | VM:ens floating IP eller nip.io-adress |
| `DEPLOY_KNOWN_HOSTS` | Variable | Output av `ssh-keyscan -H <host>`, pinnat i förväg |

De sätts på **repo-nivå** (Settings → Secrets and variables → Actions), för
M9 har bara en miljö. Spår C flyttar dem till **GitHub Environments** (`dev`
och `prod`) — se Spår C-avsnittet längre ner. Poängen med det: en nyckel som
når prod blir aldrig läsbar för ett jobb som bara deployar till dev.

### Vilka är svagheterna här? (diskussion, session 9)

Detta är MEDVETET en enkel — och bristfällig — deploy-modell. Punkter att
ta upp i diskussionen:

- **Push, inte pull.** CI:n har SSH-nycklar till produktionsmiljön och
  initierar ändringen själv. Jämför med GitOps (spår B): en agent i
  klustret (Flux) *drar* ändringar från ett Git-repo — CI:n behöver
  aldrig ha inloggningsuppgifter till produktionen.
- **Secrets sprawl.** Fyra hemligheter/variabler att hantera och rotera
  (`DEPLOY_SSH_KEY` i synnerhet) — var och en är en attackyta.
- **Snowflake-VM.** Deploy-användaren och dess `authorized_keys` (ovan)
  sattes upp manuellt på just den här VM:en — det finns ingen rad kod
  någonstans som återskapar dem. VM:ens verkliga tillstånd driver isär
  från vad repot säger, och ingen annan än den som körde kommandona vet
  exakt vad som gjordes.
- **Ingen historik/rollback.** `docker compose pull && up -d` skriver
  över det som kördes innan — det finns ingen inbyggd "vad kördes förra
  gången, och hur går jag tillbaka dit" (jämför `kubectl rollout undo`
  eller Git-historiken i ett GitOps-flöde).
- **Vad händer om VM:en byggs om?** Terraform (M8) återskapar VM:en och
  floating-IP:n, men INTE deploy-användaren eller dess
  `authorized_keys` — de sattes upp manuellt, utanför IaC:n (se
  snowflake-punkten ovan). En ombyggd VM kräver alltså manuell
  efterjustering innan denna workflow fungerar igen.

Dessa svagheter är precis vad som motiverar Spår B (GitOps/Kubernetes) —
se `kursplan.md`.
**Kom ihåg paket-synligheten:** pull:en i steg 2 är oautentiserad, så om
era GHCR-images fortfarande är privata (standard) misslyckas den tyst vid
första uppstarten — se avsnittet "Paket-synlighet" för hur ni gör
paketen publika.

## Spår C — DevSecOps: säkerhetsgrindar och två miljöer

> "Pipelinen släpper bara igenom det som är säkert och testat."

Referensimplementationen för Spår C ligger till största delen i
`course-material/templates/spar-c/` och kopieras in i det här repot när ni
väljer spåret — säkerhetsgrindar sitter per definition *i* pipelinen och inte
i en egen mapp, så de blir filer i `.github/`. Det som redan finns här är det
som inte kör något av sig självt: demo-imagen och resonemangen. Här är
kartan:

| Var | Vad |
|---|---|
| `course-material/templates/spar-c/.github/workflows/security.yml` | Trivy skannar båda images på varje PR — HIGH/CRITICAL fäller bygget — kopieras in i `.github/workflows/` |
| `course-material/templates/spar-c/.github/workflows/codeql.yml` | CodeQL analyserar er egen kod (Python + JS) — kopieras in i `.github/workflows/` |
| `course-material/templates/spar-c/.github/dependabot.yml` | Dependabot bevakar pip, base images och actions — kopieras in som `.github/dependabot.yml` |
| `.trivyignore.yaml` | Mekanismen för undantag — och reglerna för när ett undantag är legitimt |
| `course-material/templates/spar-c/.github/` | Kedjan: scan → dev → integrationstest → prod (med godkännande) — kopieras in över M9:s `deploy.yml` |
| `tests/integration/` | Svartlådetester mot den *deployade* appen |
| `course-material/templates/spar-c/iac/terraform/` | Terraform för två miljöer: `environment`-variabeln, workspace-skyddet och dev/prod-värdena — kopieras in i `iac/terraform/` (M8-modulen här bygger en miljö) |
| `security/README.md` | **Resonemanget** bakom varje grind — läs den här först |

Studentlabben steg för steg finns i
`course-material/labs/spar-c-devsecops.md`.

### Grindarna före merge

Under M1–M9 kör det här repot **en** check på varje PR: `Lint and test
backend` från `ci.yml`. Spår C lägger till två till, `security.yml` och
`codeql.yml`, plus Dependabot vid sidan av. De är nya filer och ersätter
ingenting — se copy-tabellen i `course-material/templates/spar-c/README.md`.

Räkna med att första körningen blir röd. Fynden har funnits i repot hela
tiden; det nya är att någon skannar efter dem. Ordningen för att åtgärda dem
— patcha → ignorera med utgångsdatum → acceptera — står i
`security/README.md`.

### Kedjan i Spår C:s deploy.yml

Det här repots `.github/workflows/deploy.yml` är M9-versionen: ett jobb,
ingen grind. Spår C ersätter den med referenspipelinen i
`course-material/templates/spar-c/.github/workflows/deploy.yml` (plus
composite-actionen `ssh-deploy` som hör till) — se den mappens README för
vart varje fil kopieras.

```
scan-images  →  deploy-dev  →  integration-test  →  deploy-prod
 (Trivy mot            (env: dev,      (HTTP mot den      (env: prod,
  publicerade           inget           körande            MÄNSKLIGT
  images)               godkännande)    dev-appen)         GODKÄNNANDE)
```

Ingenting når prod som inte klarat alla tre grindarna före. Allt är låst
till commitens SHA, inte `:latest` — det ni skannade, det ni testade på dev
och det ni godkänner för prod är bevisligen samma image.

### GitHub Environments (görs i webbgränssnittet)

**Settings → Environments** → skapa `dev` och `prod`. För varje miljö sätts
`DEPLOY_USER`, `DEPLOY_HOST`, `DEPLOY_KNOWN_HOSTS` och `APP_URL` som
*variables*, och `DEPLOY_SSH_KEY` som *secret* — olika värden per miljö,
eftersom det är två olika maskiner.

Skillnaden mellan miljöerna:

- **`dev`:** inga skyddsregler. Med flit — dev finns för att gå sönder
  snabbt.
- **`prod`:** kryssa i **Required reviewers** och lägg till er själva (i par:
  varandra). Det är detta enda kryss som gör att `deploy-prod` pausar och
  väntar på att en människa klickar *Approve* i Actions-vyn.

Sätt också **Deployment branches** till `main` för `prod`, så att ingen
feature-branch kan deploya dit ens av misstag.

*Varför godkännandet sitter före prod och inte före dev* — se
`security/README.md`. Kort version: en människa som klickar "approve"
tjugo gånger i veckan läser inte den tjugoförsta heller.

### Slutdemon: visa att en sårbar dependency stoppas

Hela poängen med spåret, och den går att köra lokalt utan moln:

```bash
docker build -t template-app-backend:vulnerable \
  -f security/vulnerable-demo/Dockerfile backend

docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:0.58.1 image --scanners vuln --ignore-unfixed \
  --severity HIGH,CRITICAL --exit-code 1 template-app-backend:vulnerable
echo $?    # 1 — och en nollskild exitkod är precis vad som fäller ett CI-jobb
```

## Milstolpe-checklista (M1–M9)

Varje milstolpe avslutas med en git tag i ert repo, t.ex. `git tag m3-container`.
Det är ert "bevis" på att milstolpen är klar.

**Bevisregeln:** en hel del milstolpe-arbete syns inte i repot (inställningar
på GitHub, konsolklick i molnet, lokala körningar). Därför följs varje tagg av
en kort fil i `inlamning/` (t.ex. `inlamning/m7-cloud.md`) — se
`inlamning/m0-exempel.md` för formatet. Filens ändelse är fri (`.md`, `.txt`,
Word eller vad ni är bekväma med) — det är namnet `mN-<kort-namn>` som gör
den hittbar.

- [ ] **M1 — Repo:** skapa repo från denna template, första commit. Tagg: `m1-repo`
- [ ] **M2 — Review:** arbetsflöde med branch protection, mergad PR med review. Tagg: `m2-review`
- [ ] **M3 — Container:** Dockerfiles för frontend + backend, kör helheten lokalt med `docker compose`, push till GHCR. Tagg: `m3-container`
- [ ] **M4 — Tester:** utökad testsvit, grön körning, hittad bugg via test. Tagg: `m4-tests`
- [ ] **M5 — CI del 1:** Actions-workflow kör lint + test på varje PR. Tagg: `m5-ci`
- [ ] **M6 — CI del 2:** CI bygger + pushar båda images automatiskt vid commit på main. Tagg: `m6-cd-images`
- [ ] **M7 — Molnet manuellt:** VM i cPouta, security groups, SSH, Docker — appen svarar på floating-IP/nip.io-URL. Tagg: `m7-cloud`
- [ ] **M8 — Infrastructure as Code:** Terraform återskapar M7 från noll. Tagg: `m8-iac`
- [ ] **M9 — CD:** merge till main deployar automatiskt via Actions. Tagg: `m9-cd`

Se `kursplan.md` (i kursrepot) för fullständig beskrivning av varje milstolpe.
