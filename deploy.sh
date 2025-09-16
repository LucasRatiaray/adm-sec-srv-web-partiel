#!/bin/bash

# =============================================================================
# Script d'automatisation - Projet 4IWJ
# Infrastructure Web Sécurisée avec CA et certificats SSL
# =============================================================================

# Configuration des couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Variables de configuration
CLASSE="4iwj"
DOMAIN_DOLIBARR="dolibarr.${CLASSE}.lab"
DOMAIN_GLPI="glpi.${CLASSE}.lab"
CA_SUBJECT="/C=FR/ST=IDF/L=Paris/O=4IW Lab/OU=IT/CN=4IW Root CA"
DOLIBARR_SUBJECT="/C=FR/ST=IDF/L=Paris/O=4IW Lab/OU=Services/CN=${DOMAIN_DOLIBARR}"
GLPI_SUBJECT="/C=FR/ST=IDF/L=Paris/O=4IW Lab/OU=Services/CN=${DOMAIN_GLPI}"

# URLs des applications
DOLIBARR_URL="https://github.com/Dolibarr/dolibarr/archive/refs/tags/19.0.3.tar.gz"
GLPI_URL="https://github.com/glpi-project/glpi/releases/download/10.0.20/glpi-10.0.20.tgz"

# =============================================================================
# FONCTIONS UTILITAIRES
# =============================================================================

# Affichage du banner
show_banner() {
    clear
    echo -e "${PURPLE}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${WHITE}${BOLD}                    SCRIPT D'AUTOMATISATION 4IWJ                             ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${WHITE}                Infrastructure Web Sécurisée avec SSL                          ${PURPLE}║${NC}"
    echo -e "${PURPLE}║                                                                               ║${NC}"
    echo -e "${PURPLE}║${CYAN}                      Dolibarr ERP + GLPI ITSM                                 ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${CYAN}                     CA personnalisée + HTTPS                                  ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Fonction pour afficher une étape
print_step() {
    echo -e "${BLUE}[ÉTAPE]${NC} ${WHITE}$1${NC}"
}

# Fonction pour afficher le succès
print_success() {
    echo -e "${GREEN}[✓ OK]${NC} $1"
}

# Fonction pour afficher une erreur
print_error() {
    echo -e "${RED}[✗ ERREUR]${NC} $1"
}

# Fonction pour afficher des informations
print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

# Fonction pour afficher un avertissement
print_warning() {
    echo -e "${YELLOW}[⚠ ATTENTION]${NC} $1"
}

# Fonction pour attendre une confirmation
wait_continue() {
    echo ""
    echo -e "${YELLOW}Appuyez sur Entrée pour continuer...${NC}"
    read
}

# Vérification des droits root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "Ce script ne doit PAS être exécuté en tant que root"
        print_info "Exécutez-le avec votre utilisateur normal (sudo sera utilisé quand nécessaire)"
        exit 1
    fi
}

# Vérification de l'environnement
check_environment() {
    print_step "Vérification de l'environnement"
    
    # Vérifier que sudo fonctionne
    if ! sudo -n true 2>/dev/null; then
        print_warning "Sudo nécessaire - saisissez votre mot de passe"
        sudo true || { print_error "Échec sudo"; exit 1; }
    fi
    
    print_success "Environnement validé"
}

# =============================================================================
# INSTALLATION DES DÉPENDANCES
# =============================================================================

