#!/bin/bash
# Script de gestion pour l'infrastructure Terraform MBot

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../environments/prod"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Fonction pour vérifier que Terraform est configuré
check_terraform() {
    if ! command -v terraform &> /dev/null; then
        echo -e "${RED}❌ Terraform non trouvé${NC}"
        echo "Installez Terraform: https://terraform.io/downloads"
        exit 1
    fi
    
    if [ ! -f "$TERRAFORM_DIR/terraform.tfstate" ]; then
        echo -e "${YELLOW}⚠️  État Terraform non trouvé${NC}"
        echo "Déployez d'abord votre infrastructure avec 'terraform apply'"
        return 1
    fi
    
    return 0
}

# Fonction pour obtenir l'ID de l'instance depuis Terraform
get_instance_id() {
    cd "$TERRAFORM_DIR"
    INSTANCE_ID=$(terraform output -raw instance_id 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$INSTANCE_ID" ]; then
        echo -e "${RED}❌ Impossible de récupérer l'Instance ID depuis Terraform${NC}"
        return 1
    fi
    
    echo "$INSTANCE_ID"
    return 0
}

# Fonction pour obtenir l'IP publique depuis Terraform
get_public_ip() {
    cd "$TERRAFORM_DIR"
    PUBLIC_IP=$(terraform output -raw instance_public_ip 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    echo "$PUBLIC_IP"
    return 0
}

# Fonction pour vérifier l'état de l'instance
check_instance_status() {
    echo -e "${BLUE}🔍 État de l'infrastructure${NC}"
    echo "=========================="
    
    if ! check_terraform; then
        return 1
    fi
    
    INSTANCE_ID=$(get_instance_id)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    echo "🆔 Instance ID: $INSTANCE_ID"
    
    # État de l'instance
    STATUS=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Erreur lors de la récupération de l'état${NC}"
        return 1
    fi
    
    PUBLIC_IP=$(get_public_ip)
    
    case $STATUS in
        "running")
            echo -e "${GREEN}✅ Instance: ACTIVE${NC}"
            if [ $? -eq 0 ] && [ -n "$PUBLIC_IP" ]; then
                echo -e "${GREEN}🌐 IP Publique: $PUBLIC_IP${NC}"
                echo -e "${GREEN}🎬 Application: http://$PUBLIC_IP${NC}"
            fi
            return 0
            ;;
        "stopped")
            echo -e "${YELLOW}🛑 Instance: ARRÊTÉE${NC}"
            return 1
            ;;
        "stopping")
            echo -e "${YELLOW}⏳ Instance: EN COURS D'ARRÊT${NC}"
            return 1
            ;;
        "pending")
            echo -e "${YELLOW}⏳ Instance: EN DÉMARRAGE${NC}"
            return 1
            ;;
        *)
            echo -e "${RED}❓ Instance: État inconnu ($STATUS)${NC}"
            return 1
            ;;
    esac
}

# Fonction pour démarrer l'instance
start_instance() {
    echo -e "${GREEN}🚀 Démarrage de l'instance${NC}"
    echo "========================="
    
    if ! check_terraform; then
        return 1
    fi
    
    INSTANCE_ID=$(get_instance_id)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    echo "🔄 Démarrage en cours..."
    aws ec2 start-instances --instance-ids $INSTANCE_ID >/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Commande de démarrage envoyée${NC}"
        echo -e "${BLUE}⏳ Attente du démarrage complet...${NC}"
        
        aws ec2 wait instance-running --instance-ids $INSTANCE_ID
        
        # Récupérer la nouvelle IP
        PUBLIC_IP=$(get_public_ip)
        if [ $? -eq 0 ] && [ -n "$PUBLIC_IP" ]; then
            echo -e "${GREEN}✅ Instance démarrée avec succès${NC}"
            echo -e "${GREEN}🌐 IP publique: $PUBLIC_IP${NC}"
            echo -e "${GREEN}🎬 Application: http://$PUBLIC_IP${NC}"
            echo -e "${BLUE}⏳ Attendez ~2-3 minutes que les services démarrent${NC}"
        else
            echo -e "${GREEN}✅ Instance démarrée${NC}"
            echo -e "${YELLOW}⏳ IP en cours d'assignation...${NC}"
        fi
    else
        echo -e "${RED}❌ Erreur lors du démarrage${NC}"
    fi
}

