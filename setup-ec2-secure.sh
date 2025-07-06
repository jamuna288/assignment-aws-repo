#!/bin/bash

# 🔒 Comprehensive EC2 Setup Script for Secure Agent Deployment
# This script ensures all three requirements are met:
# 1. Secure SSH access from GitHub Actions
# 2. Persistent agent hosting
# 3. Logging to logs/agent.log

set -e

echo "🚀 Starting Comprehensive EC2 Setup for Agent Deployment"
echo "Timestamp: $(date)"
echo "=========================================================="

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo "⚠️  This script should not be run as root. Please run as ubuntu user."
   echo "Usage: ./setup-ec2-secure.sh"
   exit 1
fi

# Variables
AGENT_USER="agent"
AGENT_HOME="/opt/agent"
LOG_DIR="/var/log/agent"
LOGS_DIR="/opt/agent/logs"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /tmp/ec2-setup.log
}

log "🔧 Starting EC2 configuration..."

# Update system
log "📦 Updating system packages..."
sudo apt-get update -y
sudo apt-get upgrade -y

# Install required packages
log "📦 Installing required packages..."
sudo apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    nginx \
    awscli \
    curl \
    wget \
    unzip \
    systemd \
    htop \
    git \
    jq \
    ufw \
    fail2ban

# 1. SECURE SSH CONFIGURATION
log "🔒 Configuring secure SSH access..."

# Backup SSH config
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d)

# Create secure SSH configuration
sudo tee /etc/ssh/sshd_config.d/99-security.conf > /dev/null << 'EOF'
# Enhanced SSH Security Configuration for GitHub Actions
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

# Allow specific users (ubuntu for GitHub Actions via SSM, agent for service)
AllowUsers ubuntu agent
EOF

# Restart SSH service
sudo systemctl restart sshd
log "✅ SSH security configuration completed"

# 2. CREATE AGENT USER AND DIRECTORY STRUCTURE
log "👤 Setting up agent user and directories..."

# Create agent user
if ! id "$AGENT_USER" &>/dev/null; then
    sudo useradd -m -s /bin/bash -d /home/$AGENT_USER $AGENT_USER
    log "✅ Created agent user: $AGENT_USER"
fi

# Create directory structure
sudo mkdir -p $AGENT_HOME/{current,releases,logs}
sudo mkdir -p $LOG_DIR
sudo mkdir -p $LOGS_DIR

# Set permissions
sudo chown -R $AGENT_USER:$AGENT_USER $AGENT_HOME
sudo chown -R $AGENT_USER:$AGENT_USER $LOG_DIR
sudo chown -R $AGENT_USER:$AGENT_USER $LOGS_DIR
sudo chmod 755 $AGENT_HOME $LOG_DIR $LOGS_DIR

log "✅ Agent directories created and configured"

# 3. CONFIGURE SYSTEMD SERVICE FOR PERSISTENT HOSTING
log "⚙️  Configuring systemd service for persistent hosting..."

sudo tee /etc/systemd/system/agent-service.service > /dev/null << EOF
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
ExecStartPre=/bin/bash -c 'mkdir -p $LOGS_DIR && chown $AGENT_USER:$AGENT_USER $LOGS_DIR'
ExecStart=$AGENT_HOME/current/venv/bin/python -m uvicorn main:app --host 0.0.0.0 --port 8000 --workers 1
ExecReload=/bin/kill -HUP \$MAINPID

# Restart policy for persistence
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

log "✅ Systemd service configured for persistent hosting"

# 4. CONFIGURE NGINX REVERSE PROXY
log "🌐 Configuring Nginx reverse proxy..."

sudo tee /etc/nginx/sites-available/agent > /dev/null << 'EOF'
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
        proxy_pass http://127.0.0.1:8000/health;
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
}
EOF

# Enable the site
sudo ln -sf /etc/nginx/sites-available/agent /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Test nginx configuration
sudo nginx -t
log "✅ Nginx configuration completed"

# 5. CONFIGURE LOG ROTATION
log "📝 Configuring log rotation..."

sudo tee /etc/logrotate.d/agent > /dev/null << EOF
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

log "✅ Log rotation configured"

