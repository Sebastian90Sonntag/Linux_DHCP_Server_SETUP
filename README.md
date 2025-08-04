# Linux_DHCP_Server_SETUP

# ISC DHCP Server + phpIPAM Setup Guide

## Übersicht

Diese Dokumentation beschreibt die Installation und Konfiguration von:
- **ISC DHCP Server** - für die DHCP-Funktionalität
- **phpIPAM** - für das Web-Management Interface

## Systemanforderungen

### Minimale Anforderungen
- **OS**: Ubuntu 20.04+ / Debian 11+ / CentOS 8+ / RHEL 8+
- **RAM**: 2GB minimum, 4GB empfohlen
- **Festplatte**: 10GB freier Speicher
- **Netzwerk**: Statische IP-Adresse empfohlen

### Software-Abhängigkeiten
- Apache2/Nginx Webserver
- PHP 7.4+ (8.0+ empfohlen)
- MySQL/MariaDB 10.3+
- ISC DHCP Server
- Git

## 1. Systemvorbereitung

### System aktualisieren
```bash
# Ubuntu/Debian
sudo apt update && sudo apt upgrade -y

# CentOS/RHEL/Fedora
sudo dnf update -y
# oder
sudo yum update -y
```

### Firewall-Ports öffnen
```bash
# UFW (Ubuntu)
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 80/tcp      # HTTP
sudo ufw allow 443/tcp     # HTTPS
sudo ufw allow 67/udp      # DHCP Server
sudo ufw allow 68/udp      # DHCP Client
sudo ufw enable

# Firewalld (CentOS/RHEL)
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --permanent --add-service=dhcp
sudo firewall-cmd --reload
```

## 2. ISC DHCP Server Installation

### Installation
```bash
# Ubuntu/Debian
sudo apt install -y isc-dhcp-server

# CentOS/RHEL/Fedora
sudo dnf install -y dhcp-server
# oder
sudo yum install -y dhcp-server
```

### Grundkonfiguration

#### Interface konfigurieren (Ubuntu/Debian)
```bash
sudo nano /etc/default/isc-dhcp-server
```
```ini
# Interface definieren
INTERFACESv4="eth0"
```

#### DHCP-Konfiguration erstellen
```bash
sudo nano /etc/dhcp/dhcpd.conf
```

```apache
# ISC DHCP Server Konfiguration
# Globale Einstellungen
default-lease-time 86400;
max-lease-time 172800;
authoritative;

# Logging
log-facility local7;

# Subnet Konfiguration
subnet 192.168.1.0 netmask 255.255.255.0 {
    range 192.168.1.100 192.168.1.200;
    option routers 192.168.1.1;
    option domain-name-servers 8.8.8.8, 8.8.4.4;
    option domain-name "local";
    option broadcast-address 192.168.1.255;
    
    # DDNS Updates für phpIPAM
    ddns-update-style interim;
    ddns-updates on;
}

# Statische Reservierungen
host server1 {
    hardware ethernet 00:11:22:33:44:55;
    fixed-address 192.168.1.10;
    option host-name "server1";
}
```

### Service starten
```bash
# Konfiguration testen
sudo dhcpd -t -cf /etc/dhcp/dhcpd.conf

# Service aktivieren und starten
sudo systemctl enable isc-dhcp-server  # Ubuntu/Debian
sudo systemctl enable dhcpd            # CentOS/RHEL

sudo systemctl start isc-dhcp-server   # Ubuntu/Debian
sudo systemctl start dhcpd             # CentOS/RHEL

# Status prüfen
sudo systemctl status isc-dhcp-server  # Ubuntu/Debian
sudo systemctl status dhcpd            # CentOS/RHEL
```

## 3. LAMP Stack Installation

### Apache, MySQL, PHP installieren

#### Ubuntu/Debian
```bash
sudo apt install -y apache2 mysql-server php php-mysql php-gd php-curl \
    php-json php-mbstring php-xml php-zip php-ldap php-snmp php-gmp \
    libapache2-mod-php git
```

