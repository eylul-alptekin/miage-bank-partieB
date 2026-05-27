# Partie B — Packaging Helm & Déploiement Kubernetes de MIAGE-Bank

**Étudiante :** ALPTEKIN Eylul  
**Formation :** Master MIAGE M2 ITN  
**Cours :** Cloud & Kubernetes

---

## Contexte

Cette partie déploie le microservice **amc_clients** de MIAGE-Bank sur Kubernetes via un chart Helm, avec gestion sécurisée des secrets, NetworkPolicy, RBAC et GitOps via ArgoCD.

L'image utilisée est celle construite en Partie A (`miage-bank-clients:v1`), chargée directement dans minikube via `minikube image load`.

> **Note architecturale :** MIAGE-Bank est une application composée de 7 microservices (annuaire Eureka, config server, clients, comptes, composite, API gateway, frontend) + 2 bases de données (MySQL, MongoDB). Dans ce TP, nous déployons le microservice `amc_clients` avec sa base MySQL, ce qui permet de démontrer l'ensemble des mécanismes Kubernetes/Helm demandés. Un déploiement complet nécessiterait un chart par microservice ou un chart umbrella.

---

## Stack technique

| Outil | Usage |
|---|---|
| Helm | Packaging et déploiement Kubernetes |
| kubectl | Interaction avec le cluster |
| minikube | Cluster Kubernetes local |
| ArgoCD | GitOps — synchronisation automatique |
| nginx Ingress | Exposition externe de l'application |

---

## Structure du dépôt

```
miage-bank-partieB/
├── miage-bank/                  ← Chart Helm
│   ├── Chart.yaml               ← Métadonnées du chart (nom, version)
│   ├── values.yaml              ← Configuration par défaut (dev)
│   ├── values-prod.yaml         ← Surcharges pour la production
│   └── templates/
│       ├── _helpers.tpl         ← Fonctions Helm réutilisables
│       ├── serviceaccount.yaml  ← Identité dédiée (RBAC)
│       ├── rbac.yaml            ← Role + RoleBinding (least privilege)
│       ├── configmap.yaml       ← Config non-sensible (URLs, ports)
│       ├── deployment.yaml      ← Pod amc_clients
│       ├── service.yaml         ← Service ClusterIP interne
│       ├── ingress.yaml         ← Exposition externe via nginx
│       ├── networkpolicy.yaml   ← Firewall entre pods
│       ├── mysql-deployment.yaml ← Base de données MySQL
│       └── mysql-service.yaml   ← Service ClusterIP MySQL
└── argocd/
    └── application.yaml         ← Application ArgoCD (GitOps)
```

---

## Prérequis

- minikube démarré : `minikube start`
- Addon ingress activé : `minikube addons enable ingress`
- Helm v3+ installé
- kubectl configuré sur minikube

---

## Déploiement pas à pas

### 1. Construire et charger l'image

```bash
# Cloner et compiler amc_clients
git clone https://github.com/hialmar/amc_clients.git
cd amc_clients
mvn package -DskipTests

# Construire l'image Docker
docker build -t miage-bank-clients:v1 .

# Charger l'image dans minikube (pas besoin de registry externe)
minikube image load miage-bank-clients:v1
cd ..
```

### 2. Créer le namespace et le Secret

Les credentials MySQL ne sont **jamais stockés dans le chart ou dans Git**. Le Secret est créé manuellement dans Kubernetes :

```bash
kubectl create namespace miage-bank

kubectl create secret generic miage-bank-secrets \
  --namespace miage-bank \
  --from-literal=mysql-root-password=root
```

Le `deployment.yaml` référence ce secret par son nom — aucune valeur sensible n'apparaît dans `values.yaml`.

### 3. Valider le chart

```bash
# Vérification syntaxique
helm lint miage-bank/

# Rendu des templates (simulation sans déploiement)
helm template miage-bank miage-bank/

# Dry-run complet (validation côté Kubernetes)
helm install miage-bank miage-bank/ \
  --namespace miage-bank \
  --dry-run --debug
```

### 4. Déployer

```bash
helm install miage-bank miage-bank/ --namespace miage-bank
```

### 5. Vérifier le déploiement

```bash
# Statut des pods (attendre ~5 minutes pour Spring Boot)
kubectl get pods -n miage-bank -w

# Vérifier l'ingress
kubectl get ingress -n miage-bank

# Tester l'application via port-forward
kubectl port-forward svc/miage-bank 10011:10011 -n miage-bank
curl http://localhost:10011/actuator/health
# Résultat attendu : {"status":"UP"}
```

### 6. Mettre à jour le chart

```bash
helm upgrade miage-bank miage-bank/ --namespace miage-bank
```

### 7. Désinstaller

```bash
helm uninstall miage-bank --namespace miage-bank
```

---

## Sécurité

### Gestion des secrets

Les credentials de MIAGE-Bank (mot de passe MySQL) **ne figurent pas en clair** dans `values.yaml` ni dans Git. Approche utilisée : **Secret Kubernetes natif créé séparément du chart**.

Le Deployment référence le secret par nom :
```yaml
env:
  - name: SPRING_DATASOURCE_PASSWORD
    valueFrom:
      secretKeyRef:
        name: miage-bank-secrets
        key: mysql-root-password
```

### RBAC

Un `ServiceAccount` dédié `miage-bank-sa` est assigné au pod avec un `Role` minimaliste (least privilege) :
- Lecture des `configmaps`
- Lecture des `pods`