# 6. CONFIGURE FIREWALL
log "🔥 Configuring firewall..."

sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow http
sudo ufw allow https
sudo ufw --force enable

log "✅ Firewall configured"

# 7. INSTALL AWS SSM AGENT (if not present)
log "☁️  Configuring AWS SSM Agent..."

if ! systemctl is-active --quiet amazon-ssm-agent; then
    sudo snap install amazon-ssm-agent --classic || true
    sudo systemctl enable amazon-ssm-agent
    sudo systemctl start amazon-ssm-agent
fi

log "✅ AWS SSM Agent configured"

# 8. CREATE PLACEHOLDER APPLICATION
log "📱 Creating placeholder application..."

sudo tee $AGENT_HOME/current/main.py > /dev/null << 'EOF'
import logging
import os
from datetime import datetime
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

# Configure logging to save to logs/agent.log as requested
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
    title="Flight Agent API - Ready for Deployment",
    description="Secure agent service with persistent hosting and comprehensive logging",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
async def startup_event():
    logger.info("🚀 Flight Agent API starting up...")
    logger.info(f"📝 Logging configured to save to: {log_dir}/agent.log")

@app.get("/")
async def root():
    logger.info("📍 Root endpoint accessed")
    return {
        "message": "Agent service is running and ready for deployment",
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "version": "placeholder-1.0.0",
        "features": {
            "secure_ssh": "enabled",
            "persistent_hosting": "enabled", 
            "logging_to_file": f"{log_dir}/agent.log"
        }
    }

@app.get("/health")
async def health_check():
    logger.info("🏥 Health check performed")
    return {
        "status": "healthy",
        "service": "flight-agent-placeholder",
        "timestamp": datetime.now().isoformat()
    }

@app.get("/logs/status")
async def logs_status():
    logger.info("📊 Log status endpoint accessed")
    log_file = f"{log_dir}/agent.log"
    
    if os.path.exists(log_file):
        file_size = os.path.getsize(log_file)
        return {
            "status": "active",
            "log_file": log_file,
            "file_size_bytes": file_size,
            "timestamp": datetime.now().isoformat()
        }
    else:
        return {
            "status": "log_file_not_found",
            "message": "Log file will be created on first log entry"
        }

@app.post("/recommendation")
async def recommend():
    logger.info("🤖 Placeholder recommendation endpoint accessed")
    return {
        "response": {
            "message": "Placeholder response - will be replaced after deployment",
            "status": "ready_for_deployment"
        }
    }
EOF

# Create requirements.txt
sudo tee $AGENT_HOME/current/requirements.txt > /dev/null << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
python-multipart==0.0.6
EOF

# Set up Python environment
cd $AGENT_HOME/current
sudo python3 -m venv venv
sudo ./venv/bin/pip install --upgrade pip
sudo ./venv/bin/pip install -r requirements.txt
sudo chown -R $AGENT_USER:$AGENT_USER $AGENT_HOME/current

log "✅ Placeholder application created"

# 9. CREATE HEALTH CHECK SCRIPT
log "🏥 Creating health check script..."

sudo tee /usr/local/bin/agent-health-check.sh > /dev/null << 'EOF'
#!/bin/bash
# Comprehensive health check script

LOGS_DIR="/opt/agent/logs"
LOG_FILE="$LOGS_DIR/health-check.log"

# Create log directory if it doesn't exist
mkdir -p $LOGS_DIR

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

# Check log file
if [ -f "$LOGS_DIR/agent.log" ]; then
    LOG_SIZE=$(stat -c%s "$LOGS_DIR/agent.log" 2>/dev/null || echo 0)
    if [ "$LOG_SIZE" -gt 104857600 ]; then  # 100MB
        health_log "WARNING: Agent log file is large (${LOG_SIZE} bytes)"
    fi
fi

health_log "OK: All services are healthy"
exit 0
EOF

sudo chmod +x /usr/local/bin/agent-health-check.sh

log "✅ Health check script created"

# 10. START SERVICES
log "🚀 Starting services..."

# Reload systemd
sudo systemctl daemon-reload

# Enable services
sudo systemctl enable agent-service
sudo systemctl enable nginx

