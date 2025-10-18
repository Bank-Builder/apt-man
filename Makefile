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
	gzip -9 -c apt-man.1 > apt-man.1.gz

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

# Create .deb package
deb: apt-man.1.gz apt-man.info
	@echo "Creating .deb package..."
	@mkdir -p debian/DEBIAN
	@mkdir -p debian/usr/bin
	@mkdir -p debian/usr/share/man/man1
	@mkdir -p debian/usr/share/info
	@mkdir -p debian/usr/share/bash-completion/completions
	@mkdir -p debian/usr/share/doc/apt-man
	
	# Copy files to package structure
	cp apt-man.sh debian/usr/bin/apt-man
	chmod 755 debian/usr/bin/apt-man
	cp apt-man.1.gz debian/usr/share/man/man1/
	cp apt-man.info debian/usr/share/info/
	cp apt-man-completion.bash debian/usr/share/bash-completion/completions/apt-man
	cp README.md debian/usr/share/doc/apt-man/
	cp LICENSE debian/usr/share/doc/apt-man/
	
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
	@echo " Homepage: $(HOMEPAGE)" >> debian/DEBIAN/control
	
	# Create postinst script
	@echo "#!/bin/bash" > debian/DEBIAN/postinst
	@echo "set -e" >> debian/DEBIAN/postinst
	@echo "if command -v install-info >/dev/null 2>&1; then" >> debian/DEBIAN/postinst
	@echo "    install-info --info-dir=/usr/share/info /usr/share/info/apt-man.info 2>/dev/null || true" >> debian/DEBIAN/postinst
	@echo "fi" >> debian/DEBIAN/postinst
	@echo "echo 'apt-man installed successfully!'" >> debian/DEBIAN/postinst
	@echo "echo 'Run: source /usr/share/bash-completion/completions/apt-man'" >> debian/DEBIAN/postinst
	@echo "echo 'to enable bash completion in your current shell.'" >> debian/DEBIAN/postinst
	chmod 755 debian/DEBIAN/postinst
	
	# Create prerm script
	@echo "#!/bin/bash" > debian/DEBIAN/prerm
	@echo "set -e" >> debian/DEBIAN/prerm
	@echo "if command -v install-info >/dev/null 2>&1; then" >> debian/DEBIAN/prerm
	@echo "    install-info --delete --info-dir=/usr/share/info /usr/share/info/apt-man.info 2>/dev/null || true" >> debian/DEBIAN/prerm
	@echo "fi" >> debian/DEBIAN/prerm
	chmod 755 debian/DEBIAN/prerm
	
	# Build the package
	dpkg-deb --build debian $(PACKAGE_NAME)_$(VERSION)_$(ARCHITECTURE).deb
	
	# Clean up
	rm -rf debian/
	
	@echo "Package created: $(PACKAGE_NAME)_$(VERSION)_$(ARCHITECTURE).deb"
	@echo "Install with: sudo dpkg -i $(PACKAGE_NAME)_$(VERSION)_$(ARCHITECTURE).deb"

