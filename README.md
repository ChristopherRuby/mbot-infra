# MBot Infrastructure AWS

Infrastructure Terraform pour déployer l'application MBot sur AWS EC2 avec configuration automatisée.

## 🏗️ Architecture

- **Instance EC2**: t3.small Ubuntu (optimisée coût/performance)
- **Elastic IP**: IP publique fixe attachée à l'instance
- **Stockage**: EBS GP3 20GB
- **Réseau**: VPC, subnet public, Internet Gateway
- **Sécurité**: Security groups SSH/HTTP, clé SSH
- **Services**: Nginx proxy + Streamlit + systemd

## 📋 Prérequis

1. **AWS CLI configuré** avec vos credentials
2. **Terraform** installé (>= 1.0)
3. **Clé SSH AWS** (key-pair) créée dans eu-west-3 :
   ```bash
   # Vérifier si la key-pair existe déjà
   aws ec2 describe-key-pairs --key-name mbot-key --region eu-west-3 2>/dev/null || \
   
   # Créer la key-pair dans la région eu-west-3 (Paris)
   aws ec2 create-key-pair --key-name mbot-key --region eu-west-3 --query 'KeyMaterial' --output text > ~/.ssh/mbot-key.pem
   
   # Sécuriser la clé (requis par SSH)
   chmod 400 ~/.ssh/mbot-key.pem
   
   # Vérifier la création
   ls -la ~/.ssh/mbot-key.pem
   ``` 
4. **Fichier de secrets** configuré :
   ```bash
   # Copiez le template et remplissez vos valeurs
   cp .env.secrets.todo .env.secrets
   
   # Éditez .env.secrets avec vos vraies valeurs :
   # PERPLEXITY_API_KEY=pplx-xxxxx
   # MONGODB_URI=mongodb+srv://...
   # MONGODB_DATABASE=sample_mflix
   # MONGODB_COLLECTION=movies
   ```
5. **MongoDB Atlas configuré** :
   - **Whitelist IP** : Ajouter l'IP de l'EC2 dans MongoDB Atlas Network Access
   - ⚠️ **CRITIQUE** : Sans cette étape, l'application sera très lente (timeouts SSL 20-30s)
   - **Erreur typique** : `SSL handshake failed: [...].mongodb.net:27017`
   - L'IP de l'EC2 sera affichée après le `terraform apply`

## 🚀 Déploiement Initial

1. **Configuration**:
   ```bash
   cd ~/infra/aws/mbot-infra/environments/prod
   
   # Récupérer votre IP publique actuelle
   curl -s https://ipv4.icanhazip.com
   
   # Éditez terraform.tfvars avec votre IP et nom de clé SSH
   # Remplacez allowed_ssh_cidrs par ["VOTRE_IP/32"]
   ```

2. **Déploiement**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

3. **Configuration MongoDB Atlas** (OBLIGATOIRE):
   ```bash
   # Récupérer l'Elastic IP de l'EC2 depuis les outputs Terraform
   terraform output elastic_ip
   
   # Ajouter cette IP dans MongoDB Atlas :
   # 1. Atlas Dashboard > Network Access > Add IP Address
   # 2. Ajouter l'Elastic IP de l'EC2 (ex: 13.38.50.18/32)
   # 3. Sauvegarder et attendre la propagation (~2 min)
   
   # Note: Utilisez l'Elastic IP (fixe) plutôt que l'IP publique (variable)
   ```

4. **Vérification**:
   ```bash
   # L'application sera accessible sur l'Elastic IP (fixe)
   terraform output application_url
   # Attendez ~3 minutes le démarrage des services
   # PUIS configurer MongoDB Atlas avant le premier test
   ```

5. **Configuration HTTPS** (si vous avez un domaine):
   ```bash
   # Se connecter à l'instance
   ssh -i ~/.ssh/mbot-key.pem ubuntu@$(terraform output -raw elastic_ip)
   
   # Configurer HTTPS avec Let's Encrypt
   sudo apt update && sudo apt install -y certbot python3-certbot-nginx
   sudo certbot --nginx -d votre-domaine.com --non-interactive --agree-tos --email votre-email@domaine.com --redirect
   
   # Vérifier HTTPS
   curl -I https://votre-domaine.com
   ```

## 📁 Structure

```
~/infra/aws/mbot-infra/
├── environments/prod/          # Configuration production
│   ├── main.tf                # Point d'entrée Terraform
│   ├── terraform.tfvars       # Variables de configuration
│   └── outputs.tf             # Outputs (IP, SSH, etc.)
├── modules/
│   ├── vpc/                   # Module réseau VPC
│   ├── ec2/                   # Module instance EC2
│   └── security/              # Module groupes de sécurité
└── scripts/                   # Scripts de gestion
    ├── manage.sh              # Gestion instance (start/stop)
    ├── monitoring.sh          # Surveillance système
    └── backup.sh              # Sauvegarde EBS
```

