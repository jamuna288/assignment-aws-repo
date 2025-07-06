#!/bin/bash

# Security hardening script for EC2 instance
# Run this script after the initial setup to enhance security

set -e

echo "Starting security hardening..."

# Update system packages
sudo apt-get update && sudo apt-get upgrade -y

# Install security tools
sudo apt-get install -y \
    fail2ban \
    ufw \
    unattended-upgrades \
    logwatch \
    rkhunter \
    chkrootkit

# Configure automatic security updates
sudo dpkg-reconfigure -plow unattended-upgrades

# Configure fail2ban
sudo tee /etc/fail2ban/jail.local > /dev/null <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log

[nginx-limit-req]
enabled = true
filter = nginx-limit-req
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 10
EOF

# Start and enable fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Configure UFW firewall
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable

# Secure SSH configuration
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
sudo tee /etc/ssh/sshd_config > /dev/null <<EOF
# SSH Security Configuration
Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_dsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Authentication
LoginGraceTime 60
PermitRootLogin no
StrictModes yes
MaxAuthTries 3
MaxSessions 2
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Security options
X11Forwarding no
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes
Compression delayed
ClientAliveInterval 300
ClientAliveCountMax 2
AllowTcpForwarding no
AllowAgentForwarding no
GatewayPorts no
PermitTunnel no

# Logging
SyslogFacility AUTH
LogLevel INFO

# Override default of no subsystems
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

# Restart SSH service
sudo systemctl restart sshd

# Set up log rotation for application logs
sudo tee /etc/logrotate.d/agent-security > /dev/null <<EOF
/var/log/agent/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 agent agent
    postrotate
        systemctl reload agent-service
    endscript
}

/var/log/nginx/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 www-data www-data
    postrotate
        systemctl reload nginx
    endscript
}
EOF

# Configure system limits
sudo tee /etc/security/limits.conf > /dev/null <<EOF
# Security limits
* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768
root soft nofile 65536
root hard nofile 65536
EOF

# Configure kernel parameters for security
sudo tee /etc/sysctl.d/99-security.conf > /dev/null <<EOF
# IP Spoofing protection
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.rp_filter = 1

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Ignore send redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Disable source packet routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Log Martians
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Ignore ICMP ping requests
net.ipv4.icmp_echo_ignore_all = 1

# Ignore Directed pings
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Disable IPv6 if not needed
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

# TCP SYN flood protection
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# Connection tracking
net.netfilter.nf_conntrack_max = 65536
net.netfilter.nf_conntrack_tcp_timeout_established = 1800
EOF

# Apply kernel parameters
sudo sysctl -p /etc/sysctl.d/99-security.conf

# Set up file integrity monitoring
sudo tee /etc/cron.daily/file-integrity-check > /dev/null <<'EOF'
#!/bin/bash
# File integrity monitoring

LOGFILE="/var/log/file-integrity.log"
CHECKDIRS="/opt/agent /etc/nginx /etc/systemd/system/agent-service.service"

echo "$(date): Starting file integrity check" >> $LOGFILE

for dir in $CHECKDIRS; do
    if [ -d "$dir" ] || [ -f "$dir" ]; then
        find "$dir" -type f -exec sha256sum {} \; >> /tmp/current-checksums.txt 2>/dev/null
    fi
done

if [ -f /var/lib/file-checksums.txt ]; then
    if ! diff /var/lib/file-checksums.txt /tmp/current-checksums.txt > /dev/null; then
        echo "$(date): File integrity check FAILED - changes detected" >> $LOGFILE
        diff /var/lib/file-checksums.txt /tmp/current-checksums.txt >> $LOGFILE
    else
        echo "$(date): File integrity check PASSED" >> $LOGFILE
    fi
else
    echo "$(date): Initial file integrity baseline created" >> $LOGFILE
fi

mv /tmp/current-checksums.txt /var/lib/file-checksums.txt
EOF

sudo chmod +x /etc/cron.daily/file-integrity-check

# Configure audit logging
sudo apt-get install -y auditd
sudo tee /etc/audit/rules.d/agent.rules > /dev/null <<EOF
# Audit rules for agent application
-w /opt/agent -p wa -k agent-files
-w /etc/systemd/system/agent-service.service -p wa -k agent-service
-w /etc/nginx/sites-available/agent -p wa -k nginx-config
-w /var/log/agent -p wa -k agent-logs
EOF

sudo systemctl enable auditd
sudo systemctl restart auditd