Aucun accès cluster-wide — le principe du moindre privilège est respecté.

### NetworkPolicy

Trois politiques réseau sont en place :

| Politique | Effet |
|---|---|
| `default-deny-ingress` | Bloque tout trafic entrant dans le namespace par défaut |
| `miage-bank-allow-ingress` | Autorise uniquement le contrôleur nginx à atteindre l'app |
| `miage-bank-mysql-policy` | MySQL n'est accessible que depuis le pod amc_clients |

### Ingress

L'application est exposée via nginx Ingress sur le hostname `miage-bank.local`.  
Le Service est de type `ClusterIP` — aucun accès direct depuis l'extérieur sans passer par l'Ingress.

---

## GitOps avec ArgoCD

### Principe

ArgoCD surveille le dépôt Git et maintient le cluster Kubernetes synchronisé avec l'état décrit dans Git. Si une ressource est modifiée manuellement dans le cluster (dérive), ArgoCD la détecte et la corrige automatiquement.

### Configuration

Le fichier `argocd/application.yaml` définit l'Application ArgoCD :

```yaml
syncPolicy:
  automated:
    prune: true      # Supprime les ressources retirées de Git
    selfHeal: true   # Corrige automatiquement toute dérive
```

### Déployer l'Application ArgoCD

```bash
kubectl apply -f argocd/application.yaml
```

### Vérifier la synchronisation

```bash
kubectl get application -n argocd miage-bank
# Résultat attendu : SYNC STATUS = Synced, HEALTH STATUS = Healthy
```

---

## Démonstration de la dérive (ArgoCD Drift)

Le TP demande de démontrer la détection et la réconciliation automatique d'une dérive.

> **Note sur la méthode :** ArgoCD avec `selfHeal: true` corrige les dérives en quelques secondes — trop vite pour observer l'état `OutOfSync` à l'écran. Pour la démonstration, on désactive temporairement `selfHeal` afin de rendre l'état intermédiaire visible, puis on le réactive pour montrer la réconciliation automatique. C'est une technique de ralentissement artificiel pour les besoins du TP ; en production, la correction se ferait sans intervention humaine.
>
> **Pourquoi ne pas scaler les réplicas ?** ArgoCD ignore volontairement le champ `.spec.replicas` des Deployments pour être compatible avec les HPA (Horizontal Pod Autoscaler). Supprimer une ressource gérée (comme le ConfigMap) est une dérive que ArgoCD détecte et corrige de manière fiable.

### Étape 1 — État initial (Synced)

```bash
kubectl get application -n argocd miage-bank
# SYNC STATUS: Synced | HEALTH STATUS: Healthy
```

L'application dans le cluster correspond exactement à ce qui est défini dans Git.

### Étape 2 — Suspendre selfHeal pour observer la dérive

On désactive temporairement la réconciliation automatique afin que l'état `OutOfSync` reste visible :

```bash
kubectl patch application miage-bank -n argocd \
  --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":false}}}}'
```

### Étape 3 — Créer une dérive manuellement

On supprime le ConfigMap directement dans Kubernetes, **sans toucher Git** :

```bash
kubectl delete configmap miage-bank-config -n miage-bank
```

### Étape 4 — ArgoCD détecte l'écart (OutOfSync)

ArgoCD détecte que le ConfigMap n'existe plus dans le cluster alors qu'il est défini dans Git :

```bash
kubectl get application -n argocd miage-bank
# SYNC STATUS: OutOfSync | HEALTH STATUS: Healthy
```

Dans l'interface ArgoCD, la carte `miage-bank` passe de **Synced** (vert) à **OutOfSync** (orange).

### Étape 5 — Réactiver selfHeal → réconciliation automatique

On réactive `selfHeal`. ArgoCD recrée immédiatement le ConfigMap manquant pour correspondre à Git :

```bash
kubectl patch application miage-bank -n argocd \
  --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":true}}}}'

# Observer le retour à Synced
watch -n 5 kubectl get application -n argocd miage-bank
# SYNC STATUS: Synced | HEALTH STATUS: Healthy
```

### Conclusion

Cette démonstration illustre le principe fondamental du GitOps : **Git est la source de vérité**. Toute modification manuelle du cluster est considérée comme une dérive et corrigée automatiquement. Le fait que `selfHeal` soit si rapide qu'il faille le désactiver pour observer la dérive confirme son efficacité en production.

---

## values.yaml — Configuration

| Paramètre | Valeur par défaut | Description |
|---|---|---|
| `replicaCount` | `1` | Nombre de pods |
| `image.repository` | `miage-bank-clients` | Image Docker |
| `image.tag` | `v1` | Tag de l'image |
| `image.pullPolicy` | `IfNotPresent` | Politique de pull |
| `service.type` | `ClusterIP` | Type de service |
| `service.port` | `10011` | Port applicatif |
| `ingress.hostname` | `miage-bank.local` | Hostname Ingress |
| `mysql.database` | `banquebd` | Nom de la base |
| `secretName` | `miage-bank-secrets` | Nom du Secret K8s |

## values-prod.yaml — Surcharges production

| Paramètre | Valeur prod |
|---|---|
| `replicaCount` | `2` |
| `image.pullPolicy` | `Always` |
| `resources.limits.memory` | `1Gi` |
| `ingress.hostname` | `miage-bank.prod.miage.fr` |
| `ingress.tls` | `true` |