## 🔧 Scripts de Gestion

### Variables d'Environnement (`./load-env.sh`)

**Script helper pour charger les variables d'environnement** :
```bash
# Charger les variables pour Terraform ou autres scripts
source ./load-env.sh

# Vérifier les variables chargées
echo $TF_VAR_perplexity_api_key
```

Ce script charge automatiquement les variables depuis `.env.secrets` et les exporte au format requis par Terraform (`TF_VAR_*`).

### Gestion d'Instance (`./scripts/manage.sh`)

**Aide et options disponibles**:
```bash
./scripts/manage.sh -h          # Afficher l'aide complète
./scripts/manage.sh help        # Afficher l'aide complète
```

**Mode interactif**:
```bash
cd ~/infra/aws/mbot-infra
./scripts/manage.sh
```

**Mode ligne de commande**:
```bash
./scripts/manage.sh status      # État de l'instance
./scripts/manage.sh start       # Démarrer l'instance
./scripts/manage.sh stop        # Arrêter l'instance (économie)
./scripts/manage.sh restart     # Redémarrage complet
./scripts/manage.sh quick       # Test rapide d'accès
```

### Monitoring (`./scripts/monitoring.sh`)

**Aide et options disponibles**:
```bash
./scripts/monitoring.sh -h        # Afficher l'aide complète
./scripts/monitoring.sh help      # Afficher l'aide complète
```

**Dashboard complet**:
```bash
./scripts/monitoring.sh dashboard
```

**Monitoring continu**:
```bash
./scripts/monitoring.sh           # Menu interactif
./scripts/monitoring.sh continuous # Monitoring continu
```

**Métriques spécifiques**:
```bash
./scripts/monitoring.sh health    # État instance AWS
./scripts/monitoring.sh metrics   # CPU/RAM/Disk
./scripts/monitoring.sh services  # Services mbot/nginx
./scripts/monitoring.sh logs      # Logs récents
```

### Sauvegarde (`./scripts/backup.sh`)

**Aide et options disponibles**:
```bash
./scripts/backup.sh -h           # Afficher l'aide complète
./scripts/backup.sh help         # Afficher l'aide complète
```

**Sauvegarde manuelle**:
```bash
./scripts/backup.sh create       # Créer snapshot
./scripts/backup.sh list         # Lister snapshots
./scripts/backup.sh cleanup      # Nettoyer anciens (>7j)
./scripts/backup.sh restore      # Infos restauration
./scripts/backup.sh costs        # Estimation coûts
```

**Sauvegarde automatique**:
```bash
./scripts/backup.sh auto         # Sauvegarde + nettoyage
```

**Planification (crontab)**:
```bash
# Sauvegarde quotidienne à 2h du matin
0 2 * * * cd ~/infra/aws/mbot-infra && ./scripts/backup.sh auto
```

### Redéploiement (`./scripts/redeploy.sh`)

**Aide et options disponibles**:
```bash
./scripts/redeploy.sh -h            # Afficher l'aide complète
./scripts/redeploy.sh help          # Afficher l'aide complète
```

**Redéployer la dernière version depuis GitHub**:
```bash
./scripts/redeploy.sh deploy        # Télécharge et déploie la dernière version
./scripts/redeploy.sh               # Idem (commande par défaut)
```

**Gestion des versions**:
```bash
./scripts/redeploy.sh status        # État de l'application actuelle
./scripts/redeploy.sh rollback      # Revenir à la version précédente
```

**Processus automatique** :
1. ✅ Arrêt du service MBot
2. ✅ Sauvegarde de l'ancienne version
3. ✅ Téléchargement depuis GitHub
4. ✅ Installation des dépendances Python
5. ✅ Configuration des variables d'environnement
6. ✅ Redémarrage du service
7. ✅ Vérification de l'application

## 💰 Optimisation des Coûts

### Instance t3.small (eu-west-3)
- **Allumée**: ~€0.022/heure (~€16/mois)
- **Arrêtée**: €0.00/heure (seul EBS facturé)
- **EBS 20GB**: ~€2/mois

### Stratégies d'Économie
- **Arrêt nocturne** (12h/jour): ~€8/mois économisés
- **Week-end arrêtée**: ~€3/mois économisés
- **Usage occasionnel**: jusqu'à €10/mois économisés

### Coût Total Estimé
- **Usage continu**: ~€18/mois
- **Usage optimisé**: ~€8-12/mois

## 🔐 Configuration HTTPS

L'application est configurée avec un certificat SSL Let's Encrypt pour un accès sécurisé en HTTPS.

### Configuration automatique

Si vous avez un nom de domaine pointant vers votre Elastic IP, vous pouvez configurer HTTPS facilement :