# Start nginx
sudo systemctl restart nginx

# Start agent service
sudo systemctl restart agent-service

# Wait for services to start
sleep 15

# 11. SETUP CRON JOB FOR HEALTH CHECKS
log "⏰ Setting up health check cron job..."

# Add health check to crontab (every 5 minutes)
(sudo crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/agent-health-check.sh") | sudo crontab -

log "✅ Health check cron job configured"

# 12. FINAL VERIFICATION
log "🔍 Performing final verification..."

# Check services
if systemctl is-active --quiet agent-service && systemctl is-active --quiet nginx; then
    log "✅ SUCCESS: All services are running"
    
    # Test HTTP endpoint
    sleep 5
    if curl -f http://localhost/ > /dev/null 2>&1; then
        log "✅ SUCCESS: HTTP endpoint is responding"
        
        # Get public IP
        PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "localhost")
        
        log "🌐 Application URLs:"
        log "   - Main: http://$PUBLIC_IP/"
        log "   - Health: http://$PUBLIC_IP/health"
        log "   - Logs Status: http://$PUBLIC_IP/logs/status"
        log "   - API Docs: http://$PUBLIC_IP/docs"
        
    else
        log "⚠️  WARNING: HTTP endpoint test failed"
    fi
    
    # Check log file creation
    if [ -f "$LOGS_DIR/agent.log" ]; then
        log "✅ SUCCESS: Log file created at $LOGS_DIR/agent.log"
        log "📊 Log file size: $(du -h $LOGS_DIR/agent.log | cut -f1)"
    else
        log "⚠️  WARNING: Log file not found, will be created on first request"
    fi
    
else
    log "❌ ERROR: Service startup failed"
    sudo systemctl status agent-service
    sudo systemctl status nginx
    exit 1
fi

# 13. DISPLAY SUMMARY
log "🎉 EC2 Setup Completed Successfully!"
echo ""
echo "=========================================================="
echo "🎯 SETUP SUMMARY - ALL REQUIREMENTS MET:"
echo "=========================================================="
echo ""
echo "✅ 1. SECURE SSH ACCESS FROM GITHUB ACTIONS:"
echo "   - SSH hardened with key-based authentication only"
echo "   - AWS SSM Agent enabled for GitHub Actions deployment"
echo "   - Firewall configured (SSH, HTTP, HTTPS only)"
echo "   - Fail2ban protection enabled"
echo ""
echo "✅ 2. PERSISTENT AGENT HOSTING:"
echo "   - Systemd service configured for automatic restart"
echo "   - Service runs as dedicated 'agent' user"
echo "   - Nginx reverse proxy for load balancing"
echo "   - Health checks every 5 minutes"
echo ""
echo "✅ 3. LOGGING TO logs/agent.log:"
echo "   - Application logs: $LOGS_DIR/agent.log"
echo "   - Error logs: $LOGS_DIR/agent-error.log"
echo "   - Log rotation configured (30 days retention)"
echo "   - Health check logs: $LOGS_DIR/health-check.log"
echo ""
echo "🔧 KEY LOCATIONS:"
echo "   - Application: $AGENT_HOME/current/"
echo "   - Logs: $LOGS_DIR/"
echo "   - Service: systemctl status agent-service"
echo "   - Health check: /usr/local/bin/agent-health-check.sh"
echo ""
echo "🌐 TEST YOUR SETUP:"
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "YOUR_EC2_IP")
echo "   curl http://$PUBLIC_IP/"
echo "   curl http://$PUBLIC_IP/health"
echo "   curl http://$PUBLIC_IP/logs/status"
echo ""
echo "🚀 READY FOR GITHUB ACTIONS DEPLOYMENT!"
echo "   Push changes to 'main' branch to trigger auto-deployment"
echo ""
echo "Setup completed at $(date)"
echo "=========================================================="

# Save setup log
sudo cp /tmp/ec2-setup.log $LOGS_DIR/ec2-setup.log
sudo chown $AGENT_USER:$AGENT_USER $LOGS_DIR/ec2-setup.log

log "📝 Setup log saved to $LOGS_DIR/ec2-setup.log"
