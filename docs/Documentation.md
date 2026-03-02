# Document Infrastructure pour Chatwoot

## 1. Overview

Notakaren est spécialisée dans le support client externalisé. L'infrastructure a été designé selon les contraintes suivantes: hautement disponible, sécurisée et scalable. A noter que nous sommes restés dans des contraintes raisonnables en matière de prix par rapport à ce que l'exercice nous demandé.

### 1.1 Chatwoot

Chatwoot en production nécessite les services suivants :

- **Chatwoot Web Server (Rails)** — Application Ruby on Rails servant l'interface et l'API sur le port 3000
- **Sidekiq Workers** — Traitement asynchrone des jobs (emails, webhooks, notifications)
- **PostgreSQL** — Base de données relationnelle principale
- **Redis** — Cache, sessions, file d'attente Sidekiq, Action Cable (WebSockets)
- **Stockage objet (S3)** — Pièces jointes en grande parties mais aussi avatars, exports...
- **Service email (SMTP)** — Envoi de notifications et gestion du canal email

## 2. Diagrammes d'architecture

### 2.1 Environnement Production

On peut trouver ce diagramme dans la section "../schema/schema-infra-micro.draw.io.png"

Dans les grandes lignes:

INTERNET / TRAFIC UTILISATEUR ->
ROUTE53 / CLOUDFLARE (DNS + HTTPS) ->
INTERNET GATEWAY (géré par AWS) ->
ALB ENDPOINT (Load Balancer géré par AWS) -> Dispatch entre deux zones de disponibilité:

Zone A:

PUBLIC SUBNET (ALB Node, NAT Gateway et Bastion pour gestion des instances)
PRIVATE SUBNET APPLICATIVES (AUTO SCALING GROUP (EC2 avec Docker Compose applicatifs) / EC2 Monitoring)
PRIVATE SUBNET DATABASES (RDS et ElastiCache "primaire", la ou se trouve les chemins principaux)

Zone B:

PUBLIC SUBNET (ALB Node, NAT Gateway)
PRIVATE SUBNET APPLICATIVES (AUTO SCALING GROUP (EC2 avec Docker Compose applicatifs))
PRIVATE SUBNET DATABASES (RDS et ElastiCache "backup")

S3 Bucket -> Les datas pour l'application ("Pièces jointes et autres fichiers à stocker")


### 2.2 Environnement Staging

Le Staging se trouve dans un VPC séparé pour simplifier a la fois l'architecture et par soucis d'isolation:

- **1 VPC** dédié avec un subnet public dans une seule AZ
- **1 EC2 (port 3000)** avec Docker Compose complet y compris cette fois les BDD.
- **1 EC2 (port 9090)** avec Prometheus + Grafana pour le monitoring.
- Internet Gateway + DNS avec un sous domaine spécifié pour staging accessible que par les membres de l'entreprise


## 3. Contraintes/FAQ

### Multi-AZ pour la Production : Haut Disponibilité ?

L'énoncé exige une haute disponibilité. Notakaren gère des centaines de conversations quotidiennes sur plusieurs fuseaux horaires — toute indisponibilité impacte directement la satisfaction client.

**Solution** : Déploiement sur 2 Availability Zones (AZ-A et AZ-B) avec réplication des composants critiques comme les base de données.

**Conséquences** :
- RDS PostgreSQL et Redis en Multi-AZ avec backup automatique
- ALB distribue le trafic sur les deux AZ disponibles
- Coût doublé sur les NAT Gateway et certaines instances
- En cas de panne d'AZ, le service continue de fonctionner


### Instances t3.micro pour optimisation free-tier ?

Le projet est un exercice de formation. Même si nous voulons simulé un cas réel, le volume de trafic sera en réalité très faible. Il faut maximiser le Free Tier AWS tout en démontrant que nous sommes capable de maitriser et comprendre un environnement de production.

**Solution** : Utilisation de t3.micro pour les instances EC2, db.t3.micro pour RDS, et cache.t3.micro pour ElastiCache (tous free tier available)

**Conséquences** :
- 750 heures/mois gratuites par type d'instance (Free Tier 12 mois)
- Les capacités du t3 micro côté CPU et ram sont casu suffisant pour la plus part de la charge de l'exercice
- En production "réelle", on passerait a minima en t3.small ou t3.medium selon la charge


