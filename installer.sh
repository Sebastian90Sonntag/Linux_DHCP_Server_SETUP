#!/bin/bash

# Combined ISC DHCP Server + phpIPAM Setup Script
# Supports Ubuntu/Debian and CentOS/RHEL/Fedora
# Author: DHCP + phpIPAM Setup Assistant
# Version: 2.0

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Global variables
MYSQL_ROOT_PASSWORD=""
PHPIPAM_DB_PASSWORD=""
ADMIN_EMAIL=""
DOMAIN_NAME=""

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${PURPLE}[SUCCESS]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

# Detect OS
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        error "Cannot detect operating system"
    fi
    
    log "Detected OS: $OS $VERSION"
}

# Generate secure password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Get network interface
get_interface() {
    echo -e "${BLUE}Available network interfaces:${NC}"
    ip link show | grep -E "^[0-9]+:" | cut -d: -f2 | sed 's/^ *//' | grep -v "lo"
    
    while true; do
        read -p "Enter the network interface for DHCP server (e.g., eth0, ens33): " INTERFACE
        if ip link show "$INTERFACE" &> /dev/null; then
            break
        else
            warn "Interface $INTERFACE not found. Please try again."
        fi
    done
    
    log "Selected interface: $INTERFACE"
}

# Get network configuration
get_network_config() {
    echo -e "${BLUE}=== Network Configuration ===${NC}"
    
    # Get network subnet
    read -p "Enter network subnet (e.g., 192.168.1.0): " SUBNET
    read -p "Enter subnet mask (e.g., 255.255.255.0): " NETMASK
    read -p "Enter DHCP range start (e.g., 192.168.1.100): " RANGE_START
    read -p "Enter DHCP range end (e.g., 192.168.1.200): " RANGE_END
    read -p "Enter gateway/router IP (e.g., 192.168.1.1): " GATEWAY
    
    # DNS servers
    echo -e "${BLUE}DNS Configuration:${NC}"
    echo "1) Google DNS (8.8.8.8, 8.8.4.4)"
    echo "2) Cloudflare DNS (1.1.1.1, 1.0.0.1)"
    echo "3) Custom DNS"
    read -p "Choose DNS option (1-3): " DNS_CHOICE
    
    case $DNS_CHOICE in
        1)
            DNS1="8.8.8.8"
            DNS2="8.8.4.4"
            ;;
        2)
            DNS1="1.1.1.1"
            DNS2="1.0.0.1"
            ;;
        3)
            read -p "Enter primary DNS server: " DNS1
            read -p "Enter secondary DNS server: " DNS2
            ;;
        *)
            DNS1="8.8.8.8"
            DNS2="8.8.4.4"
            ;;
    esac
    
    # Lease time
    read -p "Enter lease time in seconds (default 86400 = 24h): " LEASE_TIME
    LEASE_TIME=${LEASE_TIME:-86400}
    
    # Domain name
    read -p "Enter domain name (default: local): " DOMAIN_NAME
    DOMAIN_NAME=${DOMAIN_NAME:-local}
}

# Get phpIPAM configuration
get_phpipam_config() {
    echo -e "${BLUE}=== phpIPAM Configuration ===${NC}"
    
    read -p "Enter admin email for phpIPAM: " ADMIN_EMAIL
    
    # Generate secure passwords
    MYSQL_ROOT_PASSWORD=$(generate_password)
    PHPIPAM_DB_PASSWORD=$(generate_password)
    
    info "Generated secure database passwords (will be saved to /root/passwords.txt)"
}

# Update system
update_system() {
    log "Updating system packages..."
    
    case $OS in
        ubuntu|debian)
            apt update && apt upgrade -y
            ;;
        centos|rhel|fedora)
            if command -v dnf &> /dev/null; then
                dnf update -y
            else
                yum update -y
            fi
            ;;
    esac
    
    success "System updated"
}

