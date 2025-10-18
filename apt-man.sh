#!/usr/bin/env bash
# APT Manager – manage PPAs and repositories with ease

set -euo pipefail

SOURCES_DIR="/etc/apt/sources.list.d"
MAIN_LIST="/etc/apt/sources.list"

# Detect Ubuntu release codename
CODENAME=$(lsb_release -sc)

# Helper: classify a source
classify_source() {
    local url="$1"
    if [[ "$url" =~ (archive\.ubuntu\.com|security\.ubuntu\.com|ports\.ubuntu\.com) ]]; then
        echo "Ubuntu Official"
    elif [[ "$url" =~ (partner\.archive\.canonical\.com) ]]; then
        echo "Canonical Partner"
    else
        echo "3rd Party / PPA"
    fi
}

# Parse DEB822 format (.sources files)
parse_deb822() {
    local file="$1"
    local current_uri=""
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^URIs:[[:space:]]*(.+)$ ]]; then
            current_uri="${BASH_REMATCH[1]}"
            current_uri="${current_uri%/}"
            if [[ -n "$current_uri" ]]; then
                echo "$current_uri"
            fi
        fi
    done < "$file"
}

# Parse DEB822 format as stanzas (URI|KEY pairs)
parse_deb822_stanzas() {
    local file="$1"
    local current_uri=""
    local current_key=""
    
    while IFS= read -r line; do
        # Empty line means end of stanza
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*$ ]]; then
            if [[ -n "$current_uri" ]]; then
                echo "$current_uri|${current_key:-none}"
                current_uri=""
                current_key=""
            fi
        elif [[ "$line" =~ ^URIs:[[:space:]]*(.+)$ ]]; then
            current_uri="${BASH_REMATCH[1]}"
            current_uri="${current_uri%/}"
        elif [[ "$line" =~ ^Signed-By:[[:space:]]*(.+)$ ]]; then
            current_key="${BASH_REMATCH[1]}"
        fi
    done < "$file"
    
    # Handle last stanza if file doesn't end with empty line
    if [[ -n "$current_uri" ]]; then
        echo "$current_uri|${current_key:-none}"
    fi
}

# Extract Signed-By field from DEB822 format
parse_deb822_keys() {
    local file="$1"
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^Signed-By:[[:space:]]*(.+)$ ]]; then
            echo "${BASH_REMATCH[1]}"
        fi
    done < "$file"
}

# Classify key format
classify_key() {
    local keyfile="$1"
    
    if [[ "$keyfile" =~ ^-----BEGIN ]]; then
        echo "INLINE (embedded key)"
    elif [[ "$keyfile" == "/etc/apt/trusted.gpg" ]]; then
        echo "OLD (deprecated)"
    elif [[ "$keyfile" =~ ^/etc/apt/trusted\.gpg\.d/ ]]; then
        echo "OLD (trusted.gpg.d)"
    elif [[ "$keyfile" =~ ^/usr/share/keyrings/ ]]; then
        echo "NEW (system keyring)"
    elif [[ "$keyfile" =~ ^/etc/apt/keyrings/ ]]; then
        echo "NEW (apt keyring)"
    else
        echo "CUSTOM"
    fi
}

# Format key display (handle inline keys)
format_key_display() {
    local key="$1"
    
    if [[ "$key" =~ ^-----BEGIN ]]; then
        echo "(embedded in .sources file)"
    else
        echo "$key"
    fi
}

