# bash completion for apt-man
# Install to /etc/bash_completion.d/ or /usr/share/bash-completion/completions/

_apt_man_completion() {
    local cur prev words cword
    _init_completion || return

    # Main commands
    local commands="list show installed remove disable enable list-disabled upgrade-source lint revert migrate use-https keys help version"
    
    # Options for specific commands
    local list_opts="--keys"
    local lint_opts="--fix"
    local keys_opts="--list --check --refresh --info --move --renewal list check refresh info move renewal"
    
    # Handle completion based on position
    case $cword in
        1)
            # First argument: complete main commands
            COMPREPLY=($(compgen -W "$commands --help --version -h -V" -- "$cur"))
            return 0
            ;;
        2)
            # Second argument: depends on first command
            case ${words[1]} in
                list)
                    COMPREPLY=($(compgen -W "$list_opts" -- "$cur"))
                    return 0
                    ;;
                lint)
                    COMPREPLY=($(compgen -W "$lint_opts" -- "$cur"))
                    return 0
                    ;;
                keys)
                    COMPREPLY=($(compgen -W "$keys_opts" -- "$cur"))
                    return 0
                    ;;
                show|installed|remove|disable|enable|migrate|use-https)
                    # Complete with source IDs from apt-man list
                    local ids
                    if [[ -f /tmp/sources_index ]]; then
                        ids=$(cut -d'|' -f1 /tmp/sources_index 2>/dev/null)
                    else
                        # Try to generate the index
                        ids=$(apt-man list 2>/dev/null | grep -E '^\[' | sed 's/\[\([0-9]*\)\].*/\1/')
                    fi
                    COMPREPLY=($(compgen -W "$ids" -- "$cur"))
                    return 0
                    ;;
                revert)
                    # Complete with backup directories or numbers
                    local backups=$(ls -dt /tmp/apt-man-backup-* 2>/dev/null | head -10)
                    local numbers=$(seq 1 10)
                    COMPREPLY=($(compgen -W "$numbers" -- "$cur"))
                    if [[ "$cur" == /* || "$cur" == ./* ]]; then
                        COMPREPLY+=($(compgen -d -- "$cur"))
                    fi
                    return 0
                    ;;
                upgrade-source)
                    # Complete with Ubuntu release codenames
                    local releases="focal jammy noble oracular mantic lunar kinetic impish hirsute groovy"
                    COMPREPLY=($(compgen -W "$releases" -- "$cur"))
                    return 0
                    ;;
            esac
            ;;
        3)
            # Third argument
            case ${words[1]} in
                keys)
                    case ${words[2]} in
                        --info|info|--move|move)
                            # Complete with key file paths
                            local key_dirs="/etc/apt/keyrings /etc/apt/trusted.gpg.d /usr/share/keyrings"
                            local keyfiles=""
                            for dir in $key_dirs; do
                                if [[ -d "$dir" ]]; then
                                    keyfiles="$keyfiles $(find "$dir" -maxdepth 1 -type f \( -name '*.gpg' -o -name '*.asc' \) 2>/dev/null)"
                                fi
                            done
                            COMPREPLY=($(compgen -W "$keyfiles" -- "$cur"))
                            if [[ "$cur" == /* || "$cur" == ./* ]]; then
                                COMPREPLY+=($(compgen -f -X '!*.@(gpg|asc)' -- "$cur"))
                            fi
                            return 0
                            ;;
                    esac
                    ;;
                upgrade-source)
                    # Second release name
                    local releases="focal jammy noble oracular mantic lunar kinetic impish hirsute groovy"
                    COMPREPLY=($(compgen -W "$releases" -- "$cur"))
                    return 0
                    ;;
            esac
            ;;
    esac

    return 0
}

# Register the completion function
complete -F _apt_man_completion apt-man

