#!/bin/bash
# Script de monitoring pour l'infrastructure Terraform MBot

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

# Fonction pour obtenir la commande SSH depuis Terraform
get_ssh_command() {
    cd "$TERRAFORM_DIR"
    SSH_COMMAND=$(terraform output -raw ssh_command 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    echo "$SSH_COMMAND"
    return 0
}

# Fonction pour vérifier l'état de l'instance
check_instance_health() {
    echo -e "${BLUE}🏥 État de santé de l'instance${NC}"
    echo "==============================="
    
    INSTANCE_ID=$(get_instance_id)
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Impossible de récupérer l'Instance ID${NC}"
        return 1
    fi
    
    # État de l'instance
    INSTANCE_STATUS=$(aws ec2 describe-instance-status \
        --instance-ids $INSTANCE_ID \
        --query 'InstanceStatuses[0].InstanceStatus.Status' \
        --output text 2>/dev/null)
    
    SYSTEM_STATUS=$(aws ec2 describe-instance-status \
        --instance-ids $INSTANCE_ID \
        --query 'InstanceStatuses[0].SystemStatus.Status' \
        --output text 2>/dev/null)
    
    if [ "$INSTANCE_STATUS" = "ok" ]; then
        echo -e "${GREEN}✅ Instance Status: OK${NC}"
    elif [ "$INSTANCE_STATUS" = "None" ]; then
        echo -e "${YELLOW}⏳ Instance Status: En cours d'initialisation${NC}"
    else
        echo -e "${RED}❌ Instance Status: $INSTANCE_STATUS${NC}"
    fi
    
    if [ "$SYSTEM_STATUS" = "ok" ]; then
        echo -e "${GREEN}✅ System Status: OK${NC}"
    elif [ "$SYSTEM_STATUS" = "None" ]; then
        echo -e "${YELLOW}⏳ System Status: En cours d'initialisation${NC}"
    else
        echo -e "${RED}❌ System Status: $SYSTEM_STATUS${NC}"
    fi
}

# Fonction pour vérifier les métriques système via SSH
check_system_metrics() {
    echo -e "${BLUE}📊 Métriques système${NC}"
    echo "===================="
    
    PUBLIC_IP=$(get_public_ip)
    if [ $? -ne 0 ] || [ -z "$PUBLIC_IP" ]; then
        echo -e "${RED}❌ IP publique non disponible${NC}"
        return 1
    fi
    
    # Construire la commande SSH
    SSH_KEY_PATH="$HOME/.ssh/mbot-key.pem"
    
    if [ ! -f "$SSH_KEY_PATH" ]; then
        echo -e "${RED}❌ Clé SSH non trouvée: $SSH_KEY_PATH${NC}"
        return 1
    fi
    
    # Test de connectivité SSH
    if ! ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@$PUBLIC_IP "echo 'SSH OK'" &>/dev/null; then
        echo -e "${RED}❌ Impossible de se connecter en SSH${NC}"
        return 1
    fi
    
    echo "🔗 Connexion SSH établie"
    
    # CPU Usage
    echo -n "🖥️  CPU: "
    CPU_USAGE=$(ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@$PUBLIC_IP \
        "top -bn1 | grep 'Cpu(s)' | awk '{print \$2 + \$4}'" 2>/dev/null)
    
    if [ -n "$CPU_USAGE" ]; then
        if (( $(echo "$CPU_USAGE > 80" | bc -l) 2>/dev/null )); then
            echo -e "${RED}${CPU_USAGE}% (CRITIQUE)${NC}"
        elif (( $(echo "$CPU_USAGE > 60" | bc -l) 2>/dev/null )); then
            echo -e "${YELLOW}${CPU_USAGE}% (ÉLEVÉ)${NC}"
        else
            echo -e "${GREEN}${CPU_USAGE}%${NC}"
        fi
    else
        echo -e "${YELLOW}Non disponible${NC}"
    fi
    
    # RAM Usage
    echo -n "💾 RAM: "
    RAM_INFO=$(ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@$PUBLIC_IP \
        "free | grep Mem | awk '{printf \"%.0f %.0f\", \$3/\$2 * 100.0, \$2/1024/1024}'" 2>/dev/null)
    
    if [ -n "$RAM_INFO" ]; then
        RAM_PERCENT=$(echo $RAM_INFO | cut -d' ' -f1)
        RAM_TOTAL=$(echo $RAM_INFO | cut -d' ' -f2)
        
        if (( $(echo "$RAM_PERCENT > 85" | bc -l) 2>/dev/null )); then
            echo -e "${RED}${RAM_PERCENT}% de ${RAM_TOTAL}GB (CRITIQUE)${NC}"
        elif (( $(echo "$RAM_PERCENT > 70" | bc -l) 2>/dev/null )); then
            echo -e "${YELLOW}${RAM_PERCENT}% de ${RAM_TOTAL}GB (ÉLEVÉ)${NC}"
        else
            echo -e "${GREEN}${RAM_PERCENT}% de ${RAM_TOTAL}GB${NC}"
        fi
    else
        echo -e "${YELLOW}Non disponible${NC}"
    fi
    
    # Disk Usage
    echo -n "💽 Disque: "
    DISK_USAGE=$(ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@$PUBLIC_IP \
        "df -h / | tail -1 | awk '{print \$5}' | sed 's/%//'" 2>/dev/null)
    
    if [ -n "$DISK_USAGE" ]; then
        if (( $DISK_USAGE > 85 )); then
            echo -e "${RED}${DISK_USAGE}% (CRITIQUE)${NC}"
        elif (( $DISK_USAGE > 70 )); then
            echo -e "${YELLOW}${DISK_USAGE}% (ÉLEVÉ)${NC}"
        else
            echo -e "${GREEN}${DISK_USAGE}%${NC}"
        fi
    else
        echo -e "${YELLOW}Non disponible${NC}"
    fi
}

# Fonction pour vérifier les services
check_services_status() {
    echo -e "${BLUE}🔄 État des services${NC}"
    echo "===================="
    
    PUBLIC_IP=$(get_public_ip)
    if [ $? -ne 0 ] || [ -z "$PUBLIC_IP" ]; then
        echo -e "${RED}❌ IP publique non disponible${NC}"
        return 1
    fi
    
    SSH_KEY_PATH="$HOME/.ssh/mbot-key.pem"
    
    if [ ! -f "$SSH_KEY_PATH" ]; then
        echo -e "${RED}❌ Clé SSH non trouvée${NC}"
        return 1
    fi
    
    # Service mbot
    echo -n "🤖 Service mbot: "
    MBOT_STATUS=$(ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@$PUBLIC_IP \
        "sudo systemctl is-active mbot" 2>/dev/null)
    
    if [ "$MBOT_STATUS" = "active" ]; then
        echo -e "${GREEN}ACTIF${NC}"
    else
        echo -e "${RED}$MBOT_STATUS${NC}"
    fi
    
    # Service nginx
    echo -n "🌐 Service nginx: "
    NGINX_STATUS=$(ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@$PUBLIC_IP \
        "sudo systemctl is-active nginx" 2>/dev/null)
    
    if [ "$NGINX_STATUS" = "active" ]; then
        echo -e "${GREEN}ACTIF${NC}"
    else
        echo -e "${RED}$NGINX_STATUS${NC}"
    fi
    
    # Test HTTP
    echo -n "🌍 Application web: "
    if curl -s --max-time 10 "http://$PUBLIC_IP" >/dev/null; then
        echo -e "${GREEN}ACCESSIBLE${NC}"
    else
        echo -e "${RED}INACCESSIBLE${NC}"
    fi
}

# Fonction pour afficher les logs
show_recent_logs() {
    echo -e "${BLUE}📜 Logs récents${NC}"
    echo "==============="
    
    PUBLIC_IP=$(get_public_ip)
    if [ $? -ne 0 ] || [ -z "$PUBLIC_IP" ]; then
        echo -e "${RED}❌ IP publique non disponible${NC}"
        return 1
    fi
    
    SSH_KEY_PATH="$HOME/.ssh/mbot-key.pem"
    
    if [ ! -f "$SSH_KEY_PATH" ]; then
        echo -e "${RED}❌ Clé SSH non trouvée${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}--- Logs mbot (10 dernières lignes) ---${NC}"
    ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@$PUBLIC_IP \
        "sudo journalctl -u mbot -n 10 --no-pager" 2>/dev/null || echo "Impossible de récupérer les logs mbot"
    
    echo ""
    echo -e "${YELLOW}--- Logs système récents ---${NC}"
    ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@$PUBLIC_IP \
        "sudo journalctl -n 5 --no-pager" 2>/dev/null || echo "Impossible de récupérer les logs système"
}

# Fonction pour le monitoring continu
continuous_monitoring() {
    echo -e "${BLUE}🔄 Monitoring continu (CTRL+C pour arrêter)${NC}"
    echo "=============================================="
    
    while true; do
        clear
        echo -e "${BLUE}📊 Monitoring - $(date)${NC}"
        echo "================================="
        
        check_instance_health
        echo ""
        check_system_metrics
        echo ""
        check_services_status
        
        echo ""
        echo "Prochaine vérification dans 30 secondes..."
        sleep 30
    done
}

# Fonction pour afficher un dashboard
show_dashboard() {
    clear
    echo -e "${BLUE}🎬 Dashboard MBot - $(date)${NC}"
    echo "================================="
    
    # Informations Terraform
    PUBLIC_IP=$(get_public_ip)
    INSTANCE_ID=$(get_instance_id)
    
    if [ $? -eq 0 ] && [ -n "$PUBLIC_IP" ]; then
        echo -e "${GREEN}🌐 Application: http://$PUBLIC_IP${NC}"
        echo -e "${BLUE}🆔 Instance: $INSTANCE_ID${NC}"
        echo ""
    fi
    
    check_instance_health
    echo ""
    check_system_metrics  
    echo ""
    check_services_status
}

# Menu principal
show_menu() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}📊 Monitoring MBot - Infrastructure Terraform${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "1) 🏥 État de santé de l'instance"
    echo "2) 📊 Métriques système"
    echo "3) 🔄 État des services"
    echo "4) 📜 Logs récents"
    echo "5) 📋 Dashboard complet"
    echo "6) 🔄 Monitoring continu"
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

# Mode automatique ou interactif
if [ "$1" = "dashboard" ]; then
    show_dashboard
elif [ "$1" = "health" ]; then
    check_instance_health
elif [ "$1" = "metrics" ]; then
    check_system_metrics
elif [ "$1" = "services" ]; then
    check_services_status
elif [ "$1" = "logs" ]; then
    show_recent_logs
else
    # Mode interactif
    while true; do
        show_menu
        read -p "Choisissez une option: " choice
        echo ""
        
        case $choice in
            1) check_instance_health ;;
            2) check_system_metrics ;;
            3) check_services_status ;;
            4) show_recent_logs ;;
            5) show_dashboard ;;
            6) continuous_monitoring ;;
            0) echo -e "${GREEN}👋 Monitoring terminé !${NC}"; exit 0 ;;
            *) echo -e "${RED}❌ Option invalide${NC}" ;;
        esac
        
        if [ "$choice" != "5" ] && [ "$choice" != "6" ]; then
            echo ""
            read -p "Appuyez sur Entrée pour continuer..."
            echo ""
        fi
    done
fi