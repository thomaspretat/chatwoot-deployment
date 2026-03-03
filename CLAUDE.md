Chatwoot-La-capsule
/
En te basant sur ce que tu sais de mon projet et de la documentation qui y est mentionné ainsi que des technologies qui sont mentionnées.
Crées moi tous les tickets directement sur notion par epic, dans la page suivante (https://www.notion.so/Sprint-Product-Backlog-Lite-b6251c5150d483dcabe201304ae02be7?source=copy_link) tu trouveras un board avec des colonnes qui sont des epics, crées les tickets à destination des devops pour mener à bien ce projet étape par étape dans les colonnes correspondantes par épic. Écris les tel un product owner en respectant les bonnes pratiques

2 mars

Orchestrated comprehensive DevOps ticket creation across six project epics
Orchestrated comprehensive DevOps ticket creation across six project epics
Parfait, j'ai bien compris la structure du board. Il y a 6 épics : IaC, CI/CD, Gitlab, Sécurité, Monitoring, Gestion. Je vais maintenant créer tous les tickets. C'est parti 🚀

Compiló y organizó tickets por épicas completadas
Compiló y organizó tickets por épicas completadas
Tous les tickets sont créés ! 🎉 Voici le récapitulatif complet de ce qui a été ajouté dans ton board Notion :

📋 Récapitulatif — 43 tickets créés
🏗 IaC (12 tickets) — Sprints 1 à 3
Ticket Sprint Points
Backend Terraform (S3 + DynamoDB) 1 2
VPC Production (2 AZ) 1 5
VPC Staging (1 AZ) 1 3
Security Groups (ALB, EC2, RDS, Bastion, Redis) 1 5
NAT Gateways (1 par AZ) 1 3
ALB Production multi-AZ + ACM 1 5
Auto Scaling Group Production (t3.micro, rolling update) 2 8
RDS PostgreSQL Multi-AZ 2 5
Elasticache Redis Multi-AZ 2 5
Bastions (1 par AZ) 2 3
ACM + Route53 domaine HTTPS 2 3
Ressources Staging complètes 3 8
🔁 CI/CD (9 tickets) — Sprints 1 à 4
GitLab Runner · Build Docker · Tests unitaires/lint · SonarQube · Tests E2E · Locust · Deploy Staging · Deploy Prod (rolling update, validation manuelle) · Terraform plan/apply

🦊 GitLab (5 tickets) — Sprints 1 à 2
Git Flow + protections · Container Registry · Dockerfile Chatwoot · Variables CI/CD · .gitlab-ci.yml principal

🔐 Sécurité (6 tickets) — Sprints 2 à 4
SSH hardening (Ansible) · UFW/iptables · Anonymisation RGPD · Backups RDS · Secrets Manager · IAM Roles (Least Privilege)

📊 Monitoring (5 tickets) — Sprints 4 à 5
Prometheus + exporters · Dashboard Grafana Staging · Dashboard Grafana Production · Alertmanager (CPU, RDS, Sidekiq, dispo)

📁 Gestion (6 tickets) — Sprints 1 à 6
Architecture AWS (diagramme + ADR) · Board Notion + DoD · README technique · Procédure de mise en prod + rollback · Documentation RGPD · Recettage final

Chaque ticket est rédigé en user story avec des critères d'acceptance précis et des notes techniques pour guider l'équipe. Tu peux maintenant basculer vers la vue Board (groupé par Épic) pour tout visualiser, ou Sprint Planning pour organiser les sprints.

As-tu consulté le repo et les dockerfiles déjà présent ainsi que les fichiers du dossier db ?
Comme nous allons partir sur une architecture avec des rds et elastic cache, il n'y aura plus besoin de monter ces conteneurs dans le docker compose de production.
Par contre en staging nous devrons peut-être monter ces bases sur la même machine donc les garder dans le docker compose et initialiser la base de données avec seed dans l'environnement de staging.
Aussi je veux que tu analyses vraiment leur manière de faire dans le repo pour que je puisse avoir les bonnes actions à faire dans mes fichiers ansible pour monter la base de données et ensuite créer les tables correctement etc

2 mars

Analysé architecture Chatwoot, RDS/ElastiCache, et stratégie Ansible
Analysé architecture Chatwoot, RDS/ElastiCache, et stratégie Ansible
Voilà, j'ai maintenant une analyse très complète du repo. Laisse-moi tout te débriefier de manière structurée et précise.

🔬 Analyse complète du repo Chatwoot

1. Le docker-compose.production.yaml — ce qui existe
   Le fichier officiel contient 5 services :

base (anchor YAML)
├── rails → app Rails, port 3000, entrypoint: docker/entrypoints/rails.sh
├── sidekiq → workers de background jobs
├── postgres → image: pgvector/pgvector:pg16 ⚠️ (pas postgres:16 !)
└── redis → redis:alpine avec requirepass
→ Pour Production AWS : supprimer postgres et redis, pointer vers RDS + Elasticache via .env → Pour Staging : garder postgres et redis mais l'image postgres DOIT être pgvector/pgvector:pg16, pas postgres:16 plain. C'est une exigence de Chatwoot v4+.

2. L'entrypoint rails.sh — ce qu'il fait vraiment
   D'après les logs observés dans les issues GitHub, voici ce que fait rails.sh au démarrage :

bash
rm -rf /app/tmp/pids/server.pid # évite le "server already running"
rm -rf '/app/tmp/cache/\*'
echo 'Waiting for postgres to become ready....'

# Exécute docker/entrypoints/helpers/pg_database_url.rb

# → construit POSTGRES_PORT=5432 depuis les variables d'env

pg_isready -h <POSTGRES_HOST> -p 5432 -U postgres

# puis exec la commande passée en CMD

Point critique : il attend que PostgreSQL soit prêt (pg_isready) avant de démarrer. Si RDS n'est pas encore accessible au moment du démarrage du conteneur, il boucle en attendant. Ça veut dire que côté Ansible, il faut que RDS soit up et que le SG autorise bien la connexion avant de démarrer les conteneurs.

3. La commande de BDD critique — db:chatwoot_prepare
   C'est la commande clé, pas db:migrate. Voici pourquoi :

bash
docker compose run --rm rails bundle exec rails db:chatwoot_prepare
Ce que fait db:chatwoot_prepare (défini dans lib/tasks/db_enhancements.rake) :

Active l'extension pgvector dans PostgreSQL (CREATE EXTENSION IF NOT EXISTS vector)
Crée la base si elle n'existe pas (db:create)
Charge le schéma (db:schema:load) — premier déploiement
Applique les migrations manquantes (db:migrate) — mises à jour
Charge les seeds de configuration (db:seed) — installe les configs Chatwoot initiales (InstallationConfig, etc.)
⚠️ Ne pas utiliser db:migrate seul sur une première installation — tu auras des erreurs. db:chatwoot_prepare est idempotent et gère les deux cas (fresh install + update).

4. pgvector et AWS RDS — bonne nouvelle
   Pour AWS RDS : aucune action n'est nécessaire. RDS supporte pgvector nativement depuis 2023.
   Chatwoot
   Il faut juste t'assurer d'utiliser PostgreSQL 15 ou 16 sur RDS (pas 12 ou 14). La commande db:chatwoot_prepare se chargera d'activer l'extension automatiquement via CREATE EXTENSION IF NOT EXISTS vector.

5. Variables d'environnement — configuration RDS + Elasticache
   Voici les variables .env critiques à injecter (depuis AWS Secrets Manager via user-data/Ansible) :

bash

# ====== APP ======

SECRET_KEY_BASE=<rake_secret_output> # OBLIGATOIRE
FRONTEND_URL=https://chat.notakaren.com
RAILS_ENV=production
NODE_ENV=production
INSTALLATION_ENV=docker
RAILS_LOG_TO_STDOUT=true

# ====== POSTGRES (RDS) ======

POSTGRES_HOST=<rds-endpoint>.eu-west-3.rds.amazonaws.com
POSTGRES_PORT=5432
POSTGRES_DATABASE=chatwoot_production
POSTGRES_USERNAME=chatwoot
POSTGRES_PASSWORD=<depuis_secrets_manager>

# ====== REDIS (Elasticache) ======

# Pour Elasticache sans TLS :

REDIS_URL=redis://<elasticache-endpoint>:6379/0

# Pour Elasticache avec TLS (recommandé) :

REDIS_URL=rediss://<elasticache-endpoint>:6379/0
REDIS_OPENSSL_VERIFY_MODE=none # si certificat auto-signé AWS

# ====== STORAGE (S3 — remplace le local) ======

ACTIVE_STORAGE_SERVICE=amazon # PAS "local" en production !
S3_BUCKET_NAME=notakaren-chatwoot-storage
AWS_ACCESS_KEY_ID=<via_iam_role_pas_hardcode>
AWS_SECRET_ACCESS_KEY=<via_iam_role>
AWS_REGION=eu-west-3

# ====== MAILER ======

MAILER_SENDER_EMAIL=support@notakaren.com
SMTP_ADDRESS=<smtp_host>
SMTP_PORT=587
⚠️ Piège important : en production, si tu gardes ACTIVE_STORAGE_SERVICE=local, les pièces jointes seront stockées dans /app/storage à l'intérieur du conteneur — elles disparaissent à chaque redéploiement. Il faut passer sur S3.

6. Docker Compose Production (sans postgres/redis)
   yaml
   version: '3'
   services:
   base: &base
   image: chatwoot/chatwoot:latest
   env_file: .env
   volumes: - storage_data:/app/storage # inutile si S3, mais inoffensif

rails:
<<: \*base # PLUS de depends_on: postgres/redis → ils sont externes (RDS/Elasticache)
ports: - '127.0.0.1:3000:3000'
environment: - NODE_ENV=production - RAILS_ENV=production - INSTALLATION_ENV=docker
entrypoint: docker/entrypoints/rails.sh
command: ['bundle', 'exec', 'rails', 's', '-p', '3000', '-b', '0.0.0.0']
restart: always

sidekiq:
<<: \*base # PLUS de depends_on: postgres/redis
environment: - NODE_ENV=production - RAILS_ENV=production - INSTALLATION_ENV=docker
command: ['bundle', 'exec', 'sidekiq', '-C', 'config/sidekiq.yml']
restart: always

volumes:
storage_data:

# PLUS de postgres_data ni redis_data

7. Docker Compose Staging (avec postgres + redis locaux)
   yaml
   version: '3'
   services:
   base: &base
   image: chatwoot/chatwoot:latest
   env_file: .env
   volumes: - storage_data:/app/storage

rails:
<<: \*base
depends_on: - postgres - redis
ports: - '127.0.0.1:3000:3000'
environment: - NODE_ENV=production - RAILS_ENV=production - INSTALLATION_ENV=docker
entrypoint: docker/entrypoints/rails.sh
command: ['bundle', 'exec', 'rails', 's', '-p', '3000', '-b', '0.0.0.0']
restart: always

sidekiq:
<<: \*base
depends_on: - postgres - redis
environment: - NODE_ENV=production - RAILS_ENV=production - INSTALLATION_ENV=docker
command: ['bundle', 'exec', 'sidekiq', '-C', 'config/sidekiq.yml']
restart: always

postgres:
image: pgvector/pgvector:pg16 # ⚠️ PAS postgres:16 !
restart: always
ports: - '127.0.0.1:5432:5432'
volumes: - postgres_data:/var/lib/postgresql/data
environment: - POSTGRES_DB=chatwoot_staging - POSTGRES_USER=chatwoot - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

redis:
image: redis:alpine
restart: always
command: ["sh", "-c", "redis-server --requirepass \"$REDIS_PASSWORD\""]
env_file: .env
volumes: - redis_data:/data
ports: - '127.0.0.1:6379:6379'

volumes:
storage_data:
postgres_data:
redis_data: 8. Tâches Ansible — ordre et contenu précis
Voici le playbook complet à écrire pour monter correctement Chatwoot :

yaml

# ansible/playbooks/deploy-chatwoot.yml

# ── PHASE 1 : Dépendances système ──────────────────────────

- name: Install Docker + docker-compose-plugin
  apt:
  name: ['ca-certificates', 'curl', 'docker-ce', 'docker-compose-plugin']
  state: present

- name: Add ubuntu user to docker group
  user:
  name: ubuntu
  groups: docker
  append: yes

# ── PHASE 2 : Récupérer les secrets depuis AWS Secrets Manager ──

- name: Get DB credentials from Secrets Manager
  shell: |
  aws secretsmanager get-secret-value \
   --secret-id chatwoot/production/db \
   --query SecretString --output text
  register: db_secret_raw

- name: Parse DB secret JSON
  set_fact:
  db_secret: "{{ db_secret_raw.stdout | from_json }}"

# ── PHASE 3 : Déployer les fichiers de config ──────────────

- name: Create /opt/chatwoot directory
  file:
  path: /opt/chatwoot
  state: directory
  owner: ubuntu
  mode: '0750'

- name: Template .env file (production)
  template:
  src: templates/chatwoot.env.j2
  dest: /opt/chatwoot/.env
  owner: ubuntu
  mode: '0600' # secrets : lecture seule owner

- name: Copy docker-compose.production.yml
  copy:
  src: files/docker-compose.production.yml
  dest: /opt/chatwoot/docker-compose.yml
  owner: ubuntu

# ── PHASE 4 : Pull de l'image ──────────────────────────────

- name: Pull Chatwoot image
  community.docker.docker_image:
  name: chatwoot/chatwoot
  tag: "{{ chatwoot_version | default('latest') }}"
  source: pull

# ── PHASE 5 : Init BDD (PREMIÈRE FOIS UNIQUEMENT) ──────────

# Vérifier si la BDD est déjà initialisée

- name: Check if DB is already initialized
  shell: |
  docker compose -f /opt/chatwoot/docker-compose.yml run --rm rails \
   bundle exec rails runner "puts ActiveRecord::Base.connection.tables.any?"
  register: db_initialized
  ignore_errors: yes
  changed_when: false

- name: Run db:chatwoot_prepare (first install)
  shell: |
  docker compose -f /opt/chatwoot/docker-compose.yml run --rm rails \
   bundle exec rails db:chatwoot_prepare
  args:
  chdir: /opt/chatwoot
  when: db_initialized.stdout != "true"
  # IMPORTANT: ne tourne qu'une seule fois

# ── PHASE 6 : Migrations (déploiements suivants) ────────────

- name: Run db:chatwoot_prepare (migrations on update)
  shell: |
  docker compose -f /opt/chatwoot/docker-compose.yml run --rm rails \
   bundle exec rails db:chatwoot_prepare
  args:
  chdir: /opt/chatwoot
  when: db_initialized.stdout == "true" and chatwoot_update | default(false)

# ── PHASE 7 : Démarrage des services ───────────────────────

- name: Start Chatwoot services
  community.docker.docker_compose_v2:
  project_src: /opt/chatwoot
  state: present
  pull: always

# ── PHASE 8 : Health check ──────────────────────────────────

- name: Wait for Chatwoot to be healthy
  uri:
  url: http://localhost:3000/health
  status_code: 200
  register: health_check
  retries: 15
  delay: 10
  until: health_check.status == 200

9. Template .env.j2 Ansible (extrait)
   jinja2

# .env pour Production — généré par Ansible

SECRET_KEY_BASE={{ db_secret.secret_key_base }}
FRONTEND_URL=https://chat.notakaren.com
RAILS_ENV=production
NODE_ENV=production
INSTALLATION_ENV=docker
RAILS_LOG_TO_STDOUT=true

# PostgreSQL (RDS)

POSTGRES_HOST={{ rds_endpoint }}
POSTGRES_PORT=5432
POSTGRES_DATABASE=chatwoot_production
POSTGRES_USERNAME={{ db_secret.username }}
POSTGRES_PASSWORD={{ db_secret.password }}

# Redis (Elasticache)

REDIS_URL=rediss://{{ elasticache_endpoint }}:6379/0
REDIS_OPENSSL_VERIFY_MODE=none

# S3

ACTIVE_STORAGE_SERVICE=amazon
S3_BUCKET_NAME={{ s3_bucket_name }}
AWS_REGION=eu-west-3 10. Points de vigilance critiques à garder en tête
Problème potentiel Solution
pgvector manquant ✅ RDS le supporte nativement, db:chatwoot_prepare l'active automatiquement
db:migrate au lieu de db:chatwoot_prepare ❌ Ne jamais utiliser db:migrate seul au premier déploiement
rails.sh bloque si RDS pas prêt Assurer que RDS est en état available et SG ouvert avant de lancer les conteneurs
Storage local = perte de fichiers Utiliser ACTIVE_STORAGE_SERVICE=amazon en production
Redis avec TLS Elasticache Utiliser rediss:// (double s) + REDIS_OPENSSL_VERIFY_MODE=none
Staging postgres image Toujours pgvector/pgvector:pg16, jamais postgres:16
Seed staging db:chatwoot_prepare intègre déjà les seeds Chatwoot, pas besoin de les appeler séparément
Tu as maintenant tout ce qu'il faut pour écrire des playbooks Ansible précis et des docker-compose corrects pour les deux environnements. Tu veux qu'on mette à jour les tickets Notion en conséquence avec ces précisions techniques ?

Ajoutes tout cela dans notion en créant des tickets ou en modifiant certains déjà présent.
N'hésites pas à mettre les exemples de code que tu viens de me donner dans les tickets directement

2 mars

Orchestrated ticket creation and updates with technical code examples
Orchestrated ticket creation and updates with technical code examples
Je vais d'abord récupérer les tickets existants pour identifier ceux à modifier, puis créer les nouveaux.

Orchestrated ticket updates and creations with code examples
Orchestrated ticket updates and creations with code examples
Bien, j'ai les IDs. Je vais maintenant mettre à jour les tickets clés et créer les nouveaux. C'est parti, je travaille en batch.

Orchestrated création de tickets Notion et intégration de code
Orchestrated création de tickets Notion et intégration de code
Maintenant je crée les nouveaux tickets manquants.

Priorisa les mises à jour critiques pour les tickets Notion
Priorisa les mises à jour critiques pour les tickets Notion
Maintenant les dernières mises à jour sur les tickets Elasticache et Staging.

A utilisé l'intégration Notion
A utilisé l'intégration Notion
Tout est à jour dans Notion. Voici le récap de ce qui a été fait 👇

✅ Récapitulatif des modifications et créations
🔄 Tickets mis à jour (contenu remplacé)
Ticket Ce qui a changé
Dockerfile Chatwoot Ajout des deux docker-compose complets (production sans postgres/redis, staging avec pgvector/pgvector:pg16), tableau de diff des variables d'env, alerte ACTIVE_STORAGE_SERVICE
RDS PostgreSQL Ajout note pgvector nativement supporté sur RDS, contrainte PG16, code Terraform complet avec SG
Pipeline CD Staging Séquence db:chatwoot_prepare expliquée (pourquoi pas db:migrate), job GitLab CI complet avec ProxyJump Bastion + retry health check
Pipeline CD Production Séquence complète en 5 étapes (snapshot → migrations → LT → rolling update → health check), job GitLab CI complet avec rollback manuel
Secrets Manager Template .env.j2 Jinja2 complet (prod vs staging), tâches Ansible de récupération des secrets, liste de tous les secrets à créer
Elasticache Redis Explication redis:// vs rediss:// (TLS), code Terraform complet, output pour Secrets Manager
Ressources Staging Comparaison Option A (RDS) vs Option B (tout-en-un Docker), docker-compose staging complet, séquence d'init pas-à-pas
🆕 Tickets créés
Ticket Épic Sprint Points
Playbook Ansible deploy-chatwoot (séquence complète 8 phases, ProxyJump, secrets, health check) IaC + CI/CD Sprint 3 8
Bucket S3 stockage Chatwoot Production (ACTIVE_STORAGE_SERVICE=amazon, Terraform complet) IaC + Sécurité Sprint 3 3
User-data EC2 ASG (script bash complet, pull image, génération .env depuis Secrets Manager) IaC Sprint 3 5
J'aimerais savoir dans le cadre de l'auto scaling group, est-ce qu'on a besoin du playbook d'ansible ou est-ce compatible notamment pour la gestion des variables d'environnement

2 mars

Évalué la redondance d'Ansible avec user-data en ASG
Évalué la redondance d'Ansible avec user-data en ASG
Excellente question d'architecture — c'est un vrai sujet de fond.

La tension ASG + Ansible
Les deux approches ne jouent pas dans le même registre et se chevauchent partiellement, ce qui crée de la confusion.

🔄 Ce que fait l'ASG nativement
L'ASG avec un Launch Template contenant un user-data est auto-suffisant pour le déploiement applicatif :

Scale-out déclenché
↓
Nouvelle EC2 lancée automatiquement
↓
user-data s'exécute au boot
↓
Docker installé + secrets récupérés + .env généré + image pullée + containers up
↓
ALB health check passe → instance intégrée au Target Group
Chaque nouvelle instance est autonome dès son démarrage. C'est précisément le principe du scale-out. Ansible ne peut pas s'intercaler là-dedans — au moment où l'instance boot, Ansible ne connaît pas son IP, il n'est pas déclenché, et l'instance doit se débrouiller seule.

🗝 La gestion des variables d'environnement — user-data + Secrets Manager suffit
Pour les variables d'env Chatwoot, le flux complet dans le user-data est :

bash

# Au boot de chaque instance ASG — entièrement automatique

APP_SECRET=$(aws secretsmanager get-secret-value \
 --secret-id "chatwoot/production/app" \
 --region eu-west-3 \
 --query SecretString --output text)

# Génération du .env directement dans le script bash

cat > /opt/chatwoot/.env << EOF
SECRET_KEY_BASE=$(echo $APP_SECRET | python3 -c "import sys,json; print(json.load(sys.stdin)['SECRET_KEY_BASE'])")
POSTGRES_HOST=$(echo $DB_SECRET | python3 -c "import sys,json; print(json.load(sys.stdin)['host'])")
REDIS_URL=rediss://...
ACTIVE_STORAGE_SERVICE=amazon
...
EOF

```

Pas besoin d'Ansible pour ça — le IAM Role de l'EC2 donne accès à Secrets Manager, et le user-data fait le travail. C'est même **plus robuste** qu'Ansible pour l'ASG, parce que ça fonctionne même si le runner CI est down au moment d'un scale-out.

---

### 🔴 Le vrai problème — `db:chatwoot_prepare` dans un ASG

C'est là que ça se complique. Cette commande doit tourner **une fois, sur une instance, avant le rolling update**. Elle ne doit pas tourner dans le user-data de chaque nouvelle instance (risque de conflits de migration si deux instances bootent en parallèle).
```

❌ Mauvais pattern :
user-data de chaque instance → db:chatwoot_prepare
→ Si 2 instances bootent en même temps : conflit de migration

✅ Bon pattern :
Pipeline CI → db:chatwoot_prepare sur 1 instance existante
→ puis Rolling Update ASG (nouvelles instances ne font PAS la migration)
Pour exécuter db:chatwoot_prepare sur une instance existante depuis le pipeline CI, deux approches existent, et AWS SSM Session Manager est supérieure à SSH+Ansible ici :

bash

# Dans le pipeline GitLab CI — sans Ansible, sans SSH, sans Bastion

aws ssm send-command \
 --document-name "AWS-RunShellScript" \
 --targets "Key=tag:aws:autoscaling:groupName,Values=chatwoot-production-asg" \
 --parameters 'commands=[
"cd /opt/chatwoot",
"docker compose run --rm rails bundle exec rails db:chatwoot_prepare"
]' \
 --max-concurrency "1" \ # ← exécuté sur 1 seule instance uniquement