#### CentOS/RHEL/Fedora
```bash
sudo dnf install -y httpd mariadb-server php php-mysqlnd php-gd php-curl \
    php-json php-mbstring php-xml php-zip php-ldap php-snmp php-gmp git

# Services aktivieren
sudo systemctl enable httpd mariadb
sudo systemctl start httpd mariadb
```

### MySQL/MariaDB konfigurieren
```bash
sudo mysql_secure_installation
```

### Datenbank für phpIPAM erstellen
```bash
sudo mysql -u root -p
```

```sql
CREATE DATABASE phpipam;
CREATE USER 'phpipam'@'localhost' IDENTIFIED BY 'StarkesPasswort123!';
GRANT ALL PRIVILEGES ON phpipam.* TO 'phpipam'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

## 4. phpIPAM Installation

### Quellcode herunterladen
```bash
cd /var/www/html
sudo git clone https://github.com/phpipam/phpipam.git
sudo chown -R www-data:www-data phpipam/  # Ubuntu/Debian
sudo chown -R apache:apache phpipam/      # CentOS/RHEL
```

### Konfigurationsdatei erstellen
```bash
cd /var/www/html/phpipam
sudo cp config.dist.php config.php
sudo nano config.php
```

```php
<?php
/**
 * phpIPAM Konfiguration
 */

/* Datenbank Verbindung */
$db['host'] = 'localhost';
$db['user'] = 'phpipam';
$db['pass'] = 'StarkesPasswort123!';
$db['name'] = 'phpipam';
$db['port'] = 3306;

/* Base URL */
define('BASE', '/phpipam/');

/* SSL */
$ssl_ca     = false;
$ssl_key    = false;
$ssl_cert   = false;

/* Debugging */
$debugging = false;

/* DHCP Integration */
$dhcp = array(
    'type' => 'isc',
    'config' => '/etc/dhcp/dhcpd.conf',
    'leases' => '/var/lib/dhcp/dhcpd.leases'
);
?>
```

### Berechtigungen setzen
```bash
sudo chmod 755 /var/www/html/phpipam
sudo chmod 644 /var/www/html/phpipam/config.php

# Temp-Verzeichnis für phpIPAM
sudo mkdir -p /var/www/html/phpipam/app/temp
sudo chown -R www-data:www-data /var/www/html/phpipam/app/temp  # Ubuntu
sudo chown -R apache:apache /var/www/html/phpipam/app/temp      # CentOS
```

## 5. Apache Konfiguration

### Virtual Host erstellen
```bash
sudo nano /etc/apache2/sites-available/phpipam.conf  # Ubuntu/Debian
sudo nano /etc/httpd/conf.d/phpipam.conf             # CentOS/RHEL
```

```apache
<VirtualHost *:80>
    ServerName dhcp.local
    DocumentRoot /var/www/html/phpipam
    
    <Directory /var/www/html/phpipam>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    # Logging
    ErrorLog ${APACHE_LOG_DIR}/phpipam_error.log
    CustomLog ${APACHE_LOG_DIR}/phpipam_access.log combined
</VirtualHost>
```

### Site aktivieren (Ubuntu/Debian)
```bash
sudo a2ensite phpipam.conf
sudo a2enmod rewrite
sudo systemctl reload apache2
```

### Apache neustarten
```bash
sudo systemctl restart apache2  # Ubuntu/Debian
sudo systemctl restart httpd    # CentOS/RHEL
```

## 6. phpIPAM Web-Installation

### Browser-Installation
1. Öffne: `http://server-ip/phpipam/`
2. Wähle: **"New phpipam installation"**
3. Folge dem Installations-Assistenten:
   - Datenbankverbindung testen
   - Admin-Benutzer erstellen
   - Installation abschließen

### Erste Konfiguration

#### 1. Anmeldung
- URL: `http://server-ip/phpipam/`
- Benutzer: `admin`
- Passwort: wie bei Installation festgelegt

#### 2. Grundeinrichtung
1. **Administration** → **IP related management** → **Sections**
   - Neue Sektion erstellen (z.B. "LAN")

