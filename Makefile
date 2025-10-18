# Makefile for apt-man

PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
MANDIR = $(PREFIX)/share/man/man1
INFODIR = $(PREFIX)/share/info
COMPLETIONDIR = $(PREFIX)/share/bash-completion/completions

INSTALL = install
INSTALL_PROGRAM = $(INSTALL) -m 0755
INSTALL_DATA = $(INSTALL) -m 0644

.PHONY: all install install-bin install-man install-info install-completion uninstall clean help

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
	@echo "  test-man            View man page with 'man'"
	@echo "  test-info           View info page with 'info'"
	@echo ""
	@echo "Variables:"
	@echo "  PREFIX=$(PREFIX)"
	@echo "  BINDIR=$(BINDIR)"
	@echo "  MANDIR=$(MANDIR)"
	@echo "  INFODIR=$(INFODIR)"
	@echo "  COMPLETIONDIR=$(COMPLETIONDIR)"

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

# Test man page locally
test-man: apt-man.1
	man -l apt-man.1

# Test info page locally
test-info: apt-man.info
	info -f apt-man.info