--region eu-west-3

```

SSM ne nécessite ni SSH ouvert, ni Bastion, ni clé SSH dans les variables CI. L'agent SSM tourne sur l'instance et reçoit les commandes via l'API AWS.

---

### 📐 Où Ansible reste utile malgré tout

Ansible n'est pas inutile — il joue sur un **autre terrain** : la configuration OS, pas le déploiement applicatif.

| Tâche | User-data | Ansible | SSM |
|---|---|---|---|
| Installer Docker | ✅ Oui | Possible | Possible |
| Générer `.env` depuis Secrets Manager | ✅ Oui | Redondant | Possible |
| Démarrer les conteneurs | ✅ Oui | Redondant | Possible |
| SSH hardening (disable root, fail2ban) | Possible | ✅ Idéal | Possible |
| UFW / iptables | Possible | ✅ Idéal | Possible |
| `db:chatwoot_prepare` avant rolling update | ❌ Non | Possible mais lourd | ✅ Idéal |
| Configuration OS répétable et auditée | Fastidieux | ✅ Idéal | Limité |

La bonne pratique pour l'ASG est de **pré-cuire une AMI** (via Packer + Ansible) avec tout ce qui est configuration OS : Docker installé, SSH hardenisé, fail2ban configuré, UFW en place. Le user-data ne fait alors que la partie applicative (secrets + .env + containers).

---

### 🏆 Architecture recommandée pour ton projet
```

