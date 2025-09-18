#!/bin/bash

# Configuration variables
LOG_DIR="$HOME/elk-stack/logs"           # Directory containing static log files
MAX_SIZE="100M"                          # Maximum size before rotation (in MB)
BACKUP_DIR="$LOG_DIR/archive"           # Archive directory for rotated logs

# Create archive directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Loop through all log files in the directory
for log_file in "$LOG_DIR"/*.log; do
    if [ -f "$log_file" ]; then
        # Get file size in MB
        size=$(du -m "$log_file" | cut -f1)
        
        # Rotate if file exceeds maximum size
        if [ "$size" -gt 100 ]; then
            # Create timestamp for archived file
            timestamp=$(date +"%Y%m%d-%H%M%S")
            
            # Move current log to archive with timestamp
            mv "$log_file" "$BACKUP_DIR/$(basename "$log_file" .log)-$timestamp.log"
            
            # Create new empty log file with proper permissions
            touch "$log_file"
            chmod 644 "$log_file"
            
            echo "Rotated $log_file (${size}MB) to archive"
        fi
    fi
done