install_dependencies() {
    print_step "Installation des dépendances système"
    
    # Mise à jour des paquets
    print_info "Mise à jour des paquets..."
    sudo apt update >/dev/null 2>&1
    
    # Installation des paquets essentiels
    print_info "Installation Apache2, MariaDB, PHP, OpenSSL..."
    sudo apt install -y \
        apache2 \
        mariadb-server \
        php \
        php-mysql \
        php-gd \
        php-zip \
        php-curl \
        php-xml \
        php-mbstring \
        openssl \
        wget \
        unzip \
        curl >/dev/null 2>&1
    
    # Activation des modules Apache
    print_info "Activation des modules Apache (SSL, rewrite, headers)..."
    sudo a2enmod ssl >/dev/null 2>&1
    sudo a2enmod rewrite >/dev/null 2>&1
    sudo a2enmod headers >/dev/null 2>&1
    
    # Démarrage des services
    sudo systemctl start apache2 >/dev/null 2>&1
    sudo systemctl start mariadb >/dev/null 2>&1
    sudo systemctl enable apache2 >/dev/null 2>&1
    sudo systemctl enable mariadb >/dev/null 2>&1
    
    print_success "Dépendances installées"
}

# =============================================================================
# CRÉATION DE L'AUTORITÉ DE CERTIFICATION
# =============================================================================

create_ca_structure() {
    print_step "Création de la structure SSL"
    
    # Création des répertoires
    sudo mkdir -p /etc/ssl/private /etc/ssl/certs /etc/ssl/client
    sudo chmod 700 /etc/ssl/private
    sudo chmod 755 /etc/ssl/certs /etc/ssl/client
    
    print_success "Structure SSL créée"
}

generate_ca_certificate() {
    print_step "Génération de l'Autorité de Certification"
    
    # Génération de la clé privée CA (4096 bits)
    print_info "Génération clé privée CA (4096 bits)..."
    sudo openssl genpkey -algorithm RSA -out /etc/ssl/private/ca.key -pkeyopt rsa_keygen_bits:4096 2>/dev/null
    
    # Sécurisation de la clé CA
    sudo chmod 600 /etc/ssl/private/ca.key
    sudo chown root:root /etc/ssl/private/ca.key
    
    # Génération du certificat racine CA
    print_info "Génération certificat racine CA (validité 2 ans)..."
    sudo openssl req -x509 -new -key /etc/ssl/private/ca.key \
        -sha256 -days 730 -out /etc/ssl/certs/ca.crt \
        -subj "${CA_SUBJECT}" 2>/dev/null
    
    sudo chmod 644 /etc/ssl/certs/ca.crt
    
    print_success "CA générée: $(sudo openssl x509 -in /etc/ssl/certs/ca.crt -subject -noout | cut -d= -f2-)"
}