Packer + Ansible
↓
AMI "golden" : Ubuntu + Docker + SSH hardenisé + fail2ban + UFW
↓
Launch Template référence cette AMI
↓
User-data (léger) : secrets → .env → docker pull → docker compose up
↓
ASG utilise le Launch Template → chaque scale-out = instance prête en ~2 min

Pipeline CI pour un déploiement :

1. SSM → db:chatwoot_prepare sur 1 instance existante
2. Nouveau Launch Template (nouvelle version image)
3. ASG Instance Refresh → rolling update
   Conclusion directe
   Pour la gestion des variables d'environnement dans un ASG : non, tu n'as pas besoin d'Ansible. User-data + Secrets Manager + IAM Role gère ça proprement et de façon autonome à chaque scale-out.

Le playbook Ansible qu'on a créé est utile pour deux choses seulement dans ce contexte ASG :

La création de l'AMI (via Packer) — configuration OS initiale
Le staging "tout-en-un" (pas d'ASG, 1 seule EC2) — là Ansible est pertinent car l'instance est statique et connue
Il faudrait donc mettre à jour les tickets pour distinguer ces deux cas clairement. Tu veux que je le fasse ?

Alors on a pas besoin du playbook d'ansible pour ASG ni pour la création d'AMI pck on va en utiliser 1 qui a déjà docker.

2 mars

Recalibrated deployment strategy, scoping Ansible to staging only
Recalibrated deployment strategy, scoping Ansible to staging only
Très clair. Ça simplifie beaucoup. Voici ce que ça change concrètement :

Production ASG → user-data allégé (plus d'install Docker, juste secrets + .env + pull image + compose up)
Playbook Ansible → scoped uniquement au Staging (EC2 statique)
Ansible sécurité (SSH hardening, UFW, fail2ban) → reste valable sur toutes les instances, mais via un playbook dédié séparé du déploiement
Je mets à jour les deux tickets concernés directement.

A utilisé l'intégration Notion
A utilisé l'intégration Notion
Voilà, c'est mis à jour. En résumé de ce qui a changé :

User-data Production — le script ne contient plus d'installation Docker. Il démarre directement à l'étape "récupérer les secrets", ce qui rend le boot de chaque instance bien plus rapide.

Playbook Ansible — le scope est maintenant explicite dès le titre et le contenu : Staging uniquement, avec un tableau comparatif Production vs Staging au début pour que personne ne l'applique au mauvais endroit par erreur.

La règle simple à retenir pour ton projet :

AMI avec Docker → user-data s'allège à son strict minimum
EC2 statique (Staging) → Ansible
EC2 éphémère (ASG Production) → user-data + Secrets Manager + SSM pour les migrations
J'ai une question concernant le déploiement, est-ce qu'il est préférable de créer mes instances ec2 directement depuis terraform ou avec l'ASG je devrais plutôt éditer le launch template et laisser AWS gérer tout seul en fonction du nombre d'instance que je demande d'avoir ?
Réponds moi avec un point de vue professionnel

2 mars

Évalué l'architecture cloud entre déploiement direct et gestion automatisée
Évalué l'architecture cloud entre déploiement direct et gestion automatisée
La réponse courte : ASG + Launch Template, sans hésitation.
Créer des EC2 directement avec aws_instance en Terraform pour de la production, c'est une erreur d'architecture. Voici pourquoi.

Ce qui se passe si tu crées les EC2 directement via Terraform
Terraform devient le seul responsable de l'existence de tes instances. Ça crée une série de problèmes concrets :

Zéro tolérance aux pannes. Si une instance tombe (panne hardware AWS, OOM, crash OS), elle reste morte jusqu'à ce que quelqu'un relance un terraform apply. L'ASG, lui, détecte l'instance unhealthy via le health check ALB et en lance une nouvelle automatiquement, sans intervention humaine.

Zéro scaling. Si la charge augmente à 3h du matin, tu ne peux rien faire automatiquement. Avec l'ASG, une policy CPU > 70% peut scaler out sans que personne ne soit réveillé.

Le déploiement devient dangereux. Pour mettre à jour une instance gérée par Terraform, tu dois soit la détruire et la recréer (terraform taint), soit accepter une coupure. Avec l'ASG + Instance Refresh, AWS tourne les instances une par une en gardant l'ALB sain à tout moment — c'est le rolling update zero-downtime.

L'état Terraform diverge de la réalité. AWS peut remplacer une instance pour des raisons de maintenance. Terraform ne le sait pas, son state est désynchronisé, le prochain apply devient imprévisible.

Ce que Terraform doit gérer et ce qu'il ne doit pas gérer
C'est la distinction fondamentale.

Terraform gère l'infrastructure : le Launch Template, l'ASG (sa configuration, son min/max/desired, ses AZ, ses policies de scaling), l'ALB, les Target Groups, les Security Groups, RDS, Elasticache, S3, IAM. Tout ce qui est configuration déclarative et stable.

AWS gère le cycle de vie des instances : leur création, leur remplacement en cas de panne, leur rotation lors d'un rolling update. Les instances individuelles ne doivent jamais apparaître dans ton state Terraform.

En pratique, un déploiement avec cette architecture se résume à :

hcl

# Terraform crée une nouvelle version du Launch Template

# avec le nouveau user-data (nouvelle image Docker)

resource "aws_launch_template" "chatwoot" {
...
user_data = base64encode(templatefile("userdata.sh", {
CHATWOOT_VERSION = var.chatwoot_version # ← le seul paramètre qui change
}))
}

# L'ASG référence toujours la dernière version

resource "aws_autoscaling_group" "chatwoot" {
launch_template {
id = aws_launch_template.chatwoot.id
version = "$Latest"
}
}
Puis dans le pipeline CI :

bash

# Terraform applique la nouvelle version du Launch Template

terraform apply -var="chatwoot_version=${CI_COMMIT_SHA}"

# AWS SSM exécute les migrations sur une instance existante

aws ssm send-command ...db:chatwoot_prepare...

# L'Instance Refresh tourne les instances une par une

aws autoscaling start-instance-refresh \
 --auto-scaling-group-name chatwoot-production-asg \
 --preferences '{"MinHealthyPercentage": 50}'
Tu n'as jamais touché une instance directement. Terraform a juste mis à jour une configuration, AWS a fait le reste.

La règle professionnelle
Les instances EC2 dans un contexte de production sont du bétail, pas des animaux de compagnie. Tu ne les nommes pas, tu ne les répares pas, tu les remplaces.

aws_instance en Terraform, c'est pour un bastion, une instance de test, un cas très spécifique avec état local. Pour tout ce qui doit être disponible, scalable et déployable en zero-downtime, c'est ASG + Launch Template, point.

Donnes moi l'arborescence des fichiers et dossiers Terraform

2 mars

Architected modular Terraform structure spanning production and staging environments
Architected modular Terraform structure spanning production and staging environments
terraform/
│
├── backend.tf # Config backend S3 + DynamoDB (state distant)
├── versions.tf # Contraintes provider AWS + Terraform version
│
├── bootstrap/ # ← À appliquer UNE SEULE FOIS, manuellement
│ ├── main.tf # Crée le bucket S3 + table DynamoDB pour le state
│ ├── outputs.tf
│ └── variables.tf
│
├── modules/ # Modules réutilisables (pas d'état propre)
│ │
│ ├── networking/ # VPC, subnets, IGW, NAT GW, route tables
│ │ ├── main.tf
│ │ ├── variables.tf
│ │ └── outputs.tf
│ │
│ ├── security-groups/ # Tous les SG (ALB, EC2, RDS, Redis, Bastion)
│ │ ├── main.tf
│ │ ├── variables.tf
│ │ └── outputs.tf
│ │
│ ├── bastion/ # EC2 bastion (1 ou 2 selon l'env)
│ │ ├── main.tf
│ │ ├── variables.tf
│ │ └── outputs.tf
│ │
│ ├── alb/ # ALB + Target Group + Listeners + redirect HTTP→HTTPS
│ │ ├── main.tf
│ │ ├── variables.tf
│ │ └── outputs.tf
│ │
│ ├── asg/ # Launch Template + Auto Scaling Group + policies
│ │ ├── main.tf
│ │ ├── variables.tf
│ │ └── outputs.tf
│ │
│ ├── ec2/ # EC2 statique (Staging uniquement — pas d'ASG)
│ │ ├── main.tf
│ │ ├── variables.tf
│ │ └── outputs.tf
│ │
│ ├── rds/ # RDS PostgreSQL (multi_az en variable)
│ │ ├── main.tf
│ │ ├── variables.tf
│ │ └── outputs.tf
│ │
│ ├── elasticache/ # Redis (replication_group, multi_az en variable)
│ │ ├── main.tf
│ │ ├── variables.tf
│ │ └── outputs.tf
│ │
│ ├── s3/ # Bucket storage Chatwoot + lifecycle + policy IAM
│ │ ├── main.tf
│ │ ├── variables.tf
│ │ └── outputs.tf
│ │
│ ├── iam/ # Roles + Instance Profiles + Policies EC2
│ │ ├── main.tf
│ │ ├── variables.tf
│ │ └── outputs.tf
│ │
│ ├── acm/ # Certificat ACM + validation DNS
│ │ ├── main.tf
│ │ ├── variables.tf
│ │ └── outputs.tf
│ │
│ ├── route53/ # Enregistrements DNS (A alias → ALB)
│ │ ├── main.tf
│ │ ├── variables.tf
│ │ └── outputs.tf
│ │
│ └── secrets-manager/ # Création des secrets (vides) + rotation RDS
│ ├── main.tf
│ ├── variables.tf
│ └── outputs.tf
│
├── environments/
│ │
│ ├── production/ # Workspace production
│ │ ├── main.tf # Appels des modules avec les valeurs prod
│ │ ├── variables.tf # Déclaration des variables
│ │ ├── terraform.tfvars # Valeurs prod (committé — pas de secrets)
│ │ └── outputs.tf # Outputs utiles (ALB DNS, RDS endpoint…)
│ │
│ └── staging/ # Workspace staging
│ ├── main.tf # Appels des modules avec les valeurs staging
│ ├── variables.tf
│ ├── terraform.tfvars # Valeurs staging
│ └── outputs.tf
│
└── scripts/
└── userdata-production.sh # Script user-data référencé par le module asg
Quelques points d'architecture importants
bootstrap/ en dehors des environments — ce dossier est appliqué une seule fois manuellement avant tout le reste. Il crée le bucket S3 et la table DynamoDB qui vont stocker les states des autres workspaces. Il a son propre state local (.terraform/), jamais distant.

Un seul module rds, paramétré — la différence prod/staging passe par des variables, pas par deux modules séparés :

hcl

# environments/production/main.tf

module "rds" {
source = "../../modules/rds"
multi_az = true
...
}

# environments/staging/main.tf

module "rds" {
source = "../../modules/rds"
multi_az = false
...
}
Même logique pour networking (az_count = 2 en prod, az_count = 1 en staging), bastion (instance_count = 2 en prod, 1 en staging), et elasticache.

Pas de aws_instance dans les modules prod — le module ec2/ est appelé uniquement depuis environments/staging/main.tf. La production utilise exclusivement le module asg/.

terraform.tfvars commité, secrets jamais dedans — les valeurs non-sensibles (noms, tailles d'instance, régions, AZs) vivent dans terraform.tfvars. Les secrets (mots de passe) sont injectés via variables CI/CD GitLab au moment du terraform apply :

bash
terraform apply \
 -var="db_password=$TF_VAR_DB_PASSWORD" \
  -var="chatwoot_version=$CI_COMMIT_SHA"
Maintenant que tu as le contexte complet du projet, génères moi le contenu d'un fichier CLAUDE.md en détaillant toute l'architecture et les choix techniques qui sont fait. Tout ce qui pourra aider Claude code à avoir la meilleure compréhension du projet pour nous aider à créer la pipeline, les fichiers Terraform, Ansible et tout ce dont on aura besoin pour mener notre projet à bien tout en respectant les pratiques de sécurité, que je vais pouvoir mettre dans le repo de l'infrastructure et utiliser donc pour vscode avec claude code.

12:43

Pensant à documenter l'architecture complète, les choix techniques et les pratiques de sécurité pour un projet d'infrastructure
Pensant à documenter l'architecture complète, les choix techniques et les pratiques de sécurité pour un projet d'infrastructure
Le fichier est prêt. Il couvre 17 sections :

Vue d'ensemble — contexte client, canaux Chatwoot
Architecture globale — topologie réseau, tableau prod vs staging
Décisions d'architecture — les 8 règles absolues (ASG obligatoire, pgvector, db:chatwoot_prepare, S3, TLS Redis, SSM pour les migrations, Secrets Manager)
Structure du repository — arborescence complète avec annotations
Terraform — conventions, backend, nommage, tags, SG rules, RDS params, ASG config
Docker Compose — les deux fichiers complets (production sans postgres/redis, staging avec pgvector/pgvector:pg16)
Variables d'environnement — mapping complet prod/staging + structure Secrets Manager
Pipeline CI/CD — Git Flow, stages, séquences de déploiement, variables GitLab
Ansible — scope strict, règles de sécurité, ProxyJump
User-data — séquence exacte, ce qu'il ne fait PAS
Comportement Chatwoot — entrypoint rails.sh, health check
Monitoring — stack, exporters, alertes clés
Sécurité — règles réseau, secrets, OS, RGPD
DNS — URLs des environnements, ACM, Route53
Pièges connus — tableau symptôme/cause/solution
Commandes de référence — Terraform, Ansible, SSM, ASG refresh
Références — liens documentation officielle + Notion
À placer à la racine du repo infrastructure/ — Claude Code le lira automatiquement à chaque session.

Claude
Document · MD

Souhaitez-vous être averti lorsque Claude répond ?

Claude est une IA et peut faire des erreurs. Veuillez vérifier les réponses.
Claude · MD
Copier

# CLAUDE.md — Infrastructure Notakaren / Chatwoot

> Fichier de contexte pour Claude Code. Lire intégralement avant toute génération de code.

---

## 1. Vue d'ensemble du projet

**Client :** Notakaren — entreprise de support client externalisé  
**Application déployée :** [Chatwoot](https://github.com/chatwoot/chatwoot) (open-source, Rails + Sidekiq)  
**Objectif :** Déployer Chatwoot en production sur AWS, auto-hébergé, hautement disponible, conforme RGPD  
**Cloud provider :** AWS uniquement — région **eu-west-3 (Paris)**  
**Formation :** Bootcamp DevOps La Capsule — titre RNCP niveau 6

### Canaux gérés par Chatwoot

Chat web · Email · Facebook · Twitter/X · WhatsApp · Instagram

---

## 2. Architecture globale

### Topologie réseau

```
Internet
    │
    ▼
Application Load Balancer (public subnets, multi-AZ)
    │  HTTPS 443 → HTTP 80
    ▼
EC2 instances Chatwoot (private subnets, multi-AZ)
via Auto Scaling Group
    │
    ├──▶ RDS PostgreSQL 16 Multi-AZ (private subnet)
    ├──▶ Elasticache Redis Multi-AZ (private subnet)
    └──▶ S3 (stockage fichiers — ACTIVE_STORAGE_SERVICE=amazon)
```

### Deux environnements

|             | Production                             | Staging                                       |
| ----------- | -------------------------------------- | --------------------------------------------- |
| VPC         | Dédié prod                             | Dédié staging                                 |
| AZ          | 2 (eu-west-3a + eu-west-3b)            | 1 (eu-west-3a)                                |
| EC2         | ASG min 2 instances t3.micro           | 1 EC2 t3.micro statique                       |
| Postgres    | RDS PostgreSQL 16 Multi-AZ             | **Conteneur Docker** `pgvector/pgvector:pg16` |
| Redis       | Elasticache Redis Multi-AZ             | **Conteneur Docker** `redis:alpine`           |
| Bastion     | 2 (1 par AZ)                           | 1                                             |
| Storage     | S3 (`ACTIVE_STORAGE_SERVICE=amazon`)   | Local (`ACTIVE_STORAGE_SERVICE=local`)        |
| Déploiement | user-data + SSM + ASG Instance Refresh | Ansible via Bastion                           |

---

## 3. Décisions d'architecture — règles absolues

### 3.1 EC2 Production : ASG + Launch Template UNIQUEMENT

**Ne jamais créer d'`aws_instance` pour la production.** Les instances de production sont gérées exclusivement par l'Auto Scaling Group. Terraform gère la configuration (Launch Template, ASG), AWS gère le cycle de vie des instances.

```
✅ Correct  : aws_launch_template + aws_autoscaling_group
❌ Interdit : aws_instance pour les serveurs applicatifs production
```

Le module `modules/ec2/` existe uniquement pour le **Staging** (EC2 statique).

### 3.2 Base de données Production : RDS uniquement

Aucun conteneur postgres en production. RDS PostgreSQL 16 en subnet privé, Multi-AZ, sans accès public.

**Pourquoi PostgreSQL 16 ?** Chatwoot v4+ requiert l'extension `pgvector`. Sur RDS, pgvector est supporté nativement à partir de PostgreSQL 15. On utilise la version 16 pour être aligné avec l'image Docker `pgvector/pgvector:pg16` utilisée en staging.

### 3.3 Image Docker postgres en staging : pgvector/pgvector:pg16 OBLIGATOIRE

```yaml
# ✅ Correct
postgres:
  image: pgvector/pgvector:pg16

# ❌ Interdit — Chatwoot v4+ plantera au démarrage
postgres:
  image: postgres:16
```

### 3.4 Initialisation BDD : db:chatwoot_prepare UNIQUEMENT

```bash
# ✅ Toujours utiliser cette commande — idempotente
docker compose run --rm rails bundle exec rails db:chatwoot_prepare

# ❌ Ne jamais utiliser seul (erreurs sur fresh install)
rails db:migrate
```

`db:chatwoot_prepare` fait dans l'ordre : activation pgvector → db:create → db:schema:load → db:migrate → db:seed. Elle est **idempotente** : safe à relancer sur une base existante.

### 3.5 Stockage fichiers Production : S3 obligatoire

```bash
# ✅ Production
ACTIVE_STORAGE_SERVICE=amazon

# ❌ Local en production = perte des fichiers à chaque redéploiement
ACTIVE_STORAGE_SERVICE=local
```

Les conteneurs Docker sont éphémères. Avec `local`, tous les fichiers uploadés disparaissent à chaque `docker compose up`.

### 3.6 Redis TLS : syntaxe rediss://

```bash
# Elasticache avec TLS activé (production)
REDIS_URL=rediss://:6379/0   # double "s" obligatoire
REDIS_OPENSSL_VERIFY_MODE=none         # certificat auto-signé AWS

# Docker local (staging)
REDIS_URL=redis://redis:6379/0         # simple "s"
```

### 3.7 Migrations Production : SSM, pas SSH

Pour exécuter `db:chatwoot_prepare` sur une instance existante avant un rolling update, on utilise **AWS SSM Session Manager** — pas SSH, pas Ansible, pas de Bastion.

```bash
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets "Key=tag:aws:autoscaling:groupName,Values=chatwoot-production-asg" \
  --parameters 'commands=["cd /opt/chatwoot && docker compose run --rm rails bundle exec rails db:chatwoot_prepare"]' \
  --max-concurrency "1" \
  --region eu-west-3
```

### 3.8 Secrets : Parameter Store + IAM Role

Aucune clé, mot de passe ou secret ne doit apparaître :

- Dans le code Terraform (même dans les variables)
- Dans les fichiers `.env` commités
- Dans les logs des pipelines GitLab CI
- Dans le user-data en clair

Tout secret est stocké dans **Parameter Store** et récupéré au runtime par l'IAM Role attaché à l'EC2.

---

## 4. Structure du repository

```
infrastructure/                         ← Ce repo
│
├── CLAUDE.md                           ← Ce fichier
│
├── terraform/
│   ├── bootstrap/                      # Bucket S3 + DynamoDB pour le state
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   │
│   ├── modules/                        # Modules réutilisables
│   │   ├── networking/                 # VPC, subnets, IGW, NAT GW, route tables
│   │   ├── security-groups/            # SG ALB, EC2, RDS, Redis, Bastion
│   │   ├── bastion/                    # EC2 bastion (instance_count variable)
│   │   ├── alb/                        # ALB + Target Group + Listeners HTTPS
│   │   ├── asg/                        # Launch Template + ASG + scaling policies
│   │   ├── ec2/                        # EC2 statique (Staging uniquement)
│   │   ├── rds/                        # RDS PostgreSQL (multi_az en variable)
│   │   ├── elasticache/                # Redis (multi_az en variable)
│   │   ├── s3/                         # Bucket storage + lifecycle + IAM policy
│   │   ├── iam/                        # Roles + Instance Profiles + Policies
│   │   ├── acm/                        # Certificat ACM + validation Route53
│   │   ├── route53/                    # Enregistrements DNS
│   │   └── secrets-manager/            # Création des secrets (vides)
│   │
│   └── environments/
│       ├── production/                 # Workspace "production"
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── terraform.tfvars        # Valeurs non-sensibles commitées
│       │   └── outputs.tf
│       └── staging/                    # Workspace "staging"
│           ├── main.tf
│           ├── variables.tf
│           ├── terraform.tfvars
│           └── outputs.tf
│
├── ansible/
│   ├── playbooks/
│   │   ├── deploy-staging.yml          # Déploiement Chatwoot Staging uniquement
│   │   ├── secure-ssh.yml              # SSH hardening (tous les envs)
│   │   └── configure-firewall.yml      # UFW (tous les envs)
│   ├── templates/
│   │   └── chatwoot-staging.env.j2     # Template .env Staging
│   ├── files/
│   │   ├── docker-compose.production.yml
│   │   └── docker-compose.staging.yml
│   └── inventory/
│       ├── production.ini
│       └── staging.ini
│
├── scripts/
│   ├── userdata-production.sh          # User-data EC2 ASG Production
│   └── anonymize-dump.sh              # Anonymisation RGPD prod→staging
│
├── docker/
│   ├── docker-compose.production.yml   # Sans postgres/redis (RDS + Elasticache)
│   └── docker-compose.staging.yml      # Avec pgvector/pgvector:pg16 + redis:alpine
│
├── monitoring/
│   ├── prometheus/
│   │   ├── prometheus.yml
│   │   └── alerts/
│   │       ├── production.yml
│   │       └── staging.yml
│   └── grafana/
│       └── dashboards/
│           ├── staging.json
│           └── production.json
│
├── tests/
│   └── load/
│       └── locustfile.py
│
└── docs/
    ├── architecture.md
    ├── runbook-prod.md
    ├── rgpd.md
    └── adr/
        └── staging-database.md
```

---

## 5. Terraform — conventions et règles

### 5.1 Backend et workspaces

```hcl
# terraform/backend.tf — partagé entre les environments
terraform {
  backend "s3" {
    bucket         = "notakaren-terraform-state"
    key            = "chatwoot/${terraform.workspace}/terraform.tfstate"
    region         = "eu-west-3"
    dynamodb_table = "notakaren-terraform-locks"
    encrypt        = true
  }
}
```

Workspaces : `production` et `staging`. Jamais de state local en dehors du bootstrap.

### 5.2 Paramétrage prod vs staging via variables

Les modules sont **identiques** pour les deux environnements. La différence passe par des variables :

```hcl
# Production
module "rds" {
  source              = "../../modules/rds"
  multi_az            = true
  engine_version      = "16"
  instance_class      = "db.t3.micro"
  deletion_protection = true
}

# Staging
module "rds" {
  source              = "../../modules/rds"
  multi_az            = false
  engine_version      = "16"
  instance_class      = "db.t3.micro"
  deletion_protection = false
}
```

Variables typiquement paramétrées : `multi_az`, `instance_count`, `min_size`, `max_size`, `deletion_protection`, `backup_retention_period`.

### 5.3 Règles de nommage des ressources

```
{projet}-{environnement}-{ressource}
notakaren-production-vpc
notakaren-production-alb
notakaren-production-rds
notakaren-staging-ec2
```

### 5.4 Tags obligatoires sur toutes les ressources

```hcl
tags = {
  Name        = "notakaren-{env}-{resource}"
  Environment = "production" # ou "staging"
  Project     = "notakaren"
  ManagedBy   = "terraform"
}
```

### 5.5 Security Groups — règles absolues

```
SG ALB :
  IN  443 ← 0.0.0.0/0
  IN  80  ← 0.0.0.0/0 (redirection → 443)
  OUT 80  → SG EC2

SG EC2 :
  IN  80  ← SG ALB uniquement
  IN  22  ← SG Bastion uniquement
  OUT 5432 → SG RDS
  OUT 6379 → SG Redis
  OUT 443  → 0.0.0.0/0 (pull images, Secrets Manager, S3 via NAT)

SG RDS :
  IN  5432 ← SG EC2 uniquement — JAMAIS 0.0.0.0/0

SG Redis :
  IN  6379 ← SG EC2 uniquement — JAMAIS 0.0.0.0/0

SG Bastion :
  IN  22 ← CIDR équipe (liste blanche) uniquement
  OUT 22 → SG EC2
```

Utiliser des références SG-to-SG (`security_groups = [var.ec2_sg_id]`) plutôt que des CIDR pour les règles internes.

### 5.6 RDS — paramètres non négociables

```hcl
engine_version      = "16"          # PostgreSQL 16 — pgvector natif RDS
publicly_accessible = false         # Jamais public
multi_az            = true          # Production uniquement
storage_encrypted   = true
deletion_protection = true          # Production uniquement
skip_final_snapshot = false
backup_retention_period = 7
```

### 5.7 ASG et Launch Template

```hcl
resource "aws_autoscaling_group" "chatwoot" {
  min_size         = 2
  max_size         = 4
  desired_capacity = 2

  vpc_zone_identifier = var.private_subnet_ids  # Private subnets uniquement

  launch_template {
    id      = aws_launch_template.chatwoot.id
    version = "$Latest"
  }

  target_group_arns = [var.target_group_arn]

  health_check_type         = "ELB"     # Via l'ALB, pas EC2
  health_check_grace_period = 120       # Temps de démarrage Chatwoot

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }
}
```

**Ne pas créer de `aws_instance` pour la production.**

### 5.8 IAM — moindre privilège strict

```hcl
# Role EC2 Production — accès minimal
# Autorisé : Secrets Manager (secrets chatwoot/production/* uniquement)
# Autorisé : S3 (bucket chatwoot uniquement)
# Autorisé : SSM (pour les commandes distantes)
# Autorisé : CloudWatch Logs
# Interdit : AdministratorAccess, PowerUserAccess ou tout wildcard *
```

---

## 6. Docker Compose — deux fichiers distincts

### Production — `docker/docker-compose.production.yml`

**Pas de service `postgres` ni `redis`.** La connexion se fait vers RDS et Elasticache via les variables d'environnement du `.env`.

```yaml
version: "3"
services:
  base: &base
    image: ${CI_REGISTRY_IMAGE}:${CHATWOOT_VERSION:-latest}
    env_file: .env
    volumes:
      - storage_data:/app/storage

  rails:
    <<: *base
    # Pas de depends_on: postgres/redis
    ports:
      - "127.0.0.1:3000:3000"
    environment:
      - NODE_ENV=production
      - RAILS_ENV=production
      - INSTALLATION_ENV=docker
    entrypoint: docker/entrypoints/rails.sh
    command: ["bundle", "exec", "rails", "s", "-p", "3000", "-b", "0.0.0.0"]
    restart: always

  sidekiq:
    <<: *base
    # Pas de depends_on: postgres/redis
    environment:
      - NODE_ENV=production
      - RAILS_ENV=production
      - INSTALLATION_ENV=docker
    command: ["bundle", "exec", "sidekiq", "-C", "config/sidekiq.yml"]
    restart: always

volumes:
  storage_data:
  # Pas de postgres_data ni redis_data
```

### Staging — `docker/docker-compose.staging.yml`

**Image postgres : `pgvector/pgvector:pg16` — pas `postgres:16`.**

```yaml
version: "3"
services:
  base: &base
    image: ${CI_REGISTRY_IMAGE}:${CHATWOOT_VERSION:-latest}
    env_file: .env
    volumes:
      - storage_data:/app/storage

  rails:
    <<: *base
    depends_on:
      - postgres
      - redis
    ports:
      - "127.0.0.1:3000:3000"
    environment:
      - NODE_ENV=production
      - RAILS_ENV=production
      - INSTALLATION_ENV=docker
    entrypoint: docker/entrypoints/rails.sh
    command: ["bundle", "exec", "rails", "s", "-p", "3000", "-b", "0.0.0.0"]
    restart: always

  sidekiq:
    <<: *base
    depends_on:
      - postgres
      - redis
    environment:
      - NODE_ENV=production
      - RAILS_ENV=production
      - INSTALLATION_ENV=docker
    command: ["bundle", "exec", "sidekiq", "-C", "config/sidekiq.yml"]
    restart: always

  postgres:
    image: pgvector/pgvector:pg16 # OBLIGATOIRE — pas postgres:16
    restart: always
    ports:
      - "127.0.0.1:5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=chatwoot_staging
      - POSTGRES_USER=chatwoot
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

  redis:
    image: redis:alpine
    restart: always
    command: ["sh", "-c", 'redis-server --requirepass "$REDIS_PASSWORD"']
    env_file: .env
    volumes:
      - redis_data:/data
    ports:
      - "127.0.0.1:6379:6379"

volumes:
  storage_data:
  postgres_data:
  redis_data:
```

---

## 7. Variables d'environnement Chatwoot

### Mapping Production

```bash
# App
SECRET_KEY_BASE=   # généré avec openssl rand -hex 64
FRONTEND_URL=https://chat.notakaren.com
RAILS_ENV=production
NODE_ENV=production
INSTALLATION_ENV=docker
RAILS_LOG_TO_STDOUT=true

# PostgreSQL → RDS
POSTGRES_HOST=.eu-west-3.rds.amazonaws.com
POSTGRES_PORT=5432
POSTGRES_DATABASE=chatwoot_production
POSTGRES_USERNAME=chatwoot
POSTGRES_PASSWORD=

# Redis → Elasticache avec TLS
REDIS_URL=rediss://:6379/0   # double "s"
REDIS_OPENSSL_VERIFY_MODE=none

# Storage → S3 (obligatoire en production)
ACTIVE_STORAGE_SERVICE=amazon
S3_BUCKET_NAME=notakaren-chatwoot-production-storage
AWS_REGION=eu-west-3
# Pas de AWS_ACCESS_KEY_ID ni AWS_SECRET_ACCESS_KEY → IAM Role

# Divers
ENABLE_ACCOUNT_SIGNUP=false
DEFAULT_LOCALE=fr
CHATWOOT_VERSION=
```

### Mapping Staging

```bash
# Identique Production sauf :
FRONTEND_URL=https://staging.chat.notakaren.com
POSTGRES_HOST=postgres            # service Docker local
POSTGRES_DATABASE=chatwoot_staging
REDIS_URL=redis://redis:6379/0    # simple "s" — pas de TLS en local
ACTIVE_STORAGE_SERVICE=local      # acceptable — pas de rolling update
```

### Secrets Manager — structure des secrets

```
chatwoot/production/app     → SECRET_KEY_BASE, FRONTEND_URL
chatwoot/production/db      → host, username, password, database
chatwoot/production/redis   → url, auth_token
chatwoot/production/storage → s3_bucket_name
chatwoot/production/gitlab-registry → registry, token

chatwoot/staging/app        → (idem, valeurs staging)
chatwoot/staging/db         → (idem)
chatwoot/staging/redis      → password
```

---

## 8. Pipeline CI/CD GitLab

### Git Flow

```
feature/* → staging → main
```

- Push direct sur `main` : **interdit**
- Push direct sur `staging` : **interdit**
- Merge Request requis avec 1 reviewer minimum
- `staging` → `main` : déclenche le pipeline production (avec validation manuelle)

### Stages du pipeline

```yaml
stages:
  - test # RSpec + RuboCop + ESLint
  - sonar # SonarQube quality gate
  - build # docker build + push GitLab Container Registry
  - e2e # Tests E2E (branche staging uniquement)
  - load-test # Locust (manuel, staging uniquement)
  - terraform-plan
  - deploy-staging # Automatique sur push staging
  - terraform-apply # Manuel
  - deploy-prod # Manuel, sur main uniquement
```

### Déploiement Production — séquence obligatoire

```
1. terraform apply (nouveau Launch Template avec nouvelle image)
2. SSM → db:chatwoot_prepare sur 1 instance existante (max-concurrency 1)
3. RDS Snapshot (avant rolling update)
4. ASG Instance Refresh (rolling update, min_healthy_percentage=50)
5. Health check global → https://chat.notakaren.com/health
```

### Déploiement Staging — séquence

```
1. Ansible deploy-staging.yml via Bastion
   ├── Récupération secrets Secrets Manager
   ├── Génération .env
   ├── docker compose pull
   ├── docker compose up -d postgres redis (si pas déjà up)
   ├── db:chatwoot_prepare
   └── docker compose up -d rails sidekiq
2. Health check → https://staging.chat.notakaren.com/health
```

### Variables CI/CD GitLab (protégées + masquées)

```
AWS_ACCESS_KEY_ID          → accès AWS pour Terraform + SSM
AWS_SECRET_ACCESS_KEY
AWS_DEFAULT_REGION         = eu-west-3
SSH_PRIVATE_KEY            → accès Bastion Staging pour Ansible
TF_VAR_db_password         → injecté dans terraform apply
STAGING_BASTION_IP
PROD_BASTION_IP
SONAR_TOKEN
```

---

## 9. Ansible — périmètre et règles

### Scope strict

| Playbook                 | Cible                      | Description                  |
| ------------------------ | -------------------------- | ---------------------------- |
| `deploy-staging.yml`     | EC2 Staging uniquement     | Déploiement complet Chatwoot |
| `secure-ssh.yml`         | Tous bastions + toutes EC2 | SSH hardening                |
| `configure-firewall.yml` | Tous bastions + toutes EC2 | UFW                          |

**Ansible n'est PAS utilisé pour la Production applicative.** Le déploiement production est géré par user-data + SSM + ASG Instance Refresh.

### Connexion SSH — toujours via ProxyJump Bastion

```ini
# ansible/inventory/staging.ini
[chatwoot_staging]
chatwoot-staging ansible_host=10.1.1.10 \
  ansible_user=ubuntu \
  ansible_ssh_common_args='-J ubuntu@${STAGING_BASTION_IP}'
```

### Règles de sécurité Ansible

- `no_log: true` sur **toutes** les tâches manipulant des secrets
- Le `.env` est déployé avec `mode: '0600'`
- Les secrets viennent toujours d'AWS Secrets Manager, jamais de vars_files
- L'inventaire ne contient jamais d'IPs publiques directes (toujours via Bastion)

---

## 10. User-data Production (ASG)

### Prérequis AMI

L'AMI de base utilisée pour les instances de l'ASG **a Docker déjà installé**. Le user-data ne réinstalle pas Docker.

### Séquence user-data

```
1. Créer /opt/chatwoot/
2. Récupérer les secrets depuis Secrets Manager (IAM Role)
3. Générer /opt/chatwoot/.env (chmod 600)
4. Récupérer docker-compose.production.yml depuis S3
5. Login GitLab Container Registry (token depuis Secrets Manager)
6. docker compose pull rails sidekiq
7. docker compose up -d rails sidekiq
   ↳ PAS de db:chatwoot_prepare ici
8. Health check local localhost:3000/health (retry 20x, délai 10s)
```

### Ce que le user-data ne fait PAS

- N'installe pas Docker (déjà dans l'AMI)
- N'exécute pas `db:chatwoot_prepare` (géré par le pipeline CI via SSM)
- Ne contient aucun secret en clair

---

## 11. Comportement de Chatwoot au démarrage

### L'entrypoint `docker/entrypoints/rails.sh`

Avant de démarrer Rails, cet entrypoint :

1. Supprime `/app/tmp/pids/server.pid`
2. Exécute `pg_isready` en boucle jusqu'à ce que PostgreSQL réponde
3. Lance la commande passée en `CMD`

**Implication critique :** Si RDS n'est pas accessible (SG mal configuré, RDS pas encore `available`), le conteneur boucle indéfiniment sans erreur explicite. Toujours s'assurer que RDS est en état `available` et que les SG sont corrects avant de démarrer les conteneurs.

### Health check endpoint

```
GET /health → 200 OK si l'application est prête
```

C'est cet endpoint qui est utilisé par :

- L'ALB (Target Group health check, port 80, interval 30s)
- Le user-data (vérification locale)
- Le pipeline CI (vérification post-déploiement)
- Ansible (uri module)

---

## 12. Monitoring

### Stack

- **Prometheus** — collecte des métriques
- **Grafana** — dashboards (1 staging, 1 production)
- **Alertmanager** — notifications Slack + email

### Exporters

| Exporter          | Port | Cible                      |
| ----------------- | ---- | -------------------------- |
| node_exporter     | 9100 | Toutes les EC2             |
| postgres_exporter | 9187 | RDS (user read-only dédié) |
| redis_exporter    | 9121 | Elasticache                |

Les ports des exporters sont ouverts **uniquement vers Prometheus** (SG ou UFW).

### Alertes clés Production

```
CPU EC2 > 80% pendant 5min     → WARNING
CPU EC2 > 95% pendant 2min     → CRITICAL
/health ne répond pas 1min     → CRITICAL
RDS connexions > 90% du max    → WARNING
Redis mémoire > 90%            → WARNING
Sidekiq dead queue > 0 (10min) → WARNING
Disque EC2 > 85%               → WARNING
```

---

## 13. Sécurité — règles non négociables

### Réseau

- Les EC2 applicatives ne sont **jamais** accessibles depuis Internet
- RDS et Redis sont **toujours** en subnet privé, `publicly_accessible = false`
- L'accès SSH aux EC2 passe **obligatoirement** par le Bastion
- 2 Bastions en production (1 par AZ), 1 en staging

### Secrets

- Zéro secret dans le code, les fichiers `.env` commités, les logs
- Tout dans Parameter store
- Accès via IAM Role uniquement (pas de clés long terme sur les EC2)
- Rotation automatique des identifiants RDS

### OS

- Root login SSH désactivé (`PermitRootLogin no`)
- Authentification par mot de passe SSH désactivée
- Fail2ban configuré (ban après 3 échecs, durée 1h)
- UFW activé, politique `DENY` par défaut

### RGPD

- Infrastructure en eu-west-3 (Paris) → données en UE
- Anonymisation obligatoire avant import de données prod vers staging
- `ACTIVE_STORAGE_SERVICE=amazon` en prod → fichiers chiffrés dans S3 (SSE-S3)
- RDS chiffré at-rest (`storage_encrypted = true`)
- Logs sans données personnelles en clair

---

## 14. Domaines et DNS

| Environnement | URL                                  |
| ------------- | ------------------------------------ |
| Production    | `https://chat.notakaren.com`         |
| Staging       | `https://staging.chat.notakaren.com` |
| Grafana       | `https://grafana.notakaren.com`      |

- Certificats **ACM** validés via DNS (Route53)
- HTTPS forcé via redirection ALB 80 → 443
- Enregistrements DNS : type A alias vers l'ALB

---

## 15. Pièges connus et erreurs fréquentes

| Symptôme                                     | Cause                                                   | Solution                                                   |
| -------------------------------------------- | ------------------------------------------------------- | ---------------------------------------------------------- |
| Conteneur rails boucle au démarrage          | RDS pas prêt ou SG fermé                                | Vérifier état RDS + SG 5432 EC2→RDS                        |
| `PG::UndefinedFile: vector.control`          | Image `postgres:16` au lieu de `pgvector/pgvector:pg16` | Corriger l'image dans docker-compose.staging.yml           |
| Fichiers uploadés perdus après redéploiement | `ACTIVE_STORAGE_SERVICE=local` en production            | Passer à `amazon` + configurer S3                          |
| Erreur SSL Redis                             | `REDIS_URL=redis://` avec TLS activé sur Elasticache    | Utiliser `rediss://` (double s)                            |
| Conflits de migration sur scale-out          | `db:chatwoot_prepare` dans le user-data                 | Retirer du user-data, exécuter via SSM pipeline uniquement |
| State Terraform désynchronisé                | `aws_instance` détruites par AWS                        | Utiliser ASG, ne jamais gérer les EC2 prod directement     |
| Secrets visibles dans les logs GitLab        | `no_log: false` sur tâches Ansible avec secrets         | Ajouter `no_log: true`                                     |

---

## 16. Commandes de référence

```bash
# Terraform
terraform workspace select production
terraform init
terraform plan -var="chatwoot_version=$(git rev-parse HEAD)"
terraform apply -var="chatwoot_version=$(git rev-parse HEAD)"

# Ansible Staging (via pipeline ou manuel)
ansible-playbook ansible/playbooks/deploy-staging.yml \
  -i ansible/inventory/staging.ini \
  -e "chatwoot_version=$(git rev-parse HEAD)"

# SSM — migrations Production
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets "Key=tag:aws:autoscaling:groupName,Values=notakaren-production-asg" \
  --parameters 'commands=["cd /opt/chatwoot && docker compose run --rm rails bundle exec rails db:chatwoot_prepare"]' \
  --max-concurrency "1" \
  --region eu-west-3

# ASG Instance Refresh (rolling update Production)
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name notakaren-production-asg \
  --preferences '{"MinHealthyPercentage": 50, "InstanceWarmup": 120}' \
  --region eu-west-3

# Accès SSH Staging via Bastion
ssh -J ubuntu@ ubuntu@

# Logs user-data sur une instance
sudo cat /var/log/userdata.log

# Vérifier état Chatwoot
curl -I https://chat.notakaren.com/health
docker compose logs -f rails
docker compose logs -f sidekiq
```

---

## 17. Références

- **Repo Chatwoot :** https://github.com/chatwoot/chatwoot
- **Doc déploiement AWS :** https://developers.chatwoot.com/self-hosted/deployment/aws
- **Doc Docker :** https://developers.chatwoot.com/self-hosted/deployment/docker
- **Variables d'environnement :** https://developers.chatwoot.com/self-hosted/configuration/environment-variables
- **Migration vers v4 (pgvector) :** https://www.chatwoot.com/docs/self-hosted/runbooks/upgrade-to-chatwoot-v4/
- **Board Notion Notakaren :** https://www.notion.so/Sprint-Product-Backlog-Lite-b6251c5150d483dcabe201304ae02be7
  Claude
