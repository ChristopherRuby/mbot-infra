#!/bin/bash
# Script helper pour charger les variables d'environnement depuis .env.secrets
# Usage: source ./load-env.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
ENV_SECRETS_FILE="$SCRIPT_DIR/.env.secrets"

if [ ! -f "$ENV_SECRETS_FILE" ]; then
    echo "❌ Fichier .env.secrets non trouvé: $ENV_SECRETS_FILE"
    echo "Copiez le template et remplissez vos valeurs :"
    echo "  cp .env.secrets.todo .env.secrets"
    echo "  # Éditez .env.secrets avec vos vraies valeurs"
    return 1 2>/dev/null || exit 1
fi

# Charger les variables depuis .env.secrets
export $(grep -v '^#' "$ENV_SECRETS_FILE" | grep -v '^$' | xargs)

# Exporter les variables TF_VAR pour Terraform
export TF_VAR_perplexity_api_key="$PERPLEXITY_API_KEY"
export TF_VAR_mongodb_uri="$MONGODB_URI"
export TF_VAR_mongodb_database="$MONGODB_DATABASE"
export TF_VAR_mongodb_collection="$MONGODB_COLLECTION"

echo "✅ Variables d'environnement chargées depuis .env.secrets"
echo "   - PERPLEXITY_API_KEY: ${PERPLEXITY_API_KEY:0:10}..."
echo "   - MONGODB_URI: ${MONGODB_URI:0:20}..."
echo "   - MONGODB_DATABASE: $MONGODB_DATABASE"
echo "   - MONGODB_COLLECTION: $MONGODB_COLLECTION"