```bash
# 1. Se connecter à l'instance
ssh -i ~/.ssh/mbot-key.pem ubuntu@$(terraform output -raw elastic_ip)

# 2. Installer Certbot
sudo apt update && sudo apt install -y certbot python3-certbot-nginx

# 3. Obtenir le certificat SSL (remplacez par votre domaine)
sudo certbot --nginx -d votre-domaine.com --non-interactive --agree-tos --email votre-email@domaine.com --redirect
```

### Configuration manuelle Nginx

Si Certbot ne peut pas configurer automatiquement Nginx, voici la configuration manuelle :

**1. Obtenir le certificat uniquement :**
```bash
sudo certbot certonly --nginx -d votre-domaine.com --non-interactive --agree-tos --email votre-email@domaine.com
```

**2. Configurer Nginx manuellement :**
```bash
# Sauvegarder la configuration actuelle
sudo cp /etc/nginx/sites-available/mbot /etc/nginx/sites-available/mbot.backup

# Créer la nouvelle configuration HTTPS
sudo tee /etc/nginx/sites-available/mbot > /dev/null << 'EOF'
# HTTP to HTTPS redirect
server {
    listen 80;
    server_name votre-domaine.com;
    return 301 https://$server_name$request_uri;
}

# HTTPS configuration
server {
    listen 443 ssl;
    server_name votre-domaine.com;

    ssl_certificate /etc/letsencrypt/live/votre-domaine.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/votre-domaine.com/privkey.pem;
    
    # SSL security configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_timeout 10m;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;

    # Security headers
    add_header Strict-Transport-Security "max-age=63072000" always;
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";

    location / {
        proxy_pass http://localhost:8501;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        
        # WebSocket support for Streamlit
        proxy_read_timeout 86400;
    }
}
EOF

# Tester et recharger la configuration
sudo nginx -t && sudo systemctl reload nginx
```

### Vérification HTTPS

```bash
# Vérifier le certificat SSL
sudo certbot certificates

# Tester le renouvellement automatique
sudo certbot renew --dry-run

# Vérifier l'accès HTTPS
curl -I https://votre-domaine.com

# Vérifier la redirection HTTP->HTTPS
curl -I http://votre-domaine.com
```

### Renouvellement automatique

Le certificat Let's Encrypt se renouvelle automatiquement :

```bash
# Vérifier le timer de renouvellement
sudo systemctl status certbot.timer

# Logs de renouvellement
sudo journalctl -u certbot.service
```

### Sécurité HTTPS

La configuration inclut :
- **TLS 1.2/1.3** : Protocoles cryptographiques modernes
- **HSTS** : Force HTTPS pendant 2 ans (max-age=63072000)
- **Headers de sécurité** : Protection contre XSS, clickjacking, MIME sniffing
- **Perfect Forward Secrecy** : Chiffrement avec clés éphémères
- **WebSocket support** : Compatible avec Streamlit

### Dépannage HTTPS

**Certificat non reconnu :**
```bash
# Vérifier la configuration du domaine
dig votre-domaine.com

# Vérifier les logs Let's Encrypt
sudo tail -f /var/log/letsencrypt/letsencrypt.log
```

**Erreur Nginx :**
```bash
# Tester la configuration
sudo nginx -t

# Voir les logs d'erreur
sudo tail -f /var/log/nginx/error.log
```

**Renouvellement échoue :**
```bash
# Forcer le renouvellement
sudo certbot renew --force-renewal

# Debug mode
sudo certbot renew --dry-run --debug
```

## 🔄 Workflows Types

### Développement Quotidien
```bash
# 1. Démarrer l'instance le matin
./scripts/manage.sh start

# 2. Vérifier l'état
./scripts/manage.sh status

# 3. Monitoring si besoin
./scripts/monitoring.sh dashboard

# 4. Arrêter le soir pour économiser
./scripts/manage.sh stop
```

### Mise à Jour de l'Application
```bash
# 1. Redéployer la dernière version depuis GitHub
./scripts/redeploy.sh deploy

# 2. Vérifier le déploiement
./scripts/redeploy.sh status

# 3. En cas de problème, rollback
./scripts/redeploy.sh rollback
```

### Maintenance Hebdomadaire
```bash
# 1. Sauvegarde
./scripts/backup.sh create

# 2. Redémarrage pour nettoyage
./scripts/manage.sh restart

# 3. Vérification complète
./scripts/monitoring.sh dashboard

# 4. Nettoyage des sauvegardes anciennes
./scripts/backup.sh cleanup
```

## 🔐 Sécurité

### SSH
- Clé SSH obligatoire (pas de mot de passe)
- IP source restreinte dans terraform.tfvars
- Connexion: `ssh -i mbot-key.pem ubuntu@<ELASTIC_IP>`
- L'Elastic IP reste fixe même après redémarrage d'instance

