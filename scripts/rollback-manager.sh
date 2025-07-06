#!/bin/bash

# 🔄 Rollback Manager Script
# Manages deployment rollbacks with version control and safety checks

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="/opt/agent/releases"
CURRENT_DIR="/opt/agent/current"
LOG_FILE="/opt/agent/logs/rollback.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}❌ $1${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

# Function to display help
show_help() {
    cat << EOF
🔄 Rollback Manager - Agent Deployment Rollback Tool

USAGE:
    $0 [COMMAND] [OPTIONS]

COMMANDS:
    list                    List all available backups
    rollback [VERSION]      Rollback to specific version (or latest if not specified)
    status                  Show current deployment status
    cleanup                 Clean up old backups (keep last 10)
    verify                  Verify current deployment health
    github [VERSION]        Trigger GitHub Actions rollback
    help                    Show this help message

OPTIONS:
    -f, --force            Force rollback without confirmation
    -v, --verbose          Verbose output
    -n, --dry-run          Show what would be done without executing

EXAMPLES:
    $0 list                                    # List all backups
    $0 rollback                                # Rollback to latest backup
    $0 rollback v2024.01.15-abc123            # Rollback to specific version
    $0 rollback --force                        # Force rollback without confirmation
    $0 github v2024.01.15-abc123              # Trigger GitHub Actions rollback
    $0 status                                  # Show current status
    $0 cleanup                                 # Clean up old backups

NOTES:
    - Backups are stored in: $BACKUP_DIR
    - Service logs are in: /opt/agent/logs/
    - Always verify deployment after rollback
    - Use 'github' command for production rollbacks via GitHub Actions

EOF
}

# Function to check if running as root
check_permissions() {
    if [[ $EUID -eq 0 ]]; then
        error "This script should not be run as root for safety reasons"
        error "Run as ubuntu user and use sudo when needed"
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if backup directory exists
    if [[ ! -d "$BACKUP_DIR" ]]; then
        error "Backup directory not found: $BACKUP_DIR"
        exit 1
    fi
    
    # Check if current directory exists
    if [[ ! -d "$CURRENT_DIR" ]]; then
        error "Current deployment directory not found: $CURRENT_DIR"
        exit 1
    fi
    
    # Check if systemctl is available
    if ! command -v systemctl &> /dev/null; then
        error "systemctl not found - cannot manage agent service"
        exit 1
    fi
    
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    success "Prerequisites check passed"
}

# Function to get current version
get_current_version() {
    if [[ -f "$CURRENT_DIR/VERSION" ]]; then
        cat "$CURRENT_DIR/VERSION"
    elif [[ -f "$CURRENT_DIR/version.json" ]]; then
        grep -o '"version":"[^"]*' "$CURRENT_DIR/version.json" | cut -d'"' -f4
    else
        echo "unknown"
    fi
}

# Function to list available backups
list_backups() {
    log "Listing available backups..."
    
    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        warning "No backups found in $BACKUP_DIR"
        return 1
    fi
    
    echo ""
    echo "📦 Available Backups:"
    echo "===================="
    
    local count=0
    for backup in $(ls -t "$BACKUP_DIR"/backup-* 2>/dev/null); do
        if [[ -d "$backup" ]]; then
            local backup_name=$(basename "$backup")
            local backup_date=$(echo "$backup_name" | grep -o '[0-9]\{8\}-[0-9]\{6\}' || echo "unknown")
            local version="unknown"
            
            if [[ -f "$backup/VERSION" ]]; then
                version=$(cat "$backup/VERSION")
            elif [[ -f "$backup/version.json" ]]; then
                version=$(grep -o '"version":"[^"]*' "$backup/version.json" | cut -d'"' -f4 2>/dev/null || echo "unknown")
            fi
            
            local size=$(du -sh "$backup" 2>/dev/null | cut -f1 || echo "unknown")
            
            printf "%-3d %-30s %-20s %-15s %s\n" $((++count)) "$backup_name" "$version" "$backup_date" "$size"
        fi
    done
    
    if [[ $count -eq 0 ]]; then
        warning "No valid backups found"
        return 1
    fi
    
    echo ""
    info "Total backups: $count"
    return 0
}