2. **Administration** → **IP related management** → **Subnets**
   - Neues Subnet hinzufügen: `192.168.1.0/24`
   - DHCP aktivieren

3. **Administration** → **Server management** → **Nameservers**
   - DNS-Server hinzufügen: `8.8.8.8`, `8.8.4.4`

## 7. DHCP Integration konfigurieren

### DHCP-Berechtigungen für phpIPAM
```bash
# phpIPAM-Benutzer zur dhcp-Gruppe hinzufügen
sudo usermod -a -G dhcpd www-data  # Ubuntu
sudo usermod -a -G dhcpd apache    # CentOS

# Leseberechtigungen für DHCP-Dateien
sudo chmod 644 /etc/dhcp/dhcpd.conf
sudo chmod 644 /var/lib/dhcp/dhcpd.leases
```

### DHCP-Modul in phpIPAM aktivieren
1. **Administration** → **Server management** → **DHCP servers**
2. **Add DHCP server**:
   - Name: `Main DHCP Server`
   - Type: `ISC DHCP`
   - Hostname: `localhost`
   - Config file: `/etc/dhcp/dhcpd.conf`
   - Leases file: `/var/lib/dhcp/dhcpd.leases`

### Subnet mit DHCP verknüpfen
1. **Subnets** → Subnet auswählen → **Edit**
2. **DHCP** Tab:
   - DHCP server auswählen
   - **Enable DHCP** aktivieren

## 8. Monitoring und Wartung

### Log-Dateien überwachen
```bash
# DHCP Logs
sudo tail -f /var/log/syslog | grep dhcp  # Ubuntu/Debian
sudo tail -f /var/log/messages | grep dhcp # CentOS/RHEL

# Apache Logs
sudo tail -f /var/log/apache2/phpipam_error.log  # Ubuntu
sudo tail -f /var/log/httpd/phpipam_error.log    # CentOS

# DHCP Leases anzeigen
sudo dhcp-lease-list
```

### Backup-Strategien

#### DHCP-Konfiguration sichern
```bash
#!/bin/bash
# backup-dhcp.sh
DATE=$(date +%Y%m%d_%H%M%S)
cp /etc/dhcp/dhcpd.conf /backup/dhcpd.conf.$DATE
cp /var/lib/dhcp/dhcpd.leases /backup/dhcpd.leases.$DATE
```

#### phpIPAM-Datenbank sichern
```bash
#!/bin/bash
# backup-phpipam.sh
DATE=$(date +%Y%m%d_%H%M%S)
mysqldump -u phpipam -p phpipam > /backup/phpipam_$DATE.sql
```

## 9. Troubleshooting

### Häufige Probleme

#### DHCP-Server startet nicht
```bash
# Konfiguration prüfen
sudo dhcpd -t -cf /etc/dhcp/dhcpd.conf

# Interface prüfen
ip addr show

# Logs anzeigen
sudo journalctl -u isc-dhcp-server -f  # Ubuntu
sudo journalctl -u dhcpd -f            # CentOS
```

#### phpIPAM kann DHCP-Dateien nicht lesen
```bash
# Berechtigungen prüfen
ls -la /etc/dhcp/dhcpd.conf
ls -la /var/lib/dhcp/dhcpd.leases

# SELinux prüfen (CentOS/RHEL)
sudo setsebool -P httpd_can_network_connect 1
sudo setsebool -P httpd_unified 1
```

#### Datenbank-Verbindungsfehler
```bash
# MySQL-Status prüfen
sudo systemctl status mysql      # Ubuntu/Debian
sudo systemctl status mariadb    # CentOS/RHEL

# Verbindung testen
mysql -u phpipam -p -h localhost phpipam
```

### Performance-Optimierung

#### Apache-Tuning
```apache
# /etc/apache2/conf-available/performance.conf
ServerTokens Prod
ServerSignature Off
KeepAlive On
MaxKeepAliveRequests 100
KeepAliveTimeout 5
```

#### MySQL-Tuning
```bash
sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf  # Ubuntu
sudo nano /etc/my.cnf                         # CentOS
```

