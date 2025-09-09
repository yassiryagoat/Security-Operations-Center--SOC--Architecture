# run_lynis.sh

## **1. Header and Setup**

### A-Debugin code solutions

```bash
#!/bin/bash
set -eu
if [[ "${BASH_VERSION%%.*}" -ge 3 ]]; then set -o pipefail; fi 
```

**`set -e` (errexit) :**  Exits immediately if any command fails. Doesn't catch failures in *pipeline commands* (e.g., **`false | true`** still succeeds).

**`set -u` (nounset) :** Treats *unset variables* as errors.
Prevents subtle bugs like **`rm -rf $DIR/`** when **`$DIR`** is accidentally unset.

**`set -o pipefail` :** A pipeline (e.g., **`cmd1 | cmd2`**) fails if *any command* in the pipeline fails.
ex:

```bash

false | echo "Pipeline still runs"  # ← `false` fails, but pipeline exits 0 (success)
echo "Script continues"             # ← This line executes
```

## 2. Creating the Architecture of the project

```bash

CENTRAL_REPORTS_DIR="/opt/audit/reports" 
REMOTE_LYNIS_DIR="/tmp/lynis_scans" 
TIMESTAMP=$(date +%Y%m%d_%H%M%S) 
LOG_FILE="/opt/audit/logs/lynis_automation_${TIMESTAMP}.log" 

mkdir -p "$CENTRAL_REPORTS_DIR" /opt/audit/logs /opt/audit/processed 
```

**The project Architecture overview :**

 **/opt/audit/**
│

├── **logs/**
│     └─────── **lynis_automation_{$TIMESTAMP}.log**  # $ LOG_FILE
│

├── **processed/**
│     ├────── **{hostname}_{ip}_{$TIMESTAMP}**.html  # Single-system report
│     └────── **consolidated_report_{$TIMESTAMP}**.json # Multi-system summary

│
└── **reports/**    # $ CENTRAL_REPORT_DIR
       └─────── **{hostname}_{ip}_{timestampe_exec_record}**/
                            ├───────── **lynis_data.dat**    # Raw structured data
                            ├───────── **lynis_scan.log**    # Full scan log
                            ├───────── **parsed.json**       # Processed JSON
                            └───────── **report.html**       # Generated HTML

> **Directory Workflow:**
> 
> 1. **Scan Execution** → Raw outputs stored in **`CENTRAL_REPORTS_DIR`**
> 2. **Data Processing** → JSON/HTML generated in same scan subdirectory
> 3. **Report Consolidation** → Final reports moved to **`processed/`**

## 3. Login function

```bash
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}
```

This function displays the execution timestamp and a descriptive message in the CLI, and also appends them to the log file. The message explains which task or script block was executed.

## 4. Colors for output

```bash
# Colors for output
RED='033[0;31m'
GREEN='033[0;32m'
YELLOW='033[1;33m'
BLUE='033[0;34m'
NC='033[0m' # No Color
```

## 5. Function to execute Lynis on remote server

```bash

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

```

This function connects to a specified remote system and executes a Lynis audit:

- **Input:** Target hostname (stored in Known_host file ).
- **Process:**
    1. Retrieves the hostname of the remote system (defaults to `unknown` if unreachable).
    2. Connects via SSH and checks if **Lynis** is installed.
        - If missing, installs it using `apt`.
    3. Creates the `/tmp/lynis_scans/` directory on the remote host.
    4. Runs a **Lynis system audit** with:
        - Log file → `/tmp/lynis_scans/lynis_scan.log`
        - Report file → `/tmp/lynis_scans/lynis_report.dat`
        - `-quick` mode enabled.
    5. Adjusts file ownership to the current user.—(If root owns the files, a normal user might not be able to read or `scp` them without `sudo`.)
    6. Prints a completion message.
- **Output:** Lynis results saved on the remote host under `/tmp/lynis_scans/`.
- **Logs:** Shows info messages locally and success confirmation remotely.

## 6. retrieve_scan_results()