# Install DHCP server
install_dhcp_server() {
    log "Installing DHCP server..."
    
    case $OS in
        ubuntu|debian)
            apt install -y isc-dhcp-server
            DHCP_CONFIG="/etc/dhcp/dhcpd.conf"
            DHCP_SERVICE="isc-dhcp-server"
            DHCP_DEFAULT="/etc/default/isc-dhcp-server"
            DHCP_LEASES="/var/lib/dhcp/dhcpd.leases"
            ;;
        centos|rhel|fedora)
            if command -v dnf &> /dev/null; then
                dnf install -y dhcp-server
            else
                yum install -y dhcp-server
            fi
            DHCP_CONFIG="/etc/dhcp/dhcpd.conf"
            DHCP_SERVICE="dhcpd"
            DHCP_LEASES="/var/lib/dhcpd/dhcpd.leases"
            ;;
    esac
    
    success "DHCP server installed"
}

# Install LAMP stack
install_lamp_stack() {
    log "Installing LAMP stack..."
    
    case $OS in
        ubuntu|debian)
            apt install -y apache2 mysql-server php php-mysql php-gd php-curl \
                php-json php-mbstring php-xml php-zip php-ldap php-snmp php-gmp \
                libapache2-mod-php git wget unzip
            
            WEB_USER="www-data"
            WEB_GROUP="www-data"
            APACHE_SERVICE="apache2"
            MYSQL_SERVICE="mysql"
            WEB_ROOT="/var/www/html"
            APACHE_CONF_DIR="/etc/apache2/sites-available"
            ;;
        centos|rhel|fedora)
            if command -v dnf &> /dev/null; then
                dnf install -y httpd mariadb-server php php-mysqlnd php-gd php-curl \
                    php-json php-mbstring php-xml php-zip php-ldap php-snmp php-gmp \
                    git wget unzip
            else
                yum install -y httpd mariadb-server php php-mysqlnd php-gd php-curl \
                    php-json php-mbstring php-xml php-zip php-ldap php-snmp php-gmp \
                    git wget unzip
            fi
            
            WEB_USER="apache"
            WEB_GROUP="apache"
            APACHE_SERVICE="httpd"
            MYSQL_SERVICE="mariadb"
            WEB_ROOT="/var/www/html"
            APACHE_CONF_DIR="/etc/httpd/conf.d"
            
            # Enable services
            systemctl enable $APACHE_SERVICE $MYSQL_SERVICE
            ;;
    esac
    
    # Start services
    systemctl start $APACHE_SERVICE $MYSQL_SERVICE
    
    success "LAMP stack installed"
}

# Configure MySQL
configure_mysql() {
    log "Configuring MySQL/MariaDB..."
    
    # Secure MySQL installation
    mysql -e "UPDATE mysql.user SET Password=PASSWORD('$MYSQL_ROOT_PASSWORD') WHERE User='root';"
    mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    mysql -e "DELETE FROM mysql.user WHERE User='';"
    mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';"
    mysql -e "FLUSH PRIVILEGES;"
    
    # Create phpIPAM database and user
    mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE phpipam;"
    mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "CREATE USER 'phpipam'@'localhost' IDENTIFIED BY '$PHPIPAM_DB_PASSWORD';"
    mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON phpipam.* TO 'phpipam'@'localhost';"
    mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"
    
    success "MySQL configured"
}

# Install phpIPAM
install_phpipam() {
    log "Installing phpIPAM..."
    
    cd $WEB_ROOT
    
    # Download phpIPAM
    if [[ -d phpipam ]]; then
        rm -rf phpipam
    fi
    
    git clone --depth 1 https://github.com/phpipam/phpipam.git
    cd phpipam
    
    # Set permissions
    chown -R $WEB_USER:$WEB_GROUP $WEB_ROOT/phpipam
    chmod -R 755 $WEB_ROOT/phpipam
    
    # Create temp directory
    mkdir -p app/temp
    chown -R $WEB_USER:$WEB_GROUP app/temp
    chmod -R 777 app/temp
    
    success "phpIPAM downloaded"
}