### ASG (Auto Scaling Groups) vs Docker Swarm

L'architecture doit supporter le scaling automatique de l'application Chatwoot. Nous pouvons orchestrer nos containers via Docker Swarm ou gérer au niveau infrastructure directement avec ASG.

**Solution** : Auto Scaling Groups EC2 avec Docker Compose par instance.

**Les raisons qui nous a amené à cette décision** :
- **Le bottleneck est la création de l'EC2 elle-même** : que l'on ajoute un nœud Swarm ou une instance ASG, en fin de compte c'est le temps de lancement de la VM qui est le plus important. ASG est natif AWS et gère ça de base contrairement à Swarm qui n'est pas "automatique" nativement. Nous utiliserons donc un mixte d'AMI personnalisé et de script bash, qui sont assez léger pour ne pas voir de différences entre les deux approches une fois l'instance créez.
- **Auto Scaling natif** : ASG offre des politiques de scaling plus flexible sur les règles et avec plus de choix — CPU, mémoire, Network, et même des métriques custom CloudWatch comme la profondeur des queues Sidekiq. A noter aussi l'utilisation de Scheduler qui permettent d'augmenter la charge selon certaines heures de la journée ou nous remarquons des pics réguliers.
- **Swarm n'est pas natif AWS** : il nécessite un manager, une configuration supplémentaire, et la gestion manuelle du cluster en augmentant les réplicas. C'est une couche de complexité sans valeur ajoutée dans notre cas.
- **Rolling updates** : ASG + ALB gèrent nativement le deregistration delay et la connection, assurant un downtime casi nul. En effet, lors d’une mise à jour (scaling activé), AWS gère automatiquement la suppression des instances plus a jour et le transfert du trafic pour que tes utilisateurs ne subissent pratiquement aucune coupure.
- **Simplicité** : Docker Compose sur chaque instance est facile à comprendre, débugger et à maintenir.

**Conséquences** :
- Chaque EC2 exécute un Docker Compose identique
- L'AMI est pré-construite avec Docker, Docker Compose, aws-cli, et tout les outils (ou futurs outils apres update de l'AMI) nécessaires.
- Le User Data script clone la configuration depuis GitLab et tire les secrets depuis SSM Parameter Store (AWS Secrets Manager étant un cout additionnels non nécessaire pour nous)
- Le scaling se fait en ajoutant/retirant des instances EC2 entièrement.


### Gérer Terraform sur deux VPC

