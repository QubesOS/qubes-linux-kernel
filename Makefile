NAME := kernel
SPECFILE := kernel.spec

WORKDIR := $(shell pwd)
BRANCH ?= master

ifndef NAME
$(error "You can not run this Makefile without having NAME defined")
endif
ifndef VERSION
VERSION := $(shell cat version)
endif
ifndef RELEASE
RELEASE := $(shell cat rel)
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
SRC_BASEURL := https://${MIRROR}/pub/linux/kernel/v$(shell echo $(VERSION) | sed 's/^\(2\.[0-9]*\).*/\1/;s/^3\..*/3.x/;s/^4\..*/4.x/')
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

URL := $(SRC_BASEURL)/$(SRC_FILE)
URL_SIGN := $(SRC_BASEURL)/$(SIGN_FILE)

get-sources: $(SRC_TARFILE)

verrel:
	@echo $(NAME)-$(VERSION)-$(RELEASE)

ifeq ($(FETCH_CMD),)
$(error "You can not run this Makefile without having FETCH_CMD defined")
endif

.INTERMEDIATE: linux-keyring.gpg
linux-keyring.gpg: $(sort $(wildcard kernel.org-*.asc))
	cat $^ | gpg --dearmor >$@

.INTERMEDIATE: $(SRC_TARFILE)$(UNTRUSTED_SUFF)
%.tar$(UNTRUSTED_SUFF): %.tar.xz$(UNTRUSTED_SUFF)
	if [ -f /usr/bin/qvm-run-vm ]; \
        then qvm-run-vm --dispvm 2>/dev/null xzcat <$< > $@; \
	else xzcat <$< > $@; fi

%.tar$(UNTRUSTED_SUFF): %.tar.gz$(UNTRUSTED_SUFF)
	if [ -f /usr/bin/qvm-run-vm ]; \
        then qvm-run-vm --dispvm 2>/dev/null zcat <$< > $@; \
	else zcat <$< > $@; fi

ifeq ($(VERIFICATION),signature)
# signature based
$(SRC_TARFILE): $(SRC_TARFILE)$(UNTRUSTED_SUFF) $(SIGN_FILE) linux-keyring.gpg
	gpgv --keyring ./$(word 3,$^) $(word 2,$^) $(word 1,$^) || \
	  { echo "Wrong signature on $@$(UNTRUSTED_SUFF)!"; exit 1; }
	mv $@$(UNTRUSTED_SUFF) $@
else
# hash based
$(SRC_TARFILE): $(SRC_FILE)$(UNTRUSTED_SUFF) $(HASH_FILE)
	# there are no signatures for rc tarballs
	# verify locally based on a signed git tag and commit hash file
	sha512sum --quiet -c $(HASH_FILE)
	zcat <$< >$@
	rm -f $<
endif

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
