#cloud-config
# ----------------------------------------------------------------------------
# cloud-init user_data för M8 (DevOps-kursen)
#
# Detta är en Terraform-mall (.tpl) — terraform-modulen i TASK-5 renderar
# den med funktionen `templatefile()` och sätter in variabeln
# ${ghcr_owner} (namnet på GHCR-organisationen/användaren, samma
# namngivningsschema som i .github/workflows/publish-images.yml — se
# README-avsnittet "CI: bygg + push av images till GHCR").
#
# Filen körs av cloud-init vid FÖRSTA uppstarten av en ny cPouta-VM och gör
# tre saker helt utan SSH-inloggning ("zero SSH intervention"):
#   1. Installerar Docker Engine + compose-plugin.
#   2. Skriver en docker-compose.yml som pekar på de färdigbyggda GHCR-
#      images:erna (samma images som CI:n (M6) publicerar).
#   3. Hämtar och startar stacken med en restart-policy som gör att den
#      kommer tillbaka av sig själv efter en ombootning.
#
# Testa lokalt utan Terraform (ingen cloud-anrop krävs):
#   sed 's/\${ghcr_owner}/test-owner/' iac/cloud-init/user-data.yaml.tpl \
#     > /tmp/user-data.yaml
#   docker run --rm -v /tmp/user-data.yaml:/ci/user-data.yaml ubuntu:24.04 \
#     bash -c "apt-get update -qq && apt-get install -y -qq cloud-init && \
#              cloud-init schema --config-file /ci/user-data.yaml"
# ----------------------------------------------------------------------------

# Uppdatera apt-paketlistan innan vi installerar något (utan att göra en
# fullständig dist-upgrade, som skulle sakta ner uppstarten i onödan).
package_update: true
package_upgrade: false

write_files:
  # docker-compose.yml för appen — kopplar CI:ns GHCR-images till en
  # körande två-tjänstersstack. Backend exponeras INTE mot internet; bara
  # frontend pratar med den, via Dockers interna nätverk och tjänstenamnet
  # "backend" (samma mönster som frontend/nginx.conf och docker-compose.yml
  # i repotroten använder för lokal utveckling).
  - path: /opt/app/docker-compose.yml
    owner: root:root
    permissions: '0644'
    content: |
      services:
        backend:
          image: ghcr.io/${ghcr_owner}/template-app-backend:latest
          restart: unless-stopped

        frontend:
          image: ghcr.io/${ghcr_owner}/template-app-frontend:latest
          # unless-stopped: vid en ombootning kan frontend hinna starta
          # innan backend-tjänstenamnet går att slå upp och krascha en
          # eller ett par gånger — den här policyn startar om den tills
          # DNS:et finns, helt automatiskt.
          restart: unless-stopped
          ports:
            - "8080:8080"
          depends_on:
            - backend

runcmd:
  # 1) Docker Engine + compose-plugin. Det officiella "convenience script"
  #    installerar docker-ce, docker-ce-cli, containerd, buildx OCH
  #    compose-plugin i ett svep — ingen manuell apt-repo-konfiguration
  #    behövs. (Medvetet val: skriptet är inte versionslåst, se README.)
  - curl -fsSL https://get.docker.com | sh

  # 2) Docker-daemonen ska starta automatiskt vid varje boot. get.docker.com
  #    gör redan detta på Ubuntu/Debian, men vi är explicita här — det
  #    kostar inget och gör filen självdokumenterande.
  - systemctl enable --now docker

  # 3) Hämta images:erna explicit (så att "up -d" inte behöver hämta dem
  #    synkront första gången) och starta stacken. "restart: unless-stopped"
  #    i docker-compose.yml ovan gör sedan att containrarna kommer tillbaka
  #    av sig själva vid en ombootning — utan att cloud-init eller SSH
  #    behöver köras igen.
  #
  #    VIKTIGT: den här pull:en är OAUTENTISERAD. GHCR-paket är PRIVATA som
  #    standard, så om ni inte har gjort era images publika (paketets sida
  #    på GitHub → Package settings → Change visibility → Public, se
  #    README-avsnittet "Paket-synlighet") svarar GHCR `denied` här och
  #    stacken kommer aldrig upp — helt tyst, utan SSH-inloggning ser ni
  #    inte felet förrän ni loggar in och kollar `docker compose logs`.
  #    Att logga in VM:en mot GHCR (docker login med ett PAT, satt upp via
  #    cloud-init) är möjligt men medvetet utanför scope för kursens
  #    baseline med publika images.
  - docker compose -f /opt/app/docker-compose.yml pull
  - docker compose -f /opt/app/docker-compose.yml up -d
