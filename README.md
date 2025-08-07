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
3. **Clé SSH AWS** créée dans eu-west-3 
4. **Variables d'environnement** définies dans `~/.bashrc`:
   ```bash
   export TF_VAR_perplexity_api_key="your_perplexity_key"
   export TF_VAR_mongodb_uri="your_mongodb_connection_string"
   ```

## 🚀 Déploiement Initial

1. **Configuration**:
   ```bash
   cd ~/infra/aws/mbot/environments/prod
   # Éditez terraform.tfvars avec votre IP et nom de clé SSH
   ```

2. **Déploiement**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

3. **Vérification**:
   ```bash
   # L'application sera accessible sur l'IP publique affichée
   # Attendez ~3 minutes le démarrage des services
   ```

## 📁 Structure

```
~/infra/aws/mbot/
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
cd ~/infra/aws/mbot
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
0 2 * * * cd ~/infra/aws/mbot && ./scripts/backup.sh auto
```

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