# Configure phpIPAM
configure_phpipam() {
    log "Configuring phpIPAM..."
    
    cd $WEB_ROOT/phpipam
    
    # Create configuration file
    cat > config.php << EOF
<?php
/**
 * phpIPAM Configuration
 * Generated by setup script on $(date)
 */

/* Database connection */
\$db['host'] = 'localhost';
\$db['user'] = 'phpipam';
\$db['pass'] = '$PHPIPAM_DB_PASSWORD';
\$db['name'] = 'phpipam';
\$db['port'] = 3306;

/* Base URL */
define('BASE', '/phpipam/');

/* SSL */
\$ssl_ca     = false;
\$ssl_key    = false;
\$ssl_cert   = false;

/* Debugging */
\$debugging = false;

/* DHCP Integration */
\$dhcp = array(
    'type' => 'isc',
    'config' => '$DHCP_CONFIG',
    'leases' => '$DHCP_LEASES'
);

/* Define exit codes */
define('EXIT_SUCCESS', 0);
define('EXIT_ERROR', 1);
define('EXIT_CONFIG', 2);
define('EXIT_UNKNOWN_FILE', 3);
define('EXIT_UNKNOWN_CLASS', 4);
define('EXIT_UNKNOWN_METHOD', 5);
define('EXIT_USER_INPUT', 6);
define('EXIT_DATABASE', 8);
?>
EOF
    
    chown $WEB_USER:$WEB_GROUP config.php
    chmod 644 config.php
    
    success "phpIPAM configured"
}

# Configure Apache
configure_apache() {
    log "Configuring Apache..."
    
    # Create virtual host
    cat > $APACHE_CONF_DIR/phpipam.conf << EOF
<VirtualHost *:80>
    ServerName $DOMAIN_NAME
    ServerAlias www.$DOMAIN_NAME
    DocumentRoot $WEB_ROOT/phpipam
    
    <Directory $WEB_ROOT/phpipam>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    # Security headers
    Header always set X-Content-Type-Options nosniff
    Header always set X-Frame-Options DENY
    Header always set X-XSS-Protection "1; mode=block"
    
    # Logging
    ErrorLog \${APACHE_LOG_DIR}/phpipam_error.log
    CustomLog \${APACHE_LOG_DIR}/phpipam_access.log combined
</VirtualHost>
EOF
    
    # Enable modules and site
    case $OS in
        ubuntu|debian)
            a2enmod rewrite headers
            a2ensite phpipam.conf
            a2dissite 000-default.conf
            ;;
        centos|rhel|fedora)
            # Modules are usually enabled by default in CentOS/RHEL
            ;;
    esac
    
    # Test Apache configuration
    if apache2ctl configtest 2>/dev/null || httpd -t 2>/dev/null; then
        systemctl restart $APACHE_SERVICE
        success "Apache configured and restarted"
    else
        error "Apache configuration test failed"
    fi
}

# Configure DHCP server
configure_dhcp() {
    log "Configuring DHCP server..."
    
    # Backup original config
    if [[ -f $DHCP_CONFIG ]]; then
        cp $DHCP_CONFIG "${DHCP_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Create DHCP configuration
    cat > $DHCP_CONFIG << EOF
# ISC DHCP Server Configuration
# Generated by setup script on $(date)

# Global options
default-lease-time $LEASE_TIME;
max-lease-time $(($LEASE_TIME * 2));
authoritative;

# Logging
log-facility local7;

# DDNS settings for phpIPAM integration
ddns-update-style interim;
ddns-updates on;

# Subnet configuration
subnet $SUBNET netmask $NETMASK {
    range $RANGE_START $RANGE_END;
    option routers $GATEWAY;
    option domain-name-servers $DNS1, $DNS2;
    option domain-name "$DOMAIN_NAME";
    option broadcast-address $(echo $SUBNET | cut -d. -f1-3).255;
    
    # Additional options
    option time-offset 0;
    option ntp-servers $DNS1;
}

# Static reservations section
# Example:
# host example-device {
#     hardware ethernet 00:11:22:33:44:55;
#     fixed-address 192.168.1.10;
#     option host-name "example-device";
# }
EOF
    
    # Configure interface for Ubuntu/Debian
    if [[ $OS == "ubuntu" || $OS == "debian" ]] && [[ -f $DHCP_DEFAULT ]]; then
        sed -i "s/^INTERFACESv4=.*/INTERFACESv4=\"$INTERFACE\"/" $DHCP_DEFAULT
        sed -i "s/^#INTERFACESv4=.*/INTERFACESv4=\"$INTERFACE\"/" $DHCP_DEFAULT
    fi
    
    success "DHCP configuration created"
}