```ini
[mysqld]
innodb_buffer_pool_size = 1G
query_cache_size = 128M
query_cache_type = 1
max_connections = 200
```

## 10. Sicherheitsempfehlungen

### SSL/HTTPS aktivieren
```bash
# Let's Encrypt installieren
sudo apt install certbot python3-certbot-apache  # Ubuntu
sudo dnf install certbot python3-certbot-apache  # CentOS

# Zertifikat erstellen
sudo certbot --apache -d dhcp.yourdomain.com
```

### Zugriffsbeschränkungen
```apache
<Directory /var/www/html/phpipam>
    # IP-basierte Zugriffsbeschränkung
    <RequireAll>
        Require ip 192.168.1.0/24
        Require ip 10.0.0.0/8
    </RequireAll>
</Directory>
```

### Firewall-Härtung
```bash
# Nur notwendige Ports öffnen
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.1.0/24 to any port 22
sudo ufw allow from 192.168.1.0/24 to any port 80
sudo ufw allow from 192.168.1.0/24 to any port 443
sudo ufw allow 67/udp
sudo ufw allow 68/udp
sudo ufw enable
```

## 11. Erweiterte Funktionen

### DHCP-Reservierungen über phpIPAM verwalten
1. **IP addresses** → IP-Adresse auswählen
2. **Edit** → **DHCP reservation**
3. MAC-Adresse eingeben
4. **Save** → Konfiguration wird automatisch aktualisiert

### VLAN-Support
```apache
# DHCP-Konfiguration für VLANs
shared-network office {
    subnet 192.168.1.0 netmask 255.255.255.0 {
        range 192.168.1.100 192.168.1.150;
        option routers 192.168.1.1;
    }
    
    subnet 192.168.2.0 netmask 255.255.255.0 {
        range 192.168.2.100 192.168.2.150;
        option routers 192.168.2.1;
    }
}
```

### API-Integration
```bash
# phpIPAM API aktivieren
# Administration → phpIPAM settings → Feature settings
# API: Enable
```

## 12. Wartungsplan

### Tägliche Aufgaben
- [ ] DHCP-Logs prüfen
- [ ] Freie IP-Adressen überwachen
- [ ] System-Performance überwachen

### Wöchentliche Aufgaben
- [ ] Backups erstellen
- [ ] Lease-Database aufräumen
- [ ] Updates prüfen

### Monatliche Aufgaben
- [ ] Sicherheits-Updates installieren
- [ ] Konfiguration dokumentieren
- [ ] Disaster Recovery testen

---

## Anhang

### Wichtige Pfade

| Komponente | Ubuntu/Debian | CentOS/RHEL |
|------------|---------------|-------------|
| DHCP Config | `/etc/dhcp/dhcpd.conf` | `/etc/dhcp/dhcpd.conf` |
| DHCP Leases | `/var/lib/dhcp/dhcpd.leases` | `/var/lib/dhcpd/dhcpd.leases` |
| Apache Config | `/etc/apache2/sites-available/` | `/etc/httpd/conf.d/` |
| PHP Config | `/etc/php/*/apache2/php.ini` | `/etc/php.ini` |
| MySQL Config | `/etc/mysql/mysql.conf.d/` | `/etc/my.cnf` |

### Standard-Ports

| Service | Port | Protokoll |
|---------|------|-----------|
| DHCP Server | 67 | UDP |
| DHCP Client | 68 | UDP |
| HTTP | 80 | TCP |
| HTTPS | 443 | TCP |
| MySQL | 3306 | TCP |

### Nützliche Befehle
```bash
# DHCP-Status prüfen
sudo systemctl status isc-dhcp-server
sudo dhcp-lease-list

# phpIPAM-Logs
sudo tail -f /var/log/apache2/phpipam_error.log

# Datenbank-Backup
mysqldump -u phpipam -p phpipam > backup.sql

# Konfiguration testen
sudo dhcpd -t -cf /etc/dhcp/dhcpd.conf
sudo apache2ctl configtest
```
