# apt-man - APT Source and Key Manager

A comprehensive command-line tool for managing APT package sources, PPAs, and GPG keys on Ubuntu and Debian-based systems.

## Features

- **Source Management**
  - List all sources (both .list and .sources formats)
  - Enable/disable sources without deleting them
  - Show packages available in or installed from specific sources
  - Bulk upgrade sources between Ubuntu releases
  - Remove all packages from a source

- **Key Management**
  - List all GPG keys with format classification
  - Check for missing or problematic keys
  - Refresh keys from keyservers
  - Show detailed key information (ID, algorithm, expiration)
  - Move legacy keys to modern locations
  - Show keys expiring soon (renewal planning)
  - Support for old and new key formats

- **Security Fixes**
  - Convert HTTP sources to HTTPS automatically
  - Migrate legacy .list files to .sources format
  - Comprehensive security auditing with 17 checks

- **Format Support**
  - Legacy `.list` files (one-line format)
  - Modern `.sources` files (DEB822 format)
  - Inline PGP keys embedded in source files
  - Both old and new GPG key storage locations

## Installation

### Quick Install

```bash
sudo make install
```

This installs to `/usr/local/bin/` by default. To install to a different location:

```bash
sudo make install PREFIX=/usr
```

### Manual Install

```bash
sudo cp apt-man.sh /usr/local/bin/apt-man
sudo chmod +x /usr/local/bin/apt-man
```

### Install Documentation

Install man page:
```bash
sudo make install-man
```

Install info page:
```bash
sudo make install-info
```

## Usage

### Basic Commands

List all sources:
```bash
apt-man list
```

List sources with their GPG keys:
```bash
apt-man list --keys
```

Run comprehensive security audit:
```bash
apt-man lint
```

Interactively fix security warnings (HTTP sources, legacy keys, unreachable sources):
```bash
apt-man lint --fix
```

List available backups and revert changes:
```bash
apt-man revert           # List all backups
apt-man revert 1         # Revert most recent changes
```

Disable a source (by ID from list):
```bash
apt-man disable 5
```

Enable a disabled source:
```bash
apt-man enable 5
```

### Security Fixes

Convert HTTP source to HTTPS:
```bash
apt-man use-https 7
```

Migrate .list file to .sources format:
```bash
apt-man migrate 3
```

### Key Management

List all GPG keys:
```bash
apt-man keys
# or
apt-man keys --list
```

Check for key problems:
```bash
apt-man keys --check
```

Show detailed key information:
```bash
apt-man keys --info /etc/apt/keyrings/microsoft.gpg
```

Refresh keys from keyservers:
```bash
apt-man keys --refresh
```

Move legacy key to modern location:
```bash
apt-man keys --move /etc/apt/trusted.gpg.d/old.gpg
```

Show keys expiring in next 90 days:
```bash
apt-man keys --renewal
```

### Package Operations

Show packages in a source:
```bash
apt-man show 3
```

Show installed packages from a source:
```bash
apt-man installed 3
```

Remove all packages from a source:
```bash
apt-man remove 3
```

### Release Upgrade

Upgrade all sources to a new Ubuntu release:
```bash
apt-man upgrade-source noble oracular
sudo apt update
sudo apt dist-upgrade
```

## Documentation

View the manual page:
```bash
man apt-man
```

View the info page:
```bash
info apt-man
```

View help:
```bash
apt-man --help
```

## Key Format Classifications

apt-man categorizes GPG keys by their format and security level:

- **OLD (deprecated)** - `/etc/apt/trusted.gpg` - Single file, avoid for new keys
- **OLD (trusted.gpg.d)** - `/etc/apt/trusted.gpg.d/*.gpg` - Legacy directory format
- **NEW (apt keyring)** - `/etc/apt/keyrings/*.gpg` - Recommended for user keys
- **NEW (system keyring)** - `/usr/share/keyrings/*.gpg` - Package-managed keys
- **INLINE (embedded key)** - PGP keys embedded in .sources files

## Security Best Practices

1. Always verify GPG keys before adding them
2. Use explicit `Signed-By` references in .sources files
3. Prefer keys in `/etc/apt/keyrings/` over legacy locations
4. Regularly run `apt-man --check-keys` to identify issues
5. Keep keys updated with `apt-man --refresh-keys`
6. Remove unused sources and their keys
7. Check key expiration dates periodically

## Requirements

- Bash 4.0 or later
- Standard Linux utilities (grep, awk, sed)
- APT package manager
- GPG for key operations
- lsb_release for release detection

## Building Documentation

Build compressed man page:
```bash
make apt-man.1.gz
```

Build info page:
```bash
make apt-man.info
```

Test man page locally:
```bash
make test-man
```

Test info page locally:
```bash
make test-info
```

## Uninstallation

Remove all installed files:
```bash
sudo make uninstall
```

## Examples

### Example 1: Audit All Sources and Keys

```bash
# Run comprehensive security audit
apt-man lint

# List all sources with their keys
apt-man list --keys

# Check for any problems
apt-man keys --check

# Review key details
apt-man keys --info /etc/apt/keyrings/example.gpg
```

### Example 2: Temporarily Disable a PPA

```bash
# List sources to find ID
apt-man list

# Disable the PPA
apt-man disable 7

# Update APT
sudo apt update

# Later, re-enable it
apt-man enable 7
sudo apt update
```

### Example 3: Clean Up Before Removing a Source

```bash
# Show what's installed from the source
apt-man installed 4

# Remove all packages from that source
apt-man remove 4

# Disable the source
apt-man disable 4

# Remove the source file manually if needed
```

### Example 4: Fix Security Issues

```bash
# Run security audit
apt-man lint

# Option 1: Use interactive auto-fix (recommended)
sudo apt-man lint --fix

# Option 2: Fix issues manually
apt-man use-https 7                              # Fix HTTP sources
apt-man migrate 3                                # Migrate old format files
apt-man keys --move /etc/apt/trusted.gpg.d/old.gpg  # Move legacy keys
apt-man keys --renewal                           # Check for expiring keys

# Test the changes
sudo apt update

# Verify all fixed
apt-man lint
```

## License

GNU General Public License v3.0 or later

## Author

Written by Andrew

## Reporting Bugs

Report bugs to: https://github.com/yourusername/apt-man/issues

## See Also

- `apt(8)` - APT package manager
- `apt-get(8)` - APT package handling utility
- `sources.list(5)` - APT source list format
- `gpg(1)` - GNU Privacy Guard