# Configure firewall
configure_firewall() {
    log "Configuring firewall..."
    
    # Detect and configure firewall
    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        log "Configuring UFW firewall..."
        ufw allow ssh
        ufw allow http
        ufw allow https
        ufw allow in on $INTERFACE to any port 67 proto udp
        ufw allow in on $INTERFACE to any port 68 proto udp
        ufw --force enable
        success "UFW configured"
        
    elif command -v firewall-cmd &> /dev/null; then
        log "Configuring firewalld..."
        ZONE=$(firewall-cmd --get-zone-of-interface=$INTERFACE 2>/dev/null || echo "public")
        
        firewall-cmd --permanent --zone=$ZONE --add-service=ssh
        firewall-cmd --permanent --zone=$ZONE --add-service=http
        firewall-cmd --permanent --zone=$ZONE --add-service=https
        firewall-cmd --permanent --zone=$ZONE --add-service=dhcp
        firewall-cmd --permanent --zone=$ZONE --add-port=67/udp
        firewall-cmd --permanent --zone=$ZONE --add-port=68/udp
        firewall-cmd --reload
        success "Firewalld configured"
        
    elif command -v iptables &> /dev/null; then
        log "Configuring iptables..."
        
        # Allow DHCP and web traffic
        iptables -A INPUT -p tcp --dport 22 -j ACCEPT
        iptables -A INPUT -p tcp --dport 80 -j ACCEPT
        iptables -A INPUT -p tcp --dport 443 -j ACCEPT
        iptables -A INPUT -i $INTERFACE -p udp --dport 67 -j ACCEPT
        iptables -A INPUT -i $INTERFACE -p udp --dport 68 -j ACCEPT
        iptables -A OUTPUT -o $INTERFACE -p udp --sport 67 -j ACCEPT
        iptables -A OUTPUT -o $INTERFACE -p udp --sport 68 -j ACCEPT
        
        # Save rules
        case $OS in
            ubuntu|debian)
                apt install -y iptables-persistent
                iptables-save > /etc/iptables/rules.v4
                ;;
            centos|rhel|fedora)
                service iptables save 2>/dev/null || {
                    mkdir -p /etc/sysconfig
                    iptables-save > /etc/sysconfig/iptables
                }
                ;;
        esac
        success "Iptables configured"
    else
        warn "No supported firewall detected. Configure manually if needed."
    fi
}

# Set DHCP permissions for phpIPAM
set_dhcp_permissions() {
    log "Setting DHCP permissions for phpIPAM..."
    
    # Add web user to dhcp group
    case $OS in
        ubuntu|debian)
            usermod -a -G dhcpd $WEB_USER || groupadd dhcpd && usermod -a -G dhcpd $WEB_USER
            ;;
        centos|rhel|fedora)
            usermod -a -G dhcpd $WEB_USER || groupadd dhcpd && usermod -a -G dhcpd $WEB_USER
            ;;
    esac
    
    # Set file permissions
    chmod 644 $DHCP_CONFIG
    touch $DHCP_LEASES
    chmod 644 $DHCP_LEASES
    
    success "DHCP permissions configured"
}

# Start services
start_services() {
    log "Starting services..."
    
    # Enable and start DHCP service
    systemctl enable $DHCP_SERVICE
    systemctl start $DHCP_SERVICE
    
    # Enable and start web services
    systemctl enable $APACHE_SERVICE $MYSQL_SERVICE
    systemctl restart $APACHE_SERVICE
    
    success "All services started"
}

