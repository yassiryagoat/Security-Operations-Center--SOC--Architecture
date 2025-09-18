#!/bin/bash

# Configuration paths
LOG_FILE="$HOME/soc-automation/logs/ansible.log"    # Ansible execution log
ELK_LOGS="$HOME/elk-stack/logs"                     # Static log files directory

# Check if a scan was executed in the last hour by examining Ansible logs
if grep -q "$(date -d '1 hour ago' '+%Y-%m-%d %H')" "$LOG_FILE"; then
    echo "Recent scan detected in Ansible logs"
    
    # Count how many static log files were updated in the last hour
    # This indicates successful report processing
    updated_logs=$(find "$ELK_LOGS" -name "*.log" -mmin -60 | wc -l)
    echo "Updated log files: $updated_logs"
    
    # Verify that reports were actually processed
    if [ "$updated_logs" -gt 0 ]; then
        echo "Scan completed successfully - $updated_logs systems processed"
        exit 0
    else
        echo "Warning: Scan detected but no log files were updated"
        exit 1
    fi
else
    echo "No recent scans found - possible issue with automation"
    exit 1
fi
```find "$ELK_LOGS" -name "*.log" -mmin -60 | wc -l
else
    echo "No recent scans found - possible issue"
    exit 1
fi
