#!/bin/bash 
set -e 
set -u 
if [[ "${BASH_VERSION%%.*}" -ge 3 ]]; then set -o pipefail; fi 

CENTRAL_REPORTS_DIR="/opt/audit/reports" 
REMOTE_LYNIS_DIR="/tmp/lynis_scans" 
TIMESTAMP=$(date +%Y%m%d_%H%M%S) 
LOG_FILE="/opt/audit/logs/lynis_automation_${TIMESTAMP}.log" 

mkdir -p "$CENTRAL_REPORTS_DIR" /opt/audit/logs /opt/audit/processed 

log() { 
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE" 
} 

RED='\033[0;31m' 
GREEN='\033[0;32m' 
YELLOW='\033[1;33m' 
BLUE='\033[0;34m' 
NC='\033[0m' 

execute_remote_lynis() { 
    local target="$1" 
    local hostname 
    hostname=$(ssh "$target" hostname 2>/dev/null || echo "unknown") 
    log "${BLUE}[INFO]${NC} Starting Lynis scan on $target ($hostname)" 
    ssh "$target" " 
        if ! command -v lynis &> /dev/null; then 
            echo 'Installing Lynis...' 
            apt update && apt install lynis -y 
        fi 
        mkdir -p /tmp/lynis_scans 
        cd /tmp/lynis_scans 
        lynis audit system --logfile /tmp/lynis_scans/lynis_scan.log --report-file /tmp/lynis_scans/lynis_report.dat --quick > /dev/null 2>&1 
        chown \$(whoami):\$(whoami) lynis_* || true 
        echo 'Lynis scan completed successfully' 
    " 
} 

retrieve_scan_results() { 
    local target="$1" 
    local target_sanitized="${target//@/_}" 
    log "${BLUE}[INFO]${NC} Retrieving scan results from $target" 
    mkdir -p "$CENTRAL_REPORTS_DIR/${target_sanitized}_${TIMESTAMP}/" 
    scp "$target:/tmp/lynis_scans/lynis*" "$CENTRAL_REPORTS_DIR/${target_sanitized}_${TIMESTAMP}" 2>/dev/null \
        && echo "Successful transmission" \
        || echo "Failed to retrieve files" 
} 

main() { 
    if [[ $# -eq 0 ]]; then 
        echo "Usage: $0 <file_with_user_ip_and_key>" 
        exit 1 
    fi 
    local file="$1" 
    [[ ! -f "$file" ]] && { echo "Error: file not found"; exit 1; } 
    log "${BLUE}[INFO]${NC} Starting Lynis automation" 
    while read -r target; do 
        [[ -z "$target" || "$target" =~ ^# ]] && continue 
        log "${BLUE}[INFO]${NC} Processing target: $target " 
        if execute_remote_lynis "$target" ; then 
            if retrieve_scan_results "$target" ; then 
                echo "Retrieving data successfully from $target" 
            else 
                echo "Failed to retrieve data from $target" 
            fi 
        else 
            log "${RED}[ERROR]${NC} Failed to execute Lynis on $target" 
        fi 
    done < "$file" 
} 

main "$@"
