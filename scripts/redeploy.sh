#!/bin/bash
# Script de redéploiement pour l'application MBot
# Télécharge et déploie la dernière version depuis GitHub

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../environments/prod"
GITHUB_REPO="https://github.com/ChristopherRuby/mbot.git"

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
        echo -e "${RED}❌ Impossible de récupérer l'IP depuis Terraform${NC}"
        return 1
    fi
    
    echo "$PUBLIC_IP"
    return 0
}

# Fonction pour vérifier la connectivité SSH
check_ssh() {
    local ip=$1
    local ssh_key="$HOME/.ssh/mbot-key.pem"
    
    if [ ! -f "$ssh_key" ]; then
        echo -e "${RED}❌ Clé SSH non trouvée: $ssh_key${NC}"
        return 1
    fi
    
    ssh -i "$ssh_key" -o ConnectTimeout=10 -o BatchMode=yes ubuntu@$ip exit 2>/dev/null
    return $?
}

# Fonction de redéploiement
redeploy() {
    echo -e "${BLUE}🚀 Début du redéploiement MBot${NC}"
    echo "================================"
    
    # Obtenir l'IP de l'instance
    echo -e "🔍 Récupération de l'IP de l'instance..."
    PUBLIC_IP=$(get_public_ip)
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Échec de récupération de l'IP${NC}"
        exit 1
    fi
    echo -e "🌐 IP de l'instance: ${GREEN}$PUBLIC_IP${NC}"
    
    # Vérifier la connectivité SSH
    echo -e "🔑 Vérification de la connectivité SSH..."
    if ! check_ssh "$PUBLIC_IP"; then
        echo -e "${RED}❌ Impossible de se connecter en SSH${NC}"
        echo "Vérifiez que:"
        echo "1. L'instance est en marche"
        echo "2. La clé SSH ~/.ssh/mbot-key.pem existe et a les bonnes permissions"
        echo "3. Votre IP est autorisée dans le Security Group"
        exit 1
    fi
    echo -e "✅ SSH OK"
    
    # Arrêter le service MBot
    echo -e "🛑 Arrêt du service MBot..."
    ssh -i ~/.ssh/mbot-key.pem ubuntu@$PUBLIC_IP "sudo systemctl stop mbot" || {
        echo -e "${YELLOW}⚠️  Erreur lors de l'arrêt du service (peut-être déjà arrêté)${NC}"
    }
    
    # Sauvegarder l'ancienne version
    echo -e "💾 Sauvegarde de l'ancienne version..."
    ssh -i ~/.ssh/mbot-key.pem ubuntu@$PUBLIC_IP "
        sudo -u mbot bash -c 'cd /home/mbot && if [ -d app ]; then mv app app.backup.\$(date +%Y%m%d_%H%M%S); echo \"Sauvegarde créée: app.backup.\$(date +%Y%m%d_%H%M%S)\"; else echo \"Aucune version existante à sauvegarder\"; fi'
    "
    
    # Cloner la nouvelle version
    echo -e "📥 Téléchargement de la dernière version depuis GitHub..."
    ssh -i ~/.ssh/mbot-key.pem ubuntu@$PUBLIC_IP "
        sudo -u mbot bash -c 'cd /home/mbot && git clone $GITHUB_REPO app' &&
        echo '✅ Code téléchargé avec succès'
    " || {
        echo -e "${RED}❌ Échec du téléchargement${NC}"
        exit 1
    }
    
    # Installation des dépendances
    echo -e "📦 Installation des dépendances Python..."
    ssh -i ~/.ssh/mbot-key.pem ubuntu@$PUBLIC_IP "
        sudo -u mbot bash -c 'cd /home/mbot/app && python3 -m venv venv && ./venv/bin/pip install --upgrade pip && ./venv/bin/pip install -r requirements.txt' &&
        echo '✅ Dépendances installées'
    " || {
        echo -e "${RED}❌ Échec de l'installation des dépendances${NC}"
        exit 1
    }
    
    # Configuration des variables d'environnement
    echo -e "🔧 Configuration des variables d'environnement..."
    
    # Vérifier que les variables TF_VAR sont disponibles
    if [ -z "$TF_VAR_perplexity_api_key" ] || [ -z "$TF_VAR_mongodb_uri" ]; then
        echo -e "${YELLOW}⚠️  Variables TF_VAR non trouvées, chargement depuis ~/.bashrc...${NC}"
        source ~/.bashrc
    fi
    
    # Créer le fichier .env directement
    ssh -i ~/.ssh/mbot-key.pem ubuntu@$PUBLIC_IP "
        sudo -u mbot tee /home/mbot/app/.env > /dev/null << 'EOF'
