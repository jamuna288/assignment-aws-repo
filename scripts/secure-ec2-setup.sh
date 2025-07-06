#!/bin/bash

# Enhanced EC2 Security Setup Script
# Ensures secure SSH access, persistent agent hosting, and proper logging

set -e

echo "🔒 Starting Enhanced EC2 Security Setup..."
echo "Timestamp: $(date)"

# Variables
AGENT_USER="agent"
AGENT_HOME="/opt/agent"
LOG_DIR="/var/log/agent"
LOGS_DIR="/opt/agent/logs"

# Create logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/ec2-setup.log
}

log "Starting EC2 security configuration..."

# 1. SECURE SSH ACCESS CONFIGURATION
log "Configuring secure SSH access..."

# Backup original SSH config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d)

# Configure SSH for security
cat > /etc/ssh/sshd_config.d/99-security.conf << 'EOF'
# Enhanced SSH Security Configuration
Protocol 2
Port 22

# Authentication
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Security settings
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitTunnel no
GatewayPorts no

# Session settings
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
MaxSessions 2
LoginGraceTime 60

# Logging
SyslogFacility AUTH
LogLevel VERBOSE

# Allow specific users (ubuntu for GitHub Actions via SSM)
AllowUsers ubuntu agent
EOF

# Restart SSH service
systemctl restart sshd
log "SSH security configuration completed"

# 2. CONFIGURE AGENT USER AND DIRECTORIES
log "Setting up agent user and directories..."

# Create agent user if not exists
if ! id "$AGENT_USER" &>/dev/null; then
    useradd -m -s /bin/bash -d /home/$AGENT_USER $AGENT_USER
    log "Created agent user: $AGENT_USER"
fi

# Create directory structure
mkdir -p $AGENT_HOME/{current,releases,logs}
mkdir -p $LOG_DIR
mkdir -p $LOGS_DIR
mkdir -p /home/$AGENT_USER/.ssh

# Set proper permissions
chown -R $AGENT_USER:$AGENT_USER $AGENT_HOME
chown -R $AGENT_USER:$AGENT_USER $LOG_DIR
chown -R $AGENT_USER:$AGENT_USER $LOGS_DIR
chmod 755 $AGENT_HOME
chmod 755 $LOG_DIR
chmod 755 $LOGS_DIR

log "Agent directories created and configured"

# 3. CONFIGURE SYSTEMD SERVICE FOR PERSISTENT HOSTING
log "Configuring systemd service for persistent agent hosting..."

cat > /etc/systemd/system/agent-service.service << EOF
[Unit]
Description=Flight Agent Service - Persistent FastAPI Application
Documentation=https://github.com/jamuna288/assignment-aws-repo
After=network.target network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=$AGENT_USER
Group=$AGENT_USER
WorkingDirectory=$AGENT_HOME/current
Environment=PATH=$AGENT_HOME/current/venv/bin:/usr/local/bin:/usr/bin:/bin
Environment=PYTHONPATH=$AGENT_HOME/current
Environment=PYTHONUNBUFFERED=1

# Service execution
ExecStartPre=/bin/bash -c 'if [ ! -f $AGENT_HOME/current/main.py ]; then echo "No application found, using placeholder"; fi'
ExecStart=$AGENT_HOME/current/venv/bin/python -m uvicorn main:app --host 0.0.0.0 --port 8000 --workers 1
ExecReload=/bin/kill -HUP \$MAINPID

# Restart policy
Restart=always
RestartSec=10
StartLimitBurst=5

# Logging configuration - Save to logs/agent.log as requested
StandardOutput=append:$LOGS_DIR/agent.log
StandardError=append:$LOGS_DIR/agent-error.log

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$AGENT_HOME $LOG_DIR $LOGS_DIR /tmp

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF

# 4. CONFIGURE LOGGING SYSTEM
log "Setting up comprehensive logging system..."

# Create log rotation configuration
cat > /etc/logrotate.d/agent << EOF
$LOGS_DIR/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 $AGENT_USER $AGENT_USER
    postrotate
        systemctl reload agent-service || true
    endscript
}

$LOG_DIR/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 $AGENT_USER $AGENT_USER
    postrotate
        systemctl reload agent-service || true
    endscript
}
EOF

# Create logging configuration script
cat > $AGENT_HOME/setup-logging.sh << 'EOF'
#!/bin/bash
# Logging setup for agent application

LOGS_DIR="/opt/agent/logs"
LOG_DIR="/var/log/agent"

# Ensure log directories exist
mkdir -p $LOGS_DIR
mkdir -p $LOG_DIR

# Create initial log files with proper permissions
touch $LOGS_DIR/agent.log
touch $LOGS_DIR/agent-error.log
touch $LOG_DIR/deployment.log
touch $LOG_DIR/health-check.log

