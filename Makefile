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

WG_BASE_URL := https://git.zx2c4.com/wireguard-linux-compat/snapshot
WG_SRC_FILE := wireguard-linux-compat-0.0.20200215.tar.xz

WG_SRC_URL := $(WG_BASE_URL)/$(WG_SRC_FILE)
WG_SIG_FILE := $(WG_SRC_FILE:%.xz=%.asc)
WG_SIG_URL := $(WG_BASE_URL)/$(WG_SIG_FILE)

SPI_BASE_URL := https://github.com/roadrunner2/macbook12-spi-driver/archive
SPI_REVISION := ddfbc7733542b8474a0e8f593aba91e06542be4f
SPI_SRC_URL := $(SPI_BASE_URL)/$(SPI_REVISION).tar.gz
SPI_SRC_FILE := macbook12-spi-driver-$(SPI_REVISION).tar.gz
SPI_HASH_SHA256 := 8039f103fbb351ecbbaddd540feeb7b0b1abfa216f0689a611e43d997426470e

URL := $(SRC_BASEURL)/$(SRC_FILE)
URL_SIGN := $(SRC_BASEURL)/$(SIGN_FILE)

ifeq ($(DOWNLOAD_FROM_GIT),1)
URL := https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/snapshot/linux-$(VERSION).tar.gz
endif

verrel:
	@echo $(NAME)-$(VERSION)-$(RELEASE)

get-sources: $(SRC_FILE) $(SIGN_FILE) $(WG_SRC_FILE) $(WG_SIG_FILE) $(SPI_SRC_FILE)

$(SRC_FILE):
	@wget -q -N $(URL)

$(SIGN_FILE):
	@wget -q -N $(URL_SIGN)

$(WG_SRC_FILE):
	@wget -q -N $(WG_SRC_URL)

$(WG_SIG_FILE):
	@wget -q -N $(WG_SIG_URL)

$(SPI_SRC_FILE):
	@wget -q -N -O $(SPI_SRC_FILE) $(SPI_SRC_URL)

import-keys:
	@if [ -n "$$GNUPGHOME" ]; then rm -f "$$GNUPGHOME/linux-kernel-trustedkeys.gpg"; fi
	@gpg --no-auto-check-trustdb --no-default-keyring --keyring linux-kernel-trustedkeys.gpg -q --import kernel*-key.asc
	@if [ -n "$$GNUPGHOME" ]; then rm -f "$$GNUPGHOME/wireguard-trustedkeys.gpg"; fi
	@gpg --no-auto-check-trustdb --no-default-keyring --keyring wireguard-trustedkeys.gpg -q --import wireguard*-key.asc

verify-sources: import-keys
	@xzcat $(WG_SRC_FILE) | gpgv --keyring wireguard-trustedkeys.gpg $(WG_SIG_FILE) - 2>/dev/null
ifeq ($(VERIFICATION),signature)
	@xzcat $(SRC_FILE) | gpgv --keyring linux-kernel-trustedkeys.gpg $(SIGN_FILE) - 2>/dev/null
else
	# there are no signatures for rc tarballs
	# verify locally based on a signed git tag and commit hash file
	sha512sum --quiet -c $(HASH_FILE)
endif
	@gunzip -c $(SPI_SRC_FILE) | sha256sum | head -c64 | grep -q "^$(SPI_HASH_SHA256)$$"

.PHONY: clean-sources
clean-sources:
ifneq ($(SRC_FILE), None)
	-rm $(SRC_FILE) $(SIGN_FILE)
endif
ifneq ($(WG_SRC_FILE), None)
	-rm $(WG_SRC_FILE) $(WG_SIG_FILE)
endif
ifneq ($(SPI_SRC_FILE), None)
	-rm $(SPI_SRC_FILE)
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
