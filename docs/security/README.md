# Security Guide

## Overview

This document outlines the security measures implemented in the Agent CI/CD Pipeline and provides best practices for maintaining a secure deployment.

## Security Architecture

### Network Security

#### VPC Configuration
- **Custom VPC**: Isolated network environment
- **Public Subnets**: For load balancer and EC2 instances
- **Internet Gateway**: Controlled internet access
- **Route Tables**: Proper routing configuration

#### Security Groups
- **Minimal Ports**: Only required ports are open
  - Port 22 (SSH) - Restricted to specific IPs
  - Port 80 (HTTP) - Public access for application
  - Port 443 (HTTPS) - Ready for SSL/TLS
  - Port 8000 (Application) - For direct testing

### Access Control

#### IAM Roles and Policies

**EC2 Instance Role**:
- `AmazonSSMManagedInstanceCore` - SSM access
- `CloudWatchAgentServerPolicy` - CloudWatch logging
- Custom S3 policy for deployment bucket access

**GitHub Actions Role** (to be created):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::your-deployment-bucket",
        "arn:aws:s3:::your-deployment-bucket/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:SendCommand",
        "ssm:ListCommands",
        "ssm:GetCommandInvocation"
      ],
      "Resource": "*"
    }
  ]
}
```

#### SSH Access
- **Key-based Authentication**: No password authentication
- **Restricted Access**: Security groups limit SSH access
- **SSM Session Manager**: Alternative secure access method

### Data Protection

#### Encryption at Rest
- **S3 Bucket**: AES-256 encryption enabled
- **EBS Volumes**: Encrypted storage
- **CloudWatch Logs**: Encrypted log storage

#### Encryption in Transit
- **HTTPS Ready**: SSL/TLS configuration prepared
- **Internal Communication**: Secure communication between components

### Application Security

#### Service Configuration
- **Non-root User**: Application runs as `agent` user
- **Systemd Service**: Proper service isolation
- **Log Separation**: Separate log files for different components

#### Firewall Configuration
- **UFW Firewall**: Host-based firewall enabled
- **Fail2ban**: Intrusion prevention system
- **Port Restrictions**: Only necessary ports exposed

## Security Hardening

### Automated Hardening Script

Run the security hardening script on your EC2 instance:

```bash
ssh -i ~/.ssh/your-key.pem ubuntu@your-instance-ip
sudo ./scripts/security-setup.sh
```

### Manual Security Steps

#### 1. SSH Hardening
```bash
# Disable root login
sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config

# Disable password authentication
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# Restart SSH service
sudo systemctl restart sshd
```

#### 2. Firewall Configuration
```bash
# Configure UFW
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

#### 3. Fail2ban Setup
```bash
# Install and configure fail2ban
sudo apt-get install fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

#### 4. System Updates
```bash
# Enable automatic security updates
sudo apt-get install unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

## Monitoring and Alerting

### Security Monitoring

#### Log Monitoring
- **Authentication Logs**: Monitor SSH login attempts
- **Application Logs**: Monitor for suspicious activity
- **System Logs**: Monitor system-level events

#### CloudWatch Alarms
- **High CPU Usage**: Potential DDoS or resource abuse
- **Failed Login Attempts**: Brute force detection
- **Disk Usage**: Prevent disk exhaustion attacks

### Incident Response

#### Security Incident Checklist
1. **Identify**: Detect and analyze the incident
2. **Contain**: Isolate affected systems
3. **Eradicate**: Remove the threat
4. **Recover**: Restore normal operations
5. **Learn**: Document and improve

#### Emergency Contacts
- AWS Support: [AWS Support Center](https://console.aws.amazon.com/support/)
- Security Team: your-security-team@domain.com

## Compliance and Auditing

### Audit Logging
- **CloudTrail**: AWS API call logging
- **CloudWatch Logs**: Application and system logs
- **System Audit**: File integrity monitoring

### Compliance Frameworks
- **SOC 2**: Security controls implementation
- **ISO 27001**: Information security management
- **GDPR**: Data protection compliance (if applicable)

## Security Best Practices

### Development
- **Code Reviews**: Security-focused code reviews
- **Dependency Scanning**: Regular vulnerability scans
- **Secret Management**: Use AWS SSM Parameter Store
- **Input Validation**: Sanitize all user inputs

### Deployment
- **Least Privilege**: Minimal required permissions
- **Network Segmentation**: Proper subnet isolation
- **Encryption**: Encrypt data at rest and in transit
- **Monitoring**: Comprehensive logging and alerting

### Operations
- **Regular Updates**: Keep systems patched
- **Access Reviews**: Regular permission audits
- **Backup Strategy**: Regular data backups
- **Disaster Recovery**: Tested recovery procedures

## Security Checklist

### Pre-Deployment
- [ ] Review IAM policies for least privilege
- [ ] Verify encryption settings
- [ ] Test security group rules
- [ ] Validate SSL/TLS configuration
- [ ] Review application security settings

### Post-Deployment
- [ ] Run security hardening script
- [ ] Verify monitoring and alerting
- [ ] Test incident response procedures
- [ ] Document security configuration
- [ ] Schedule regular security reviews

### Ongoing Maintenance
- [ ] Monthly security updates
- [ ] Quarterly access reviews
- [ ] Annual security assessments
- [ ] Regular backup testing
- [ ] Continuous monitoring review

## Reporting Security Issues

If you discover a security vulnerability, please report it to:
- Email: security@your-domain.com
- Create a private GitHub issue
- Contact the development team directly

**Do not** disclose security vulnerabilities publicly until they have been addressed.
