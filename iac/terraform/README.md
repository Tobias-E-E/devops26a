# Terraform-modul för cPouta (M8 — Infrastructure as Code)

Den här modulen återskapar M7 (VM:en ni byggde manuellt i Pouta-UI:t) som
kod: en VM, en security group (SSH + app-porten), en nätverksport, en
floating IP, och cloud-init som installerar Docker och startar appen —
helt utan SSH-inloggning. Se `../cloud-init/user-data.yaml.tpl` för själva
cloud-init-filen (TASK-6) och kursplanens session 8 för sammanhanget.

## 1. clouds.yaml — autentisering mot cPouta

Terraform pratar med OpenStack via `clouds.yaml`, inte via variabler i
denna modul (så att ingen råkar committa credentials i `.tf`-filer).

Autentiseringen sker med en **application credential** — en separat nyckel
för maskinen, inte ditt CSC-lösenord. Den har ett utgångsdatum, går att
återkalla direkt och kan begränsas till en enda roll.

1. Logga in i cPouta Horizon-webbgränssnittet (<https://pouta.csc.fi>).
2. Gå till **Identity → Application Credentials** (i vänstermenyn) och
   klicka på **"Create Application Credential"**.
3. Fyll i dialogen:
   - **Name**: en egen etikett, t.ex. `devops-m8`.
   - **Secret**: lämna tomt — hemligheten genereras och visas **en enda
     gång** efter att du klickat Create.
   - **Expiration Date**: ett datum efter kursens slut, t.ex.
     `08.11.2026`. Utgången räknas i UTC och ett datum utan klockslag
     betyder `00:00:00` — sätt den alltså med marginal.
   - **Roles**: kryssa i **member** explicit — det räcker för allt den
     här modulen gör. Utan val får credentialen alla dina roller.
   - **Access Rules**: tomt. **Unrestricted (dangerous)**: okryssat.
4. I dialogen "Your application credential" som visas efteråt: klicka
   **"Download clouds.yaml"** (hemligheten är redan ifylld i filen).
5. Lägg filen på **`~/.config/openstack/clouds.yaml`** — i din
   **hemkatalog**, även när du kör i devcontainern/codespacen (där är `~`
   = `/home/vscode`, inte repot). Terraform och OpenStack-CLI:t letar
   automatiskt där; en `.config/`-mapp i repot hittas aldrig.
   **Committa aldrig filen till git** — secreten ger åtkomst till hela
   projektet. Tappad secret går inte att läsa ut igen: skapa då en ny
   application credential.
6. Sätt cloud-namnet — nyckeln under `clouds:` i den nedladdade filen,
   som för application credentials heter `openstack` — som miljövariabel
   innan du kör Terraform:

   ```bash
   export OS_CLOUD=openstack   # nyckeln under clouds: i din clouds.yaml
   ```

   Providern i `versions.tf` är medvetet tom (`provider "openstack" {}`) —
   den läser `OS_CLOUD` från miljön, precis som `openstack`-CLI:t gör.

`openstack`-CLI:t (python-openstackclient) finns förinstallerat i
devcontainern. Kör ni lokalt utan devcontainer: `pip install
python-openstackclient`. Ingen lust att installera något alls? Horizon
(webbgränssnittet) visar samma information — se avsnitt 2 nedan för var,
med en reservation om att exakta menytexter kan skilja sig åt.

## 2. Egna variabler

```bash
cp terraform.tfvars.example terraform.tfvars
# redigera terraform.tfvars: sätt network_name, ghcr_owner och
# instance_name
```

`network_name` hittar ni med `openstack network list` (er projektinterna
nätverk, inte "public"). Utan CLI:t: samma namn syns i Horizon, ungefär
under **Project → Network → Networks** (exakt menytext kan skilja sig
mot vad ni ser — leta efter vyn som listar era nätverk). `ghcr_owner`
är samma namn som `.github/workflows/publish-images.yml` publicerar
images under.

**`instance_name`:** sätt ett eget värde per person, t.ex.
`m8-<förnamn>`. Alla resursnamn i modulen byggs av det — VM, security
group, port, keypair — så ni ser i Horizon vad som är ert, bredvid det ni
byggde för hand i M7. Med default `instance_name = "template-app"` heter
allas resurser exakt likadant i samma projekt: OpenStack namespacear dem
per PROJEKT, inte per Terraform-state, och tillåter dubbletter av samma
namn. Ingen får då något felmeddelande (Terraform refererar resurserna
via id, inte via namn) — men det blir omöjligt att se vems VM som är
vems, och lätt att riva fel security group för hand i Horizon. Det
händer så snart två personer kör `apply` i samma projekt, t.ex. båda i
paret i parets eget CSC-projekt.

## 3. Kör det

```bash
terraform init
terraform plan
terraform apply
```

Efter apply, se output `app_url` (eller `app_url_nip_io`) — appen svarar
där så fort cloud-init hunnit köra klart (någon minut).

## 4. AC#2 — riv & återuppbygg VM:en, IP:n återanvänds

Den här modulen allokerar floating IP:n som en **egen resurs**
(`openstack_networking_floatingip_v2.this`), separat från VM:en. Den
kopplas inte till VM:en direkt utan till VM:ens **nätverksport**
(`openstack_networking_port_v2.this`), som också är en egen resurs — det
är så Neutron modellerar en floating IP: adress → port, inte adress →
server. VM:en bara *lånar* porten.

Därför är det bara VM:en som behöver rivas:

```bash
terraform destroy -target=openstack_compute_instance_v2.this

terraform apply
```

Porten, kopplingen och floating IP:n rörs aldrig. När `apply` bygger en
ny VM fäster den vid samma port som förut — så `floating_ip`-outputen
visar samma publika adress som innan, och VM:en får till och med tillbaka
samma interna IP. Det är hela poängen med M8: servern är utbytbar,
nätverksidentiteten ligger kvar i infrastrukturkoden.

**Viktigt om vanlig `terraform destroy` (utan `-target`):** floating-IP-
resursen har `lifecycle { prevent_destroy = true }` i `main.tf`. Det är
medvetet — det är själva mekanismen som garanterar att adressen
överlever, eftersom cPouta har begränsad kvot på floating IPs och en
tappad adress annars måste tilldelas på nytt (och kan bli en annan). Om ni
kör ett vanligt `terraform destroy` (t.ex. i CI eller av misstag) stoppar
Terraform redan vid **plan**-steget med ett fel på floating-IP-resursen —
**INGENTING rivs**, varken VM, security group, keypair eller
association. Det är förväntat, inte trasigt: kommandot avbryts helt
innan det rör någon resurs alls. Använd `-target`-kommandot ovan om ni
bara vill riva om VM:en.

## 5. Riva allt på riktigt (kursens slut)

När ni verkligen är klara och vill släppa floating IP:n också (så den går
tillbaka till projektets kvot), välj ett av:

- **Kommentera bort `lifecycle`-blocket** på
  `openstack_networking_floatingip_v2.this` i `main.tf`, och kör sedan
  `terraform destroy` som vanligt (`prevent_destroy` utvärderas vid
  plan-tid mot konfigurationen — det lagras inte i state, så ingen
  `apply` behövs mellan de två stegen).
- **Eller**, utan att röra koden: `terraform state rm
  openstack_networking_floatingip_v2.this` (tar bort resursen ur
  Terraforms bokföring utan att röra cPouta), riv resten med
  `terraform destroy`, och släpp adressen manuellt i Horizon-UI:t under
  **Network → Floating IPs → Release Floating IP** (eller
  `openstack floating ip delete <adress>`).

## 6. Lokal validering (ingen molnaccess krävs)

```bash
terraform fmt -check
terraform init -backend=false
terraform validate
```

Dessa kommandon laddar bara ner providern från Terraform Registry — ingen
`OS_CLOUD`, ingen `clouds.yaml`, och absolut ingen `plan`/`apply` mot
riktig cPouta krävs eller ska köras för detta.

## 7. Två miljöer: dev och prod (Spår C)

Modulen ovan bygger **en** miljö, och det är allt M8 behöver. Spår C kör
samma konfiguration två gånger — en dev-VM och en prod-VM — genom att lägga
till en `environment`-variabel, environment-prefixade resursnamn, en
`precondition` som vägrar köra om Terraform-workspace och var-file inte
hör ihop, och två committade värdefiler `envs/dev.tfvars` / `envs/prod.tfvars`.

De filerna ligger inte här, utan i kursmaterialets referens:
`course-material/templates/spar-c/iac/terraform/` (README:n där beskriver
vad som kopieras vart och varför). Kör ni Spår C: kopiera in dem. Kör ni
bara M8: rör dem inte — kommandona i avsnitt 3 och 4 gäller som de står.
