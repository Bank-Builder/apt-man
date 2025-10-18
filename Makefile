# Makefile for apt-man

PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
MANDIR = $(PREFIX)/share/man/man1
INFODIR = $(PREFIX)/share/info
COMPLETIONDIR = $(PREFIX)/share/bash-completion/completions

# Package information
PACKAGE_NAME = apt-man
VERSION = $(shell git describe --tags --always --dirty 2>/dev/null | sed 's/^v//' | sed 's/-dirty$$//' | sed 's/-/~/g' || echo "1.0")
ARCHITECTURE = all
MAINTAINER = Bank-Builder <bank-builder@example.com>
DESCRIPTION = APT Source and Key Manager
HOMEPAGE = https://github.com/Bank-Builder/apt-man

INSTALL = install
INSTALL_PROGRAM = $(INSTALL) -m 0755
INSTALL_DATA = $(INSTALL) -m 0644

.PHONY: all install install-bin install-man install-info install-completion uninstall clean help deb

all: apt-man.1.gz apt-man.info

help:
	@echo "apt-man Makefile targets:"
	@echo "  all                 Build compressed man and info pages"
	@echo "  install             Install script, documentation, and completion"
	@echo "  install-bin         Install script only"
	@echo "  install-man         Install man page only"
	@echo "  install-info        Install info page only"
	@echo "  install-completion  Install bash completion only"
	@echo "  uninstall           Remove installed files"
	@echo "  clean               Remove built files"
	@echo "  deb                 Create .deb package for Debian/Ubuntu"
	@echo "  test-man            View man page with 'man'"
	@echo "  test-info           View info page with 'info'"
	@echo ""
	@echo "Variables:"
	@echo "  PREFIX=$(PREFIX)"
	@echo "  BINDIR=$(BINDIR)"
	@echo "  MANDIR=$(MANDIR)"
	@echo "  INFODIR=$(INFODIR)"
	@echo "  COMPLETIONDIR=$(COMPLETIONDIR)"
	@echo "  VERSION=$(VERSION)"
	@echo "  ARCHITECTURE=$(ARCHITECTURE)"
	@echo ""
	@echo "Version Management:"
	@echo "  Current version: $(VERSION)"
	@echo "  To create a new version:"
	@echo "    git tag v1.1.0"
	@echo "    git push origin v1.1.0"
	@echo "    make deb"

# Build compressed man page
apt-man.1.gz: apt-man.1
	@rm -f apt-man.1.gz
	gzip -9 -n -c apt-man.1 > apt-man.1.gz

# Build info page
apt-man.info: apt-man.texi
	makeinfo apt-man.texi

# Install everything
install: install-bin install-man install-info install-completion

# Install script only
install-bin: apt-man.sh
	$(INSTALL) -d $(DESTDIR)$(BINDIR)
	$(INSTALL_PROGRAM) apt-man.sh $(DESTDIR)$(BINDIR)/apt-man

# Install man page only
install-man: apt-man.1.gz
	$(INSTALL) -d $(DESTDIR)$(MANDIR)
	$(INSTALL_DATA) apt-man.1.gz $(DESTDIR)$(MANDIR)/apt-man.1.gz

# Install info page only
install-info: apt-man.info
	$(INSTALL) -d $(DESTDIR)$(INFODIR)
	$(INSTALL_DATA) apt-man.info $(DESTDIR)$(INFODIR)/apt-man.info
	@if command -v install-info >/dev/null 2>&1; then \
		install-info --info-dir=$(DESTDIR)$(INFODIR) $(DESTDIR)$(INFODIR)/apt-man.info; \
		echo "Info page registered"; \
	else \
		echo "Warning: install-info not found, info page not registered"; \
	fi

# Install bash completion only
install-completion: apt-man-completion.bash
	$(INSTALL) -d $(DESTDIR)$(COMPLETIONDIR)
	$(INSTALL_DATA) apt-man-completion.bash $(DESTDIR)$(COMPLETIONDIR)/apt-man
	@echo "Bash completion installed"
	@echo "Reload your shell or run: source $(DESTDIR)$(COMPLETIONDIR)/apt-man"