Nous avons deux environnements sur deux VPC disctint (Production et Staging) qui partagent une structure similaire mais avec des paramètres différents (taille des instances, nombre d'AZ, ALB ou non). 

**Solution** : Pour optimiser le workflow nous utilisons alors les modules Terraform sous forme de "template". Mais nous n'utilisons pas de "workspace" car notre environnement de staging n'est pas assez "complexe" pour avoir recous a un workspace completement différent pour notre terraform.

**Structure** :
terraform
    bootstrap
        main.tf
        variables.tf
        outputs.tf
    environments
        production
            .... .tf
        staging
            .... .tf
    modules
        acm
        alb
        asg
        ...
    scripts
        user-data.sh # Notre script bash pour le provisionning
backend.tf  # Mettre notre state sur un S3 Bucket pour facilité le versionning
versions.tf  # Provider AWS

**Conséquences** :
- Les tfstate files sont complètement isolés chacun dans leurs dossier prod/staging
- Les modules sont versionnés et testés de manière isolé
- Le staging n'affecte pas la prod en cas de changement


## 4. Estimation des coûts AWS

### 4.1 Estimation des coûts mensuels

| Composant | Free Tier (12 mois) | Coût hors Free Tier |
|---|---|---|
| EC2 t3.micro ×4 (prod) + ×1 (staging) | 750h gratuites (couvre ~1 instance) | ~$30/mois (4 restantes) |
| RDS db.t3.micro (primaire) | 750h gratuites (single-AZ) | ~$12/mois |
| RDS Multi-AZ replica | Non couvert Free Tier | ~$22/mois |
| ElastiCache cache.t3.micro ×1 | 750h gratuites | Gratuit |
| ElastiCache replica | Non couvert | ~$12/mois |
| NAT Gateway ×2 | Non couvert | ~$65/mois |
| ALB | Non couvert | ~$16/mois |
| S3 (5 Go) | 5 Go gratuits | Négligeable |
| Route 53 | — | ~$0.50/mois |
| ACM / SSM Parameter Store | Gratuit | Gratuit |
| **Total estimé** | | **~$160/mois** (hors Free Tier) |

Avec le Free Tier actif, le coût réel descend à environ **~$100/mois**, les NAT Gateways étant le poste le plus coûteux. A noter que pour l'exercice, on peut limiter la durée de fonctionnement des ressources la journée lors de nos tests, ou utiliser un seul NAT Gateway le temps de nos tests. D'autres alternatives pourrait être exploré pour remplacer les BDD et les NAT Gateway sur des instances à parts (couts potentiels sur ajout d'instance).


## 5. Flux de trafic

### 5.1 Utilisateur -> Application

Utilisateur (navigateur/mobile) -> HTTPS (port 443)
DNS (Route53 / Cloudflare) -> Résolution → ALB DNS name
Internet Gateway
ALB (Application Load Balancer) -> TLS, HealthCheck, redigirge 80 vers 443, et 443 vers 3000.
Target Group (instances EC2 dans l'ASG) -> Round robin sur les AZ
EC2 Instance (Private Subnet)
Docker Compose (Nginx, Rails, Sidekiq, RDS/Elasticache sur private subnet -> S3 via natgateway)

### 5.2 WebSocket (temps réel)

Navigateur
ALB (WebSocket supporté nativement) -> Connection
EC2 → Rails Action Cable / pub/sub via Redis
ElastiCache Redis


### 5.3 SSH pour l'administration

Administrateur -> SSH sur port custom via private key
Bastion Host 
EC2 Application (Private Subnet)


## 6. Flux de déploiement (CI/CD)

A DEFINIR

## 7. Sécurité

### 7.1 Security Groups

sg-alb (80,443) <- 0.0.0.0/0
sg-bastion (22) <- IP Admin
sg-app (3000) <- sg-alb
sg-app (22) <- sg-bastion
sg-rds (5432) <- sg-app
sg-redis (6379) <- sg-app
sg-monitoring (9090, 3000) <- sg-bastion, sg-app

### 7.3 Secrets

Nous avons choisis d'utiliser SSM Parameter Store pour gérer nos secrets, alternatives gratuite à AWS Secrets Manager avec les features dont nous avons besoin. Inutile de payer pour AWS Secrets Manager pour des features trop avancé pour notre besoin comme le versionning et le rollout auto des passwords. Reste chiffré.
A noter que nos EC2 accèderont à ces secrets via IAM Role.


## 8. Monitoring

- **Prometheus** : scrape des métriques Rails (`/metrics`), Sidekiq, Node Exporter sur chaque EC2
- **Grafana** : dashboards applicatifs (profondeur des queues Sidekiq pourrait être utile) et infrastructure (CPU, RAM, réseaux etc...)
- **CloudWatch** : métriques de nos différents composants ASG, ALB, RDS et ElastiCache
- **Alertes** : A configurer pour avoir les différentes erreurs en temps réel sur des metrics cibles à définir.


## 9. Sauvegarde

- **RDS/Elasticache** : snapshots automatiques quotidiens, dispo selon Free tier. Manuel vers S3 si besoin dans le futur.
- **S3** : versionning activé sur le bucket de stockage
- **Configuration** : tout "l'infrastructure as code" sera versionné dans GitLab directement dans notre ce repo chatwoot-infra


## 10. Docs et références

- Documentation Chatwoot pour l'infra/architecture : https://developers.chatwoot.com/self-hosted/deployment/architecture
- Documentation Chatwoot avec Docker : https://developers.chatwoot.com/self-hosted/deployment/docker
- Dépôt GitHub Chatwoot officiel : https://github.com/chatwoot/chatwoot
- Dépôt Gitlab Chatwoot personnalisé : https://gitlab.com/batch23-gr1/chatwoot
- Dépôt Gitlab Chatwoot Infra personnalisé : https://gitlab.com/batch23-gr1/chatwoot-infra