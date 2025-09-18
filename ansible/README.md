# Ansible Integration with Custom Lynis Scripts

## Overview
Ansible runs on Blue Kali host as the central automation controller, orchestrating your existing Lynis automation scripts (`automated_lynis.sh` and `wrapper_lynis.sh`) that are located and execute on Purple Kali VM. The workflow triggers your scripts remotely, collects the generated reports, and appends them to static log files for ELK stack processing.

## Integration Architecture

```
Blue Kali (Ansible Controller)
    ↓ SSH to Purple Kali
Purple Kali VM (Your Scripts Location)
    ├── wrapper_lynis.sh (executes here)
    ├── automated_lynis.sh (executes here)
    ├── list.txt (Ubuntu targets)
    └── Reports Generated (.dat, .log)
    ↓ Reports Retrieved by Ansible
Blue Kali Static Log Files
    ↓ Monitored by
ELK Stack (Logstash)
```

## Ansible's Role in Your Architecture

Ansible coordinates your Purple Kali-based workflow by:

1. **Remote Script Execution**: SSH to Purple Kali and triggers your `wrapper_lynis.sh`
2. **Report Collection**: Retrieves your generated .dat and .log files from Purple Kali
3. **Data Processing**: Parses and formats reports for ELK ingestion  
4. **Log Management**: Appends processed data to Blue Kali static log files
5. **Cleanup**: Manages temporary files on both systems

## Prerequisites

### Ansible Installation (Blue Kali)
```bash
# Update package index
sudo apt update

# Install Ansible
sudo apt install -y ansible python3-pip

# Verify installation
ansible --version
```

### SSH Key Setup
```bash
# Generate SSH key pair (if not exists)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/soc_automation

# Copy public key to Purple Kali VM
ssh-copy-id -i ~/.ssh/soc_automation.pub user@purple-kali-ip
```

### Directory Structure
```bash
# Create Ansible project directory
mkdir -p ~/soc-automation
cd ~/soc-automation

# Create subdirectories
mkdir -p {playbooks,inventory,logs,scripts}
```

## Ansible Configuration

### ansible.cfg
**File: `~/soc-automation/ansible.cfg`**
```ini
[defaults]
# Path to inventory file containing host definitions
inventory = ./inventory/hosts.yml
# SSH private key for authentication to all managed hosts
private_key_file = ~/.ssh/soc_automation
# Skip SSH host key verification (lab environment only)
host_key_checking = False
# SSH connection timeout in seconds
timeout = 30
# Disable retry files to avoid clutter
retry_files_enabled = False
# Central logging for all Ansible operations
log_path = ./logs/ansible.log

[ssh_connection]
# SSH connection optimization for faster execution
ssh_args = -o ControlMaster=auto -o ControlPersist=60s
# Enable SSH pipelining for performance improvement
pipelining = True
```

### Custom Script Integration
**File: `~/soc-automation/inventory/hosts.yml`**
```yaml
all:
  children:
    # Purple Kali VM - Security Operations Orchestrator
    orchestrators:
      hosts:
        purple-kali:
          ansible_host: 192.168.1.100          # Purple Kali VM IP address
          ansible_user: kali                    # SSH username for Purple Kali
          ansible_python_interpreter: /usr/bin/python3  # Python path on target
          log_file: purple-kali.log            # Corresponding static log file name
          
          # Your existing script paths on Purple Kali VM
          wrapper_script: "/home/kali/lynis_automation/wrapper_lynis.sh"
          main_script: "/home/kali/lynis_automation/automated_lynis.sh"
          target_list: "/home/kali/lynis_automation/list.txt"
          reports_base_dir: "/home/kali/lynis_automation/reports"

  vars:
    # Global SSH configuration for all hosts
    ansible_ssh_private_key_file: ~/.ssh/soc_automation
    # Timestamp variable for consistent logging across all tasks
    scan_timestamp: "{{ ansible_date_time.iso8601 }}"
    # Local directory on Blue Kali for static log files (ELK integration)
    local_logs_dir: "~/elk-stack/logs"
```

### Your Script Integration Requirements
Your existing scripts work perfectly with this integration:

**Expected Directory Structure on Purple Kali:**
```
/home/kali/lynis_automation/
├── wrapper_lynis.sh
├── automated_lynis.sh
├── list.txt
└── reports/
    ├── ubuntu_server1/
    │   ├── report_timestamp1.dat
    │   ├── report_timestamp1.log
    │   ├── report_timestamp2.dat
    │   └── report_timestamp2.log
    └── ubuntu_server2/
        ├── report_timestamp1.dat
        ├── report_timestamp1.log
        └── report_timestamp2.dat
    
```

