#!/bin/bash
# Script de redéploiement pour l'application MBot
# Télécharge et déploie la dernière version depuis GitHub

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../environments/prod"
GITHUB_REPO="https://github.com/ChristopherRuby/mbot.git"
ENV_SECRETS_FILE="$SCRIPT_DIR/../.env.secrets"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Fonction pour charger les variables d'environnement depuis .env.secrets
load_env_secrets() {
    if [ ! -f "$ENV_SECRETS_FILE" ]; then
        echo -e "${RED}❌ Fichier .env.secrets non trouvé: $ENV_SECRETS_FILE${NC}"
        echo "Copiez le template et remplissez vos valeurs :"
        echo "  cp .env.secrets.todo .env.secrets"
        echo "  # Éditez .env.secrets avec vos vraies valeurs"
        return 1
    fi
    
    # Exporter les variables pour Terraform et les scripts
    export $(grep -v '^#' "$ENV_SECRETS_FILE" | grep -v '^$' | xargs)
    export TF_VAR_perplexity_api_key="$PERPLEXITY_API_KEY"
    export TF_VAR_mongodb_uri="$MONGODB_URI"
    export TF_VAR_mongodb_database="$MONGODB_DATABASE"
    export TF_VAR_mongodb_collection="$MONGODB_COLLECTION"
    
    return 0
}

# Fonction pour obtenir l'IP publique depuis Terraform (priorité à l'EIP)
get_public_ip() {
    cd "$TERRAFORM_DIR"
    # Essayer d'abord l'Elastic IP
    PUBLIC_IP=$(terraform output -raw elastic_ip 2>/dev/null)
    
    # Si pas d'EIP, utiliser l'IP publique de l'instance
    if [ $? -ne 0 ] || [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" = "null" ]; then
        PUBLIC_IP=$(terraform output -raw instance_public_ip 2>/dev/null)
    fi
    
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
    
    # Charger les variables d'environnement
    echo -e "🔑 Chargement des variables d'environnement..."
    if ! load_env_secrets; then
        exit 1
    fi
    echo -e "✅ Variables chargées depuis .env.secrets"
    
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
    
    # Configuration du fichier .env sur l'EC2
    echo -e "🔧 Configuration du fichier .env sur l'EC2..."
    
    # Copier le fichier .env.secrets vers l'EC2
    scp -i ~/.ssh/mbot-key.pem "$ENV_SECRETS_FILE" ubuntu@$PUBLIC_IP:/tmp/.env.tmp || {
        echo -e "${RED}❌ Échec de la copie du fichier .env.secrets${NC}"
        exit 1
    }
    
    # Déplacer le fichier avec les bonnes permissions
    ssh -i ~/.ssh/mbot-key.pem ubuntu@$PUBLIC_IP "
        sudo mv /tmp/.env.tmp /home/mbot/app/.env &&
        sudo chown mbot:mbot /home/mbot/app/.env &&
        sudo chmod 600 /home/mbot/app/.env &&
        echo '✅ Fichier .env configuré'
    " || {
        echo -e "${RED}❌ Échec de la configuration du fichier .env${NC}"
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