# Set up intrusion detection
sudo rkhunter --update
sudo rkhunter --propupd

# Create security monitoring script
sudo tee /usr/local/bin/security-monitor.sh > /dev/null <<'EOF'
#!/bin/bash
# Security monitoring script

LOGFILE="/var/log/security-monitor.log"

# Check for failed login attempts
FAILED_LOGINS=$(grep "Failed password" /var/log/auth.log | tail -10 | wc -l)
if [ $FAILED_LOGINS -gt 5 ]; then
    echo "$(date): WARNING: $FAILED_LOGINS failed login attempts detected" >> $LOGFILE
fi

# Check for unusual network connections
CONNECTIONS=$(netstat -an | grep :8000 | wc -l)
if [ $CONNECTIONS -gt 100 ]; then
    echo "$(date): WARNING: High number of connections ($CONNECTIONS) to application port" >> $LOGFILE
fi

# Check disk usage
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ $DISK_USAGE -gt 80 ]; then
    echo "$(date): WARNING: Disk usage is at $DISK_USAGE%" >> $LOGFILE
fi

# Check memory usage
MEM_USAGE=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
if [ $MEM_USAGE -gt 80 ]; then
    echo "$(date): WARNING: Memory usage is at $MEM_USAGE%" >> $LOGFILE
fi

# Check if agent service is running
if ! systemctl is-active --quiet agent-service; then
    echo "$(date): CRITICAL: Agent service is not running" >> $LOGFILE
fi
EOF

sudo chmod +x /usr/local/bin/security-monitor.sh

# Set up cron job for security monitoring
echo "*/5 * * * * root /usr/local/bin/security-monitor.sh" | sudo tee -a /etc/crontab

# Create security report script
sudo tee /usr/local/bin/security-report.sh > /dev/null <<'EOF'
#!/bin/bash
# Generate daily security report

REPORT_FILE="/var/log/security-report-$(date +%Y%m%d).log"

echo "Security Report for $(date)" > $REPORT_FILE
echo "=================================" >> $REPORT_FILE
echo "" >> $REPORT_FILE

echo "System Information:" >> $REPORT_FILE
echo "- Hostname: $(hostname)" >> $REPORT_FILE
echo "- Uptime: $(uptime)" >> $REPORT_FILE
echo "- Load Average: $(cat /proc/loadavg)" >> $REPORT_FILE
echo "" >> $REPORT_FILE

echo "Security Status:" >> $REPORT_FILE
echo "- Fail2ban Status: $(systemctl is-active fail2ban)" >> $REPORT_FILE
echo "- UFW Status: $(ufw status | head -1)" >> $REPORT_FILE
echo "- SSH Service: $(systemctl is-active sshd)" >> $REPORT_FILE
echo "- Agent Service: $(systemctl is-active agent-service)" >> $REPORT_FILE
echo "" >> $REPORT_FILE

echo "Recent Failed Logins:" >> $REPORT_FILE
grep "Failed password" /var/log/auth.log | tail -5 >> $REPORT_FILE
echo "" >> $REPORT_FILE

echo "Disk Usage:" >> $REPORT_FILE
df -h >> $REPORT_FILE
echo "" >> $REPORT_FILE

echo "Memory Usage:" >> $REPORT_FILE
free -h >> $REPORT_FILE
echo "" >> $REPORT_FILE

echo "Network Connections:" >> $REPORT_FILE
netstat -an | grep :8000 | wc -l | xargs echo "Active connections to port 8000:" >> $REPORT_FILE
EOF

sudo chmod +x /usr/local/bin/security-report.sh

# Set up daily security report
echo "0 6 * * * root /usr/local/bin/security-report.sh" | sudo tee -a /etc/crontab

# Restart services
sudo systemctl restart cron

echo "Security hardening completed successfully!"
echo "Please review the following:"
echo "1. SSH configuration has been updated - password authentication disabled"
echo "2. Firewall (UFW) has been enabled"
echo "3. Fail2ban has been configured"
echo "4. Security monitoring scripts have been installed"
echo "5. File integrity monitoring has been set up"
echo "6. Audit logging has been enabled"
echo ""
echo "Security logs location:"
echo "- Security monitor: /var/log/security-monitor.log"
echo "- Daily reports: /var/log/security-report-*.log"
echo "- File integrity: /var/log/file-integrity.log"
echo "- Fail2ban: /var/log/fail2ban.log"