# Uninstall everything
uninstall:
	rm -f $(DESTDIR)$(BINDIR)/apt-man
	rm -f $(DESTDIR)$(MANDIR)/apt-man.1.gz
	@if command -v install-info >/dev/null 2>&1; then \
		install-info --delete --info-dir=$(DESTDIR)$(INFODIR) $(DESTDIR)$(INFODIR)/apt-man.info 2>/dev/null || true; \
	fi
	rm -f $(DESTDIR)$(INFODIR)/apt-man.info
	rm -f $(DESTDIR)$(COMPLETIONDIR)/apt-man
	@echo "Uninstall complete"

# Clean built files
clean:
	rm -f apt-man.1.gz apt-man.info
	rm -f *.deb
	rm -rf debian/

# Test man page locally
test-man: apt-man.1
	man -l apt-man.1

# Test info page locally
test-info: apt-man.info
	info -f apt-man.info

# Create debian files
debian/copyright:
	@mkdir -p debian
	@echo "Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/" > debian/copyright
	@echo "Upstream-Name: apt-man" >> debian/copyright
	@echo "Upstream-Contact: Bank-Builder <bank-builder@example.com>" >> debian/copyright
	@echo "Source: https://github.com/Bank-Builder/apt-man" >> debian/copyright
	@echo "" >> debian/copyright
	@echo "Files: *" >> debian/copyright
	@echo "Copyright: 2025 Bank-Builder" >> debian/copyright
	@echo "License: GPL-3+" >> debian/copyright
	@echo "" >> debian/copyright
	@echo "Files: debian/*" >> debian/copyright
	@echo "Copyright: 2025 Bank-Builder" >> debian/copyright
	@echo "License: GPL-3+" >> debian/copyright
	@echo "" >> debian/copyright
	@echo "License: GPL-3+" >> debian/copyright
	@echo " This program is free software: you can redistribute it and/or modify" >> debian/copyright
	@echo " it under the terms of the GNU General Public License as published by" >> debian/copyright
	@echo " the Free Software Foundation, either version 3 of the License, or" >> debian/copyright
	@echo " (at your option) any later version." >> debian/copyright
	@echo " ." >> debian/copyright
	@echo " This program is distributed in the hope that it will be useful," >> debian/copyright
	@echo " but WITHOUT ANY WARRANTY; without even the implied warranty of" >> debian/copyright
	@echo " MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the" >> debian/copyright
	@echo " GNU General Public License for more details." >> debian/copyright
	@echo " ." >> debian/copyright
	@echo " You should have received a copy of the GNU General Public License" >> debian/copyright
	@echo " along with this program.  If not, see <https://www.gnu.org/licenses/>." >> debian/copyright
	@echo " ." >> debian/copyright
	@echo " On Debian systems, the complete text of the GNU General Public" >> debian/copyright
	@echo " License version 3 can be found in \"/usr/share/common-licenses/GPL-3\"." >> debian/copyright

debian/changelog:
	@mkdir -p debian
	@echo "apt-man (1.0.0~3~g2cb1f12) unstable; urgency=medium" > debian/changelog
	@echo "" >> debian/changelog
	@echo "  * Initial release" >> debian/changelog
	@echo "  * Comprehensive APT source and key management tool" >> debian/changelog
	@echo "  * Features include source management, key management, security auditing" >> debian/changelog
	@echo "  * Package operations: fix-deps, cache management, held packages" >> debian/changelog
	@echo "  * Duplicate source detection and removal" >> debian/changelog
	@echo "  * Interactive fixes for common issues" >> debian/changelog
	@echo "  * 22 comprehensive lint checks for security and health auditing" >> debian/changelog
	@echo "" >> debian/changelog
	@echo " -- Bank-Builder <bank-builder@example.com>  Sat, 18 Oct 2025 16:30:00 +0000" >> debian/changelog