# Set permissions
chown -R agent:agent $LOGS_DIR
chown -R agent:agent $LOG_DIR
chmod 644 $LOGS_DIR/*.log
chmod 644 $LOG_DIR/*.log

echo "Logging setup completed at $(date)" >> $LOG_DIR/deployment.log
EOF

chmod +x $AGENT_HOME/setup-logging.sh
$AGENT_HOME/setup-logging.sh

# 5. CONFIGURE NGINX AS REVERSE PROXY
log "Configuring Nginx reverse proxy..."

cat > /etc/nginx/sites-available/agent << 'EOF'
server {
    listen 80;
    server_name _;
    
    # Logging
    access_log /var/log/nginx/agent-access.log;
    error_log /var/log/nginx/agent-error.log;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header X-Robots-Tag "noindex, nofollow" always;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_req zone=api burst=20 nodelay;

    # Main application proxy
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Health check endpoint
    location /health {
        proxy_pass http://127.0.0.1:8000/;
        proxy_set_header Host $host;
        access_log off;
    }

    # Nginx status for monitoring
    location /nginx_status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        deny all;
    }

    # Block sensitive files
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}
EOF

# Enable the site
ln -sf /etc/nginx/sites-available/agent /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test nginx configuration
nginx -t
log "Nginx configuration completed"

# 6. CREATE DEPLOYMENT SCRIPTS
log "Creating deployment scripts..."

cat > $AGENT_HOME/deploy.sh << 'EOF'
#!/bin/bash
# Deployment script for agent application

set -e

DEPLOYMENT_FILE="$1"
LOGS_DIR="/opt/agent/logs"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')

# Logging function
deploy_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEPLOY: $1" | tee -a $LOGS_DIR/deployment.log
}

deploy_log "Starting deployment with file: $DEPLOYMENT_FILE"

if [ -z "$DEPLOYMENT_FILE" ]; then
    deploy_log "ERROR: No deployment file specified"
    exit 1
fi

# Stop the service
deploy_log "Stopping agent service..."
sudo systemctl stop agent-service || true

# Backup current deployment
if [ -d "/opt/agent/current" ] && [ "$(ls -A /opt/agent/current)" ]; then
    deploy_log "Backing up current deployment..."
    sudo mkdir -p /opt/agent/releases
    sudo mv /opt/agent/current /opt/agent/releases/backup-$TIMESTAMP
fi

# Create new current directory
sudo mkdir -p /opt/agent/current
cd /opt/agent/current

# Extract new deployment
deploy_log "Extracting deployment package..."
sudo tar -xzf "$DEPLOYMENT_FILE" -C /opt/agent/current/

# Set permissions
sudo chown -R agent:agent /opt/agent/current/

# Setup virtual environment and install dependencies
deploy_log "Setting up Python environment..."
sudo -u agent python3 -m venv venv
sudo -u agent ./venv/bin/pip install --upgrade pip
sudo -u agent ./venv/bin/pip install -r requirements.txt

# Start the service
deploy_log "Starting agent service..."
sudo systemctl start agent-service
sudo systemctl enable agent-service

# Wait for service to start
sleep 10

# Health check
deploy_log "Performing health check..."
if curl -f http://localhost:8000/ > /dev/null 2>&1; then
    deploy_log "SUCCESS: Deployment completed successfully"
    # Clean up old backups (keep last 5)
    sudo find /opt/agent/releases -name "backup-*" -type d | sort | head -n -5 | xargs sudo rm -rf
else
    deploy_log "ERROR: Health check failed"
    exit 1
fi

deploy_log "Deployment completed at $(date)"
EOF

chmod +x $AGENT_HOME/deploy.sh

# 7. CREATE HEALTH CHECK SCRIPT
cat > /usr/local/bin/agent-health-check.sh << 'EOF'
#!/bin/bash
# Comprehensive health check script

LOGS_DIR="/opt/agent/logs"
LOG_FILE="$LOGS_DIR/health-check.log"

# Logging function
health_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] HEALTH: $1" | tee -a $LOG_FILE
}

# Check agent service
if ! systemctl is-active --quiet agent-service; then
    health_log "CRITICAL: Agent service is not running"
    exit 1
fi

# Check nginx service
if ! systemctl is-active --quiet nginx; then
    health_log "CRITICAL: Nginx is not running"
    exit 1
fi

# Check application response
if ! curl -f -s http://localhost:8000/ > /dev/null; then
    health_log "WARNING: Application not responding on port 8000"
    exit 1
fi

# Check log file sizes (prevent disk space issues)
if [ -f "$LOGS_DIR/agent.log" ]; then
    LOG_SIZE=$(stat -f%z "$LOGS_DIR/agent.log" 2>/dev/null || stat -c%s "$LOGS_DIR/agent.log" 2>/dev/null || echo 0)
    if [ "$LOG_SIZE" -gt 104857600 ]; then  # 100MB
        health_log "WARNING: Agent log file is large (${LOG_SIZE} bytes)"
    fi
fi

health_log "OK: All services are healthy"
exit 0
EOF

chmod +x /usr/local/bin/agent-health-check.sh

# 8. CREATE PLACEHOLDER APPLICATION
log "Creating placeholder application..."

cat > $AGENT_HOME/current/main.py << 'EOF'
import logging
import os
from datetime import datetime
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

# Configure logging to save to logs/agent.log
log_dir = "/opt/agent/logs"
os.makedirs(log_dir, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(f'{log_dir}/agent.log'),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

app = FastAPI(
    title="Flight Agent API - Placeholder",
    description="Secure agent service ready for deployment",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
async def root():
    logger.info("Root endpoint accessed")
    return {
        "message": "Agent service is running and ready for deployment",
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "version": "placeholder-1.0.0"
    }

@app.get("/health")
async def health_check():
    logger.info("Health check performed")
    return {
        "status": "healthy",
        "service": "agent-placeholder",
        "timestamp": datetime.now().isoformat()
    }

@app.get("/logs")
async def get_logs():
    """Endpoint to check if logging is working"""
    logger.info("Logs endpoint accessed - testing logging functionality")
    return {
        "message": "Logging is configured and working",
        "log_location": "/opt/agent/logs/agent.log",
        "timestamp": datetime.now().isoformat()
    }

if __name__ == "__main__":
    import uvicorn
    logger.info("Starting agent service...")
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

# Create requirements.txt for placeholder
cat > $AGENT_HOME/current/requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
python-multipart==0.0.6
EOF

# Set up placeholder application
cd $AGENT_HOME/current
python3 -m venv venv
./venv/bin/pip install --upgrade pip
./venv/bin/pip install -r requirements.txt
chown -R $AGENT_USER:$AGENT_USER $AGENT_HOME/current

# 9. CONFIGURE FIREWALL
log "Configuring firewall..."

# Install and configure UFW
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# Allow SSH (port 22)
ufw allow ssh

# Allow HTTP (port 80)
ufw allow http

# Allow HTTPS (port 443) for future SSL
ufw allow https

# Enable firewall
ufw --force enable

log "Firewall configured"

# 10. START SERVICES
log "Starting services..."

# Reload systemd
systemctl daemon-reload

# Enable and start services
systemctl enable agent-service
systemctl enable nginx

# Start nginx first
systemctl restart nginx

# Start agent service
systemctl restart agent-service

# Wait for services to start
sleep 15

# 11. FINAL VERIFICATION
log "Performing final verification..."

# Test services
if systemctl is-active --quiet agent-service && systemctl is-active --quiet nginx; then
    log "✅ SUCCESS: All services are running"
    
    # Test HTTP endpoint
    if curl -f http://localhost/ > /dev/null 2>&1; then
        log "✅ SUCCESS: HTTP endpoint is responding"
    else
        log "⚠️  WARNING: HTTP endpoint test failed"
    fi
    
    # Check log file creation
    if [ -f "$LOGS_DIR/agent.log" ]; then
        log "✅ SUCCESS: Log file created at $LOGS_DIR/agent.log"
    else
        log "⚠️  WARNING: Log file not found"
    fi
    
else
    log "❌ ERROR: Service startup failed"
    systemctl status agent-service
    systemctl status nginx
    exit 1
fi

# 12. CREATE CRON JOB FOR HEALTH CHECKS
log "Setting up health check cron job..."

# Add health check to crontab (every 5 minutes)
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/agent-health-check.sh") | crontab -

log "🎉 Enhanced EC2 Security Setup Completed Successfully!"
log "📋 Summary:"
log "   ✅ Secure SSH access configured"
log "   ✅ Agent service configured for persistent hosting"
log "   ✅ Logging configured to save to logs/agent.log"
log "   ✅ Nginx reverse proxy configured"
log "   ✅ Firewall configured"
log "   ✅ Health checks enabled"
log "   ✅ Log rotation configured"
log ""
log "🔍 Key locations:"
log "   - Application: /opt/agent/current/"
log "   - Logs: /opt/agent/logs/agent.log"
log "   - Service: systemctl status agent-service"
log "   - Health check: /usr/local/bin/agent-health-check.sh"
log ""
log "🌐 Test endpoints:"
log "   - http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)/"
log "   - http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)/health"
log "   - http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)/logs"

echo "Setup completed at $(date)" >> $LOGS_DIR/agent.log
