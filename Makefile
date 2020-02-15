NAME := kernel
SPECFILE := kernel.spec

WORKDIR := $(shell pwd)

ifndef NAME
$(error "You can not run this Makefile without having NAME defined")
endif
ifndef VERSION
VERSION := $(shell cat version)
endif
ifndef RELEASE
RELEASE := $(shell cat rel)
endif

all: help

MIRROR := cdn.kernel.org
ifeq (,$(DISTFILES_MIRROR))
SRC_BASEURL := https://${MIRROR}/pub/linux/kernel/v$(shell echo $(VERSION) | sed 's/^\(2\.[0-9]*\).*/\1/;s/^3\..*/3.x/;s/^4\..*/4.x/')
else
SRC_BASEURL := $(DISTFILES_MIRROR)
endif

SRC_FILE := linux-${VERSION}.tar.xz
ifeq ($(BUILD_FLAVOR),pvops)
SIGN_FILE := linux-${VERSION}.tar.sign
else
SIGN_FILE := linux-${VERSION}.tar.bz2.sign
endif
HASH_FILE :=${SRC_FILE}.sha1sum

URL := $(SRC_BASEURL)/$(SRC_FILE)
URL_SIGN := $(SRC_BASEURL)/$(SIGN_FILE)

get-sources: $(SRC_FILE) $(SIGN_FILE)

$(SRC_FILE):
	@wget -q -N $(URL)

$(SIGN_FILE):
	@wget -q -N $(URL_SIGN)

import-keys:
	@if [ -n "$$GNUPGHOME" ]; then rm -f "$$GNUPGHOME/linux-kernel-trustedkeys.gpg"; fi
	@gpg --no-auto-check-trustdb --no-default-keyring --keyring linux-kernel-trustedkeys.gpg -q --import *-key.asc

verify-sources: import-keys
ifeq ($(BUILD_FLAVOR),pvops)
	@xzcat $(SRC_FILE) | gpgv --keyring linux-kernel-trustedkeys.gpg $(SIGN_FILE) - 2>/dev/null
else
#	@gpg --verify $(SIGN_FILE) $(SRC_FILE)
#	The key has been compromised
#	and kernel.org decided not to release signature
#	with a new key... oh, well...
	sha1sum --quiet -c ${HASH_FILE}
endif

.PHONY: clean-sources
clean-sources:
ifneq ($(SRC_FILE), None)
	-rm $(SRC_FILE)
endif

verrel:
	@echo $(NAME)-$(VERSION)-$(RELEASE)

help:
	@echo "Usage: make <target>"
	@echo
	@echo "get-sources      Download kernel sources from kernel.org"
	@echo "verify-sources"
	@echo
	@echo "verrel"          Echo version release"	