**Script Execution Flow:**
```bash
# Ansible will execute on Purple Kali:
cd /home/kali/lynis_automation
bash wrapper_lynis.sh automated_lynis.sh list.txt

# Your scripts generate organized reports:
# reports/ubuntu_server1/report_<timestamp>.dat
# reports/ubuntu_server1/report_<timestamp>.log
# reports/ubuntu_server2/report_<timestamp>.dat  
# etc.
```

## Ansible Playbooks

### Main Security Scan Playbook
**File: `~/soc-automation/playbooks/security-scan.yml`**
```yaml
---
- name: SOC Security Scanning Automation
  hosts: localhost
  gather_facts: yes
  vars:
    scan_id: "{{ ansible_date_time.epoch }}"
    
  tasks:
    - name: Create local reports directory
      file:
        path: "{{ local_logs_dir }}"
        state: directory
        mode: '0755'
    
    - name: Initialize static log files
      file:
        path: "{{ local_logs_dir }}/{{ hostvars[item]['log_file'] }}"
        state: touch
        mode: '0644'
      loop: "{{ groups['all'] }}"
      when: hostvars[item]['log_file'] is defined

- name: Execute Lynis Scans on Purple Kali
  hosts: orchestrators
  gather_facts: yes
  become: yes
  
  tasks:
    - name: Check if Lynis is installed
      command: which lynis
      register: lynis_check
      failed_when: false
      
    - name: Install Lynis if not present
      apt:
        name: lynis
        state: present
      when: lynis_check.rc != 0
    
    - name: Create reports directory
      file:
        path: "{{ reports_dir }}"
        state: directory
        mode: '0755'
    
- name: Execute Your Lynis Automation Scripts
  hosts: orchestrators
  gather_facts: yes
  
  tasks:
    - name: Create reports base directory if not exists
      file:
        path: "{{ reports_base_dir }}"
        state: directory
        mode: '0755'
    
    - name: Check if your scripts exist
      stat:
        path: "{{ item }}"
      register: script_check
      loop:
        - "{{ wrapper_script }}"
        - "{{ main_script }}"
        - "{{ target_list }}"
      failed_when: not script_check.stat.exists
    
    - name: Execute Your Lynis Scripts Remotely on Purple Kali
      shell: |
        cd {{ reports_base_dir | dirname }}
        bash {{ wrapper_script }} {{ main_script }} {{ target_list }} > /tmp/lynis-execution-{{ scan_id }}.log 2>&1
      register: lynis_execution
      async: 1800  # 30 minutes timeout
      poll: 30     # Check every 30 seconds
    
    - name: Verify script execution completed
      debug:
        msg: |
          Remote Lynis automation completed on Purple Kali
          Exit code: {{ lynis_execution.rc }}
          Execution time: {{ lynis_execution.delta }}
          Check Purple Kali:/tmp/lynis-execution-{{ scan_id }}.log for details

- name: Collect and Process Reports
  hosts: orchestrators
  gather_facts: yes
  
  tasks:
    - name: Find server directories and latest reports
      find:
        paths: "{{ reports_base_dir }}"
        file_type: directory
        patterns: "*server*"
      register: server_directories
    
    - name: Find latest reports from each server directory  
      find:
        paths: "{{ item.path }}"
        patterns: 
          - "report_*.dat"
          - "report_*.log"
        age: "-1h"  # Files modified in last hour
      register: latest_reports
      loop: "{{ server_directories.files }}"
    
    - name: Fetch latest Lynis reports from organized directories
      fetch:
        src: "{{ item.1.path }}"
        dest: "/tmp/fetched-reports/{{ item.1.path | basename }}"
        flat: yes
      loop: "{{ latest_reports.results | subelements('files') }}"
      when: latest_reports.results is defined
    
    - name: Clean up remote reports
      file:
        path: "{{ reports_dir }}"
        state: absent

- name: Process Reports Locally
  hosts: localhost
  gather_facts: yes
  
  tasks:
    - name: Process collected reports for ELK ingestion
      shell: |
        TIMESTAMP="{{ scan_timestamp }}"
        
        # Process each fetched report file
        for report_file in /tmp/fetched-reports/report_*.dat /tmp/fetched-reports/report_*.log; do
          if [ -f "$report_file" ]; then
            # Extract server name from directory structure or filename
            FILENAME=$(basename "$report_file")
            
            # Determine server from the parent directory name stored in fetch
            if [[ "$FILENAME" =~ ubuntu_server([0-9]+) ]]; then
              HOSTNAME="ubuntu-server-${BASH_REMATCH[1]}"
              LOG_FILE="{{ local_logs_dir }}/ubuntu-server-${BASH_REMATCH[1]}.log"
            elif [[ "$FILENAME" =~ purple.kali ]]; then
              HOSTNAME="purple-kali"  
              LOG_FILE="{{ local_logs_dir }}/purple-kali.log"
            else
              HOSTNAME="unknown-host"
              LOG_FILE="{{ local_logs_dir }}/unknown-host.log"
            fi
            
            # Create static log file if it doesn't exist
            touch "$LOG_FILE"
            
            # Add scan header with timestamp from filename if possible
            REPORT_TIMESTAMP=$(echo "$FILENAME" | grep -o 'report_[0-9]*' | cut -d'_' -f2)
            echo "[$TIMESTAMP] $HOSTNAME - Lynis Scan (Report: $REPORT_TIMESTAMP)" >> "$LOG_FILE"
            
            # Process .dat files for warnings and suggestions  
            if [[ "$report_file" == *.dat ]]; then
              grep -E "warning\[\]|suggestion\[\]|manual\[\]" "$report_file" | sed "s/.*=//g" | \
              sed "s/^/[$TIMESTAMP] $HOSTNAME - /" >> "$LOG_FILE"
            fi
            
            # Process .log files for key findings
            if [[ "$report_file" == *.log ]]; then
              grep -E "(WARNING|SUGGESTION|Found)" "$report_file" | head -20 | \
              sed "s/^/[$TIMESTAMP] $HOSTNAME - /" >> "$LOG_FILE"
            fi
            
            # Add completion marker
            echo "[$TIMESTAMP] $HOSTNAME - Report processed: $FILENAME" >> "$LOG_FILE"
          fi
        done
    
    - name: Cleanup temporary files
      file:
        path: /tmp/fetched-reports
        state: absent
    
    - name: Display scan summary
      debug:
        msg: |
          Security scan completed successfully!
          Scan ID: {{ scan_id }}
          Reports updated in: {{ local_logs_dir }}
          Check Kibana dashboard for real-time results
```

