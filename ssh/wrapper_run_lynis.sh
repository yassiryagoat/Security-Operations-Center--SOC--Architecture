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

while read -r target key; do 
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