generate_service_certificates() {
    print_step "Génération des certificats pour les services"
    
    # Certificat Dolibarr
    print_info "Génération certificat Dolibarr (${DOMAIN_DOLIBARR})..."
    sudo openssl genpkey -algorithm RSA -out /etc/ssl/private/dolibarr.key -pkeyopt rsa_keygen_bits:2048 2>/dev/null
    sudo openssl req -new -key /etc/ssl/private/dolibarr.key \
        -out /tmp/dolibarr.csr -subj "${DOLIBARR_SUBJECT}" 2>/dev/null
    sudo openssl x509 -req -in /tmp/dolibarr.csr \
        -CA /etc/ssl/certs/ca.crt -CAkey /etc/ssl/private/ca.key \
        -CAcreateserial -out /etc/ssl/certs/dolibarr.crt \
        -days 365 -sha256 2>/dev/null
    
    # Certificat GLPI
    print_info "Génération certificat GLPI (${DOMAIN_GLPI})..."
    sudo openssl genpkey -algorithm RSA -out /etc/ssl/private/glpi.key -pkeyopt rsa_keygen_bits:2048 2>/dev/null
    sudo openssl req -new -key /etc/ssl/private/glpi.key \
        -out /tmp/glpi.csr -subj "${GLPI_SUBJECT}" 2>/dev/null
    sudo openssl x509 -req -in /tmp/glpi.csr \
        -CA /etc/ssl/certs/ca.crt -CAkey /etc/ssl/private/ca.key \
        -CAcreateserial -out /etc/ssl/certs/glpi.crt \
        -days 365 -sha256 2>/dev/null
    
    # Nettoyage et permissions
    sudo rm -f /tmp/*.csr
    sudo chmod 600 /etc/ssl/private/*.key
    sudo chmod 644 /etc/ssl/certs/*.crt
    sudo chown root:root /etc/ssl/private/* /etc/ssl/certs/*
    
    print_success "Certificats services générés"
}

generate_client_certificate() {
    print_step "Génération du certificat client"
    
    # Génération certificat client pour authentification
    print_info "Génération certificat client administrateur..."
    sudo openssl genpkey -algorithm RSA -out /tmp/admin-client.key -pkeyopt rsa_keygen_bits:2048 2>/dev/null
    sudo openssl req -new -key /tmp/admin-client.key \
        -out /tmp/admin-client.csr \
        -subj "/C=FR/ST=IDF/L=Paris/O=4IW Lab/OU=Clients/CN=admin-4iwj" 2>/dev/null
    sudo openssl x509 -req -in /tmp/admin-client.csr \
        -CA /etc/ssl/certs/ca.crt -CAkey /etc/ssl/private/ca.key \
        -out /tmp/admin-client.crt -days 365 -sha256 2>/dev/null
    
    # Bundle PKCS#12
    sudo openssl pkcs12 -export -out /etc/ssl/client/admin-client.p12 \
        -inkey /tmp/admin-client.key -in /tmp/admin-client.crt \
        -certfile /etc/ssl/certs/ca.crt -name "Admin 4IWJ Client Certificate" \
        -passout pass:4iwj2025 2>/dev/null
    
    sudo rm -f /tmp/admin-client.*
    sudo chmod 644 /etc/ssl/client/admin-client.p12
    
    print_success "Certificat client généré"
}

verify_certificates() {
    print_step "Validation de la chaîne de certification"
    
    # Vérification des certificats
    if sudo openssl verify -CAfile /etc/ssl/certs/ca.crt /etc/ssl/certs/dolibarr.crt >/dev/null 2>&1; then
        print_success "Chaîne Dolibarr validée"
    else
        print_error "Problème chaîne Dolibarr"
    fi
    
    if sudo openssl verify -CAfile /etc/ssl/certs/ca.crt /etc/ssl/certs/glpi.crt >/dev/null 2>&1; then
        print_success "Chaîne GLPI validée"
    else
        print_error "Problème chaîne GLPI"
    fi
}

# =============================================================================
# CONFIGURATION BASES DE DONNÉES
# =============================================================================

configure_mariadb() {
    print_step "Configuration MariaDB"
    
    # Configuration sécurisée de MariaDB
    print_info "Sécurisation MariaDB..."
    sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'MariaDB_${CLASSE}2025!';" 2>/dev/null
    sudo mysql -u root -pMariaDB_${CLASSE}2025! -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null
    sudo mysql -u root -pMariaDB_${CLASSE}2025! -e "DROP DATABASE IF EXISTS test;" 2>/dev/null
    sudo mysql -u root -pMariaDB_${CLASSE}2025! -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';" 2>/dev/null
    sudo mysql -u root -pMariaDB_${CLASSE}2025! -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" 2>/dev/null
    sudo mysql -u root -pMariaDB_${CLASSE}2025! -e "FLUSH PRIVILEGES;" 2>/dev/null
    
    # Création des bases de données
    print_info "Création bases de données Dolibarr et GLPI..."
    sudo mysql -u root -pMariaDB_${CLASSE}2025! -e "
        CREATE DATABASE dolibarr;
        CREATE USER 'dolibarr'@'localhost' IDENTIFIED BY 'dolibarr';
        GRANT ALL PRIVILEGES ON dolibarr.* TO 'dolibarr'@'localhost';
        
        CREATE DATABASE glpi;
        CREATE USER 'glpi'@'localhost' IDENTIFIED BY 'glpi';
        GRANT ALL PRIVILEGES ON glpi.* TO 'glpi'@'localhost';
        
        FLUSH PRIVILEGES;
    " 2>/dev/null
    
    print_success "MariaDB configuré"
}

# =============================================================================
# TÉLÉCHARGEMENT ET INSTALLATION DES APPLICATIONS
# =============================================================================

download_applications() {
    print_step "Téléchargement des applications"
    
    # Création répertoire de travail
    mkdir -p /tmp/4iw-deployment
    cd /tmp/4iw-deployment
    
    # Téléchargement Dolibarr
    print_info "Téléchargement Dolibarr 19.0.3..."
    wget -q "${DOLIBARR_URL}" -O dolibarr.tar.gz
    
    # Téléchargement GLPI
    print_info "Téléchargement GLPI 10.0.20..."
    wget -q "${GLPI_URL}" -O glpi.tar.gz
    
    print_success "Applications téléchargées"
}

install_applications() {
    print_step "Installation des applications"
    
    cd /tmp/4iw-deployment
    
    # Installation Dolibarr
    print_info "Installation Dolibarr dans /var/www/dolibarr..."
    sudo tar -xzf dolibarr.tar.gz -C /var/www/
    sudo mv /var/www/dolibarr-* /var/www/dolibarr 2>/dev/null || true
    sudo chown -R www-data:www-data /var/www/dolibarr
    sudo chmod -R 755 /var/www/dolibarr
    
    # Installation GLPI
    print_info "Installation GLPI dans /var/www/glpi..."
    sudo tar -xzf glpi.tar.gz -C /var/www/
    sudo chown -R www-data:www-data /var/www/glpi
    sudo chmod -R 755 /var/www/glpi
    
    print_success "Applications installées"
}

# =============================================================================
# CONFIGURATION APACHE
# =============================================================================

configure_virtual_hosts() {
    print_step "Configuration des Virtual Hosts Apache"
    
    # Virtual Host Dolibarr
    print_info "Configuration Virtual Host Dolibarr..."
    sudo tee /etc/apache2/sites-available/001-dolibarr.conf > /dev/null << EOF
# Virtual Host HTTP
<VirtualHost *:80>
    ServerName ${DOMAIN_DOLIBARR}
    DocumentRoot /var/www/dolibarr/htdocs
    
    ErrorLog \${APACHE_LOG_DIR}/dolibarr_error.log
    CustomLog \${APACHE_LOG_DIR}/dolibarr_access.log combined
</VirtualHost>

# Virtual Host HTTPS
<VirtualHost *:443>
    ServerName ${DOMAIN_DOLIBARR}
    DocumentRoot /var/www/dolibarr/htdocs
    
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/dolibarr.crt
    SSLCertificateKeyFile /etc/ssl/private/dolibarr.key
    SSLCACertificateFile /etc/ssl/certs/ca.crt
    
    ErrorLog \${APACHE_LOG_DIR}/dolibarr_ssl_error.log
    CustomLog \${APACHE_LOG_DIR}/dolibarr_ssl_access.log combined
</VirtualHost>
EOF
    
    # Virtual Host GLPI
    print_info "Configuration Virtual Host GLPI..."
    sudo tee /etc/apache2/sites-available/002-glpi.conf > /dev/null << EOF
# Virtual Host HTTP
<VirtualHost *:80>
    ServerName ${DOMAIN_GLPI}
    DocumentRoot /var/www/glpi
    
    ErrorLog \${APACHE_LOG_DIR}/glpi_error.log
    CustomLog \${APACHE_LOG_DIR}/glpi_access.log combined
</VirtualHost>

# Virtual Host HTTPS
<VirtualHost *:443>
    ServerName ${DOMAIN_GLPI}
    DocumentRoot /var/www/glpi
    
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/glpi.crt
    SSLCertificateKeyFile /etc/ssl/private/glpi.key
    SSLCACertificateFile /etc/ssl/certs/ca.crt
    
    ErrorLog \${APACHE_LOG_DIR}/glpi_ssl_error.log
    CustomLog \${APACHE_LOG_DIR}/glpi_ssl_access.log combined
</VirtualHost>
EOF
    
    print_success "Virtual Hosts configurés"
}

configure_basic_auth() {
    print_step "Configuration authentification basique"
    
    # Création du fichier de mots de passe
    print_info "Création fichier de mots de passe..."
    sudo htpasswd -bc /etc/apache2/.htpasswd admin Admin${CLASSE}2025! 2>/dev/null
    
    # Modification de la page par défaut
    print_info "Protection page par défaut Apache..."
    sudo tee /etc/apache2/sites-available/000-default.conf > /dev/null << EOF
<VirtualHost *:80>
    DocumentRoot /var/www/html
    
    # Protection par authentification basique
    <Directory "/var/www/html">
        AuthType Basic
        AuthName "Zone Protégée - Administration ${CLASSE^^}"
        AuthBasicProvider file
        AuthUserFile /etc/apache2/.htpasswd
        Require valid-user
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF
    
    print_success "Authentification basique configurée"
}

activate_sites() {
    print_step "Activation des sites Apache"
    
    # Activation des sites
    sudo a2ensite 001-dolibarr.conf >/dev/null 2>&1
    sudo a2ensite 002-glpi.conf >/dev/null 2>&1
    
    # Test de la configuration
    if sudo apache2ctl configtest >/dev/null 2>&1; then
        print_success "Configuration Apache validée"
    else
        print_error "Erreur configuration Apache"
        sudo apache2ctl configtest
    fi
    
    # Rechargement Apache
    sudo systemctl reload apache2
    
    print_success "Sites activés"
}

# =============================================================================
# FINALISATION
# =============================================================================

create_deployment_info() {
    print_step "Création des informations de déploiement"
    
    # Créer fichier d'informations
    sudo tee /var/www/html/deployment-info.html > /dev/null << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Déploiement 4IWJ - Informations</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        .success { color: #27ae60; font-weight: bold; }
        .info { background: #ecf0f1; padding: 15px; border-radius: 5px; margin: 10px 0; }
        .warning { background: #f39c12; color: white; padding: 10px; border-radius: 5px; }
        a { color: #3498db; text-decoration: none; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Déploiement Infrastructure 4IWJ</h1>
        
        <p class="success">✅ Installation réussie le $(date)</p>
        
        <div class="info">
            <h3>Applications déployées :</h3>
            <ul>
                <li><strong>Dolibarr ERP/CRM :</strong> 
                    <a href="http://${DOMAIN_DOLIBARR}">http://${DOMAIN_DOLIBARR}</a> | 
                    <a href="https://${DOMAIN_DOLIBARR}">https://${DOMAIN_DOLIBARR}</a>
                </li>
                <li><strong>GLPI ITSM :</strong> 
                    <a href="http://${DOMAIN_GLPI}">http://${DOMAIN_GLPI}</a> | 
                    <a href="https://${DOMAIN_GLPI}">https://${DOMAIN_GLPI}</a>
                </li>
            </ul>
        </div>
        
        <div class="info">
            <h3>Certificats SSL :</h3>
            <ul>
                <li><strong>CA Racine :</strong> <a href="/ca.crt">Télécharger ca.crt</a></li>
                <li><strong>Certificat Client :</strong> Disponible pour import navigateur</li>
                <li><strong>Algorithme :</strong> RSA 4096 bits (CA) / 2048 bits (services)</li>
                <li><strong>Validité :</strong> CA 2 ans, services 1 an</li>
            </ul>
        </div>
        
        <div class="warning">
            ⚠️ Pour HTTPS sans erreur : Installez ca.crt dans votre navigateur (Paramètres > Sécurité > Certificats > Autorités)
        </div>
        
        <div class="info">
            <h3>Authentification :</h3>
            <ul>
                <li><strong>Page par défaut :</strong> admin / Admin${CLASSE}2025!</li>
                <li><strong>Base Dolibarr :</strong> dolibarr / dolibarr</li>
                <li><strong>Base GLPI :</strong> glpi / glpi</li>
                <li><strong>MariaDB root :</strong> MariaDB_${CLASSE}2025!</li>
            </ul>
        </div>
        
        <p><em>Infrastructure déployée automatiquement par le script 4IWJ</em></p>
    </div>
</body>
</html>
EOF
    
    # Rendre le certificat CA téléchargeable
    sudo cp /etc/ssl/certs/ca.crt /var/www/html/ca.crt
    
    print_success "Informations de déploiement créées"
}

show_summary() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${WHITE}${BOLD}                       DÉPLOIEMENT TERMINÉ !                                   ${GREEN}║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${WHITE}${BOLD}🎯 Applications déployées :${NC}"
    echo -e "${CYAN}   • Dolibarr ERP/CRM :${NC} http://${DOMAIN_DOLIBARR} | https://${DOMAIN_DOLIBARR}"
    echo -e "${CYAN}   • GLPI ITSM :${NC}        http://${DOMAIN_GLPI} | https://${DOMAIN_GLPI}"
    echo ""
    echo -e "${WHITE}${BOLD}🔐 Sécurité SSL :${NC}"
    echo -e "${GREEN}   ✓ CA personnalisée créée${NC}"
    echo -e "${GREEN}   ✓ Certificats services signés${NC}"
    echo -e "${GREEN}   ✓ Chaîne de certification valide${NC}"
    echo -e "${GREEN}   ✓ Authentification basique configurée${NC}"
    echo ""
    echo -e "${WHITE}${BOLD}📋 Accès et authentification :${NC}"
    echo -e "${YELLOW}   • Page par défaut :${NC} admin / Admin${CLASSE}2025!"
    echo -e "${YELLOW}   • Base Dolibarr :${NC}   dolibarr / dolibarr"
    echo -e "${YELLOW}   • Base GLPI :${NC}       glpi / glpi"
    echo -e "${YELLOW}   • MariaDB root :${NC}    MariaDB_${CLASSE}2025!"
    echo ""
    echo -e "${WHITE}${BOLD}🔧 Pour HTTPS sans erreur :${NC}"
    echo -e "${PURPLE}   1. Téléchargez :${NC} http://$(hostname -I | awk '{print $1}')/ca.crt"
    echo -e "${PURPLE}   2. Installez dans navigateur (Paramètres > Sécurité > Certificats)${NC}"
    echo ""
    echo -e "${WHITE}${BOLD}📖 Informations complètes :${NC} http://$(hostname -I | awk '{print $1}')/deployment-info.html"
    echo ""
}

# =============================================================================
# FONCTION PRINCIPALE
# =============================================================================

main() {
    show_banner
    
    print_info "Démarrage du déploiement automatisé infrastructure 4IWJ"
    print_warning "Ce script va installer et configurer :"
    echo -e "   ${CYAN}• Apache2, MariaDB, PHP, OpenSSL${NC}"
    echo -e "   ${CYAN}• Autorité de Certification personnalisée${NC}"
    echo -e "   ${CYAN}• Certificats SSL pour Dolibarr et GLPI${NC}"
    echo -e "   ${CYAN}• Applications Dolibarr ERP et GLPI ITSM${NC}"
    echo -e "   ${CYAN}• Virtual Hosts Apache avec HTTPS${NC}"
    echo -e "   ${CYAN}• Authentification basique${NC}"
    echo ""
    
    wait_continue
    
    # Vérifications préliminaires
    check_root
    check_environment
    
    # Déploiement
    install_dependencies
    create_ca_structure
    generate_ca_certificate
    generate_service_certificates
    generate_client_certificate
    verify_certificates
    configure_mariadb
    download_applications
    install_applications
    configure_virtual_hosts
    configure_basic_auth
    activate_sites
    create_deployment_info
    
    # Nettoyage
    rm -rf /tmp/4iw-deployment
    
    # Résumé final
    show_summary
    
    print_success "Script terminé avec succès !"
}

# =============================================================================
# POINT D'ENTRÉE
# =============================================================================

# Exécution du script principal
main "$@"
