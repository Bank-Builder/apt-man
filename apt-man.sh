#!/usr/bin/env bash
# APT Manager - manage PPAs and repositories with ease

set -euo pipefail

VERSION="1.0"
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
    
    # Extract codename from URL if it contains a version number
    local repo_codename="$CODENAME"
    if [[ "$url" =~ /ubuntu/([0-9]+\.[0-9]+)/ ]]; then
        local ubuntu_version="${BASH_REMATCH[1]}"
        case "$ubuntu_version" in
            20.04) repo_codename="focal" ;;
            22.04) repo_codename="jammy" ;;
            24.04) repo_codename="noble" ;;
            25.04) repo_codename="plucky" ;;
            *) repo_codename="$CODENAME" ;;
        esac
    fi
    
    # Try the detected codename first
    local packages_url="${url}/dists/${repo_codename}/main/binary-amd64/Packages"
    local packages=$(curl -s "$packages_url" 2>/dev/null)
    
    # Check if we got valid package data (starts with Package:)
    if [[ "$packages" =~ ^Package: ]]; then
        echo "$packages" | grep -E '^Package: ' | awk '{print $2}' | sort | uniq
    else
        echo "No packages found at: $packages_url"
        echo ""
        echo "Trying alternative paths..."
        
        # Try common alternative paths
        local alternatives=(
            "${url}/dists/${CODENAME}/main/binary-amd64/Packages"
            "${url}/dists/main/binary-amd64/Packages"
            "${url}/dists/${repo_codename}/Packages"
        )
        
        for alt_url in "${alternatives[@]}"; do
            echo "Trying: $alt_url"
            local alt_packages=$(curl -s "$alt_url" 2>/dev/null)
            if [[ "$alt_packages" =~ ^Package: ]]; then
                echo "$alt_packages" | grep -E '^Package: ' | awk '{print $2}' | sort | uniq
                break
            fi
        done
    fi
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
    local file
    url=$(grep "^$id|" /tmp/sources_index | cut -d'|' -f3)
    file=$(grep "^$id|" /tmp/sources_index | cut -d'|' -f2)
    
    if [[ -z "$url" || -z "$file" ]]; then
        echo "Error: Source ID $id not found"
        return 1
    fi
    
    echo "Source: $url"
    echo "File: $file"
    echo ""
    
    local packages=()
    local is_disabled=0
    
    # Check if source is disabled
    if [[ "$file" =~ \.disabled$ ]]; then
        is_disabled=1
        echo "Source is disabled. Skipping package search (disabled sources don't show in apt-cache)."
        echo ""
    else
        # Get total package count to estimate time
        local total_pkgs=$(dpkg-query -W | wc -l)
        echo "Note: Your system has $total_pkgs packages installed total."
        echo "      Searching through all of them to find packages from this source"
        echo "      may take 1-2 minutes on systems with many packages."
        echo ""
        read -p "Search for installed packages from this source? [y/N] " -n 1 -r
        echo
        echo ""
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Finding packages installed from this source..."
            
            local checked=0
            local last_percent=-1
            
            for pkg in $(dpkg-query -W -f='${binary:Package}\n'); do
                checked=$((checked + 1))
                local percent=$((checked * 100 / total_pkgs))
                
                # Show progress every 10%
                if [ $((percent / 10)) -gt $((last_percent / 10)) ]; then
                    echo -ne "Checking packages: ${percent}%\r"
                    last_percent=$percent
                fi
                
                if apt-cache policy "$pkg" 2>/dev/null | grep -q "$url"; then
                    packages+=("$pkg")
                fi
            done
            
            echo -ne "\r\033[K"  # Clear the progress line
            echo "Package search complete."
            echo ""
        else
            echo "Skipping package search."
            echo ""
        fi
    fi
    
    # Step 1: Handle installed packages
    if [ ${#packages[@]} -gt 0 ]; then
        echo "Found ${#packages[@]} package(s) installed from this source:"
        printf '  %s\n' "${packages[@]}"
        echo ""
        read -p "Remove these packages? [y/N] " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Running: sudo apt remove ${packages[*]}"
            sudo apt remove "${packages[@]}"
        else
            echo "Skipping package removal."
        fi
        echo ""
    else
        echo "No packages installed from this source."
        echo ""
    fi
    
    # Step 2: Offer to disable/remove the source file
    if [[ "$file" == "$MAIN_LIST" ]]; then
        echo "Cannot remove main sources.list file."
    else
        if [[ $is_disabled -eq 1 ]]; then
            # Source is already disabled, offer to remove it completely
            echo "Source file: $file"
            read -p "Remove this disabled source file permanently? [y/N] " -n 1 -r
            echo
            
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if [[ -f "$file" ]]; then
                    sudo rm "$file"
                    echo "Source file removed: $file"
                else
                    echo "Source file not found: $file"
                fi
            else
                echo "Source file left unchanged."
            fi
        else
            # Source is enabled, offer to disable it
            echo "Source file: $file"
            read -p "Disable this source (rename to .disabled)? [y/N] " -n 1 -r
            echo
            
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if [[ -f "$file" ]]; then
                    sudo mv "$file" "$file.disabled"
                    echo "Source disabled: $file.disabled"
                else
                    echo "Source file not found: $file"
                fi
            else
                echo "Source file left unchanged."
            fi
        fi
        echo ""
    fi
    
    # Step 3: Offer to remove associated keys (for .sources files)
    if [[ "$file" =~ \.sources$ ]] || [[ "$file" =~ \.sources\.disabled$ ]]; then
        local actual_file="$file"
        [[ ! -f "$actual_file" ]] && actual_file="$file.disabled"
        
        if [[ -f "$actual_file" ]]; then
            local keys=()
            while IFS='|' read -r src_url key; do
                [[ -n "$key" ]] && [[ "$key" != "none" ]] && [[ ! "$key" =~ ^-----BEGIN ]] && keys+=("$key")
            done < <(parse_deb822_stanzas "$actual_file")
            
            if [ ${#keys[@]} -gt 0 ]; then
                echo "Found ${#keys[@]} associated key(s):"
                printf '  %s\n' "${keys[@]}"
                echo ""
                echo "WARNING: Removing keys may affect other sources using the same keys."
                read -p "Remove these keys? [y/N] " -n 1 -r
                echo
                
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    for key in "${keys[@]}"; do
                        if [[ -f "$key" ]]; then
                            echo "Removing: $key"
                            sudo rm "$key"
                        fi
                    done
                    echo "Keys removed."
                else
                    echo "Keys left unchanged."
                fi
                echo ""
            fi
        fi
    fi
    
    echo "Done. Run 'sudo apt update' to refresh package lists."
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

# 14. Comprehensive security lint/audit
lint_sources() {
    echo "APT Security Lint - Checking Best Practices"
    echo "============================================"
    echo ""
    
    local issues_found=0
    local warnings_found=0
    local checks_passed=0
    
    # Check 1: Legacy keyring file
    echo "[CHECK 1] Deprecated keyring file"
    if [[ -f "/etc/apt/trusted.gpg" ]]; then
        local keycount=$(gpg --no-default-keyring --keyring /etc/apt/trusted.gpg --list-keys 2>/dev/null | grep -c "^pub" || echo 0)
        if [[ $keycount -gt 0 ]]; then
            echo "  [FAIL] Found $keycount key(s) in deprecated /etc/apt/trusted.gpg"
            echo "         Recommendation: Migrate keys to /etc/apt/keyrings/"
            echo ""
            issues_found=$((issues_found + 1))
        else
            echo "  [PASS] No keys in deprecated keyring file"
            echo ""
            checks_passed=$((checks_passed + 1))
        fi
    else
        echo "  [PASS] Deprecated keyring file does not exist"
        echo ""
        checks_passed=$((checks_passed + 1))
    fi
    
    # Check 2: Legacy .list files without explicit keys
    echo "[CHECK 2] Legacy .list files (should migrate to .sources)"
    local list_count=0
    for file in "$SOURCES_DIR"/*.list; do
        [[ -f "$file" ]] || continue
        [[ "$file" =~ \.disabled$ ]] && continue
        echo "  [WARN] Legacy format: $file"
        echo "         Recommendation: Convert to .sources format with explicit Signed-By"
        list_count=$((list_count + 1))
    done
    if [[ $list_count -gt 0 ]]; then
        echo "         Found $list_count legacy .list file(s)"
        echo ""
        warnings_found=$((warnings_found + 1))
    else
        echo "  [PASS] No legacy .list files in use"
        echo ""
        checks_passed=$((checks_passed + 1))
    fi
    
    # Check 3: Sources without explicit keys
    echo "[CHECK 3] Sources without explicit key references"
    local no_key_count=0
    for file in "$SOURCES_DIR"/*.sources; do
        [[ -f "$file" ]] || continue
        [[ -s "$file" ]] || continue
        [[ "$file" =~ \.disabled$ ]] && continue
        
        local has_key=0
        while IFS='|' read -r url key; do
            [[ -n "$url" ]] || continue
            if [[ "$key" == "none" ]]; then
                echo "  [FAIL] No key specified: $url"
                echo "         File: $file"
                echo "         Recommendation: Add Signed-By field"
                no_key_count=$((no_key_count + 1))
                has_key=0
            else
                has_key=1
            fi
        done < <(parse_deb822_stanzas "$file")
    done
    if [[ $no_key_count -gt 0 ]]; then
        echo "         Found $no_key_count source(s) without keys"
        echo ""
        issues_found=$((issues_found + 1))
    else
        echo "  [PASS] All .sources files have explicit keys"
        echo ""
        checks_passed=$((checks_passed + 1))
    fi
    
    # Check 4: Missing key files
    echo "[CHECK 4] Missing or unreadable key files"
    local missing_count=0
    for file in "$SOURCES_DIR"/*.sources; do
        [[ -f "$file" ]] || continue
        [[ -s "$file" ]] || continue
        [[ "$file" =~ \.disabled$ ]] && continue
        
        while IFS='|' read -r url key; do
            [[ -n "$url" ]] || continue
            if [[ "$key" != "none" ]] && [[ ! "$key" =~ ^-----BEGIN ]]; then
                if [[ ! -f "$key" ]]; then
                    echo "  [FAIL] Missing key: $key"
                    echo "         Required by: $url"
                    echo "         File: $file"
                    missing_count=$((missing_count + 1))
                elif [[ ! -r "$key" ]]; then
                    echo "  [FAIL] Unreadable key: $key"
                    echo "         Required by: $url"
                    echo "         File: $file"
                    missing_count=$((missing_count + 1))
                fi
            fi
        done < <(parse_deb822_stanzas "$file")
    done
    if [[ $missing_count -gt 0 ]]; then
        echo "         Found $missing_count missing/unreadable key(s)"
        echo ""
        issues_found=$((issues_found + 1))
    else
        echo "  [PASS] All referenced key files exist and are readable"
        echo ""
        checks_passed=$((checks_passed + 1))
    fi
    
    # Check 5: Keys in old locations (trusted.gpg.d)
    echo "[CHECK 5] Keys in legacy trusted.gpg.d directory"
    local old_keys=0
    for keyfile in /etc/apt/trusted.gpg.d/*.gpg; do
        [[ -f "$keyfile" ]] || continue
        echo "  [WARN] Old format key: $keyfile"
        old_keys=$((old_keys + 1))
    done
    for keyfile in /etc/apt/trusted.gpg.d/*.asc; do
        [[ -f "$keyfile" ]] || continue
        echo "  [WARN] Old format key: $keyfile"
        old_keys=$((old_keys + 1))
    done
    if [[ $old_keys -gt 0 ]]; then
        echo "         Found $old_keys key(s) in legacy location"
        echo "         Recommendation: Migrate to /etc/apt/keyrings/ with explicit Signed-By"
        echo ""
        warnings_found=$((warnings_found + 1))
    else
        echo "  [PASS] No keys in legacy trusted.gpg.d directory"
        echo ""
        checks_passed=$((checks_passed + 1))
    fi
    
    # Check 6: Expired keys
    echo "[CHECK 6] Expired GPG keys"
    local expired_count=0
    local now=$(date +%s)
    
    for keyfile in /etc/apt/keyrings/*.gpg /usr/share/keyrings/*.gpg; do
        [[ -f "$keyfile" ]] || continue
        
        while IFS=: read -r type trust length algo keyid date expires rest; do
            if [[ "$type" == "pub" ]] && [[ -n "$expires" ]] && [[ "$expires" -lt "$now" ]]; then
                echo "  [FAIL] Expired key: $keyfile"
                echo "         Key ID: $keyid"
                echo "         Expired: $(date -d @$expires 2>/dev/null || echo $expires)"
                expired_count=$((expired_count + 1))
            fi
        done < <(gpg --no-default-keyring --keyring "$keyfile" --list-keys --with-colons 2>/dev/null || true)
    done
    
    if [[ $expired_count -gt 0 ]]; then
        echo "         Found $expired_count expired key(s)"
        echo "         Recommendation: Update or remove expired keys"
        echo ""
        issues_found=$((issues_found + 1))
    else
        echo "  [PASS] No expired keys found"
        echo ""
        checks_passed=$((checks_passed + 1))
    fi
    
    # Check 7: Keys expiring soon (within 30 days)
    echo "[CHECK 7] Keys expiring soon (within 30 days)"
    local expiring_count=0
    local thirty_days=$((now + 2592000))
    
    for keyfile in /etc/apt/keyrings/*.gpg /usr/share/keyrings/*.gpg; do
        [[ -f "$keyfile" ]] || continue
        
        while IFS=: read -r type trust length algo keyid date expires rest; do
            if [[ "$type" == "pub" ]] && [[ -n "$expires" ]] && [[ "$expires" -gt "$now" ]] && [[ "$expires" -lt "$thirty_days" ]]; then
                echo "  [WARN] Key expiring soon: $keyfile"
                echo "         Key ID: $keyid"
                echo "         Expires: $(date -d @$expires 2>/dev/null || echo $expires)"
                expiring_count=$((expiring_count + 1))
            fi
        done < <(gpg --no-default-keyring --keyring "$keyfile" --list-keys --with-colons 2>/dev/null || true)
    done
    
    if [[ $expiring_count -gt 0 ]]; then
        echo "         Found $expiring_count key(s) expiring soon"
        echo "         Recommendation: Plan to update these keys"
        echo ""
        warnings_found=$((warnings_found + 1))
    else
        echo "  [PASS] No keys expiring in the next 30 days"
        echo ""
        checks_passed=$((checks_passed + 1))
    fi
    
    # Check 8: HTTP sources (should use HTTPS)
    echo "[CHECK 8] Sources using HTTP instead of HTTPS"
    local http_count=0
    
    for file in "$SOURCES_DIR"/*.list; do
        [[ -f "$file" ]] || continue
        [[ "$file" =~ \.disabled$ ]] && continue
        while read -r line; do
            [[ "$line" =~ ^deb ]] || continue
            if [[ "$line" =~ http:// ]] && [[ ! "$line" =~ (archive\.ubuntu\.com|security\.ubuntu\.com) ]]; then
                local url=$(echo "$line" | awk '{print $2}')
                echo "  [WARN] HTTP source: $url"
                echo "         File: $file"
                http_count=$((http_count + 1))
            fi
        done < "$file"
    done
    
    for file in "$SOURCES_DIR"/*.sources; do
        [[ -f "$file" ]] || continue
        [[ -s "$file" ]] || continue
        [[ "$file" =~ \.disabled$ ]] && continue
        
        while IFS='|' read -r url key; do
            [[ -n "$url" ]] || continue
            if [[ "$url" =~ ^http:// ]] && [[ ! "$url" =~ (archive\.ubuntu\.com|security\.ubuntu\.com) ]]; then
                echo "  [WARN] HTTP source: $url"
                echo "         File: $file"
                http_count=$((http_count + 1))
            fi
        done < <(parse_deb822_stanzas "$file")
    done
    
    if [[ $http_count -gt 0 ]]; then
        echo "         Found $http_count HTTP source(s)"
        echo "         Recommendation: Use HTTPS for third-party sources"
        echo ""
        warnings_found=$((warnings_found + 1))
    else
        echo "  [PASS] No third-party HTTP sources found"
        echo ""
        checks_passed=$((checks_passed + 1))
    fi
    
    # Check 9: Weak key algorithms
    echo "[CHECK 9] Weak key algorithms (RSA < 2048 bits)"
    local weak_count=0
    
    for keyfile in /etc/apt/keyrings/*.gpg /usr/share/keyrings/*.gpg /etc/apt/trusted.gpg.d/*.gpg; do
        [[ -f "$keyfile" ]] || continue
        
        while IFS=: read -r type trust length algo keyid rest; do
            if [[ "$type" == "pub" ]] && [[ "$algo" == "1" ]] && [[ "$length" -lt 2048 ]]; then
                echo "  [FAIL] Weak RSA key: $keyfile"
                echo "         Key ID: $keyid"
                echo "         Length: ${length} bits (should be >= 2048)"
                weak_count=$((weak_count + 1))
            fi
        done < <(gpg --no-default-keyring --keyring "$keyfile" --list-keys --with-colons 2>/dev/null || true)
    done
    
    if [[ $weak_count -gt 0 ]]; then
        echo "         Found $weak_count weak key(s)"
        echo "         Recommendation: Replace with stronger keys"
        echo ""
        issues_found=$((issues_found + 1))
    else
        echo "  [PASS] No weak keys found"
        echo ""
        checks_passed=$((checks_passed + 1))
    fi
    
    # Check 10: Duplicate sources
    echo "[CHECK 10] Duplicate repository sources"
    local dup_count=0
    declare -A seen_urls
    
    # Collect all URLs with their files
    for file in "$SOURCES_DIR"/*.list; do
        [[ -f "$file" ]] || continue
        [[ "$file" =~ \.disabled$ ]] && continue
        while read -r line; do
            [[ "$line" =~ ^deb ]] || continue
            local url=$(echo "$line" | awk '{print $2}')
            url="${url%/}"  # Remove trailing slash
            if [[ -v "seen_urls[$url]" ]]; then
                echo "  [WARN] Duplicate source: $url"
                echo "         First seen in: ${seen_urls[$url]}"
                echo "         Also found in: $file"
                dup_count=$((dup_count + 1))
            else
                seen_urls[$url]="$file"
            fi
        done < "$file"
    done
    
    for file in "$SOURCES_DIR"/*.sources; do
        [[ -f "$file" ]] || continue
        [[ -s "$file" ]] || continue
        [[ "$file" =~ \.disabled$ ]] && continue
        
        while IFS='|' read -r url key; do
            [[ -n "$url" ]] || continue
            url="${url%/}"  # Remove trailing slash
            if [[ -v "seen_urls[$url]" ]]; then
                echo "  [WARN] Duplicate source: $url"
                echo "         First seen in: ${seen_urls[$url]}"
                echo "         Also found in: $file"
                dup_count=$((dup_count + 1))
            else
                seen_urls[$url]="$file"
            fi
        done < <(parse_deb822_stanzas "$file")
    done
    
    if [[ $dup_count -gt 0 ]]; then
        echo "         Found $dup_count duplicate source(s)"
        echo "         Recommendation: Remove duplicate entries to avoid confusion"
        echo ""
        warnings_found=$((warnings_found + 1))
    else
        echo "  [PASS] No duplicate sources found"
        echo ""
        checks_passed=$((checks_passed + 1))
    fi
    
    # Check 11: Unreachable sources
    echo "[CHECK 11] Unreachable repository URLs (timeout 5s)"
    local unreachable_count=0
    declare -A tested_urls
    
    # Test each unique URL
    for file in "$SOURCES_DIR"/*.list; do
        [[ -f "$file" ]] || continue
        [[ "$file" =~ \.disabled$ ]] && continue
        while read -r line; do
            [[ "$line" =~ ^deb ]] || continue
            local url=$(echo "$line" | awk '{print $2}')
            url="${url%/}"
            
            # Skip if already tested
            [[ -v "tested_urls[$url]" ]] && continue
            tested_urls[$url]=1
            
            # Test URL with timeout
            if ! curl -sf --max-time 5 --head "$url" >/dev/null 2>&1; then
                echo "  [WARN] Unreachable source: $url"
                echo "         File: $file"
                unreachable_count=$((unreachable_count + 1))
            fi
        done < "$file"
    done
    
    for file in "$SOURCES_DIR"/*.sources; do
        [[ -f "$file" ]] || continue
        [[ -s "$file" ]] || continue
        [[ "$file" =~ \.disabled$ ]] && continue
        
        while IFS='|' read -r url key; do
            [[ -n "$url" ]] || continue
            url="${url%/}"
            
            # Skip if already tested
            [[ -v "tested_urls[$url]" ]] && continue
            tested_urls[$url]=1
            
            # Test URL with timeout
            if ! curl -sf --max-time 5 --head "$url" >/dev/null 2>&1; then
                echo "  [WARN] Unreachable source: $url"
                echo "         File: $file"
                unreachable_count=$((unreachable_count + 1))
            fi
        done < <(parse_deb822_stanzas "$file")
    done
    
    if [[ $unreachable_count -gt 0 ]]; then
        echo "         Found $unreachable_count unreachable source(s)"
        echo "         Recommendation: Remove or fix unreachable repositories"
        echo ""
        warnings_found=$((warnings_found + 1))
    else
        echo "  [PASS] All sources are reachable"
        echo ""
        checks_passed=$((checks_passed + 1))
    fi
    
    # Check 12: EOL (End-of-Life) Ubuntu releases
    echo "[CHECK 12] End-of-Life Ubuntu releases (no security updates)"
    local eol_count=0
    
    # List of EOL Ubuntu releases (as of 2025)
    local eol_releases="bionic|cosmic|disco|eoan|groovy|hirsute|impish|kinetic|lunar|mantic"
    
    for file in "$SOURCES_DIR"/*.list; do
        [[ -f "$file" ]] || continue
        [[ "$file" =~ \.disabled$ ]] && continue
        while read -r line; do
            [[ "$line" =~ ^deb ]] || continue
            # Check if line contains any EOL release
            if [[ "$line" =~ ($eol_releases) ]]; then
                local release="${BASH_REMATCH[1]}"
                echo "  [FAIL] EOL release detected: $release"
                echo "         File: $file"
                echo "         Line: $line"
                eol_count=$((eol_count + 1))
            fi
        done < "$file"
    done
    
    for file in "$SOURCES_DIR"/*.sources; do
        [[ -f "$file" ]] || continue
        [[ -s "$file" ]] || continue
        [[ "$file" =~ \.disabled$ ]] && continue
        
        # Check Suites field for EOL releases
        while IFS= read -r line; do
            if [[ "$line" =~ ^Suites:[[:space:]]*(.+)$ ]]; then
                local suites="${BASH_REMATCH[1]}"
                if [[ "$suites" =~ ($eol_releases) ]]; then
                    local release="${BASH_REMATCH[1]}"
                    echo "  [FAIL] EOL release detected: $release"
                    echo "         File: $file"
                    echo "         Suites: $suites"
                    eol_count=$((eol_count + 1))
                fi
            fi
        done < "$file"
    done
    
    if [[ $eol_count -gt 0 ]]; then
        echo "         Found $eol_count EOL release(s)"
        echo "         Recommendation: Upgrade to a supported Ubuntu release immediately"
        echo "         EOL releases receive NO security updates"
        echo ""
        issues_found=$((issues_found + 1))
    else
        echo "  [PASS] No EOL releases detected"
        echo ""
        checks_passed=$((checks_passed + 1))
    fi
    
    # Check 13: File permissions and ownership
    echo "[CHECK 13] Source file permissions and ownership"
    local perm_issues=0
    
    for file in "$SOURCES_DIR"/*.list "$SOURCES_DIR"/*.sources; do
        [[ -f "$file" ]] || continue
        
        # Check ownership
        local owner=$(stat -c '%U:%G' "$file" 2>/dev/null)
        if [[ "$owner" != "root:root" ]]; then
            echo "  [FAIL] Incorrect ownership: $file"
            echo "         Owner: $owner (should be root:root)"
            perm_issues=$((perm_issues + 1))
        fi
        
        # Check if world-writable
        if [[ -w "$file" ]] && [[ $(stat -c '%a' "$file") =~ ^.{2}[2367]$ ]]; then
            echo "  [FAIL] World-writable file: $file"
            echo "         Permissions: $(stat -c '%a' "$file")"
            perm_issues=$((perm_issues + 1))
        fi
        
        # Check if executable
        if [[ -x "$file" ]]; then
            echo "  [WARN] Executable source file: $file"
            echo "         Permissions: $(stat -c '%a' "$file")"
            echo "         Source files should not be executable"
            perm_issues=$((perm_issues + 1))
        fi
        
        # Check if it's a symlink (potential attack vector)
        if [[ -L "$file" ]]; then
            local target=$(readlink -f "$file")
            echo "  [WARN] Symlink detected: $file -> $target"
            echo "         Recommendation: Use regular files instead of symlinks"
            perm_issues=$((perm_issues + 1))
        fi
    done
    
    if [[ $perm_issues -gt 0 ]]; then
        echo "         Found $perm_issues permission/ownership issue(s)"
        echo "         Recommendation: Fix with: sudo chown root:root FILE && sudo chmod 644 FILE"
        echo ""
        issues_found=$((issues_found + 1))
    else
        echo "  [PASS] All source files have correct permissions"
        echo ""
        checks_passed=$((checks_passed + 1))
    fi
    
    # Check 14: Missing security repositories
    echo "[CHECK 14] Missing security update repositories"
    local has_main_repo=0
    local has_security_repo=0
    
    # Check for Ubuntu official repos
    for file in "$SOURCES_DIR"/*.list; do
        [[ -f "$file" ]] || continue
        [[ "$file" =~ \.disabled$ ]] && continue
        while read -r line; do
            [[ "$line" =~ ^deb ]] || continue
            if [[ "$line" =~ archive\.ubuntu\.com ]]; then
                has_main_repo=1
            fi
            if [[ "$line" =~ security\.ubuntu\.com ]] || [[ "$line" =~ -security ]]; then
                has_security_repo=1
            fi
        done < "$file"
    done
    
    for file in "$SOURCES_DIR"/*.sources; do
        [[ -f "$file" ]] || continue
        [[ -s "$file" ]] || continue
        [[ "$file" =~ \.disabled$ ]] && continue
        
        while IFS='|' read -r url key; do
            [[ -n "$url" ]] || continue
            if [[ "$url" =~ archive\.ubuntu\.com ]]; then
                has_main_repo=1
            fi
            if [[ "$url" =~ security\.ubuntu\.com ]]; then
                has_security_repo=1
            fi
        done < <(parse_deb822_stanzas "$file")
        
        # Also check Suites field for -security
        while IFS= read -r line; do
            if [[ "$line" =~ ^Suites:[[:space:]]*(.+)$ ]]; then
                if [[ "${BASH_REMATCH[1]}" =~ -security ]]; then
                    has_security_repo=1
                fi
            fi
        done < "$file"
    done
    
    if [[ $has_main_repo -eq 1 ]] && [[ $has_security_repo -eq 0 ]]; then
        echo "  [FAIL] Main Ubuntu repository found but NO security repository"
        echo "         Your system will NOT receive security updates"
        echo "         Recommendation: Add security.ubuntu.com or -security suite"
        echo ""
        issues_found=$((issues_found + 1))
    elif [[ $has_main_repo -eq 0 ]]; then
        echo "  [WARN] No Ubuntu official repositories found"
        echo ""
        warnings_found=$((warnings_found + 1))
    else
        echo "  [PASS] Security repository is configured"
        echo ""
        checks_passed=$((checks_passed + 1))
    fi
    
    # Check 15: Development/testing repositories
    echo "[CHECK 15] Development or testing repositories"
    local dev_count=0
    
    # Keywords indicating development repos (with word boundaries)
    local dev_keywords="-proposed|-testing|/testing/|unstable|experimental|-devel|-alpha|-beta|-rc[0-9]|/nightly/"
    
    for file in "$SOURCES_DIR"/*.list; do
        [[ -f "$file" ]] || continue
        [[ "$file" =~ \.disabled$ ]] && continue
        while read -r line; do
            [[ "$line" =~ ^deb ]] || continue
            if [[ "$line" =~ ($dev_keywords) ]]; then
                echo "  [WARN] Development repository: $file"
                echo "         Line: $line"
                echo "         Type: ${BASH_REMATCH[1]}"
                dev_count=$((dev_count + 1))
            fi
        done < "$file"
    done
    
    for file in "$SOURCES_DIR"/*.sources; do
        [[ -f "$file" ]] || continue
        [[ -s "$file" ]] || continue
        [[ "$file" =~ \.disabled$ ]] && continue
        
        while IFS= read -r line; do
            if [[ "$line" =~ ^Suites:[[:space:]]*(.+)$ ]]; then
                local suites="${BASH_REMATCH[1]}"
                if [[ "$suites" =~ ($dev_keywords) ]]; then
                    echo "  [WARN] Development repository: $file"
                    echo "         Suites: $suites"
                    echo "         Type: ${BASH_REMATCH[1]}"
                    dev_count=$((dev_count + 1))
                fi
            fi
            if [[ "$line" =~ ^URIs:[[:space:]]*(.+)$ ]]; then
                local uri="${BASH_REMATCH[1]}"
                if [[ "$uri" =~ ($dev_keywords) ]]; then
                    echo "  [WARN] Development repository: $file"
                    echo "         URI: $uri"
                    echo "         Type: ${BASH_REMATCH[1]}"
                    dev_count=$((dev_count + 1))
                fi
            fi
        done < "$file"
    done
    
    if [[ $dev_count -gt 0 ]]; then
        echo "         Found $dev_count development/testing repository(ies)"
        echo "         Recommendation: Avoid development repos on production systems"
        echo "         These may contain unstable or untested packages"
        echo ""
        warnings_found=$((warnings_found + 1))
    else
        echo "  [PASS] No development/testing repositories found"
        echo ""
        checks_passed=$((checks_passed + 1))
    fi
    
    # Check 16: Unnecessary deb-src entries
    echo "[CHECK 16] Unnecessary source package repositories (deb-src)"
    local debsrc_count=0
    
    for file in "$SOURCES_DIR"/*.list; do
        [[ -f "$file" ]] || continue
        [[ "$file" =~ \.disabled$ ]] && continue
        while read -r line; do
            if [[ "$line" =~ ^deb-src ]]; then
                echo "  [WARN] Source package repository: $file"
                echo "         Line: $line"
                debsrc_count=$((debsrc_count + 1))
            fi
        done < "$file"
    done
    
    for file in "$SOURCES_DIR"/*.sources; do
        [[ -f "$file" ]] || continue
        [[ -s "$file" ]] || continue
        [[ "$file" =~ \.disabled$ ]] && continue
        
        while IFS= read -r line; do
            if [[ "$line" =~ ^Types:[[:space:]]*(.+)$ ]]; then
                local types="${BASH_REMATCH[1]}"
                if [[ "$types" =~ deb-src ]]; then
                    echo "  [WARN] Source package repository: $file"
                    echo "         Types: $types"
                    debsrc_count=$((debsrc_count + 1))
                fi
            fi
        done < "$file"
    done
    
    if [[ $debsrc_count -gt 0 ]]; then
        echo "         Found $debsrc_count deb-src repository(ies)"
        echo "         Recommendation: Remove unless you compile packages from source"
        echo "         deb-src entries waste bandwidth and slow 'apt update'"
        echo ""
        warnings_found=$((warnings_found + 1))
    else
        echo "  [PASS] No unnecessary deb-src repositories found"
        echo ""
        checks_passed=$((checks_passed + 1))
    fi
    
    # Check 17: Architecture mismatches
    echo "[CHECK 17] Architecture mismatches"
    local arch_issues=0
    local system_arch=$(dpkg --print-architecture)
    
    # Common wrong architecture patterns
    for file in "$SOURCES_DIR"/*.list; do
        [[ -f "$file" ]] || continue
        [[ "$file" =~ \.disabled$ ]] && continue
        while read -r line; do
            [[ "$line" =~ ^deb ]] || continue
            # Check if line explicitly specifies architecture
            if [[ "$line" =~ \[arch=([a-z0-9,]+)\] ]]; then
                local archs="${BASH_REMATCH[1]}"
                if [[ ! "$archs" =~ (^|,)${system_arch}(,|$) ]]; then
                    echo "  [FAIL] Architecture mismatch: $file"
                    echo "         Line: $line"
                    echo "         Source architecture: $archs"
                    echo "         System architecture: $system_arch"
                    arch_issues=$((arch_issues + 1))
                fi
            fi
            # Check URL path for obvious architecture mismatches
            if [[ "$system_arch" == "amd64" ]] && [[ "$line" =~ (arm64|armhf|i386)/? ]]; then
                echo "  [WARN] Possible architecture mismatch in URL: $file"
                echo "         Line: $line"
                echo "         System: $system_arch"
                arch_issues=$((arch_issues + 1))
            elif [[ "$system_arch" == "arm64" ]] && [[ "$line" =~ (amd64|i386)/? ]]; then
                echo "  [WARN] Possible architecture mismatch in URL: $file"
                echo "         Line: $line"
                echo "         System: $system_arch"
                arch_issues=$((arch_issues + 1))
            fi
        done < "$file"
    done
    
    for file in "$SOURCES_DIR"/*.sources; do
        [[ -f "$file" ]] || continue
        [[ -s "$file" ]] || continue
        [[ "$file" =~ \.disabled$ ]] && continue
        
        # Check Architectures field
        while IFS= read -r line; do
            if [[ "$line" =~ ^Architectures:[[:space:]]*(.+)$ ]]; then
                local archs="${BASH_REMATCH[1]}"
                if [[ ! "$archs" =~ (^| )${system_arch}( |$) ]]; then
                    echo "  [FAIL] Architecture mismatch: $file"
                    echo "         Architectures: $archs"
                    echo "         System architecture: $system_arch"
                    arch_issues=$((arch_issues + 1))
                fi
            fi
        done < "$file"
    done
    
    if [[ $arch_issues -gt 0 ]]; then
        echo "         Found $arch_issues architecture issue(s)"
        echo "         Recommendation: Fix or remove sources for wrong architecture"
        echo ""
        issues_found=$((issues_found + 1))
    else
        echo "  [PASS] No architecture mismatches detected"
        echo ""
        checks_passed=$((checks_passed + 1))
    fi
    
    # Summary
    echo "============================================"
    echo "LINT SUMMARY"
    echo "============================================"
    echo "Checks passed:      $checks_passed"
    echo "Warnings:           $warnings_found"
    echo "Critical issues:    $issues_found"
    echo ""
    
    if [[ $issues_found -gt 0 ]]; then
        echo "Result: FAILED - Critical security issues found"
        echo ""
        echo "Fix issues with these commands:"
        echo "  apt-man keys --check       - Check key problems"
        echo "  apt-man keys --refresh     - Update keys from keyservers"
        echo "  apt-man keys --move <id>   - Move legacy keys to modern location"
        return 1
    elif [[ $warnings_found -gt 0 ]]; then
        echo "Result: PASSED WITH WARNINGS"
        echo ""
        echo "Fix warnings with these commands:"
        echo "  apt-man migrate <id>       - Convert .list to .sources format"
        echo "  apt-man keys --move <id>   - Move keys to /etc/apt/keyrings/"
        echo "  apt-man use-https <id>     - Convert HTTP to HTTPS"
        echo "  apt-man keys --renewal     - Show keys expiring soon"
        echo ""
        echo "Or run: apt-man lint --fix  (to attempt automatic fixes)"
        return 0
    else
        echo "Result: EXCELLENT - All security checks passed!"
        echo ""
        echo "Your APT configuration follows current best practices."
        return 0
    fi
}

# Auto-fix lint warnings interactively
lint_fix() {
    echo "============================================"
    echo "APT SECURITY AUTO-FIX"
    echo "============================================"
    echo ""
    echo "This will scan for security issues and attempt to fix them."
    echo "You will be prompted before each change."
    echo ""
    
    local fixes_applied=0
    local fixes_skipped=0
    local fixes_failed=0
    
    # Create a backup directory
    local backup_dir="/tmp/apt-man-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    local manifest_file="$backup_dir/MANIFEST.txt"
    
    # Create manifest header
    cat > "$manifest_file" << EOF
# apt-man lint --fix manifest
# Created: $(date)
# This file tracks all changes for potential revert
#
# Format: ACTION|TARGET|BACKUP|DETAILS
EOF
    
    echo "Backup directory: $backup_dir"
    echo ""
    
    # Collect HTTP sources that need fixing
    echo "Scanning for HTTP sources..."
    rm -f /tmp/sources_index
    list_sources > /dev/null
    
    local http_sources=()
    while IFS='|' read -r id file url rest; do
        if [[ "$url" =~ ^http:// ]]; then
            http_sources+=("$id|$file|$url")
        fi
    done < /tmp/sources_index
    
    if [[ ${#http_sources[@]} -gt 0 ]]; then
        echo "Found ${#http_sources[@]} HTTP source(s) that should use HTTPS"
        echo ""
        
        for source_info in "${http_sources[@]}"; do
            IFS='|' read -r id file url <<< "$source_info"
            local https_url="${url/http:/https:}"
            
            echo "Source ID $id: $url"
            echo "  File: $file"
            echo "  Would change to: $https_url"
            
            # Test if HTTPS works
            if curl -sf --max-time 5 --head "$https_url" >/dev/null 2>&1; then
                echo "  Status: HTTPS URL is reachable"
                read -p "  Fix this source? [y/N] " -n 1 -r
                echo
                
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    # Backup the file
                    sudo cp "$file" "$backup_dir/$(basename "$file")"
                    
                    # Apply the fix
                    if sudo sed -i "s|http://|https://|g" "$file" 2>/dev/null; then
                        echo "  SUCCESS: Converted to HTTPS"
                        echo "HTTP_TO_HTTPS|$file|$backup_dir/$(basename "$file")|$url -> $https_url" >> "$manifest_file"
                        fixes_applied=$((fixes_applied + 1))
                    else
                        echo "  ERROR: Failed to update file"
                        fixes_failed=$((fixes_failed + 1))
                    fi
                else
                    echo "  SKIPPED"
                    fixes_skipped=$((fixes_skipped + 1))
                fi
            else
                echo "  Status: HTTPS URL not reachable - CANNOT AUTO-FIX"
                echo "  This repository may not support HTTPS"
                fixes_skipped=$((fixes_skipped + 1))
            fi
            echo ""
        done
    else
        echo "No HTTP sources found"
        echo ""
    fi
    
    # Collect legacy keys that need moving
    echo "Scanning for legacy keys in trusted.gpg.d/..."
    local legacy_keys=()
    
    for keyfile in /etc/apt/trusted.gpg.d/*.gpg /etc/apt/trusted.gpg.d/*.asc; do
        [[ -f "$keyfile" ]] || continue
        legacy_keys+=("$keyfile")
    done
    
    if [[ ${#legacy_keys[@]} -gt 0 ]]; then
        echo "Found ${#legacy_keys[@]} legacy key(s) in trusted.gpg.d/"
        echo ""
        echo "NOTE: Keys will be moved to /etc/apt/keyrings/ and removed from legacy location."
        echo "INFO: .sources files will be automatically updated with new key paths."
        echo "Backups will be saved in: $backup_dir"
        echo ""
        
        for keyfile in "${legacy_keys[@]}"; do
            local basename=$(basename "$keyfile")
            local newfile="/etc/apt/keyrings/$basename"
            
            echo "Key: $keyfile"
            echo "  Would move to: $newfile"
            read -p "  Move this key? [y/N] " -n 1 -r
            echo
            
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                # Backup the key first
                sudo cp "$keyfile" "$backup_dir/$(basename "$keyfile")"
                
                # Create keyrings directory if needed
                if [[ ! -d "/etc/apt/keyrings" ]]; then
                    sudo mkdir -p /etc/apt/keyrings
                    sudo chmod 755 /etc/apt/keyrings
                fi
                
                # Copy the key and remove old one
                if sudo cp "$keyfile" "$newfile" 2>/dev/null && sudo chmod 644 "$newfile" 2>/dev/null; then
                    # Update .sources files that reference this key
                    local sources_updated=0
                    for sourcefile in /etc/apt/sources.list.d/*.sources; do
                        [[ -f "$sourcefile" ]] || continue
                        
                        # Check if this source file references the old key
                        if grep -q "$keyfile" "$sourcefile" 2>/dev/null; then
                            # Backup the source file
                            sudo cp "$sourcefile" "$backup_dir/$(basename "$sourcefile")"
                            
                            # Update the key reference
                            if sudo sed -i "s|$keyfile|$newfile|g" "$sourcefile" 2>/dev/null; then
                                echo "  Updated: $(basename "$sourcefile")"
                                sources_updated=$((sources_updated + 1))
                            fi
                        fi
                    done
                    
                    # Remove the legacy key
                    if sudo rm "$keyfile" 2>/dev/null; then
                        echo "  SUCCESS: Key moved to $newfile"
                        echo "  Old key removed from: $keyfile"
                        if [[ $sources_updated -gt 0 ]]; then
                            echo "  Updated $sources_updated .sources file(s)"
                        fi
                        echo "  Backup saved in: $backup_dir"
                        echo "  Test with 'sudo apt update'"
                        echo "KEY_MOVED|$keyfile|$backup_dir/$(basename "$keyfile")|$newfile" >> "$manifest_file"
                        fixes_applied=$((fixes_applied + 1))
                    else
                        echo "  WARNING: Key copied but failed to remove old key"
                        echo "  New key: $newfile"
                        echo "  Old key still exists: $keyfile"
                        if [[ $sources_updated -gt 0 ]]; then
                            echo "  Updated $sources_updated .sources file(s)"
                        fi
                        echo "KEY_COPIED|$keyfile|$backup_dir/$(basename "$keyfile")|$newfile" >> "$manifest_file"
                        fixes_applied=$((fixes_applied + 1))
                    fi
                else
                    echo "  ERROR: Failed to copy key"
                    fixes_failed=$((fixes_failed + 1))
                fi
            else
                echo "  SKIPPED"
                fixes_skipped=$((fixes_skipped + 1))
            fi
            echo ""
        done
    else
        echo "No legacy keys found in trusted.gpg.d/"
        echo ""
    fi
    
    # Check for unreachable sources
    echo "Scanning for unreachable sources..."
    local unreachable_sources=()
    
    # Re-scan sources to get latest state
    rm -f /tmp/sources_index
    list_sources > /dev/null
    
    while IFS='|' read -r id file url rest; do
        # Skip empty lines
        [[ -z "$url" ]] && continue
        
        # Test if URL is reachable
        if ! curl -sf --max-time 5 --head "$url" >/dev/null 2>&1; then
            unreachable_sources+=("$id|$file|$url")
        fi
    done < /tmp/sources_index
    
    if [[ ${#unreachable_sources[@]} -gt 0 ]]; then
        echo "Found ${#unreachable_sources[@]} unreachable source(s)"
        echo ""
        
        for source_info in "${unreachable_sources[@]}"; do
            IFS='|' read -r id file url <<< "$source_info"
            
            echo "Source ID $id: $url"
            echo "  File: $file"
            echo "  Status: UNREACHABLE (timeout after 5s)"
            echo ""
            echo "  Options:"
            echo "    d) Disable this source (rename to .disabled)"
            echo "    r) Remove source file completely"
            echo "    s) Skip (leave as is)"
            read -p "  Action? [d/r/S] " -n 1 -r
            echo
            
            if [[ $REPLY =~ ^[Dd]$ ]]; then
                # Disable the source
                local disabled_file="${file}.disabled"
                
                # Backup first
                sudo cp "$file" "$backup_dir/$(basename "$file")"
                
                if sudo mv "$file" "$disabled_file" 2>/dev/null; then
                    echo "  SUCCESS: Source disabled"
                    echo "  Moved to: $disabled_file"
                    echo "SOURCE_DISABLED|$file|$backup_dir/$(basename "$file")|$disabled_file" >> "$manifest_file"
                    fixes_applied=$((fixes_applied + 1))
                else
                    echo "  ERROR: Failed to disable source"
                    fixes_failed=$((fixes_failed + 1))
                fi
            elif [[ $REPLY =~ ^[Rr]$ ]]; then
                echo "  WARNING: This will permanently delete the source file!"
                read -p "  Are you sure? [y/N] " -n 1 -r
                echo
                
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    # Backup first
                    sudo cp "$file" "$backup_dir/$(basename "$file")"
                    
                    if sudo rm "$file" 2>/dev/null; then
                        echo "  SUCCESS: Source file removed"
                        echo "  Backup saved in: $backup_dir"
                        echo "SOURCE_REMOVED|$file|$backup_dir/$(basename "$file")|deleted" >> "$manifest_file"
                        fixes_applied=$((fixes_applied + 1))
                    else
                        echo "  ERROR: Failed to remove source"
                        fixes_failed=$((fixes_failed + 1))
                    fi
                else
                    echo "  CANCELLED"
                    fixes_skipped=$((fixes_skipped + 1))
                fi
            else
                echo "  SKIPPED"
                fixes_skipped=$((fixes_skipped + 1))
            fi
            echo ""
        done
    else
        echo "All sources are reachable"
        echo ""
    fi
    
    # Summary
    echo "============================================"
    echo "AUTO-FIX SUMMARY"
    echo "============================================"
    echo "Fixes applied:  $fixes_applied"
    echo "Fixes skipped:  $fixes_skipped"
    echo "Fixes failed:   $fixes_failed"
    echo ""
    
    if [[ $fixes_applied -gt 0 ]]; then
        echo "Changes have been applied. Run 'sudo apt update' to test."
        echo "Backups saved in: $backup_dir"
        echo "Manifest: $manifest_file"
        echo ""
        echo "To revert all changes, run:"
        echo "  sudo apt-man revert $backup_dir"
        echo ""
        echo "Run 'apt-man lint' again to verify the fixes."
    else
        echo "No changes were made."
        rm -f "$manifest_file"
        rmdir "$backup_dir" 2>/dev/null || true
    fi
}

# Revert changes from a lint --fix session
revert_changes() {
    local backup_selection="$1"
    
    # If no argument provided, list available backups with details
    if [[ -z "$backup_selection" ]]; then
        echo "============================================"
        echo "AVAILABLE BACKUPS"
        echo "============================================"
        echo ""
        
        local backups=()
        mapfile -t backups < <(ls -dt /tmp/apt-man-backup-* 2>/dev/null)
        
        if [[ ${#backups[@]} -eq 0 ]]; then
            echo "No backups found in /tmp/"
            echo ""
            echo "Backups are created by 'apt-man lint --fix'"
            return 1
        fi
        
        local idx=1
        for backup_dir in "${backups[@]}"; do
            local manifest_file="$backup_dir/MANIFEST.txt"
            local timestamp=$(basename "$backup_dir" | sed 's/apt-man-backup-//')
            
            echo "[$idx] $timestamp"
            echo "    Directory: $backup_dir"
            
            if [[ -f "$manifest_file" ]]; then
                local action_count=0
                while IFS='|' read -r action target backup details; do
                    [[ "$action" =~ ^# ]] && continue
                    [[ -z "$action" ]] && continue
                    action_count=$((action_count + 1))
                done < "$manifest_file"
                echo "    Changes: $action_count action(s)"
            else
                echo "    Changes: No manifest found"
            fi
            echo ""
            
            idx=$((idx + 1))
        done
        
        echo "To revert a backup, run:"
        echo "  sudo apt-man revert <number>"
        echo "  sudo apt-man revert <full-path>"
        return 0
    fi
    
    local backup_dir
    
    # Check if selection is a number
    if [[ "$backup_selection" =~ ^[0-9]+$ ]]; then
        # Get the Nth backup (most recent first)
        local backups=()
        mapfile -t backups < <(ls -dt /tmp/apt-man-backup-* 2>/dev/null)
        
        if [[ ${#backups[@]} -eq 0 ]]; then
            echo "Error: No backups found"
            return 1
        fi
        
        local idx=$((backup_selection - 1))
        if [[ $idx -lt 0 ]] || [[ $idx -ge ${#backups[@]} ]]; then
            echo "Error: Invalid backup number: $backup_selection"
            echo "Available backups: 1-${#backups[@]}"
            return 1
        fi
        
        backup_dir="${backups[$idx]}"
    else
        # Assume it's a directory path
        backup_dir="$backup_selection"
    fi
    
    if [[ ! -d "$backup_dir" ]]; then
        echo "Error: Backup directory not found: $backup_dir"
        return 1
    fi
    
    local manifest_file="$backup_dir/MANIFEST.txt"
    if [[ ! -f "$manifest_file" ]]; then
        echo "Error: Manifest file not found: $manifest_file"
        echo "Cannot safely revert without manifest"
        return 1
    fi
    
    echo "============================================"
    echo "APT REVERT CHANGES"
    echo "============================================"
    echo ""
    echo "This will revert changes from: $backup_dir"
    echo ""
    
    # Read and display what will be reverted
    local action_count=0
    while IFS='|' read -r action target backup details; do
        [[ "$action" =~ ^# ]] && continue
        [[ -z "$action" ]] && continue
        action_count=$((action_count + 1))
        
        case "$action" in
            HTTP_TO_HTTPS)
                echo "  [$action_count] Revert HTTPS to HTTP: $(basename "$target")"
                ;;
            KEY_MOVED|KEY_COPIED)
                echo "  [$action_count] Restore key: $(basename "$target")"
                ;;
            SOURCE_DISABLED)
                echo "  [$action_count] Re-enable source: $(basename "$target")"
                ;;
            SOURCE_REMOVED)
                echo "  [$action_count] Restore removed source: $(basename "$target")"
                ;;
        esac
    done < "$manifest_file"
    
    if [[ $action_count -eq 0 ]]; then
        echo "No actions to revert"
        return 0
    fi
    
    echo ""
    read -p "Proceed with revert? [y/N] " -n 1 -r
    echo
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Revert cancelled"
        return 0
    fi
    
    # Process revert actions
    local reverted=0
    local failed=0
    
    while IFS='|' read -r action target backup details; do
        [[ "$action" =~ ^# ]] && continue
        [[ -z "$action" ]] && continue
        
        case "$action" in
            HTTP_TO_HTTPS)
                echo "Reverting: $target"
                if [[ -f "$backup" ]] && sudo cp "$backup" "$target" 2>/dev/null; then
                    echo "  SUCCESS: Restored from backup"
                    reverted=$((reverted + 1))
                else
                    echo "  ERROR: Failed to restore"
                    failed=$((failed + 1))
                fi
                ;;
                
            KEY_MOVED)
                # Restore old key and remove new key
                local newfile="$details"
                echo "Reverting: $target"
                if [[ -f "$backup" ]] && sudo cp "$backup" "$target" 2>/dev/null; then
                    # Remove the new key location
                    if [[ -f "$newfile" ]]; then
                        sudo rm "$newfile" 2>/dev/null
                    fi
                    echo "  SUCCESS: Key restored to legacy location"
                    reverted=$((reverted + 1))
                else
                    echo "  ERROR: Failed to restore key"
                    failed=$((failed + 1))
                fi
                ;;
                
            KEY_COPIED)
                # Just restore the old key (it wasn't deleted)
                echo "Reverting: $target (was not deleted)"
                if [[ ! -f "$target" ]] && [[ -f "$backup" ]]; then
                    if sudo cp "$backup" "$target" 2>/dev/null; then
                        echo "  SUCCESS: Key restored"
                        reverted=$((reverted + 1))
                    else
                        echo "  ERROR: Failed to restore"
                        failed=$((failed + 1))
                    fi
                else
                    echo "  SKIP: Key still exists"
                fi
                ;;
                
            SOURCE_DISABLED)
                # Re-enable by renaming .disabled back to original
                local disabled_file="$details"
                echo "Reverting: $target"
                if [[ -f "$disabled_file" ]] && sudo mv "$disabled_file" "$target" 2>/dev/null; then
                    echo "  SUCCESS: Source re-enabled"
                    reverted=$((reverted + 1))
                else
                    echo "  ERROR: Failed to re-enable"
                    failed=$((failed + 1))
                fi
                ;;
                
            SOURCE_REMOVED)
                # Restore from backup
                echo "Reverting: $target"
                if [[ -f "$backup" ]] && sudo cp "$backup" "$target" 2>/dev/null; then
                    echo "  SUCCESS: Source restored"
                    reverted=$((reverted + 1))
                else
                    echo "  ERROR: Failed to restore"
                    failed=$((failed + 1))
                fi
                ;;
        esac
    done < "$manifest_file"
    
    echo ""
    echo "============================================"
    echo "REVERT SUMMARY"
    echo "============================================"
    echo "Actions reverted: $reverted"
    echo "Actions failed:   $failed"
    echo ""
    
    if [[ $reverted -gt 0 ]]; then
        echo "Changes have been reverted. Run 'sudo apt update' to test."
        echo ""
        echo "The backup directory is preserved:"
        echo "  $backup_dir"
    fi
}

# 18. Migrate .list file to .sources format
migrate_source() {
    local id="$1"
    [[ -n "$id" ]] || { echo "Usage: apt-man migrate <id>"; exit 1; }
    
    echo "Migration feature coming soon!"
    echo "This will convert .list files to modern .sources format"
    echo ""
    echo "Manual steps:"
    echo "1. Identify the .list file from 'apt-man list'"
    echo "2. Create a new .sources file in /etc/apt/sources.list.d/"
    echo "3. Use DEB822 format with explicit Signed-By field"
    echo "4. Test with 'sudo apt update'"
    echo "5. Remove the old .list file"
}

# 19. Convert HTTP to HTTPS
use_https() {
    local id="$1"
    [[ -n "$id" ]] || { echo "Usage: apt-man use-https <id>"; exit 1; }
    
    rm -f /tmp/sources_index
    list_sources > /dev/null
    
    local file
    local url
    file=$(grep "^$id|" /tmp/sources_index | cut -d'|' -f2)
    url=$(grep "^$id|" /tmp/sources_index | cut -d'|' -f3)
    
    if [[ -z "$file" ]] || [[ ! -f "$file" ]]; then
        echo "Error: Source ID $id not found"
        return 1
    fi
    
    if [[ ! "$url" =~ ^http:// ]]; then
        echo "Source $id already uses HTTPS or is not HTTP"
        return 0
    fi
    
    local https_url="${url/http:/https:}"
    
    echo "Converting source $id to HTTPS:"
    echo "  File: $file"
    echo "  From: $url"
    echo "  To:   $https_url"
    echo ""
    
    # Test if HTTPS URL is reachable
    if ! curl -sf --max-time 5 --head "$https_url" >/dev/null 2>&1; then
        echo "ERROR: HTTPS URL is not reachable: $https_url"
        echo "This repository may not support HTTPS"
        return 1
    fi
    
    # Backup the file
    sudo cp "$file" "$file.backup"
    
    # Replace HTTP with HTTPS in the file
    sudo sed -i "s|http://|https://|g" "$file"
    
    echo "SUCCESS: Converted to HTTPS"
    echo "Backup saved: $file.backup"
    echo "Run 'sudo apt update' to test"
}

# 20. Move legacy keys to modern location
move_legacy_key() {
    local keyfile="$1"
    [[ -n "$keyfile" ]] || { echo "Usage: apt-man keys --move <keyfile>"; exit 1; }
    
    if [[ ! -f "$keyfile" ]]; then
        echo "Error: Key file not found: $keyfile"
        return 1
    fi
    
    if [[ ! "$keyfile" =~ ^/etc/apt/trusted\.gpg\.d/ ]]; then
        echo "Error: Key is not in legacy location (trusted.gpg.d)"
        return 1
    fi
    
    local basename=$(basename "$keyfile")
    local newfile="/etc/apt/keyrings/$basename"
    
    echo "Moving legacy key to modern location:"
    echo "  From: $keyfile"
    echo "  To:   $newfile"
    echo ""
    
    # Create backup
    local backup_file="/tmp/$(basename "$keyfile").backup-$(date +%Y%m%d-%H%M%S)"
    sudo cp "$keyfile" "$backup_file"
    echo "Backup created: $backup_file"
    echo ""
    
    # Create keyrings directory if it doesn't exist
    if [[ ! -d "/etc/apt/keyrings" ]]; then
        sudo mkdir -p /etc/apt/keyrings
        sudo chmod 755 /etc/apt/keyrings
    fi
    
    # Copy the key
    sudo cp "$keyfile" "$newfile"
    sudo chmod 644 "$newfile"
    
    # Update .sources files that reference this key
    echo "Updating .sources files..."
    local sources_updated=0
    for sourcefile in /etc/apt/sources.list.d/*.sources; do
        [[ -f "$sourcefile" ]] || continue
        
        # Check if this source file references the old key
        if grep -q "$keyfile" "$sourcefile" 2>/dev/null; then
            # Backup the source file
            local source_backup="/tmp/$(basename "$sourcefile").backup-$(date +%Y%m%d-%H%M%S)"
            sudo cp "$sourcefile" "$source_backup"
            
            # Update the key reference
            if sudo sed -i "s|$keyfile|$newfile|g" "$sourcefile" 2>/dev/null; then
                echo "  Updated: $(basename "$sourcefile")"
                sources_updated=$((sources_updated + 1))
            fi
        fi
    done
    
    # Remove the old key
    if sudo rm "$keyfile" 2>/dev/null; then
        echo ""
        echo "SUCCESS: Key moved to $newfile"
        echo "Old key removed from: $keyfile"
        if [[ $sources_updated -gt 0 ]]; then
            echo "Updated $sources_updated .sources file(s) automatically"
        fi
        echo "Backup saved: $backup_file"
    else
        echo ""
        echo "SUCCESS: Key copied to $newfile"
        echo "WARNING: Failed to remove old key: $keyfile"
        if [[ $sources_updated -gt 0 ]]; then
            echo "Updated $sources_updated .sources file(s) automatically"
        fi
        echo "You may need to manually remove it"
    fi
    
    echo ""
    echo "Next steps:"
    echo "1. Test with 'sudo apt update'"
    if [[ $sources_updated -eq 0 ]]; then
        echo "2. If needed, manually update any .list files to reference: $newfile"
    fi
}

# 21. Show keys needing renewal
keys_renewal() {
    echo "Keys expiring in the next 90 days:"
    echo "--------------------------------------"
    
    local now=$(date +%s)
    local ninety_days=$((now + 7776000))
    local found=0
    
    for keyfile in /etc/apt/keyrings/*.gpg /usr/share/keyrings/*.gpg /etc/apt/trusted.gpg.d/*.gpg; do
        [[ -f "$keyfile" ]] || continue
        
        while IFS=: read -r type trust length algo keyid date expires rest; do
            if [[ "$type" == "pub" ]]; then
                if [[ -n "$expires" ]] && [[ "$expires" -gt "$now" ]] && [[ "$expires" -lt "$ninety_days" ]]; then
                    local days_left=$(( (expires - now) / 86400 ))
                    echo "Key: $keyfile"
                    echo "  Key ID: $keyid"
                    echo "  Expires: $(date -d @$expires '+%Y-%m-%d')"
                    echo "  Days left: $days_left"
                    echo ""
                    found=1
                fi
            fi
        done < <(gpg --no-default-keyring --keyring "$keyfile" --list-keys --with-colons 2>/dev/null || true)
    done
    
    if [[ $found -eq 0 ]]; then
        echo "No keys expiring in the next 90 days"
    else
        echo "--------------------------------------"
        echo "Recommendation: Plan to update these keys before expiration"
        echo "Use 'apt-man keys --refresh' to update from keyservers"
    fi
}

# Show help message
show_help() {
    cat << 'EOF'
Usage: apt-man [COMMAND] [OPTIONS] [ARGS]
Manage APT sources, PPAs, and GPG keys with ease.

Commands:
  list [--keys]                list all sources (optionally with keys)
  show ID                      show packages in a source
  installed ID                 show installed packages from a source
  remove ID                    remove all packages from a source
  disable ID                   disable a source
  enable ID                    enable a disabled source
  list-disabled                list disabled sources
  upgrade-source OLD NEW       upgrade sources to new release
  lint                         comprehensive security audit of sources and keys
  lint --fix                   interactively fix warnings (HTTP, keys, unreachable)
  revert [NUMBER|PATH]         revert changes from lint --fix (lists backups if no arg)
  
  migrate ID                   convert .list file to .sources format
  use-https ID                 convert HTTP source to HTTPS
  
  keys [OPTIONS]               manage GPG keys
    --list                     list all GPG keys (default)
    --check                    check for missing or problematic keys
    --refresh                  refresh keys from keyservers
    --info KEYFILE             show detailed info about a key
    --move KEYFILE             move legacy key to /etc/apt/keyrings/
    --renewal                  show keys expiring in next 90 days

General Options:
  --help, -h                   display this help and exit
  --version, -V                output version information and exit

Key Format Classifications:
  OLD (deprecated)             /etc/apt/trusted.gpg (single file)
  OLD (trusted.gpg.d)          /etc/apt/trusted.gpg.d/*.gpg
  NEW (apt keyring)            /etc/apt/keyrings/*.gpg (recommended)
  NEW (system keyring)         /usr/share/keyrings/*.gpg
  INLINE (embedded key)        embedded in .sources files

Examples:
  apt-man list                 List all sources
  apt-man list --keys          List sources with their keys
  apt-man disable 5            Disable source ID 5
  apt-man use-https 7          Convert source ID 7 to HTTPS
  apt-man migrate 3            Convert .list file to .sources format
  apt-man lint                 Run comprehensive security audit
  apt-man lint --fix           Interactively fix security warnings
  apt-man revert               List all available backups
  apt-man revert 1             Revert the most recent backup
  apt-man keys --check         Check for key problems
  apt-man keys --renewal       Show keys expiring soon
  apt-man keys --move /etc/apt/trusted.gpg.d/old.gpg
  apt-man keys --info /etc/apt/keyrings/microsoft.gpg
  apt-man upgrade-source noble oracular

Exit status:
  0  if OK,
  1  if problems with arguments or execution,
  2  if file not found or permission denied.

Report bugs to: <https://github.com/yourusername/apt-man/issues>
apt-man home page: <https://github.com/yourusername/apt-man>
EOF
}

# Show version
show_version() {
    cat << EOF
apt-man $VERSION
Copyright (C) 2025 Free Software
License: GNU GPL version 3 or later <https://gnu.org/licenses/gpl.html>.
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.

Written by Andrew.
EOF
}

# CLI entry
# Parse command (first argument)
COMMAND="${1:-}"

# Handle help and version first
case "$COMMAND" in
    --help|-h|help)
        show_help
        exit 0
        ;;
    --version|-V|version)
        show_version
        exit 0
        ;;
esac

# Handle empty command
if [[ -z "$COMMAND" ]]; then
    echo "apt-man: missing command" >&2
    echo "Try 'apt-man --help' for more information." >&2
    exit 1
fi

# Main command dispatcher
case "$COMMAND" in
    list)
        if [[ "${2:-}" == "--keys" ]]; then
            list_sources_with_keys
        else
            rm -f /tmp/sources_index
            list_sources
        fi
        ;;
    
    show)
        [[ $# -eq 2 ]] || { echo "Usage: apt-man show <id>"; exit 1; }
        rm -f /tmp/sources_index
        list_sources > /dev/null
        show_packages "$2"
        ;;
    
    installed)
        [[ $# -eq 2 ]] || { echo "Usage: apt-man installed <id>"; exit 1; }
        show_installed "$2"
        ;;
    
    remove)
        [[ $# -eq 2 ]] || { echo "Usage: apt-man remove <id>"; exit 1; }
        rm -f /tmp/sources_index
        list_sources > /dev/null
        remove_packages "$2"
        ;;
    
    disable)
        [[ $# -eq 2 ]] || { echo "Usage: apt-man disable <id>"; exit 1; }
        rm -f /tmp/sources_index
        list_sources > /dev/null
        disable_source "$2"
        ;;
    
    enable)
        [[ $# -eq 2 ]] || { echo "Usage: apt-man enable <id>"; exit 1; }
        rm -f /tmp/sources_index
        list_sources > /dev/null
        enable_source "$2"
        ;;
    
    list-disabled)
        list_disabled
        ;;
    
    upgrade-source)
        [[ $# -eq 3 ]] || { echo "Usage: apt-man upgrade-source <old> <new>"; exit 1; }
        upgrade_sources "$2" "$3"
        ;;
    
    lint)
        if [[ "${2:-}" == "--fix" ]]; then
            lint_fix
        else
            lint_sources
        fi
        ;;
    
    migrate)
        [[ $# -eq 2 ]] || { echo "Usage: apt-man migrate <id>"; exit 1; }
        migrate_source "$2"
        ;;
    
    use-https)
        [[ $# -eq 2 ]] || { echo "Usage: apt-man use-https <id>"; exit 1; }
        use_https "$2"
        ;;
    
    revert)
        revert_changes "${2:-}"
        ;;
    
    keys)
        # Sub-command for keys
        KEYS_CMD="${2:---list}"
        case "$KEYS_CMD" in
            --list|list)
                list_keys
                ;;
            --check|check)
                check_missing_keys
                ;;
            --refresh|refresh)
                refresh_keys
                ;;
            --info|info)
                [[ $# -eq 3 ]] || { echo "Usage: apt-man keys --info <keyfile>"; exit 1; }
                show_key_details "$3"
                ;;
            --move|move)
                [[ $# -eq 3 ]] || { echo "Usage: apt-man keys --move <keyfile>"; exit 1; }
                move_legacy_key "$3"
                ;;
            --renewal|renewal)
                keys_renewal
                ;;
            *)
                echo "apt-man keys: invalid option -- '$KEYS_CMD'" >&2
                echo "Try 'apt-man --help' for more information." >&2
                exit 1
                ;;
        esac
        ;;
    
    *)
        echo "apt-man: invalid command -- '$COMMAND'" >&2
        echo "Try 'apt-man --help' for more information." >&2
        exit 1
        ;;
esac