# Fonction pour arrêter l'instance
stop_instance() {
    echo -e "${YELLOW}🛑 Arrêt de l'instance${NC}"
    echo "===================="
    
    if ! check_terraform; then
        return 1
    fi
    
    INSTANCE_ID=$(get_instance_id)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    echo "🔄 Arrêt en cours..."
    aws ec2 stop-instances --instance-ids $INSTANCE_ID >/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Commande d'arrêt envoyée${NC}"
        echo -e "${BLUE}⏳ Attente de l'arrêt complet...${NC}"
        
        aws ec2 wait instance-stopped --instance-ids $INSTANCE_ID
        echo -e "${GREEN}✅ Instance arrêtée avec succès${NC}"
        echo -e "${YELLOW}💰 Économie: Facturation CPU/RAM arrêtée${NC}"
    else
        echo -e "${RED}❌ Erreur lors de l'arrêt${NC}"
    fi
}

# Fonction pour redémarrer l'instance
restart_instance() {
    echo -e "${YELLOW}🔄 Redémarrage de l'instance${NC}"
    echo "==========================="
    
    stop_instance
    if [ $? -eq 0 ]; then
        echo -e "${BLUE}⏳ Attente de 10 secondes...${NC}"
        sleep 10
        start_instance
    fi
}

# Fonction de monitoring rapide
quick_status() {
    if ! check_terraform; then
        return 1
    fi
    
    INSTANCE_ID=$(get_instance_id)
    PUBLIC_IP=$(get_public_ip)
    
    if [ $? -eq 0 ] && [ -n "$PUBLIC_IP" ]; then
        # Test rapide HTTP
        if curl -s --max-time 5 "http://$PUBLIC_IP" >/dev/null; then
            echo -e "${GREEN}✅ Application accessible sur http://$PUBLIC_IP${NC}"
        else
            echo -e "${RED}❌ Application non accessible${NC}"
        fi
    fi
}

# Fonction pour afficher les informations Terraform
show_terraform_info() {
    echo -e "${BLUE}🏗️ Informations Terraform${NC}"
    echo "========================="
    
    if ! check_terraform; then
        return 1
    fi
    
    cd "$TERRAFORM_DIR"
    
    echo -e "${YELLOW}📊 Outputs Terraform:${NC}"
    terraform output 2>/dev/null || echo "Pas d'outputs disponibles"
    
    echo ""
    echo -e "${YELLOW}📋 Ressources déployées:${NC}"
    terraform state list 2>/dev/null | head -10 || echo "État Terraform non accessible"
}

# Menu principal
show_menu() {
    echo -e "${BLUE}======================================${NC}"
    echo -e "${BLUE}🎬 Gestion MBot - Infrastructure Terraform${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo ""
    echo "1) 🔍 État de l'instance"
    echo "2) 🚀 Démarrer l'instance"
    echo "3) 🛑 Arrêter l'instance"
    echo "4) 🔄 Redémarrer l'instance"
    echo "5) ⚡ Test rapide d'accès"
    echo "6) 🏗️ Informations Terraform"
    echo "7) 💰 Estimation des coûts"
    echo "0) ❌ Quitter"
    echo ""
}

# Estimation des coûts
cost_estimation() {
    echo -e "${BLUE}💰 Estimation des coûts${NC}"
    echo "======================="
    echo ""
    echo "📊 Instance t3.small (eu-west-3) :"
    echo "   - En marche: ~€0.022/heure (~€16/mois)"
    echo "   - Arrêtée: €0.00/heure"
    echo "   - EBS 20GB: ~€2/mois"
    echo ""
    echo "💡 Économies avec start/stop :"
    echo "   - Arrêt 12h/jour: ~€8/mois économisé"
    echo "   - Week-end arrêtée: ~€3/mois économisé"
    echo "   - Usage occasionnel: jusqu'à €10/mois économisé"
    echo ""
    echo "🏗️ Coût total estimé: €18-25/mois selon usage"
}

# Configuration initiale
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI non trouvé${NC}"
    echo "Installez et configurez AWS CLI"
    exit 1
fi

# Boucle du menu principal
if [ "$1" = "status" ]; then
    check_instance_status
elif [ "$1" = "start" ]; then
    start_instance
elif [ "$1" = "stop" ]; then
    stop_instance
elif [ "$1" = "restart" ]; then
    restart_instance
elif [ "$1" = "quick" ]; then
    quick_status
else
    # Mode interactif
    while true; do
        show_menu
        read -p "Choisissez une option: " choice
        echo ""
        
        case $choice in
            1) check_instance_status ;;
            2) start_instance ;;
            3) stop_instance ;;
            4) restart_instance ;;
            5) quick_status ;;
            6) show_terraform_info ;;
            7) cost_estimation ;;
            0) echo -e "${GREEN}👋 Gestion terminée !${NC}"; exit 0 ;;
            *) echo -e "${RED}❌ Option invalide${NC}" ;;
        esac
        
        echo ""
        read -p "Appuyez sur Entrée pour continuer..."
        echo ""
    done
fi