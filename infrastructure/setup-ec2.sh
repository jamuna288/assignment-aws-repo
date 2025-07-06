#!/bin/bash

# EC2 Instance Setup Script for Agent Deployment
# Run this script on your Ubuntu EC2 instance to prepare it for deployments

set -e

echo "Starting EC2 setup for agent deployment..."

# Update system packages
sudo apt-get update
sudo apt-get upgrade -y

# Install required packages
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
    git

# Install AWS SSM Agent (if not already installed)
if ! command -v amazon-ssm-agent &> /dev/null; then
    echo "Installing AWS SSM Agent..."
    wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb
    sudo dpkg -i amazon-ssm-agent.deb
    sudo systemctl enable amazon-ssm-agent
    sudo systemctl start amazon-ssm-agent
fi

# Create agent user and directories
sudo useradd -m -s /bin/bash agent || true
sudo mkdir -p /opt/agent/current
sudo mkdir -p /opt/agent/logs
sudo mkdir -p /var/log/agent
sudo chown -R agent:agent /opt/agent
sudo chown -R agent:agent /var/log/agent

# Create systemd service file
sudo tee /etc/systemd/system/agent-service.service > /dev/null <<EOF
[Unit]
Description=Sample Agent Service
After=network.target

[Service]
Type=simple
User=agent
Group=agent
WorkingDirectory=/opt/agent/current
Environment=PATH=/opt/agent/current/venv/bin
ExecStart=/opt/agent/current/venv/bin/python -m uvicorn main:app --host 0.0.0.0 --port 8000
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=10
StandardOutput=append:/var/log/agent/agent.log
StandardError=append:/var/log/agent/agent-error.log

[Install]
WantedBy=multi-user.target
EOF

# Configure nginx as reverse proxy
sudo tee /etc/nginx/sites-available/agent > /dev/null <<EOF
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location /health {
        proxy_pass http://127.0.0.1:8000/docs;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

# Enable nginx site
sudo ln -sf /etc/nginx/sites-available/agent /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl enable nginx
sudo systemctl restart nginx

# Configure log rotation
sudo tee /etc/logrotate.d/agent > /dev/null <<EOF
/var/log/agent/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 644 agent agent
    postrotate
        systemctl reload agent-service
    endscript
}
EOF

# Configure CloudWatch agent (optional)
if [ "$INSTALL_CLOUDWATCH" = "true" ]; then
    echo "Installing CloudWatch agent..."
    wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
    sudo dpkg -i amazon-cloudwatch-agent.deb
    
    # Create CloudWatch config
    sudo tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json > /dev/null <<EOF
{
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/agent/agent.log",
                        "log_group_name": "/aws/ec2/agent/application",
                        "log_stream_name": "{instance_id}-application"
                    },
                    {
                        "file_path": "/var/log/agent/agent-error.log",
                        "log_group_name": "/aws/ec2/agent/error",
                        "log_stream_name": "{instance_id}-error"
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
                "metrics_collection_interval": 60
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
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            }
        }
    }
}
EOF

    sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
        -a fetch-config \
        -m ec2 \
        -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
        -s
fi

# Set up firewall rules
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable

# Reload systemd
sudo systemctl daemon-reload

echo "EC2 setup completed successfully!"
echo "Next steps:"
echo "1. Configure AWS credentials for the EC2 instance"
echo "2. Set up the S3 bucket for deployments"
echo "3. Configure GitHub secrets"
echo "4. Tag your EC2 instance with Environment tag"