# Create .deb package
deb: apt-man.1.gz debian/copyright debian/changelog
	@echo "Creating .deb package..."
	@mkdir -p debian/DEBIAN
	@mkdir -p debian/usr/bin
	@mkdir -p debian/usr/share/man/man1
	@mkdir -p debian/usr/share/bash-completion/completions
	@mkdir -p debian/usr/share/doc/apt-man
	
	# Copy files to package structure
	cp apt-man.sh debian/usr/bin/apt-man
	chmod 755 debian/usr/bin/apt-man
	cp apt-man.1.gz debian/usr/share/man/man1/
	cp apt-man-completion.bash debian/usr/share/bash-completion/completions/apt-man
	cp README.md debian/usr/share/doc/apt-man/
	cp LICENCE debian/usr/share/doc/apt-man/
	cp debian/copyright debian/usr/share/doc/apt-man/copyright
	gzip -9 -c debian/changelog > debian/usr/share/doc/apt-man/changelog.gz
	
	# Fix file permissions
	chmod 644 debian/usr/share/doc/apt-man/*
	chmod 644 debian/usr/share/man/man1/apt-man.1.gz
	chmod 644 debian/usr/share/bash-completion/completions/apt-man
	
	# Fix directory permissions
	find debian/usr -type d -exec chmod 755 {} \;
	
	# Create control file
	@echo "Package: $(PACKAGE_NAME)" > debian/DEBIAN/control
	@echo "Version: $(VERSION)" >> debian/DEBIAN/control
	@echo "Section: admin" >> debian/DEBIAN/control
	@echo "Priority: optional" >> debian/DEBIAN/control
	@echo "Architecture: $(ARCHITECTURE)" >> debian/DEBIAN/control
	@echo "Maintainer: $(MAINTAINER)" >> debian/DEBIAN/control
	@echo "Description: $(DESCRIPTION)" >> debian/DEBIAN/control
	@echo " A comprehensive command-line tool for managing APT package sources," >> debian/DEBIAN/control
	@echo " PPAs, and GPG keys on Ubuntu and Debian-based systems." >> debian/DEBIAN/control
	@echo " Features include:" >> debian/DEBIAN/control
	@echo "  - Source management (list, enable, disable, upgrade)" >> debian/DEBIAN/control
	@echo "  - Key management (list, check, refresh, move)" >> debian/DEBIAN/control
	@echo "  - Security auditing (22 comprehensive checks)" >> debian/DEBIAN/control
	@echo "  - Package operations (fix-deps, cache management, held packages)" >> debian/DEBIAN/control
	@echo "  - Duplicate source detection and removal" >> debian/DEBIAN/control
	@echo "  - Interactive fixes for common issues" >> debian/DEBIAN/control
	
	# Create postinst script
	@echo "#!/bin/bash" > debian/DEBIAN/postinst
	@echo "set -e" >> debian/DEBIAN/postinst
	@echo "echo 'apt-man installed successfully!'" >> debian/DEBIAN/postinst
	@echo "echo 'Run: source /usr/share/bash-completion/completions/apt-man'" >> debian/DEBIAN/postinst
	@echo "echo 'to enable bash completion in your current shell.'" >> debian/DEBIAN/postinst
	chmod 755 debian/DEBIAN/postinst
	
	# Create prerm script
	@echo "#!/bin/bash" > debian/DEBIAN/prerm
	@echo "set -e" >> debian/DEBIAN/prerm
	@echo "# Package removal completed successfully" >> debian/DEBIAN/prerm
	@echo "exit 0" >> debian/DEBIAN/prerm
	chmod 755 debian/DEBIAN/prerm
	
	# Remove debian directory files from root to avoid file-in-unusual-dir warnings
	rm -f debian/changelog debian/copyright
	
	# Build the package with proper ownership
	dpkg-deb --build --root-owner-group debian $(PACKAGE_NAME)_$(VERSION)_$(ARCHITECTURE).deb
	
	# Clean up
	rm -rf debian/
	
	@echo "Package created: $(PACKAGE_NAME)_$(VERSION)_$(ARCHITECTURE).deb"
	@echo "Install with: sudo dpkg -i $(PACKAGE_NAME)_$(VERSION)_$(ARCHITECTURE).deb"