# 1. List all sources
list_sources() {
    echo "Detected APT sources:"
    echo "--------------------------------------"
    local i=1
    
    # Process old-style .list files
    for file in "$MAIN_LIST" "$SOURCES_DIR"/*.list; do
        [[ -f "$file" ]] || continue
        while read -r line; do
            [[ "$line" =~ ^deb ]] || continue
            url=$(echo "$line" | awk '{print $2}')
            label=$(classify_source "$url")
            printf "[%02d] %-30s %-40s\n" "$i" "$label" "$url"
            echo "$i|$file|$url" >> /tmp/sources_index
            ((i++))
        done < "$file"
    done
    
    # Process new-style .sources files (DEB822 format)
    for file in "$SOURCES_DIR"/*.sources; do
        [[ -f "$file" ]] || continue
        [[ -s "$file" ]] || continue
        while IFS= read -r url; do
            [[ -n "$url" ]] || continue
            label=$(classify_source "$url")
            printf "[%02d] %-30s %-40s\n" "$i" "$label" "$url"
            echo "$i|$file|$url" >> /tmp/sources_index
            ((i++))
        done < <(parse_deb822 "$file")
    done
    
    # Process disabled old-style .list files
    for file in "$SOURCES_DIR"/*.list.disabled; do
        [[ -f "$file" ]] || continue
        while read -r line; do
            [[ "$line" =~ ^deb ]] || continue
            url=$(echo "$line" | awk '{print $2}')
            label=$(classify_source "$url")
            printf "[%02d] %-30s [disabled] %-40s\n" "$i" "$label" "$url"
            echo "$i|$file|$url" >> /tmp/sources_index
            ((i++))
        done < "$file"
    done
    
    # Process disabled new-style .sources files
    for file in "$SOURCES_DIR"/*.sources.disabled; do
        [[ -f "$file" ]] || continue
        [[ -s "$file" ]] || continue
        while IFS= read -r url; do
            [[ -n "$url" ]] || continue
            label=$(classify_source "$url")
            printf "[%02d] %-30s [disabled] %-40s\n" "$i" "$label" "$url"
            echo "$i|$file|$url" >> /tmp/sources_index
            ((i++))
        done < <(parse_deb822 "$file")
    done
    
    echo "--------------------------------------"
}

# 2. Show packages in a source
show_packages() {
    local id="$1"
    local url
    url=$(grep "^$id|" /tmp/sources_index | cut -d'|' -f3)
    echo "Packages in $url:"
    echo "--------------------------------------"
    curl -s "${url}/dists/${CODENAME}/main/binary-amd64/Packages" \
        | grep -E '^Package: ' | awk '{print $2}'
}

# 3. Show installed packages from a source
show_installed() {
    local id="$1"
    local url
    url=$(grep "^$id|" /tmp/sources_index | cut -d'|' -f3)
    echo "Installed packages from $url:"
    echo "--------------------------------------"
    for pkg in $(dpkg-query -W -f='${binary:Package}\n'); do
        if apt-cache policy "$pkg" 2>/dev/null | grep -q "$url"; then
            echo "$pkg"
        fi
    done
}

# 4. Remove all installed packages from a 3rd-party source
remove_packages() {
    local id="$1"
    local url
    url=$(grep "^$id|" /tmp/sources_index | cut -d'|' -f3)
    echo "Removing all packages installed from $url..."
    for pkg in $(dpkg-query -W -f='${binary:Package}\n'); do
        if apt-cache policy "$pkg" 2>/dev/null | grep -q "$url"; then
            sudo apt-get remove -y "$pkg"
        fi
    done
}

# 5. Upgrade all sources to a new codename
upgrade_sources() {
    local old="$1"
    local new="$2"
    echo "Upgrading all APT sources from $old to $new ..."
    
    # Handle old-style .list files
    if [[ -f "$MAIN_LIST" ]]; then
        sudo sed -i "s|$old|$new|g" "$MAIN_LIST"
    fi
    for file in "$SOURCES_DIR"/*.list; do
        [[ -f "$file" ]] || continue
        sudo sed -i "s|$old|$new|g" "$file"
    done
    
    # Handle new-style .sources files
    for file in "$SOURCES_DIR"/*.sources; do
        [[ -f "$file" ]] || continue
        sudo sed -i "s|$old|$new|g" "$file"
    done
    
    echo "Upgrade complete. You may now run: sudo apt update"
}

# 6. Disable a source by renaming it
disable_source() {
    local id="$1"
    local file
    file=$(grep "^$id|" /tmp/sources_index | cut -d'|' -f2)
    
    if [[ -z "$file" || ! -f "$file" ]]; then
        echo "Error: Source ID $id not found"
        return 1
    fi
    
    if [[ "$file" == "$MAIN_LIST" ]]; then
        echo "Error: Cannot disable the main sources.list file"
        return 1
    fi
    
    if [[ "$file" =~ \.disabled$ ]]; then
        echo "Source is already disabled: $file"
        return 0
    fi
    
    echo "Disabling source: $file"
    sudo mv "$file" "$file.disabled"
    echo "Source disabled. Run 'sudo apt update' to apply changes."
}

# 7. Enable a source by removing .disabled extension
enable_source() {
    local id="$1"
    local file
    file=$(grep "^$id|" /tmp/sources_index | cut -d'|' -f2)
    
    if [[ -z "$file" || ! -f "$file" ]]; then
        echo "Error: Source ID $id not found"
        return 1
    fi
    
    if [[ ! "$file" =~ \.disabled$ ]]; then
        echo "Source is already enabled: $file"
        return 0
    fi
    
    local newfile="${file%.disabled}"
    echo "Enabling source: $file -> $newfile"
    sudo mv "$file" "$newfile"
    echo "Source enabled. Run 'sudo apt update' to apply changes."
}

# 8. List disabled sources
list_disabled() {
    echo "Disabled APT sources:"
    echo "--------------------------------------"
    local i=1
    local found=0
    
    for file in "$SOURCES_DIR"/*.list.disabled "$SOURCES_DIR"/*.sources.disabled; do
        [[ -f "$file" ]] || continue
        found=1
        printf "[%02d] %s\n" "$i" "$(basename "$file")"
        ((i++))
    done
    
    if [[ $found -eq 0 ]]; then
        echo "No disabled sources found."
    fi
    echo "--------------------------------------"
}

# 9. List all GPG keys
list_keys() {
    echo "APT GPG Keys:"
    echo "--------------------------------------"
    local i=1
    
    # Check old deprecated keyring
    if [[ -f "/etc/apt/trusted.gpg" ]]; then
        local format=$(classify_key "/etc/apt/trusted.gpg")
        printf "[%02d] %-25s %s\n" "$i" "$format" "/etc/apt/trusted.gpg"
        ((i++))
    fi
    
    # Check old-style trusted.gpg.d directory
    for keyfile in /etc/apt/trusted.gpg.d/*.gpg; do
        [[ -f "$keyfile" ]] || continue
        local format=$(classify_key "$keyfile")
        printf "[%02d] %-25s %s\n" "$i" "$format" "$keyfile"
        ((i++))
    done
    
    # Check new-style keyrings directory
    for keyfile in /etc/apt/keyrings/*.gpg; do
        [[ -f "$keyfile" ]] || continue
        local format=$(classify_key "$keyfile")
        printf "[%02d] %-25s %s\n" "$i" "$format" "$keyfile"
        ((i++))
    done
    
    # Check system keyrings
    for keyfile in /usr/share/keyrings/*.gpg; do
        [[ -f "$keyfile" ]] || continue
        local format=$(classify_key "$keyfile")
        printf "[%02d] %-25s %s\n" "$i" "$format" "$keyfile"
        ((i++))
    done
    
    echo "--------------------------------------"
}

# 10. List sources with their keys
list_sources_with_keys() {
    echo "APT sources with their signing keys:"
    echo "--------------------------------------"
    local i=1
    
    # Process old-style .list files
    for file in "$MAIN_LIST" "$SOURCES_DIR"/*.list; do
        [[ -f "$file" ]] || continue
        while read -r line; do
            [[ "$line" =~ ^deb ]] || continue
            url=$(echo "$line" | awk '{print $2}')
            label=$(classify_source "$url")
            printf "[%02d] %-30s %-40s\n" "$i" "$label" "$url"
            echo "     Key: Uses default keyring (old-style)"
            ((i++))
        done < "$file"
    done
    
    # Process new-style .sources files (DEB822 format)
    for file in "$SOURCES_DIR"/*.sources; do
        [[ -f "$file" ]] || continue
        [[ -s "$file" ]] || continue
        
        # Parse stanzas to get URI|KEY pairs
        while IFS='|' read -r url key; do
            [[ -n "$url" ]] || continue
            label=$(classify_source "$url")
            printf "[%02d] %-30s %-40s\n" "$i" "$label" "$url"
            
            if [[ "$key" == "none" ]]; then
                echo "     Key: None specified (uses default)"
            else
                local key_format=$(classify_key "$key")
                local key_display=$(format_key_display "$key")
                printf "     Key: %-25s %s\n" "$key_format" "$key_display"
            fi
            ((i++))
        done < <(parse_deb822_stanzas "$file")
    done
    
    # Process disabled old-style .list files
    for file in "$SOURCES_DIR"/*.list.disabled; do
        [[ -f "$file" ]] || continue
        while read -r line; do
            [[ "$line" =~ ^deb ]] || continue
            url=$(echo "$line" | awk '{print $2}')
            label=$(classify_source "$url")
            printf "[%02d] %-30s [disabled] %-40s\n" "$i" "$label" "$url"
            echo "     Key: Uses default keyring (old-style)"
            ((i++))
        done < "$file"
    done
    
    # Process disabled new-style .sources files
    for file in "$SOURCES_DIR"/*.sources.disabled; do
        [[ -f "$file" ]] || continue
        [[ -s "$file" ]] || continue
        
        # Parse stanzas to get URI|KEY pairs
        while IFS='|' read -r url key; do
            [[ -n "$url" ]] || continue
            label=$(classify_source "$url")
            printf "[%02d] %-30s [disabled] %-40s\n" "$i" "$label" "$url"
            
            if [[ "$key" == "none" ]]; then
                echo "     Key: None specified (uses default)"
            else
                local key_format=$(classify_key "$key")
                local key_display=$(format_key_display "$key")
                printf "     Key: %-25s %s\n" "$key_format" "$key_display"
            fi
            ((i++))
        done < <(parse_deb822_stanzas "$file")
    done
    
    echo "--------------------------------------"
}

# 11. Check for missing keys
check_missing_keys() {
    echo "Checking for missing or problematic keys..."
    echo "--------------------------------------"
    local found_issues=0
    
    # Process new-style .sources files (DEB822 format)
    for file in "$SOURCES_DIR"/*.sources; do
        [[ -f "$file" ]] || continue
        [[ -s "$file" ]] || continue
        
        # Parse stanzas to get URI|KEY pairs
        while IFS='|' read -r url key; do
            [[ -n "$url" ]] || continue
            
            if [[ "$key" == "none" ]]; then
                echo "[WARN] No key specified: $url"
                echo "       File: $file"
                echo "       Uses default keyring (may be insecure)"
                echo ""
                found_issues=1
            elif [[ "$key" =~ ^-----BEGIN ]]; then
                echo "[OK] Inline key: $url"
                echo "     File: $file"
                echo ""
            elif [[ ! -f "$key" ]]; then
                echo "[ERROR] Missing key file: $key"
                echo "        Required by: $url"
                echo "        File: $file"
                echo ""
                found_issues=1
            elif [[ ! -r "$key" ]]; then
                echo "[ERROR] Key file not readable: $key"
                echo "        Required by: $url"
                echo "        File: $file"
                echo ""
                found_issues=1
            else
                local key_format=$(classify_key "$key")
                echo "[OK] $key_format: $url"
                echo "     Key: $key"
                echo ""
            fi
        done < <(parse_deb822_stanzas "$file")
    done
    
    echo "--------------------------------------"
    if [[ $found_issues -eq 0 ]]; then
        echo "All keys appear to be present and readable."
    else
        echo "Found issues with one or more keys."
        echo "Fix missing keys by installing the appropriate keyring package"
        echo "or by manually adding the key to /etc/apt/keyrings/"
    fi
}

# 12. Refresh keys from keyserver
refresh_keys() {
    echo "Refreshing GPG keys from keyservers..."
    echo "--------------------------------------"
    
    # Refresh keys in /etc/apt/keyrings/
    local refreshed=0
    for keyfile in /etc/apt/keyrings/*.gpg; do
        [[ -f "$keyfile" ]] || continue
        echo "Refreshing: $keyfile"
        if sudo gpg --no-default-keyring --keyring "$keyfile" --refresh-keys 2>&1 | grep -q "refreshed"; then
            echo "  Success"
            refreshed=1
        else
            echo "  No updates or error"
        fi
    done
    
    echo "--------------------------------------"
    if [[ $refreshed -eq 0 ]]; then
        echo "Note: Most modern keys are managed by packages and don't need manual refresh."
        echo "Keys in /usr/share/keyrings/ are updated via apt package updates."
    fi
    echo "Key refresh complete."
}

# 13. Show key details
show_key_details() {
    local keyfile="$1"
    
    if [[ ! -f "$keyfile" ]]; then
        echo "Error: Key file not found: $keyfile"
        return 1
    fi
    
    echo "Key details for: $keyfile"
    echo "--------------------------------------"
    
    # Show key information
    gpg --no-default-keyring --keyring "$keyfile" --list-keys --with-colons 2>/dev/null | \
    while IFS=: read -r type trust length algo keyid date expires dummy uids rest; do
        if [[ "$type" == "pub" ]]; then
            echo "Key ID: $keyid"
            echo "Algorithm: $algo (${length} bits)"
            if [[ -n "$date" ]]; then
                echo "Created: $(date -d @$date 2>/dev/null || echo $date)"
            fi
            if [[ -n "$expires" ]]; then
                echo "Expires: $(date -d @$expires 2>/dev/null || echo $expires)"
                # Check if expired
                if [[ "$expires" -lt $(date +%s) ]]; then
                    echo "Status: EXPIRED"
                else
                    echo "Status: Valid"
                fi
            else
                echo "Expires: Never"
                echo "Status: Valid"
            fi
        elif [[ "$type" == "uid" ]]; then
            echo "UID: $uids"
        fi
    done
    
    echo "--------------------------------------"
}

# CLI entry
case "${1:-}" in
    --list)
        if [[ "${2:-}" == "--keys" ]]; then
            list_sources_with_keys
        else
            rm -f /tmp/sources_index
            list_sources
        fi
        ;;
    --keys)
        list_keys
        ;;
    --show)
        [[ $# -eq 2 ]] || { echo "Usage: $0 --show <id>"; exit 1; }
        show_packages "$2"
        ;;
    --installed)
        [[ $# -eq 2 ]] || { echo "Usage: $0 --installed <id>"; exit 1; }
        show_installed "$2"
        ;;
    --remove)
        [[ $# -eq 2 ]] || { echo "Usage: $0 --remove <id>"; exit 1; }
        remove_packages "$2"
        ;;
    --upgrade-source)
        [[ $# -eq 3 ]] || { echo "Usage: $0 --upgrade-source <old> <new>"; exit 1; }
        upgrade_sources "$2" "$3"
        ;;
    --disable)
        [[ $# -eq 2 ]] || { echo "Usage: $0 --disable <id>"; exit 1; }
        rm -f /tmp/sources_index
        list_sources > /dev/null
        disable_source "$2"
        ;;
    --enable)
        [[ $# -eq 2 ]] || { echo "Usage: $0 --enable <id>"; exit 1; }
        rm -f /tmp/sources_index
        list_sources > /dev/null
        enable_source "$2"
        ;;
    --list-disabled)
        list_disabled
        ;;
    --check-keys)
        check_missing_keys
        ;;
    --refresh-keys)
        refresh_keys
        ;;
    --key-info)
        [[ $# -eq 2 ]] || { echo "Usage: $0 --key-info <keyfile>"; exit 1; }
        show_key_details "$2"
        ;;
    *)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Source Management:"
        echo "  --list [--keys]              List all sources (optionally with keys)"
        echo "  --show <id>                  Show packages in a source"
        echo "  --installed <id>             Show installed packages from a source"
        echo "  --remove <id>                Remove all packages from a source"
        echo "  --disable <id>               Disable a source"
        echo "  --enable <id>                Enable a disabled source"
        echo "  --list-disabled              List disabled sources"
        echo "  --upgrade-source <old> <new> Upgrade sources to new release"
        echo ""
        echo "Key Management:"
        echo "  --keys                       List all GPG keys"
        echo "  --check-keys                 Check for missing or problematic keys"
        echo "  --refresh-keys               Refresh keys from keyservers"
        echo "  --key-info <keyfile>         Show detailed info about a key"
        exit 1
        ;;
esac