# Function to show current status
show_status() {
    log "Checking current deployment status..."
    
    echo ""
    echo "📊 Current Deployment Status:"
    echo "============================="
    
    # Current version
    local current_version=$(get_current_version)
    echo "Current Version: $current_version"
    
    # Service status
    local service_status=$(systemctl is-active agent-service 2>/dev/null || echo "inactive")
    if [[ "$service_status" == "active" ]]; then
        success "Service Status: $service_status"
    else
        error "Service Status: $service_status"
    fi
    
    # Health check
    echo -n "Health Check: "
    if curl -f -s http://localhost:8000/health > /dev/null 2>&1; then
        success "Healthy"
    else
        error "Unhealthy"
    fi
    
    # Deployment info
    if [[ -f "$CURRENT_DIR/version.json" ]]; then
        echo ""
        echo "📋 Deployment Details:"
        echo "====================="
        cat "$CURRENT_DIR/version.json" | jq . 2>/dev/null || cat "$CURRENT_DIR/version.json"
    fi
    
    # Recent logs
    echo ""
    echo "📝 Recent Logs (last 10 lines):"
    echo "==============================="
    if [[ -f "/opt/agent/logs/agent.log" ]]; then
        tail -10 "/opt/agent/logs/agent.log"
    else
        warning "No logs found"
    fi
}

# Function to verify deployment health
verify_deployment() {
    log "Verifying deployment health..."
    
    local health_checks=0
    local passed_checks=0
    
    # Check 1: Service is running
    ((health_checks++))
    if systemctl is-active --quiet agent-service; then
        success "Service is running"
        ((passed_checks++))
    else
        error "Service is not running"
    fi
    
    # Check 2: HTTP endpoint responds
    ((health_checks++))
    if curl -f -s http://localhost:8000/ > /dev/null; then
        success "HTTP endpoint responding"
        ((passed_checks++))
    else
        error "HTTP endpoint not responding"
    fi
    
    # Check 3: Health endpoint responds
    ((health_checks++))
    if curl -f -s http://localhost:8000/health > /dev/null; then
        success "Health endpoint responding"
        ((passed_checks++))
    else
        error "Health endpoint not responding"
    fi
    
    # Check 4: Log file exists and is being written
    ((health_checks++))
    if [[ -f "/opt/agent/logs/agent.log" ]] && [[ -n "$(find /opt/agent/logs/agent.log -mmin -5 2>/dev/null)" ]]; then
        success "Log file is being updated"
        ((passed_checks++))
    else
        warning "Log file is not being updated recently"
    fi
    
    echo ""
    if [[ $passed_checks -eq $health_checks ]]; then
        success "All health checks passed ($passed_checks/$health_checks)"
        return 0
    else
        error "Health checks failed ($passed_checks/$health_checks passed)"
        return 1
    fi
}

