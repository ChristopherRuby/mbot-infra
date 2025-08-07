#!/bin/bash
# Script de sauvegarde pour l'infrastructure Terraform MBot

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../environments/prod"
BACKUP_RETENTION_DAYS=7

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Fonction pour obtenir l'Instance ID depuis Terraform
get_instance_id() {
    cd "$TERRAFORM_DIR"
    INSTANCE_ID=$(terraform output -raw instance_id 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$INSTANCE_ID" ]; then
        return 1
    fi
    
    echo "$INSTANCE_ID"
    return 0
}

# Fonction pour obtenir l'ID du volume depuis l'instance
get_volume_id() {
    INSTANCE_ID=$(get_instance_id)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    VOLUME_ID=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --query 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId' \
        --output text 2>/dev/null)
    
    if [ $? -ne 0 ] || [ "$VOLUME_ID" = "None" ]; then
        return 1
    fi
    
    echo "$VOLUME_ID"
    return 0
}

# Fonction pour créer un snapshot
create_snapshot() {
    echo -e "${BLUE}💾 Création du snapshot de sauvegarde${NC}"
    echo "===================================="
    
    INSTANCE_ID=$(get_instance_id)
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Impossible de récupérer l'Instance ID${NC}"
        return 1
    fi
    
    VOLUME_ID=$(get_volume_id)
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Impossible de récupérer l'ID du volume${NC}"
        return 1
    fi
    
    echo "🖥️  Instance: $INSTANCE_ID"
    echo "💽 Volume: $VOLUME_ID"
    
    # Créer le snapshot avec timestamp
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    DESCRIPTION="mbot-backup-terraform-$TIMESTAMP"
    
    echo "📸 Création du snapshot..."
    SNAPSHOT_ID=$(aws ec2 create-snapshot \
        --volume-id $VOLUME_ID \
        --description "$DESCRIPTION" \
        --tag-specifications "ResourceType=snapshot,Tags=[{Key=Name,Value=$DESCRIPTION},{Key=Project,Value=mbot-terraform},{Key=Environment,Value=prod},{Key=ManagedBy,Value=terraform-scripts},{Key=CreatedBy,Value=backup-script}]" \
        --query 'SnapshotId' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$SNAPSHOT_ID" ]; then
        echo -e "${GREEN}✅ Snapshot créé avec succès: $SNAPSHOT_ID${NC}"
        echo "📝 Description: $DESCRIPTION"
        
        # Sauvegarder les informations localement
        BACKUP_INFO_FILE="$SCRIPT_DIR/last_backup.json"
        cat > "$BACKUP_INFO_FILE" << EOF
{
    "snapshot_id": "$SNAPSHOT_ID",
    "instance_id": "$INSTANCE_ID",
    "volume_id": "$VOLUME_ID",
    "created_at": "$(date -Iseconds)",
    "description": "$DESCRIPTION"
}
EOF
        echo "💾 Informations sauvegardées dans $BACKUP_INFO_FILE"
        
        # Attendre que le snapshot soit prêt si demandé
        if [ "$1" = "--wait" ]; then
            echo "⏳ Attente de la finalisation du snapshot..."
            aws ec2 wait snapshot-completed --snapshot-ids $SNAPSHOT_ID
            echo -e "${GREEN}✅ Snapshot finalisé${NC}"
        else
            echo "ℹ️  Le snapshot continue en arrière-plan"
        fi
        
        return 0
    else
        echo -e "${RED}❌ Erreur lors de la création du snapshot${NC}"
        return 1
    fi
}

# Fonction pour lister les snapshots
list_snapshots() {
    echo -e "${BLUE}📋 Snapshots de sauvegarde MBot${NC}"
    echo "==============================="
    
    SNAPSHOTS=$(aws ec2 describe-snapshots \
        --owner-ids self \
        --filters "Name=tag:Project,Values=mbot-terraform" \
        --query 'Snapshots[*].[SnapshotId,Description,StartTime,State,Progress,VolumeSize]' \
        --output table 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$SNAPSHOTS" ]; then
        echo "$SNAPSHOTS"
        echo ""
        
        # Compter les snapshots
        SNAPSHOT_COUNT=$(aws ec2 describe-snapshots \
            --owner-ids self \
            --filters "Name=tag:Project,Values=mbot-terraform" \
            --query 'length(Snapshots[])' \
            --output text 2>/dev/null)
        
        echo "📊 Total: $SNAPSHOT_COUNT snapshots"
        
        # Afficher le dernier backup local si disponible
        if [ -f "$SCRIPT_DIR/last_backup.json" ]; then
            echo ""
            echo -e "${BLUE}📁 Dernier backup local:${NC}"
            cat "$SCRIPT_DIR/last_backup.json" | jq . 2>/dev/null || cat "$SCRIPT_DIR/last_backup.json"
        fi
    else
        echo "❌ Aucun snapshot trouvé ou erreur"
    fi
}

# Fonction pour nettoyer les anciens snapshots
cleanup_old_snapshots() {
    echo -e "${BLUE}🧹 Nettoyage des anciens snapshots${NC}"
    echo "=================================="
    
    # Date limite
    CUTOFF_DATE=$(date -d "$BACKUP_RETENTION_DAYS days ago" +%Y-%m-%d)
    echo "📅 Suppression des snapshots antérieurs au: $CUTOFF_DATE"
    
    # Récupérer les snapshots anciens
    OLD_SNAPSHOTS=$(aws ec2 describe-snapshots \
        --owner-ids self \
        --filters "Name=tag:Project,Values=mbot-terraform" \
        --query "Snapshots[?StartTime<'$CUTOFF_DATE'].SnapshotId" \
        --output text 2>/dev/null)
    
    if [ -z "$OLD_SNAPSHOTS" ] || [ "$OLD_SNAPSHOTS" = "None" ]; then
        echo -e "${GREEN}✅ Aucun snapshot ancien à supprimer${NC}"
        return 0
    fi
    
    echo "🗑️  Snapshots à supprimer: $OLD_SNAPSHOTS"
    echo ""
    
    # Confirmation
    if [ "$1" != "--force" ]; then
        read -p "Confirmer la suppression ? (y/N): " -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "❌ Suppression annulée"
            return 1
        fi
    fi
    
    # Suppression
    for snapshot_id in $OLD_SNAPSHOTS; do
        echo "🗑️  Suppression du snapshot: $snapshot_id"
        aws ec2 delete-snapshot --snapshot-id $snapshot_id
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ Snapshot $snapshot_id supprimé${NC}"
        else
            echo -e "${RED}❌ Erreur lors de la suppression de $snapshot_id${NC}"
        fi
    done
}

# Fonction pour estimer les coûts
cost_estimation() {
    echo -e "${BLUE}💰 Estimation des coûts de sauvegarde${NC}"
    echo "===================================="
    
    # Récupérer la taille total des snapshots
    TOTAL_SIZE=$(aws ec2 describe-snapshots \
        --owner-ids self \
        --filters "Name=tag:Project,Values=mbot-terraform" \
        --query "sum(Snapshots[].VolumeSize)" \
        --output text 2>/dev/null)
    
    if [ -n "$TOTAL_SIZE" ] && [ "$TOTAL_SIZE" != "None" ]; then
        # Prix approximatif par GB/mois pour les snapshots EBS en eu-west-3
        PRICE_PER_GB=0.05
        
        MONTHLY_COST=$(echo "scale=2; $TOTAL_SIZE * $PRICE_PER_GB" | bc 2>/dev/null)
        
        echo "📊 Calcul basé sur :"
        echo "   - Snapshots totaux: ${TOTAL_SIZE}GB"
        echo "   - Prix: €${PRICE_PER_GB}/GB/mois (eu-west-3)"
        echo "   - Rétention: ${BACKUP_RETENTION_DAYS} jours"
        echo ""
        
        if [ -n "$MONTHLY_COST" ]; then
            echo "💰 Coût estimé: ~€${MONTHLY_COST}/mois"
        else
            echo "💰 Coût estimé: ~€$(echo "$TOTAL_SIZE * 0.05" | bc)/mois"
        fi
        echo ""
        echo "💡 Notes :"
        echo "   - Snapshots incrémentiaux (seules les modifications)"
        echo "   - Premier snapshot = taille complète du volume"
        echo "   - Snapshots suivants = seulement les changements"
        echo "   - Suppression automatique après $BACKUP_RETENTION_DAYS jours"
    else
        echo "❌ Impossible de calculer les coûts (pas de snapshots)"
    fi
}

# Fonction pour les informations de restauration
restore_info() {
    echo -e "${BLUE}🔄 Informations sur la restauration${NC}"
    echo "===================================="
    echo ""
    echo "Pour restaurer depuis un snapshot avec Terraform :"
    echo ""
    echo "1. 🛑 Détruire l'infrastructure actuelle :"
    echo "   cd $TERRAFORM_DIR"
    echo "   terraform destroy"
    echo ""
    echo "2. 📝 Modifier la configuration Terraform :"
    echo "   # Dans modules/ec2/main.tf, ajouter:"
    echo "   # snapshot_id = \"snap-xxxxxxxxx\""
    echo "   # dans la resource aws_ebs_volume"
    echo ""
    echo "3. 🚀 Redéployer l'infrastructure :"
    echo "   terraform apply"
    echo ""
    echo "4. ✅ L'instance démarrera avec les données du snapshot"
    echo ""
    echo -e "${YELLOW}⚠️  ATTENTION: Processus avancé${NC}"
    echo -e "${YELLOW}   Sauvegardez votre terraform.tfvars avant !${NC}"
    echo ""
    
    if [ -f "$SCRIPT_DIR/last_backup.json" ]; then
        echo -e "${BLUE}📁 Dernier snapshot disponible:${NC}"
        LAST_SNAPSHOT=$(cat "$SCRIPT_DIR/last_backup.json" | jq -r '.snapshot_id' 2>/dev/null)
        if [ -n "$LAST_SNAPSHOT" ]; then
            echo "   Snapshot ID: $LAST_SNAPSHOT"
        fi
    fi
}

# Menu principal
show_menu() {
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${BLUE}💾 Sauvegarde MBot - Infrastructure Terraform${NC}"
    echo -e "${BLUE}===========================================${NC}"
    echo ""
    echo "1) 💾 Créer une sauvegarde (snapshot)"
    echo "2) 📋 Lister les sauvegardes"
    echo "3) 🧹 Nettoyer les anciennes sauvegardes"
    echo "4) 🔄 Informations restauration"
    echo "5) 💰 Estimation des coûts"
    echo "6) ⚡ Sauvegarde + nettoyage automatique"
    echo "0) ❌ Quitter"
    echo ""
}

# Vérifier les prérequis
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI non trouvé${NC}"
    echo "Installez et configurez AWS CLI"
    exit 1
fi

if ! command -v terraform &> /dev/null; then
    echo -e "${RED}❌ Terraform non trouvé${NC}"
    echo "Installez Terraform"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}⚠️  'jq' recommandé pour un meilleur affichage${NC}"
fi

# Mode automatique ou interactif
if [ "$1" = "create" ]; then
    create_snapshot "$2"
elif [ "$1" = "list" ]; then
    list_snapshots
elif [ "$1" = "cleanup" ]; then
    cleanup_old_snapshots "$2"
elif [ "$1" = "auto" ]; then
    echo -e "${BLUE}🤖 Mode automatique - Sauvegarde + Nettoyage${NC}"
    create_snapshot
    if [ $? -eq 0 ]; then
        cleanup_old_snapshots --force
    fi
else
    # Mode interactif
    while true; do
        show_menu
        read -p "Choisissez une option: " choice
        echo ""
        
        case $choice in
            1) create_snapshot ;;
            2) list_snapshots ;;
            3) cleanup_old_snapshots ;;
            4) restore_info ;;
            5) cost_estimation ;;
            6) 
                create_snapshot
                if [ $? -eq 0 ]; then
                    echo ""
                    cleanup_old_snapshots
                fi
                ;;
            0) echo -e "${GREEN}👋 Sauvegarde terminée !${NC}"; exit 0 ;;
            *) echo -e "${RED}❌ Option invalide${NC}" ;;
        esac
        
        echo ""
        read -p "Appuyez sur Entrée pour continuer..."
        echo ""
    done
fi