### Variables Sensibles
- APIs keys dans le fichier `.env.secrets` (ignoré par Git)
- Jamais dans le code source ou commits
- Chargées automatiquement par les scripts de déploiement

### Sauvegardes
- Snapshots EBS chiffrés
- Rétention automatique (7 jours)
- Restauration via modification Terraform

## 🆘 Dépannage

### Instance ne démarre pas
```bash
# Vérifier les logs AWS
aws logs describe-log-groups
# Vérifier l'état détaillé
aws ec2 describe-instance-status --instance-ids <ID>
```

### Application inaccessible
```bash
# Vérifier les services sur l'instance
./scripts/monitoring.sh services
# Voir les logs récents
./scripts/monitoring.sh logs
```

### Application très lente / Timeouts MongoDB Atlas

**Symptômes caractéristiques** :
- Application très lente (20-30 secondes de délai)
- Timeouts SSL/TLS lors des requêtes MongoDB
- Erreur typique dans les logs : `SSL handshake failed: [...].mongodb.net:27017: [SSL: TLSV1_ALERT_INTERNAL_ERROR]`

**Diagnostic** :
```bash
# Vérifier les logs pour les erreurs MongoDB
./scripts/monitoring.sh logs | grep -i "mongodb\|ssl\|handshake\|timeout"

# Ou directement sur l'instance :
ssh -i mbot-key.pem ubuntu@<IP> "sudo journalctl -u mbot | grep -i mongodb"
```

**Solution** (CRITIQUE pour les performances) :
```bash
# 1. Obtenir l'Elastic IP de l'EC2
terraform output elastic_ip

# 2. Ajouter cette IP dans MongoDB Atlas Network Access :
#    - Atlas Dashboard > Network Access > Add IP Address
#    - Ajouter l'Elastic IP de l'EC2 (format: xx.xx.xx.xx/32)
#    - Sauvegarder et attendre la propagation (~2 minutes)

# 3. Redémarrer l'application
ssh -i mbot-key.pem ubuntu@<IP> "sudo systemctl restart mbot"

# 4. Vérifier la résolution
./scripts/monitoring.sh logs | tail -20
```

**Note importante** : Sans cette configuration, MongoDB Atlas bloque les connexions par défaut, causant des timeouts SSL qui ralentissent drastiquement l'application.

### Erreurs Terraform
```bash
# Rafraîchir l'état
terraform refresh
# Réimporter une ressource si besoin
terraform import aws_instance.mbot i-xxxxxxxxx
```

## 📚 Commandes Utiles

### Terraform
```bash
terraform plan                    # Prévisualiser les changements
terraform apply -auto-approve     # Appliquer sans confirmation
terraform destroy                 # Détruire l'infrastructure
terraform output                  # Afficher tous les outputs
terraform output elastic_ip       # Afficher l'Elastic IP
terraform state list              # Lister les ressources
```

### AWS CLI
```bash
aws ec2 describe-instances --instance-ids i-xxx
aws ec2 describe-snapshots --owner-ids self
aws logs tail /var/log/user-data.log --follow
```

### Gestion des Key-Pairs
```bash
# Lister les key-pairs
aws ec2 describe-key-pairs --region eu-west-3

# Supprimer une key-pair (ATTENTION: supprime aussi la clé AWS)
aws ec2 delete-key-pair --key-name mbot-key --region eu-west-3

# Re-créer la key-pair si supprimée
aws ec2 create-key-pair --key-name mbot-key --region eu-west-3 --query 'KeyMaterial' --output text > ~/.ssh/mbot-key.pem && chmod 400 ~/.ssh/mbot-key.pem
```

### SSH Direct
```bash
ssh -i mbot-key.pem ubuntu@<IP> "sudo systemctl status mbot"
ssh -i mbot-key.pem ubuntu@<IP> "sudo journalctl -u mbot -f"
```

## 🔧 Personnalisation

### Modifier la taille d'instance
Dans `terraform.tfvars`:
```hcl
instance_type = "t3.medium"  # Plus de puissance
```

### Changer la région
Dans `terraform.tfvars`:
```hcl
aws_region = "eu-west-1"     # Irlande au lieu de Paris
```

### Modifier les ports/sécurité
Dans `modules/security/main.tf`:
```hcl
# Ajouter HTTPS
ingress {
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = var.allowed_cidrs
}
```

## 📞 Support

En cas de problème:
1. Vérifiez les logs: `./scripts/monitoring.sh logs`
2. Consultez l'état: `./scripts/manage.sh status`
3. Redémarrez si nécessaire: `./scripts/manage.sh restart`
4. Vérifiez la configuration Terraform
5. Consultez les logs AWS CloudWatch

Cette infrastructure est conçue pour être simple, économique et facile à maintenir tout en étant robuste pour un usage production.