# MBot Infrastructure AWS

Infrastructure Terraform pour déployer l'application MBot sur AWS EC2 avec configuration automatisée.

## 🏗️ Architecture

- **Instance EC2**: t3.small Ubuntu (optimisée coût/performance)
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
4. **Variables d'environnement** définies dans `~/.bashrc`:
   ```bash
   export TF_VAR_perplexity_api_key="your_perplexity_key"
   export TF_VAR_mongodb_uri="your_mongodb_connection_string"
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
   # Récupérer l'IP publique de l'EC2 depuis les outputs Terraform
   terraform output instance_public_ip
   
   # Ajouter cette IP dans MongoDB Atlas :
   # 1. Atlas Dashboard > Network Access > Add IP Address
   # 2. Ajouter l'IP de l'EC2 (ex: 13.38.50.18/32)
   # 3. Sauvegarder et attendre la propagation (~2 min)
   ```

4. **Vérification**:
   ```bash
   # L'application sera accessible sur l'IP publique affichée
   # Attendez ~3 minutes le démarrage des services
   # PUIS configurer MongoDB Atlas avant le premier test
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

### Gestion d'Instance (`./scripts/manage.sh`)

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

**Dashboard complet**:
```bash
./scripts/monitoring.sh dashboard
```

**Monitoring continu**:
```bash
./scripts/monitoring.sh         # Menu interactif
```

**Métriques spécifiques**:
```bash
./scripts/monitoring.sh health    # État instance AWS
./scripts/monitoring.sh metrics   # CPU/RAM/Disk
./scripts/monitoring.sh services  # Services mbot/nginx
./scripts/monitoring.sh logs      # Logs récents
```

### Sauvegarde (`./scripts/backup.sh`)

**Sauvegarde manuelle**:
```bash
./scripts/backup.sh create       # Créer snapshot
./scripts/backup.sh list         # Lister snapshots
./scripts/backup.sh cleanup      # Nettoyer anciens (>7j)
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

**Redéployer la dernière version depuis GitHub**:
```bash
./scripts/redeploy.sh deploy        # Télécharge et déploie la dernière version
./scripts/redeploy.sh               # Idem (commande par défaut)
```

**Gestion des versions**:
```bash
./scripts/redeploy.sh status        # État de l'application actuelle
./scripts/redeploy.sh rollback      # Revenir à la version précédente
./scripts/redeploy.sh help          # Aide détaillée
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
- Connexion: `ssh -i mbot-key.pem ubuntu@<IP_PUBLIQUE>`

### Variables Sensibles
- APIs keys dans variables d'environnement TF_VAR_*
- Jamais dans le code source
- Chargées automatiquement par Terraform

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
# 1. Obtenir l'IP publique de l'EC2
terraform output instance_public_ip

# 2. Ajouter cette IP dans MongoDB Atlas Network Access :
#    - Atlas Dashboard > Network Access > Add IP Address
#    - Ajouter l'IP de l'EC2 (format: xx.xx.xx.xx/32)
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
terraform output                  # Afficher les outputs
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