### Quick Test Playbook
**File: `~/soc-automation/playbooks/test-connectivity.yml`**
```yaml
---
# Simple connectivity test to verify SSH access to Purple Kali
- name: Test Connectivity to All Hosts
  hosts: all
  gather_facts: no
  
  tasks:
    # Basic ICMP ping test (if ICMP is allowed)
    - name: Ping test
      ping:
    
    # Verify SSH connectivity and user context
    - name: Check SSH connectivity
      command: whoami
      register: ssh_test
    
    # Display connection status for verification
    - name: Display connection info
      debug:
        msg: "Connected to {{ inventory_hostname }} as {{ ssh_test.stdout }}"
```

## Scheduling and Automation

### Cron Job Setup
```bash
# Edit crontab for automated scheduling
crontab -e

# Add scheduled scans (example: every 6 hours)
# Runs security scan every 6 hours and logs output
0 */6 * * * cd ~/soc-automation && ansible-playbook playbooks/security-scan.yml >> logs/cron.log 2>&1

# Daily comprehensive scan at 2 AM
# Runs with full_scan flag for more detailed analysis
0 2 * * * cd ~/soc-automation && ansible-playbook playbooks/security-scan.yml --extra-vars "full_scan=true" >> logs/daily-scan.log 2>&1

# Weekly comprehensive scan on Sundays at 1 AM
# Runs with comprehensive flag for complete system assessment
0 1 * * 0 cd ~/soc-automation && ansible-playbook playbooks/security-scan.yml --extra-vars "comprehensive=true" >> logs/weekly-scan.log 2>&1
```


## Log File Management

### Static Log File Structure
```
~/elk-stack/logs/
├── purple-kali.log         # Purple Kali system scans
├── ubuntu-server-01.log    # Ubuntu target 1 scans
├── ubuntu-server-02.log    # Ubuntu target 2 scans
└── ubuntu-server-03.log    # Ubuntu target 3 scans
```


### Log Rotation Script
**File: `~/soc-automation/scripts/rotate-logs.sh`**
```bash
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
```

### Debugging Commands
```bash
# Test and validate inventory configuration
ansible-inventory --list

# Check host connectivity and gather system facts
ansible all -m setup | grep ansible_fqdn

# Validate playbook syntax before execution
ansible-playbook --syntax-check playbooks/security-scan.yml

# Perform dry run to see what would be executed without making changes
ansible-playbook --check playbooks/security-scan.yml

# Test specific tasks or tags within a playbook
ansible-playbook playbooks/security-scan.yml --tags "execution" --check
```

## Monitoring and Alerts

### Ansible Execution Monitoring
**File: `~/soc-automation/scripts/check-scan-status.sh`**
```bash
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
```

### Integration with ELK Stack
The static log files are automatically monitored by Logstash using the configuration:
```ruby
input {
  file {
    path => "/var/log/security-scans/*.log"
    start_position => "end"
    sincedb_path => "/dev/null"
  }
}
```

This ensures that as soon as Ansible appends new scan results to the static log files, Logstash immediately processes and indexes them for real-time visualization in Kibana.