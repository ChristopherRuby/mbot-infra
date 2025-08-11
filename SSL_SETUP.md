# Configuration SSL Automatique

## Fonctionnalité

Le déploiement de l'infrastructure EC2 inclut désormais la configuration automatique de SSL/HTTPS avec Let's Encrypt.

## Configuration

### Variables ajoutées

- `domain_name` : Nom de domaine pour le certificat SSL (défaut: `mbot.augmented-systems.com`)
- `ssl_email` : Email pour l'enregistrement du certificat SSL (défaut: `christopherruby1408@gmail.com`)

### Ce qui est automatisé

1. **Installation de Certbot** : Installation automatique de `certbot` et `python3-certbot-nginx`
2. **Configuration Nginx** : Mise à jour du `server_name` avec le domaine correct
3. **Génération du certificat** : Création automatique du certificat SSL Let's Encrypt
4. **Configuration HTTPS** : Configuration automatique de Nginx pour HTTPS
5. **Redirection HTTP → HTTPS** : Redirection automatique des requêtes HTTP vers HTTPS
6. **Renouvellement automatique** : Configuration du renouvellement automatique du certificat

### Processus de déploiement

1. L'instance EC2 démarre et installe les dépendances
2. L'application MBot est configurée et démarrée
3. Nginx est configuré avec le nom de domaine
4. Attente de 30 secondes pour s'assurer que tout est opérationnel
5. Tentative de configuration SSL avec retry (max 3 tentatives)
6. En cas de succès : Application accessible via HTTPS
7. En cas d'échec : Instructions pour configuration manuelle

### Points importants

- **Prérequis DNS** : Le domaine doit pointer vers l'EIP avant le déploiement
- **Retry automatique** : 3 tentatives avec pause de 60 secondes entre chaque tentative
- **Logs disponibles** : Logs de déploiement dans `/var/log/user-data.log`
- **Fallback manuel** : Instructions fournies si la configuration automatique échoue

### Utilisation

Aucune action supplémentaire n'est requise. Lors du prochain `terraform apply`, l'instance sera déployée avec SSL automatiquement configuré.

### Personnalisation

Pour modifier les paramètres SSL, mettez à jour les variables dans votre configuration Terraform :

```hcl
module "mbot_ec2" {
  # ... autres configurations ...
  
  domain_name = "votre-domaine.com"
  ssl_email   = "votre-email@exemple.com"
}
```

### Vérification

Après déploiement, vérifiez que HTTPS fonctionne :

```bash
curl -I https://mbot.augmented-systems.com
```

Le certificat expire tous les 90 jours et se renouvelle automatiquement via un timer systemd configuré par Certbot.