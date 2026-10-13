# GitOps-referens (Spar B)

Referensinnehåll för Spar B: Kubernetes-manifest för template-app, Kustomize-overlays
för dev/prod, och Flux-objekten som håller ett kluster i synk med git. Detta är
inte ett eget repo — det är en katalog i `template-app` som du kopierar in i ett
EGET manifest-repo (se "Kopiera till eget repo" nedan). Bakgrund och verifierade
fynd: TASK-8:s implementation notes (Flux på Rahti, körd live 2026-08-07).

## Katalogstruktur

```
gitops/
  base/                     App-manifest: Deployment + Service för backend och
                             frontend, samt en Route mot frontend.
  overlays/
    dev/kustomization.yaml  1 replika vardera, label environment=dev.
    prod/kustomization.yaml 2 replikor vardera, label environment=prod.
  flux/
    dev/                    GitRepository + ServiceAccount + RoleBinding +
    prod/                   Flux Kustomization CR för respektive miljö.
```

`kubectl kustomize gitops/overlays/dev` (eller `.../prod`) renderar hela
app-manifestet för den miljön. `gitops/flux/*` är inte kustomize-kataloger —
de är enskilda objekt som appliceras en gång för att koppla på Flux (se
"Bootstrap" nedan).

## Varför ingen `namespace:` i overlays

`base/` och `overlays/*/kustomization.yaml` sätter medvetet inget
`namespace:`-fält. Det är `spec.targetNamespace` på Flux Kustomization-CR:n
(`flux/<env>/kustomization.yaml`) som avgör var resurserna hamnar — samma
mönster som verifierades i TASK-8.

## Flux-objekten (TASK-8:s verifierade spec)

CSC kör centrala Flux-controllers som reconcilar tenant-namespaces direkt.
Det finns **ingen FluxInstance att applicera** — en sådan i ett
tenant-namespace ignoreras helt av operatorn (verifierat i TASK-8). Det som
faktiskt behövs, per miljö:

1. `GitRepository` — url/ref/interval mot ditt manifest-repo.
2. `ServiceAccount` (`flux-applier`) — kustomize-controller applicerar annars
   som namespacets default-SA, som saknar skrivrättigheter och failar med
   Forbidden på första reconcile.
3. `RoleBinding` — binder `flux-applier` till den inbyggda ClusterRole:en
   `admin`, skopat till namespacet (RoleBinding, inte ClusterRoleBinding).
4. Flux `Kustomization` (CRD `kustomize.toolkit.fluxcd.io`, inte att
   förväxla med kustomize.config.k8s.io-filen i samma katalog) —
   `spec.serviceAccountName: flux-applier`, `spec.targetNamespace`,
   `spec.prune: true`, `spec.path` mot rätt overlay.

## Fallgrop: Rahtis LimitRange (CPU-ratio <= 5)

Rahti har en LimitRange som kräver att `limits.cpu / requests.cpu <= 5` per
container. Många upstream-manifest (t.ex. podinfos default 100m/2000m = 20)
blockeras av det på pod-nivå. Här sätts `requests.cpu: 100m` /
`limits.cpu: 500m` (ratio 5) direkt i `base/*-deployment.yaml`, eftersom vi
äger manifesten själva — ingen inline Flux-patch behövs (den knepen
behövdes bara i TASK-8:s test mot ett upstream-repo vi inte äger).

## Route och TLS

`base/route.yaml` använder edge-terminering
(`spec.tls.termination: edge`, `insecureEdgeTerminationPolicy: Redirect`) —
det är standardbeteendet OpenShift-konsolen ger dig när du exponerar en
Service, så det är det studenterna kommer se i praktiken på Rahti.

## Kopiera till eget repo

Denna katalog är en referens i `template-app`, inte ett fristående repo.
Flux pekar mot ETT git-repo (`spec.url` i `flux/<env>/gitrepository.yaml`),
så för din egen labb:

1. Skapa ett eget manifest-repo (kan vara tomt, eller en kopia av denna
   katalog som utgångspunkt).
2. Kopiera in `base/`, `overlays/` och `flux/` (eller bara det du behöver).
3. Fyll i platshållarna:
   - `<ägare>` i `base/*-deployment.yaml` → din (gemener) GitHub-org/user,
     samma värde `publish-images.yml` skriver till GHCR.
   - `<manifest-repo-url>` i `flux/*/gitrepository.yaml` → URL:en till DITT
     EGET manifest-repo (steg 1 ovan) — inget kursrepo att peka mot här.
   - `<projekt-namespace>-dev` / `<projekt-namespace>-prod` → dina
     tilldelade Rahti-namespace. OBS: namespace-modellen för projekt
     (kvot per projekt) är inte färdigbestämd än (se TASK-17) — om du bara
     har ETT namespace, peka båda Flux Kustomization-CR:erna dit istället
     och hoppa över dev/prod-separationen tills vidare.
4. Bootstrap (engångs-`oc apply`, inte något Flux gör åt dig): applicera
   `flux/<env>/serviceaccount.yaml`, `rolebinding.yaml`, `gitrepository.yaml`
   och `kustomization.yaml` i valfri ordning i respektive namespace. Flux
   tar över därifrån — push till main i ditt manifest-repo = deploy, ingen
   pipeline behövs.

## Lokal verifiering

```
kubectl kustomize gitops/overlays/dev
kubectl kustomize gitops/overlays/prod
```

Ska rendera utan fel. `gitops/flux/*` och `route.yaml` kan inte
apply-dry-run:as lokalt (CRD:erna `source.toolkit.fluxcd.io`,
`kustomize.toolkit.fluxcd.io` och `route.openshift.io` finns inte i ett
lokalt kluster) — de är strukturellt granskade mot TASK-8:s verifierade
spec istället.
