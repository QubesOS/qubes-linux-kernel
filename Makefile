NAME := kernel
SPECFILE := kernel.spec

WORKDIR := $(shell pwd)
BRANCH ?= master

ifndef NAME
$(error "You can not run this Makefile without having NAME defined")
endif
ifndef VERSION
VERSION := $(file <version)
endif
ifndef RELEASE
RELEASE := $(file <rel)
endif

ifneq ($(VERSION),$(subst -rc,,$(VERSION)))
DOWNLOAD_FROM_GIT=1
VERIFICATION := hash
else
VERIFICATION := signature
endif

all: help

UNTRUSTED_SUFF := .UNTRUSTED

MIRROR := cdn.kernel.org
ifeq (,$(DISTFILES_MIRROR))
SRC_BASEURL := https://${MIRROR}/pub/linux/kernel/v$(shell echo $(VERSION) | sed 's/^\(2\.[0-9]*\).*/\1/;s/^3\..*/3.x/;s/^4\..*/4.x/;s/^5\..*/5.x/')
else
SRC_BASEURL := $(DISTFILES_MIRROR)
endif

ifeq ($(VERIFICATION),signature)
SRC_FILE := linux-${VERSION}.tar.xz
SIGN_FILE := linux-${VERSION}.tar.sign
else
SRC_FILE := linux-${VERSION}.tar.gz
HASH_FILE := $(SRC_FILE).sha512
endif
SRC_TARFILE := linux-${VERSION}.tar

WG_BASE_URL := https://git.zx2c4.com/wireguard-linux-compat/snapshot/
WG_SRC_FILE := wireguard-linux-compat-1.0.20201112.tar.xz

WG_SRC_URL := $(WG_BASE_URL)/$(WG_SRC_FILE)
WG_SIG_FILE := $(WG_SRC_FILE:%.xz=%.asc)
WG_SRC_TARFILE := $(WG_SRC_FILE:%.xz=%)
WG_SIG_URL := $(WG_BASE_URL)/$(WG_SIG_FILE)

URL := $(SRC_BASEURL)/$(SRC_FILE)
URL_SIGN := $(SRC_BASEURL)/$(SIGN_FILE)

ifeq ($(DOWNLOAD_FROM_GIT),1)
URL := https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/snapshot/linux-$(VERSION).tar.gz
endif

get-sources: $(SRC_TARFILE) $(WG_SRC_TARFILE)
	git submodule update --init --recursive

verrel:
	@echo $(NAME)-$(VERSION)-$(RELEASE)

ifeq ($(FETCH_CMD),)
$(error "You can not run this Makefile without having FETCH_CMD defined")
endif

.INTERMEDIATE: linux-keyring.gpg
linux-keyring.gpg: $(sort $(wildcard kernel.org-*.asc))
	cat $^ | gpg --dearmor >$@

.INTERMEDIATE: wireguard-keyring.gpg
wireguard-keyring.gpg: $(sort $(wildcard wireguard-*.asc))
	cat $^ | gpg --dearmor >$@

$(WG_SRC_FILE)$(UNTRUSTED_SUFF):
	@$(FETCH_CMD) $@ -- $(WG_SRC_URL)

.SECONDARY: $(WG_SIG_FILE)
$(WG_SIG_FILE):
	@$(FETCH_CMD) $@ -- $(WG_SIG_URL)

.INTERMEDIATE: $(SRC_TARFILE)$(UNTRUSTED_SUFF) $(WG_SRC_TARFILE)$(UNTRUSTED_SUFF)
%.tar$(UNTRUSTED_SUFF): %.tar.xz$(UNTRUSTED_SUFF)
	if [ -f /usr/bin/qvm-run-vm ]; \
        then qvm-run-vm --dispvm 2>/dev/null xzcat <$< > $@; \
	else xzcat <$< > $@; fi

%.tar$(UNTRUSTED_SUFF): %.tar.gz$(UNTRUSTED_SUFF)
	if [ -f /usr/bin/qvm-run-vm ]; \
        then qvm-run-vm --dispvm 2>/dev/null zcat <$< > $@; \
	else zcat <$< > $@; fi

$(SRC_TARFILE): $(SRC_TARFILE)$(UNTRUSTED_SUFF) $(SIGN_FILE) linux-keyring.gpg
	gpgv --keyring ./$(word 3,$^) $(word 2,$^) $(word 1,$^) || \
	  { echo "Wrong signature on $@$(UNTRUSTED_SUFF)!"; exit 1; }
	mv $@$(UNTRUSTED_SUFF) $@

$(WG_SRC_TARFILE): $(WG_SRC_TARFILE)$(UNTRUSTED_SUFF) $(WG_SIG_FILE) wireguard-keyring.gpg
	gpgv --keyring ./$(word 3,$^) $(word 2,$^) $(word 1,$^) || \
	  { echo "Wrong signature on $@$(UNTRUSTED_SUFF)!"; exit 1; }
	mv $@$(UNTRUSTED_SUFF) $@

$(SRC_FILE)$(UNTRUSTED_SUFF):
	@$(FETCH_CMD) $@ -- $(URL)

.SECONDARY: $(SIGN_FILE)
$(SIGN_FILE):
	@$(FETCH_CMD) $(SIGN_FILE) -- $(URL_SIGN)

verify-sources:
	@true

.PHONY: clean-sources
clean-sources:
ifneq ($(SRC_FILE), None)
	-rm $(SRC_FILE)$(UNTRUSTED_SUFF) $(SRC_TARFILE) $(SIGN_FILE)
endif
ifneq ($(WG_SRC_FILE), None)
	-rm $(WG_SRC_FILE)$(UNTRUSTED_SUFF) $(WG_SRC_TARFILE) $(WG_SIG_FILE)
endif

.PHONY: update-sources
update-sources:
	@$(WORKDIR)/update-sources $(BRANCH)

help:
	@echo "Usage: make <target>"
	@echo
	@echo "get-sources      Download kernel sources from kernel.org"
	@echo "verify-sources"
	@echo
	@echo "verrel"          Echo version release"