# Function to perform rollback
perform_rollback() {
    local target_version="$1"
    local force_rollback="$2"
    local dry_run="$3"
    
    log "Starting rollback process..."
    
    # Find backup to rollback to
    local backup_path=""
    
    if [[ -n "$target_version" ]]; then
        # Look for specific version
        backup_path=$(find "$BACKUP_DIR" -name "*$target_version*" -type d | head -1)
        if [[ -z "$backup_path" ]]; then
            error "Backup for version '$target_version' not found"
            return 1
        fi
    else
        # Use latest backup
        backup_path=$(ls -t "$BACKUP_DIR"/backup-* 2>/dev/null | head -1)
        if [[ -z "$backup_path" ]]; then
            error "No backups available for rollback"
            return 1
        fi
    fi
    
    local backup_name=$(basename "$backup_path")
    local backup_version="unknown"
    
    if [[ -f "$backup_path/VERSION" ]]; then
        backup_version=$(cat "$backup_path/VERSION")
    elif [[ -f "$backup_path/version.json" ]]; then
        backup_version=$(grep -o '"version":"[^"]*' "$backup_path/version.json" | cut -d'"' -f4 2>/dev/null || echo "unknown")
    fi
    
    echo ""
    echo "🔄 Rollback Plan:"
    echo "================="
    echo "Current Version: $(get_current_version)"
    echo "Target Version:  $backup_version"
    echo "Backup Path:     $backup_path"
    echo "Backup Name:     $backup_name"
    
    if [[ "$dry_run" == "true" ]]; then
        info "DRY RUN - No changes will be made"
        echo ""
        echo "Steps that would be executed:"
        echo "1. Stop agent-service"
        echo "2. Backup current deployment"
        echo "3. Restore from: $backup_path"
        echo "4. Start agent-service"
        echo "5. Verify health"
        return 0
    fi
    
    # Confirmation
    if [[ "$force_rollback" != "true" ]]; then
        echo ""
        read -p "Do you want to proceed with the rollback? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            warning "Rollback cancelled by user"
            return 1
        fi
    fi
    
    # Perform rollback
    log "Executing rollback..."
    
    # Step 1: Stop service
    log "Stopping agent service..."
    sudo systemctl stop agent-service || true
    sleep 5
    
    # Step 2: Create emergency backup of current state
    local emergency_backup="$BACKUP_DIR/emergency-backup-$(date +%Y%m%d-%H%M%S)"
    log "Creating emergency backup: $emergency_backup"
    sudo cp -r "$CURRENT_DIR" "$emergency_backup"
    
    # Step 3: Restore from backup
    log "Restoring from backup: $backup_path"
    sudo rm -rf "$CURRENT_DIR"/*
    sudo cp -r "$backup_path"/* "$CURRENT_DIR"/
    sudo chown -R agent:agent "$CURRENT_DIR"
    
    # Step 4: Start service
    log "Starting agent service..."
    sudo systemctl start agent-service
    sleep 10
    
    # Step 5: Verify health
    log "Verifying rollback..."
    local retry_count=0
    local max_retries=6
    
    while [[ $retry_count -lt $max_retries ]]; do
        if curl -f -s http://localhost:8000/health > /dev/null; then
            success "Rollback completed successfully!"
            success "Service is healthy and responding"
            
            # Show final status
            echo ""
            show_status
            return 0
        else
            ((retry_count++))
            warning "Health check failed (attempt $retry_count/$max_retries)"
            sleep 10
        fi
    done
    
    # Rollback failed - restore emergency backup
    error "Rollback verification failed - restoring emergency backup"
    sudo systemctl stop agent-service || true
    sudo rm -rf "$CURRENT_DIR"/*
    sudo cp -r "$emergency_backup"/* "$CURRENT_DIR"/
    sudo chown -R agent:agent "$CURRENT_DIR"
    sudo systemctl start agent-service
    
    error "Rollback failed and emergency backup restored"
    return 1
}

# Function to trigger GitHub Actions rollback
github_rollback() {
    local target_version="$1"
    
    log "Triggering GitHub Actions rollback..."
    
    # Check if GitHub CLI is available
    if ! command -v gh &> /dev/null; then
        error "GitHub CLI not found. Please install it first:"
        echo "  https://cli.github.com/"
        return 1
    fi
    
    # Check if authenticated
    if ! gh auth status &> /dev/null; then
        error "Please login to GitHub CLI first:"
        echo "  gh auth login"
        return 1
    fi
    
    # Trigger workflow
    if [[ -n "$target_version" ]]; then
        log "Triggering rollback to version: $target_version"
        gh workflow run deploy-enhanced.yml -f action=rollback -f version="$target_version"
    else
        log "Triggering rollback to latest backup"
        gh workflow run deploy-enhanced.yml -f action=rollback
    fi
    
    success "GitHub Actions rollback triggered"
    info "Monitor progress at: https://github.com/$(gh repo view --json owner,name -q '.owner.login + \"/\" + .name')/actions"
}

# Function to cleanup old backups
cleanup_backups() {
    local keep_count=10
    
    log "Cleaning up old backups (keeping last $keep_count)..."
    
    local backup_count=$(ls -1 "$BACKUP_DIR"/backup-* 2>/dev/null | wc -l)
    
    if [[ $backup_count -le $keep_count ]]; then
        info "Only $backup_count backups found, no cleanup needed"
        return 0
    fi
    
    local to_delete=$((backup_count - keep_count))
    log "Found $backup_count backups, will delete $to_delete oldest ones"
    
    ls -t "$BACKUP_DIR"/backup-* | tail -n +$((keep_count + 1)) | while read -r backup; do
        log "Deleting old backup: $(basename "$backup")"
        sudo rm -rf "$backup"
    done
    
    success "Cleanup completed - kept $keep_count most recent backups"
}

# Main function
main() {
    local command="$1"
    local force_rollback="false"
    local verbose="false"
    local dry_run="false"
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                force_rollback="true"
                shift
                ;;
            -v|--verbose)
                verbose="true"
                shift
                ;;
            -n|--dry-run)
                dry_run="true"
                shift
                ;;
            -h|--help|help)
                show_help
                exit 0
                ;;
            *)
                if [[ -z "$command" ]]; then
                    command="$1"
                elif [[ "$command" == "rollback" || "$command" == "github" ]] && [[ -z "$target_version" ]]; then
                    target_version="$1"
                fi
                shift
                ;;
        esac
    done
    
    # Check permissions and prerequisites
    check_permissions
    check_prerequisites
    
    # Execute command
    case "$command" in
        list)
            list_backups
            ;;
        rollback)
            perform_rollback "$target_version" "$force_rollback" "$dry_run"
            ;;
        status)
            show_status
            ;;
        verify)
            verify_deployment
            ;;
        github)
            github_rollback "$target_version"
            ;;
        cleanup)
            cleanup_backups
            ;;
        "")
            error "No command specified"
            show_help
            exit 1
            ;;
        *)
            error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