```bash
retrieve_scan_results() { 
    local target="$1" 
    local target_sanitized="${target//@/_}" 
    log "${BLUE}[INFO]${NC} Retrieving scan results from $target" 
    mkdir -p "$CENTRAL_REPORTS_DIR/${target_sanitized}_${TIMESTAMP}/" 
    scp "$target:/tmp/lynis_scans/lynis*" "$CENTRAL_REPORTS_DIR/${target_sanitized}_${TIMESTAMP}" 2>/dev/null \
        && echo "Successful transmission" \
        || echo "Failed to retrieve files" 
} 
```

This function **retrieves Lynis scan results from a remote target** via `scp` and saves them locally:
**Input:** 

- Target hostname (saved in known_hosts file).

**Process:**

- Creates a timestamped folder inside the central reports directory.
- Uses `scp` to copy all files matching `lynis*` from `/tmp/lynis_scans/` on the target.

**Output:**

Files stored locally under:

```bash
$CENTRAL_REPORTS_DIR/<target>_<timestamp>/
```

- **Logs:** Prints success or failure messages.

## 7. main function

```bash
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
```

This is the entry point of the script, orchestrating the **remote Lynis scans** and **result collection**.

- **Input:**
    - A file containing a list of targets (format: `ssh_target`), one per line.
    - Empty lines or lines starting with `#` are ignored.
- **Process:**
    1. Checks if an argument (file path) is provided; otherwise, prints usage and exits.
    2. Verifies that the provided file exists.
    3. Iterates over each target in the file.
        - Calls `execute_remote_lynis()` to run the Lynis audit remotely.
        - If successful, calls `retrieve_scan_results()` to fetch the reports.
    4. Logs info and error messages for each target.
- **Output:**
    - Results stored locally under:
        
        ```bash
        $CENTRAL_REPORTS_DIR/<target>_<timestamp>/
        ```
        
    - Console messages indicating scan execution and retrieval status.

---

# wrapper_run_lynis.sh

```bash
#!/bin/bash 
# Wrapper script to run Lynis script for each target separately 

if [[ $# -ne 2 ]]; then 
    echo "Usage: $0 <lynis_script.sh> <list.txt>" 
    exit 1 
fi 

LYNIS_SCRIPT="$1" 
LIST_FILE="$2" 

[[ ! -f "$LYNIS_SCRIPT" ]] && { 
    echo "Error: Lynis script not found: $LYNIS_SCRIPT" 
    exit 1 
} 

[[ ! -f "$LIST_FILE" ]] && { 
    echo "Error: list file not found: $LIST_FILE" 
    exit 1 
} 

while read -r target ; do 
    [[ -z "$target" || "$target" =~ ^# ]] && continue 
    echo ">>> Running Lynis script for $target" 
    
    # Create temporary file for this host 
    TMP_FILE=$(mktemp) 
    echo "$target" > "$TMP_FILE" 
    
    # Call Lynis script passing temp file as argument 
    bash "$LYNIS_SCRIPT" "$TMP_FILE" 
    
    # Remove temporary file 
    rm -f "$TMP_FILE" 
done < "$LIST_FILE"
```

This script runs a **Lynis automation script** (`lynis_script.sh`) for each target defined in a list.

- **Usage:**
    
    ```bash
    ./wrapper_lynis.sh <lynis_script.sh> <list.txt>
    ```
    
- **Arguments:**
    - `<lynis_script.sh>` → The automation script that handles Lynis execution and result retrieval.
    - `<list.txt>` → File containing a list of targets (format: `user@ip [optional_key]`), one per line.
        - Lines starting with `#` or empty lines are ignored.
- **Process:**
    1. Validates input arguments and existence of the required files.
    2. Iterates through each target in the list.
    3. For each target:
        - Creates a temporary file containing only that target.
        - Runs the Lynis script using this temporary file.
        - Deletes the temporary file after execution.
- **Output:**
    - Console messages showing which target is being processed.
    - Results are handled by the `lynis_script.sh` provided.

---

# list.txt

```bash
# list.txt
# List of targets (one per line) to run Lynis on.
# Empty lines and lines starting with "#" are ignored.
ubuntu_server
```

This file defines the list of remote targets for the Lynis automation scripts.

- **Format:**
    - One target per line (`user@ip`, hostname, or SSH alias).
    - Empty lines are skipped.
    - Lines starting with `#` are treated as comments.

**Usage:**

- Passed as an argument to the **wrapper script**:
    
    ```bash
    ./wrapper_lynis.sh lynis_script.sh list.txt
    ```