PERPLEXITY_API_KEY=$TF_VAR_perplexity_api_key
MONGODB_URI=$TF_VAR_mongodb_uri
MONGODB_DATABASE=sample_mflix
MONGODB_COLLECTION=movies
EOF
        echo '✅ Variables d'environnement configurées'
    " || {
        echo -e "${RED}❌ Échec de la configuration${NC}"
        exit 1
    }
    
    # Redémarrer le service
    echo -e "🔄 Redémarrage du service MBot..."
    ssh -i ~/.ssh/mbot-key.pem ubuntu@$PUBLIC_IP "
        sudo systemctl start mbot &&
        sleep 3 &&
        sudo systemctl status mbot --no-pager
    " || {
        echo -e "${RED}❌ Échec du redémarrage du service${NC}"
        exit 1
    }
    
    # Vérifier que l'application répond
    echo -e "🌐 Vérification de l'application..."
    sleep 5
    
    if curl -f -s -o /dev/null http://$PUBLIC_IP; then
        echo -e "${GREEN}✅ Redéploiement réussi !${NC}"
        echo -e "🎬 Application accessible: ${GREEN}http://$PUBLIC_IP${NC}"
    else
        echo -e "${YELLOW}⚠️  Service démarré mais l'application peut mettre quelques secondes à répondre${NC}"
        echo -e "🎬 URL: http://$PUBLIC_IP"
    fi
    
    echo ""
    echo -e "${BLUE}📋 Actions post-déploiement recommandées:${NC}"
    echo "1. Vérifier les logs: ./scripts/monitoring.sh logs"
    echo "2. Tester l'application dans le navigateur"
    echo "3. Vérifier la connexion MongoDB Atlas si problème"
}

# Fonction d'aide
show_help() {
    echo -e "${BLUE}🚀 Script de redéploiement MBot${NC}"
    echo ""
    echo "Usage: $0 [option]"
    echo ""
    echo "Options:"
    echo "  deploy    - Redéployer l'application (par défaut)"
    echo "  status    - Vérifier l'état de l'application"
    echo "  rollback  - Revenir à la version précédente"
    echo "  help      - Afficher cette aide"
    echo ""
    echo "Exemples:"
    echo "  $0                # Redéploiement"
    echo "  $0 deploy         # Redéploiement explicite"
    echo "  $0 status         # État de l'application"
    echo "  $0 rollback       # Rollback vers version précédente"
}

# Fonction de rollback
rollback() {
    echo -e "${YELLOW}🔄 Rollback vers la version précédente${NC}"
    
    PUBLIC_IP=$(get_public_ip)
    if [ $? -ne 0 ]; then exit 1; fi
    
    # Trouver la dernière sauvegarde
    BACKUP_DIR=$(ssh -i ~/.ssh/mbot-key.pem ubuntu@$PUBLIC_IP "
        sudo -u mbot bash -c 'cd /home/mbot && ls -1d app.backup.* 2>/dev/null | sort -r | head -n1'
    ")
    
    if [ -z "$BACKUP_DIR" ]; then
        echo -e "${RED}❌ Aucune sauvegarde trouvée${NC}"
        exit 1
    fi
    
    echo -e "📦 Restauration depuis: $BACKUP_DIR"
    
    ssh -i ~/.ssh/mbot-key.pem ubuntu@$PUBLIC_IP "
        sudo systemctl stop mbot &&
        sudo -u mbot bash -c 'cd /home/mbot && rm -rf app && mv $BACKUP_DIR app' &&
        sudo systemctl start mbot
    "
    
    echo -e "${GREEN}✅ Rollback terminé${NC}"
}

# Fonction de status
show_status() {
    PUBLIC_IP=$(get_public_ip)
    if [ $? -ne 0 ]; then exit 1; fi
    
    echo -e "${BLUE}📊 État de l'application MBot${NC}"
    echo "=========================="
    
    # Status du service
    SERVICE_STATUS=$(ssh -i ~/.ssh/mbot-key.pem ubuntu@$PUBLIC_IP "systemctl is-active mbot 2>/dev/null || echo 'inactive'")
    if [ "$SERVICE_STATUS" = "active" ]; then
        echo -e "🤖 Service MBot: ${GREEN}ACTIF${NC}"
    else
        echo -e "🤖 Service MBot: ${RED}INACTIF${NC}"
    fi
    
    # Test HTTP
    if curl -f -s -o /dev/null --max-time 10 http://$PUBLIC_IP; then
        echo -e "🌐 Application web: ${GREEN}ACCESSIBLE${NC}"
    else
        echo -e "🌐 Application web: ${RED}INACCESSIBLE${NC}"
    fi
    
    echo -e "🔗 URL: http://$PUBLIC_IP"
    
    # Version du commit (si disponible)
    COMMIT=$(ssh -i ~/.ssh/mbot-key.pem ubuntu@$PUBLIC_IP "sudo -u mbot bash -c 'cd /home/mbot/app && git rev-parse --short HEAD 2>/dev/null' || echo 'N/A'")
    echo -e "📝 Version: $COMMIT"
}

# Point d'entrée principal
case "${1:-deploy}" in
    "deploy")
        redeploy
        ;;
    "status")
        show_status
        ;;
    "rollback")
        rollback
        ;;
    "help"|"-h"|"--help")
        show_help
        ;;
    *)
        echo -e "${RED}❌ Option inconnue: $1${NC}"
        show_help
        exit 1
        ;;
esac