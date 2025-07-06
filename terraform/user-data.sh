#!/bin/bash

# User data script for EC2 instance initialization
# This script sets up the environment for the agent application

set -e

# Variables from Terraform
ENVIRONMENT="${environment}"
DEPLOYMENT_BUCKET="${deployment_bucket}"
AWS_REGION="${aws_region}"

# Logging
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting EC2 initialization at $(date)"
echo "Environment: $ENVIRONMENT"
echo "Deployment Bucket: $DEPLOYMENT_BUCKET"
echo "AWS Region: $AWS_REGION"

# Update system packages
apt-get update
apt-get upgrade -y

# Install required packages
apt-get install -y \
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
    jq

# Install AWS SSM Agent (usually pre-installed on Ubuntu AMIs)
if ! systemctl is-active --quiet amazon-ssm-agent; then
    echo "Installing AWS SSM Agent..."
    snap install amazon-ssm-agent --classic
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
fi

# Create agent user and directories
useradd -m -s /bin/bash agent || true
mkdir -p /opt/agent/current
mkdir -p /opt/agent/logs
mkdir -p /var/log/agent
chown -R agent:agent /opt/agent
chown -R agent:agent /var/log/agent

# Create systemd service file for the agent
cat > /etc/systemd/system/agent-service.service << 'EOF'
[Unit]
Description=Sample Agent Service
After=network.target

[Service]
Type=simple
User=agent
Group=agent
WorkingDirectory=/opt/agent/current
Environment=PATH=/opt/agent/current/venv/bin
Environment=PYTHONPATH=/opt/agent/current
ExecStart=/opt/agent/current/venv/bin/python -m uvicorn main:app --host 0.0.0.0 --port 8000
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
RestartSec=10
StandardOutput=append:/var/log/agent/agent.log
StandardError=append:/var/log/agent/agent-error.log

[Install]
WantedBy=multi-user.target
EOF

# Configure nginx as reverse proxy
cat > /etc/nginx/sites-available/agent << 'EOF'
server {
    listen 80;
    server_name _;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Handle WebSocket connections
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    location /health {
        proxy_pass http://127.0.0.1:8000/docs;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
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

# Enable nginx site
ln -sf /etc/nginx/sites-available/agent /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test nginx configuration
nginx -t

# Configure log rotation
cat > /etc/logrotate.d/agent << 'EOF'
/var/log/agent/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 644 agent agent
    postrotate
        systemctl reload agent-service || true
    endscript
}
EOF

# Install CloudWatch agent
echo "Installing CloudWatch agent..."
wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb

# Create CloudWatch agent configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/agent/agent.log",
                        "log_group_name": "/aws/ec2/agent/application",
                        "log_stream_name": "{instance_id}-application",
                        "timezone": "UTC"
                    },
                    {
                        "file_path": "/var/log/agent/agent-error.log",
                        "log_group_name": "/aws/ec2/agent/error",
                        "log_stream_name": "{instance_id}-error",
                        "timezone": "UTC"
                    },
                    {
                        "file_path": "/var/log/nginx/access.log",
                        "log_group_name": "/aws/ec2/agent/nginx-access",
                        "log_stream_name": "{instance_id}-nginx-access",
                        "timezone": "UTC"
                    },
                    {
                        "file_path": "/var/log/nginx/error.log",
                        "log_group_name": "/aws/ec2/agent/nginx-error",
                        "log_stream_name": "{instance_id}-nginx-error",
                        "timezone": "UTC"
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "Agent/Application",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60,
                "totalcpu": false
            },
            "disk": {
                "measurement": [
                    "used_percent"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "diskio": {
                "measurement": [
                    "io_time"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            },
            "netstat": {
                "measurement": [
                    "tcp_established",
                    "tcp_time_wait"
                ],
                "metrics_collection_interval": 60
            },
            "swap": {
                "measurement": [
                    "swap_used_percent"
                ],
                "metrics_collection_interval": 60
            }
        }
    }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
    -s

# Create a simple health check script
cat > /usr/local/bin/health-check.sh << 'EOF'
#!/bin/bash
# Simple health check script

# Check if agent service is running
if ! systemctl is-active --quiet agent-service; then
    echo "CRITICAL: Agent service is not running"
    exit 1
fi

# Check if nginx is running
if ! systemctl is-active --quiet nginx; then
    echo "CRITICAL: Nginx is not running"
    exit 1
fi

# Check if application responds
if ! curl -f -s http://localhost:8000/docs > /dev/null; then
    echo "WARNING: Application not responding on port 8000"
    exit 1
fi

echo "OK: All services are running"
exit 0
EOF

chmod +x /usr/local/bin/health-check.sh

# Create initial deployment placeholder
mkdir -p /opt/agent/current
cat > /opt/agent/current/main.py << 'EOF'
from fastapi import FastAPI

app = FastAPI(title="Agent Placeholder", version="0.1.0")

@app.get("/")
def read_root():
    return {"message": "Agent service is ready for deployment"}

@app.get("/health")
def health_check():
    return {"status": "healthy", "service": "agent-placeholder"}

@app.get("/docs")
def get_docs():
    return {"message": "API documentation will be available after deployment"}
EOF

# Create requirements.txt for placeholder
cat > /opt/agent/current/requirements.txt << 'EOF'
fastapi
uvicorn[standard]
EOF

# Set up placeholder application
cd /opt/agent/current
python3 -m venv venv
./venv/bin/pip install --upgrade pip
./venv/bin/pip install -r requirements.txt
chown -R agent:agent /opt/agent/current

# Enable and start services
systemctl daemon-reload
systemctl enable nginx
systemctl enable agent-service
systemctl start nginx
systemctl start agent-service

# Wait for services to start
sleep 10

# Test the setup
echo "Testing service setup..."
if curl -f http://localhost/health; then
    echo "SUCCESS: Services are running correctly"
else
    echo "WARNING: Service test failed, checking logs..."
    systemctl status agent-service
    systemctl status nginx
fi

echo "EC2 initialization completed at $(date)"
echo "Instance is ready for deployments"
