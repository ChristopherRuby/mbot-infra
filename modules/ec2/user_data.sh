#!/bin/bash

# Logs de démarrage
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# Mise à jour du système
apt-get update
apt-get upgrade -y

# Installation des dépendances
apt-get install -y python3 python3-pip python3-venv git nginx curl certbot python3-certbot-nginx

# Création de l'utilisateur mbot
useradd -m -s /bin/bash mbot
mkdir -p /home/mbot/app
chown mbot:mbot /home/mbot/app

# Clonage du repository
cd /home/mbot
sudo -u mbot git clone ${github_repo} app

# Installation Python et dépendances
cd /home/mbot/app
sudo -u mbot python3 -m venv venv
sudo -u mbot ./venv/bin/pip install --upgrade pip
sudo -u mbot ./venv/bin/pip install -r requirements.txt

# Configuration des variables d'environnement
sudo -u mbot cat > /home/mbot/app/.env << EOF
PERPLEXITY_API_KEY=${perplexity_api_key}
MONGODB_URI=${mongodb_uri}
MONGODB_DATABASE=${mongodb_database}
MONGODB_COLLECTION=${mongodb_collection}
EOF

# Configuration du service systemd
cat > /etc/systemd/system/mbot.service << EOF
[Unit]
Description=MBot Chatbot Application
After=network.target

[Service]
Type=exec
User=mbot
Group=mbot
WorkingDirectory=/home/mbot/app
Environment=PATH=/home/mbot/app/venv/bin
ExecStart=/home/mbot/app/venv/bin/streamlit run app.py --server.port=8501 --server.address=0.0.0.0
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Configuration Nginx
cat > /etc/nginx/sites-available/mbot << EOF
server {
    listen 80;
    server_name ${domain_name};

    location / {
        proxy_pass http://localhost:8501;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

# Activation de la configuration Nginx
ln -s /etc/nginx/sites-available/mbot /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test de la configuration Nginx
nginx -t

# Démarrage des services
systemctl daemon-reload
systemctl enable mbot
systemctl start mbot
systemctl enable nginx
systemctl restart nginx

# Attendre que les services démarrent
sleep 10

# Vérification des services
systemctl status mbot
systemctl status nginx

echo "Déploiement terminé. Application accessible sur port 80."

# Attendre que l'application soit complètement opérationnelle
sleep 30

# Configuration SSL avec Let's Encrypt (avec retry)
echo "Configuration SSL avec Let's Encrypt..."
SSL_RETRY_COUNT=0
SSL_MAX_RETRIES=3

while [ $SSL_RETRY_COUNT -lt $SSL_MAX_RETRIES ]; do
    if certbot --nginx -d ${domain_name} --email ${ssl_email} --agree-tos --non-interactive --redirect; then
        echo "SSL configuré avec succès!"
        systemctl reload nginx
        break
    else
        SSL_RETRY_COUNT=$((SSL_RETRY_COUNT + 1))
        echo "Échec de la configuration SSL, tentative $SSL_RETRY_COUNT/$SSL_MAX_RETRIES"
        if [ $SSL_RETRY_COUNT -lt $SSL_MAX_RETRIES ]; then
            echo "Nouvelle tentative dans 60 secondes..."
            sleep 60
        else
            echo "Configuration SSL échouée après $SSL_MAX_RETRIES tentatives."
            echo "Vous pouvez configurer SSL manuellement plus tard avec:"
            echo "sudo certbot --nginx -d ${domain_name} --email ${ssl_email} --agree-tos --non-interactive --redirect"
        fi
    fi
done

echo "Déploiement complet. Application accessible sur https://${domain_name}"