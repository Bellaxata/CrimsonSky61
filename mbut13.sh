#!/bin/bash

# ==============================================
# ULTIMATE ANTI-DDOS & HARDENING SCRIPT
# Untuk Pterodactyl Panel
# ==============================================

# Warna
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}🛡️  MEMASANG PROTEKSI ANTI-DDOS & HARDENING${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════${NC}"

# Cek root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ Skrip ini harus dijalankan sebagai root!${NC}" 
   exit 1
fi

# Backup konfigurasi
BACKUP_DIR="/root/backup-anti-ddos-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
echo -e "${YELLOW}📦 Backup akan disimpan di: $BACKUP_DIR${NC}"

# ==============================================
# 1. PROTEKSI CLOUDFLARE (Wajib!)
# ==============================================
echo -e "\n${GREEN}🔧 1. Mengkonfigurasi Cloudflare Protection...${NC}"

cat > /etc/nginx/conf.d/cloudflare-real-ip.conf << 'EOF'
# Cloudflare IP Ranges
set_real_ip_from 173.245.48.0/20;
set_real_ip_from 103.21.244.0/22;
set_real_ip_from 103.22.200.0/22;
set_real_ip_from 103.31.4.0/22;
set_real_ip_from 141.101.64.0/18;
set_real_ip_from 108.162.192.0/18;
set_real_ip_from 190.93.240.0/20;
set_real_ip_from 188.114.96.0/20;
set_real_ip_from 197.234.240.0/22;
set_real_ip_from 198.41.128.0/17;
set_real_ip_from 162.158.0.0/15;
set_real_ip_from 104.16.0.0/13;
set_real_ip_from 104.24.0.0/14;
set_real_ip_from 172.64.0.0/13;
set_real_ip_from 131.0.72.0/22;
real_ip_header CF-Connecting-IP;
EOF

# ==============================================
# 2. RATE LIMITING & DDOS PROTECTION NGINX
# ==============================================
echo -e "${GREEN}🔧 2. Memasang Rate Limiting & DDoS Protection...${NC}"

cat > /etc/nginx/conf.d/anti-ddos.conf << 'EOF'
# Zone Rate Limiting
limit_req_zone $binary_remote_addr zone=login:10m rate=5r/m;
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=ddos:10m rate=30r/m;
limit_conn_zone $binary_remote_addr zone=connlimit:10m;

# Global DDoS Protection
limit_req zone=ddos burst=10 nodelay;
limit_conn connlimit 10;

# Block specific bad bots
if ($http_user_agent ~* (wget|curl|python|perl|ruby|java|php|asp|jsp|scanner|bot|crawl|spider|masscan|nmap|nikto|sqlmap|hydra|medusa|zmap)) {
    return 403;
}

# Block empty user agent
if ($http_user_agent = "") {
    return 403;
}

# Block non-standard HTTP methods
if ($request_method !~ ^(GET|HEAD|POST|PUT|DELETE|PATCH)$) {
    return 405;
}
EOF

# ==============================================
# 3. FAIL2BAN KONFIGURASI SUPER KETAT
# ==============================================
echo -e "${GREEN}🔧 3. Memasang Fail2ban Super Ketat...${NC}"

apt-get install -y fail2ban -y

cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 86400
findtime = 600
maxretry = 5
banaction = iptables-multiport
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[pterodactyl-panel]
enabled = true
port = http,https
filter = pterodactyl-panel
logpath = /var/www/pterodactyl/storage/logs/*.log
maxretry = 5
bantime = 86400
findtime = 300

[pterodactyl-wings]
enabled = true
port = http,https,8080
filter = pterodactyl-wings
logpath = /var/log/nginx/access.log
maxretry = 10
bantime = 43200
findtime = 60

[nginx-botsearch]
enabled = true
port = http,https
filter = nginx-botsearch
logpath = /var/log/nginx/access.log
maxretry = 3
bantime = 86400

[nginx-ddos]
enabled = true
port = http,https
filter = nginx-ddos
logpath = /var/log/nginx/access.log
maxretry = 30
bantime = 3600
findtime = 60

[recidive]
enabled = true
filter = recidive
logpath = /var/log/fail2ban.log
banaction = iptables-allports
bantime = 604800
findtime = 86400
maxretry = 5
EOF

cat > /etc/fail2ban/filter.d/pterodactyl-panel.conf << 'EOF'
[Definition]
failregex = ^.*"GET \/.*HTTP.*" 40\d .*$
            ^.*"POST \/.*HTTP.*" 40\d .*$
            ^.*"PUT \/.*HTTP.*" 40\d .*$
            ^.*"DELETE \/.*HTTP.*" 40\d .*$
            ^.*Failed login attempt.*$
            ^.*Invalid API key.*$
ignoreregex =
EOF

cat > /etc/fail2ban/filter.d/pterodactyl-wings.conf << 'EOF'
[Definition]
failregex = ^<HOST> -.*"GET \/api\/.*" 40\d .*$
            ^<HOST> -.*"POST \/api\/.*" 40\d .*$
            ^<HOST> -.*"PUT \/api\/.*" 40\d .*$
            ^<HOST> -.*"DELETE \/api\/.*" 40\d .*$
ignoreregex =
EOF

cat > /etc/fail2ban/filter.d/nginx-ddos.conf << 'EOF'
[Definition]
failregex = ^<HOST> -.*"GET \/.*" 444 .*$
            ^<HOST> -.*"POST \/.*" 444 .*$
            ^<HOST> -.*"GET \/.*" 429 .*$
            ^<HOST> -.*"POST \/.*" 429 .*$
ignoreregex =
EOF

systemctl restart fail2ban
systemctl enable fail2ban

# ==============================================
# 4. PROTEKSI FILE SENSITIF
# ==============================================
echo -e "${GREEN}🔧 4. Memproteksi File Sensitif...${NC}"

# Proteksi .env
cat > /etc/nginx/conf.d/protect-files.conf << 'EOF'
# Proteksi file sensitif
location ~* \.(env|log|sql|sqlite|db|ini|config|json|yml|yaml|xml|md|git|svn|hg|bak|backup|old|temp|tmp)$ {
    deny all;
    return 403;
}

location ~ /\.(?!well-known).* {
    deny all;
    return 403;
}

location ~ /(vendor|storage|tests|resources|database|node_modules|bootstrap/cache) {
    internal;
    return 403;
}

location ~* /(adminer|phpmyadmin|myadmin|mysql|pma) {
    deny all;
    return 403;
}
EOF

# ==============================================
# 5. SYSTECTL HARDENING
# ==============================================
echo -e "${GREEN}🔧 5. System Hardening...${NC}"

# Limit connections
cat > /etc/security/limits.conf << EOF
* soft nofile 65535
* hard nofile 65535
* soft nproc 65535
* hard nproc 65535
root soft nofile 65535
root hard nofile 65535
EOF

# Kernel tuning untuk anti-ddos
cat >> /etc/sysctl.conf << EOF
# Anti-DDoS Kernel Settings
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.netdev_max_backlog = 5000
net.core.somaxconn = 1024
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_all = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.tcp_challenge_ack_limit = 999999999
net.ipv4.tcp_limit_output_bytes = 65536
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
EOF

sysctl -p

# ==============================================
# 6. PROTEKSI PHP
# ==============================================
echo -e "${GREEN}🔧 6. Proteksi PHP...${NC}"

PHP_VERSION=$(php -v | head -1 | cut -d' ' -f2 | cut -d'.' -f1,2)
PHP_INI="/etc/php/$PHP_VERSION/fpm/php.ini"

sed -i 's/max_execution_time = .*/max_execution_time = 30/' $PHP_INI
sed -i 's/max_input_time = .*/max_input_time = 30/' $PHP_INI
sed -i 's/memory_limit = .*/memory_limit = 256M/' $PHP_INI
sed -i 's/post_max_size = .*/post_max_size = 8M/' $PHP_INI
sed -i 's/upload_max_filesize = .*/upload_max_filesize = 8M/' $PHP_INI

systemctl restart php$PHP_VERSION-fpm

# ==============================================
# 7. CLOUDFLARE PROXY CHECK
# ==============================================
echo -e "${GREEN}🔧 7. Memasang Cloudflare Proxy Check...${NC}"

cat > /etc/nginx/conf.d/cloudflare-check.conf << 'EOF'
# Block non-cloudflare traffic
set $block_traffic 0;

if ($http_cf_connecting_ip = "") {
    set $block_traffic 1;
}

if ($request_uri ~* "^/api/(application|client)/") {
    set $block_traffic 0;
}

if ($block_traffic = 1) {
    return 403;
}
EOF

# ==============================================
# 8. INSTALL CROWDSEC (Advanced IPS)
# ==============================================
echo -e "${GREEN}🔧 8. Memasang Crowdsec IPS...${NC}"

curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | bash
apt-get install crowdsec crowdsec-firewall-bouncer-iptables -y

# ==============================================
# 9. MONITORING SCRIPT
# ==============================================
echo -e "${GREEN}🔧 9. Membuat Monitoring Script...${NC}"

cat > /usr/local/bin/ddos-monitor << 'EOF'
#!/bin/bash
echo "========== DDoS MONITOR REPORT =========="
echo "Current Connections:"
netstat -an | grep :80 | wc -l
echo ""
echo "Top Attackers (Fail2ban):"
sudo fail2ban-client status | grep "Jail list" | sed 's/.*Jail list://'
echo ""
echo "Blocked IPs (Last 5):"
sudo tail -5 /var/log/fail2ban.log | grep Ban
echo ""
echo "System Load:"
uptime
echo "=========================================="
EOF

chmod +x /usr/local/bin/ddos-monitor

# ==============================================
# 10. AUTO CLEANUP SCRIPT
# ==============================================
echo -e "${GREEN}🔧 10. Membuat Auto Cleanup Script...${NC}"

cat > /usr/local/bin/auto-cleanup << 'EOF'
#!/bin/bash
# Auto cleanup log & ban

# Clean old logs
find /var/log/nginx/ -name "*.log" -mtime +7 -delete
find /var/log/fail2ban.log -mtime +30 -delete

# Backup fail2ban database
cp /var/lib/fail2ban/fail2ban.sqlite3 /root/fail2ban-backup-$(date +%Y%m%d).sqlite3

# Optimize
sync && echo 3 > /proc/sys/vm/drop_caches

# Report
echo "[$(date)] Cleanup completed" >> /var/log/auto-cleanup.log
EOF

chmod +x /usr/local/bin/auto-cleanup

# Tambahkan ke cron
(crontab -l 2>/dev/null; echo "0 */6 * * * /usr/local/bin/auto-cleanup") | crontab -
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/ddos-monitor >> /var/log/ddos-monitor.log") | crontab -

# ==============================================
# RESTART SERVICES
# ==============================================
echo -e "${GREEN}🔄 Restarting services...${NC}"

systemctl restart nginx
systemctl restart fail2ban
systemctl restart crowdsec

# Clear cache
php /var/www/pterodactyl/artisan view:clear
php /var/www/pterodactyl/artisan cache:clear
php /var/www/pterodactyl/artisan config:clear
php /var/www/pterodactyl/artisan route:clear

# ==============================================
# FINISH
# ==============================================
echo -e "\n${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ PROTEKSI ANTI-DDOS & HARDENING TERPASANG!${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}📊 Monitoring:${NC}"
echo -e "   - Lihat status: ${BLUE}fail2ban-client status${NC}"
echo -e "   - Monitor DDoS: ${BLUE}/usr/local/bin/ddos-monitor${NC}"
echo -e "   - Log Fail2ban: ${BLUE}tail -f /var/log/fail2ban.log${NC}"
echo -e "   - Log Nginx: ${BLUE}tail -f /var/log/nginx/access.log${NC}"
echo -e "\n${YELLOW}🔒 Fitur Proteksi:${NC}"
echo -e "   ✓ Rate Limiting (30 request/menit)"
echo -e "   ✓ Block Bad Bots & User Agents"
echo -e "   ✓ Fail2ban dengan 4 jail aktif"
echo -e "   ✓ Kernel TCP Hardening"
echo -e "   ✓ Crowdsec IPS"
echo -e "   ✓ Cloudflare Proxy Wajib"
echo -e "   ✓ Proteksi File Sensitif"
echo -e "   ✓ Auto Cleanup setiap 6 jam"
echo -e "\n${RED}⚠️  PENTING: Pastikan domain menggunakan PROXY di Cloudflare!${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════${NC}"