# Test configuration
test_configuration() {
    log "Testing configuration..."
    
    # Test DHCP configuration
    if dhcpd -t -cf $DHCP_CONFIG; then
        success "DHCP configuration is valid"
    else
        error "DHCP configuration has errors"
    fi
    
    # Test Apache configuration
    if apache2ctl configtest 2>/dev/null || httpd -t 2>/dev/null; then
        success "Apache configuration is valid"
    else
        warn "Apache configuration may have issues"
    fi
    
    # Test MySQL connection
    if mysql -u phpipam -p"$PHPIPAM_DB_PASSWORD" -e "USE phpipam;" &>/dev/null; then
        success "Database connection is working"
    else
        warn "Database connection may have issues"
    fi
    
    # Test services
    if systemctl is-active --quiet $DHCP_SERVICE; then
        success "DHCP service is running"
    else
        warn "DHCP service is not running"
    fi
    
    if systemctl is-active --quiet $APACHE_SERVICE; then
        success "Apache service is running"
    else
        warn "Apache service is not running"
    fi
}

# Save passwords and configuration
save_passwords() {
    log "Saving passwords and configuration..."
    
    cat > /root/dhcp-phpipam-config.txt << EOF
# DHCP + phpIPAM Installation Configuration
# Generated on: $(date)

## Database Credentials
MySQL Root Password: $MYSQL_ROOT_PASSWORD
phpIPAM Database Password: $PHPIPAM_DB_PASSWORD

## Network Configuration
Interface: $INTERFACE
Subnet: $SUBNET/$NETMASK
DHCP Range: $RANGE_START - $RANGE_END
Gateway: $GATEWAY
DNS Servers: $DNS1, $DNS2
Domain: $DOMAIN_NAME
Lease Time: $LEASE_TIME seconds

## Access Information
phpIPAM URL: http://$(hostname -I | awk '{print $1}')/phpipam/
Admin Email: $ADMIN_EMAIL

## Important Files
DHCP Config: $DHCP_CONFIG
DHCP Leases: $DHCP_LEASES
phpIPAM Config: $WEB_ROOT/phpipam/config.php
Apache Config: $APACHE_CONF_DIR/phpipam.conf

## Service Commands
Start DHCP: systemctl start $DHCP_SERVICE
Stop DHCP: systemctl stop $DHCP_SERVICE
Restart DHCP: systemctl restart $DHCP_SERVICE
DHCP Status: systemctl status $DHCP_SERVICE

Start Apache: systemctl start $APACHE_SERVICE
Stop Apache: systemctl stop $APACHE_SERVICE
Restart Apache: systemctl restart $APACHE_SERVICE

## Log Files
DHCP Logs: /var/log/syslog (Ubuntu) or /var/log/messages (CentOS)
Apache Error Log: /var/log/apache2/phpipam_error.log (Ubuntu) or /var/log/httpd/phpipam_error.log (CentOS)
Apache Access Log: /var/log/apache2/phpipam_access.log (Ubuntu) or /var/log/httpd/phpipam_access.log (CentOS)
EOF
    
    chmod 600 /root/dhcp-phpipam-config.txt
    success "Configuration saved to /root/dhcp-phpipam-config.txt"
}

# Show final summary
show_summary() {
    local server_ip=$(hostname -I | awk '{print $1}')
    
    echo -e "\n${GREEN}=========================================${NC}"
    echo -e "${GREEN}  DHCP + phpIPAM Setup Complete!${NC}"
    echo -e "${GREEN}=========================================${NC}"
    
    echo -e "\n${BLUE}🌐 Access Information:${NC}"
    echo -e "   phpIPAM URL: ${YELLOW}http://$server_ip/phpipam/${NC}"
    echo -e "   Admin Email: ${YELLOW}$ADMIN_EMAIL${NC}"
    
    echo -e "\n${BLUE}🔧 Network Configuration:${NC}"
    echo -e "   Interface:   $INTERFACE"
    echo -e "   Subnet:      $SUBNET/$NETMASK"
    echo -e "   DHCP Range:  $RANGE_START - $RANGE_END"
    echo -e "   Gateway:     $GATEWAY"
    echo -e "   DNS:         $DNS1, $DNS2"
    
    echo -e "\n${BLUE}📁 Important Files:${NC}"
    echo -e "   Configuration: ${YELLOW}/root/dhcp-phpipam-config.txt${NC}"
    echo -e "   DHCP Config:   $DHCP_CONFIG"
    echo -e "   phpIPAM Config: $WEB_ROOT/phpipam/config.php"
    
    echo -e "\n${BLUE}🔄 Next Steps:${NC}"
    echo -e "   1. Open browser: ${YELLOW}http://$server_ip/phpipam/${NC}"
    echo -e "   2. Complete phpIPAM installation wizard"
    echo -e "   3. Configure DHCP integration in phpIPAM"
    echo -e "   4. Add your network subnets"
    
    echo -e "\n${BLUE}📊 Service Status:${NC}"
    systemctl is-active --quiet $DHCP_SERVICE && echo -e "   DHCP Server: ${GREEN}✓ Running${NC}" || echo -e "   DHCP Server: ${RED}✗ Stopped${NC}"
    systemctl is-active --quiet $APACHE_SERVICE && echo -e "   Apache:      ${GREEN}✓ Running${NC}" || echo -e "   Apache:      ${RED}✗ Stopped${NC}"
    systemctl is-active --quiet $MYSQL_SERVICE && echo -e "   MySQL:       ${GREEN}✓ Running${NC}" || echo -e "   MySQL:       ${RED}✗ Stopped${NC}"
    
    echo -e "\n${BLUE}🛠️  Useful Commands:${NC}"
    echo -e "   Check DHCP logs:    ${YELLOW}journalctl -u $DHCP_SERVICE -f${NC}"
    echo -e "   List DHCP leases:   ${YELLOW}dhcp-lease-list${NC}"
    echo -e "   Test DHCP config:   ${YELLOW}dhcpd -t -cf $DHCP_CONFIG${NC}"
    echo -e "   View configuration: ${YELLOW}cat /root/dhcp-phpipam-config.txt${NC}"
    
    echo -e "\n${GREEN}🎉 Installation completed successfully!${NC}"
    echo -e "${GREEN}=========================================${NC}\n"
}

# Main execution function
main() {
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}    DHCP + phpIPAM Setup Script${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${BLUE}This script will install and configure:${NC}"
    echo -e "  • ISC DHCP Server"
    echo -e "  • phpIPAM Web Interface"
    echo -e "  • Apache Web Server"
    echo -e "  • MySQL/MariaDB Database"
    echo -e "  • Firewall Configuration"
    echo ""
    
    read -p "Do you want to continue with the installation? (y/N): " CONFIRM
    if [[ $CONFIRM != [yY] && $CONFIRM != [yY][eE][sS] ]]; then
        echo "Installation cancelled."
        exit 0
    fi
    
    echo -e "\n${YELLOW}Starting installation process...${NC}\n"
    
    # Pre-installation checks
    check_root
    detect_os
    
    # Get configuration
    echo -e "${YELLOW}=== Configuration Phase ===${NC}"
    get_interface
    get_network_config
    get_phpipam_config
    
    # Installation phase
    echo -e "\n${YELLOW}=== Installation Phase ===${NC}"
    update_system
    install_dhcp_server
    install_lamp_stack
    
    # Configuration phase
    echo -e "\n${YELLOW}=== Configuration Phase ===${NC}"
    configure_mysql
    install_phpipam
    configure_phpipam
    configure_apache
    configure_dhcp
    configure_firewall
    set_dhcp_permissions
    
    # Final phase
    echo -e "\n${YELLOW}=== Final Phase ===${NC}"
    start_services
    test_configuration
    save_passwords
    
    # Show results
    show_summary
}

# Trap errors
trap 'error "Installation failed at line $LINENO"' ERR

# Run main function
main "$@"
