NAME := kernel
SPECFILE := kernel.spec


WORKDIR := $(shell pwd)
SPECDIR ?= $(WORKDIR)
SRCRPMDIR ?= $(WORKDIR)/srpm
BUILDDIR ?= $(WORKDIR)
RPMDIR ?= $(WORKDIR)/rpm
SOURCEDIR := $(WORKDIR)

NO_OF_CPUS := $(shell grep -c ^processor /proc/cpuinfo)

BUILD_FLAVOR := pvops

RPM_DEFINES := --define "_sourcedir $(SOURCEDIR)" \
		--define "_specdir $(SPECDIR)" \
		--define "_builddir $(BUILDDIR)" \
		--define "_srcrpmdir $(SRCRPMDIR)" \
		--define "_rpmdir $(RPMDIR)" \
		--define "build_flavor $(BUILD_FLAVOR)" \
		--define "jobs $(NO_OF_CPUS)"

VER_REL := $(shell rpm $(RPM_DEFINES) -q --qf "%{VERSION} %{RELEASE}\n" --specfile $(SPECFILE)| head -1)

ifndef NAME
$(error "You can not run this Makefile without having NAME defined")
endif
ifndef VERSION
VERSION := $(word 1, $(VER_REL))
endif
ifndef RELEASE
RELEASE := $(word 2, $(VER_REL))
endif

all: help

MIRROR := ftp.kernel.org
SRC_BASEURL := http://${MIRROR}/pub/linux/kernel/v$(shell echo $(VERSION) | sed 's/^\(2\.[0-9]*\).*/\1/;s/^3\..*/3.x/')
SRC_FILE := linux-${VERSION}.tar.bz2
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
	 gpg -q --import *-key.asc

verify-sources: import-keys
ifeq ($(BUILD_FLAVOR),pvops)
	@bzcat $(SRC_FILE) | gpg -q --verify $(SIGN_FILE) - 2>/dev/null
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


#RPM := rpmbuild --buildroot=/dev/shm/buildroot/
RPM := rpmbuild 

RPM_WITH_DIRS = $(RPM) $(RPM_DEFINES)

rpms: rpms-dom0

rpms-vm:

rpms-dom0: get-sources $(SPECFILE)
	$(RPM_WITH_DIRS) -bb $(SPECFILE)
	rpm --addsign $(RPMDIR)/x86_64/*$(VERSION)-$(RELEASE)*.rpm

rpms-nobuild:
	$(RPM_WITH_DIRS) --nobuild -bb $(SPECFILE)

rpms-just-build: 
	$(RPM_WITH_DIRS) --short-circuit -bc $(SPECFILE)

rpms-install: 
	$(RPM_WITH_DIRS) -bi $(SPECFILE)

prep: get-sources $(SPECFILE)
	$(RPM_WITH_DIRS) -bp $(SPECFILE)

srpm: get-sources $(SPECFILE)
	$(RPM_WITH_DIRS) -bs $(SPECFILE)

verrel:
	@echo $(NAME)-$(VERSION)-$(RELEASE)


update-repo-current:
	ln -f rpm/x86_64/kernel-$(VERSION)-$(RELEASE)*.rpm ../yum/current-release/current/dom0/rpm/
	ln -f rpm/x86_64/kernel-debuginfo-$(VERSION)-$(RELEASE)*.rpm ../yum/current-release/current/dom0/rpm/
	ln -f rpm/x86_64/kernel-devel-$(VERSION)-$(RELEASE)*.rpm ../yum/current-release/current/dom0/rpm/
	for vmrepo in ../yum/current-release/current/vm/* ; do \
		ln -f rpm/x86_64/kernel-devel-$(VERSION)-$(RELEASE)*.rpm $$vmrepo/rpm/ ;\
	done
	ln -f rpm/x86_64/kernel-qubes-vm-$(VERSION)-$(RELEASE)*.rpm ../yum/current-release/current/dom0/rpm/


update-repo-current-testing:
	ln -f rpm/x86_64/kernel-$(VERSION)-$(RELEASE)*.rpm ../yum/current-release/current-testing/dom0/rpm/
	ln -f rpm/x86_64/kernel-debuginfo-$(VERSION)-$(RELEASE)*.rpm ../yum/current-release/current-testing/dom0/rpm/
	ln -f rpm/x86_64/kernel-devel-$(VERSION)-$(RELEASE)*.rpm ../yum/current-release/current-testing/dom0/rpm/
	for vmrepo in ../yum/current-release/current-testing/vm/* ; do \
		ln -f rpm/x86_64/kernel-devel-$(VERSION)-$(RELEASE)*.rpm $$vmrepo/rpm/ ;\
	done
	ln -f rpm/x86_64/kernel-qubes-vm-$(VERSION)-$(RELEASE)*.rpm ../yum/current-release/current-testing/dom0/rpm/

update-repo-unstable:
	ln -f rpm/x86_64/kernel-$(VERSION)-$(RELEASE)*.rpm ../yum/current-release/unstable/dom0/rpm/
	ln -f rpm/x86_64/kernel-debuginfo-$(VERSION)-$(RELEASE)*.rpm ../yum/current-release/unstable/dom0/rpm/
	ln -f rpm/x86_64/kernel-devel-$(VERSION)-$(RELEASE)*.rpm ../yum/current-release/unstable/dom0/rpm/
	for vmrepo in ../yum/current-release/unstable/vm/* ; do \
		ln -f rpm/x86_64/kernel-devel-$(VERSION)-$(RELEASE)*.rpm $$vmrepo/rpm/ ;\
	done
	ln -f rpm/x86_64/kernel-qubes-vm-$(VERSION)-$(RELEASE)*.rpm ../yum/current-release/unstable/dom0/rpm/

update-repo-installer: update-repo-installer-kernel-dom0 update-repo-installer-kernel-vm

update-repo-installer-kernel-dom0:
	ln -f rpm/x86_64/kernel-$(VERSION)-$(RELEASE)*.rpm ../installer/yum/qubes-dom0/rpm/

update-repo-installer-kernel-vm:
	ln -f rpm/x86_64/kernel-qubes-vm-$(VERSION)-$(RELEASE)*.rpm ../installer/yum/qubes-dom0/rpm/

# mop up, printing out exactly what was mopped.

.PHONY : clean
clean ::
	@echo "Running the %clean script of the rpmbuild..."
	$(RPM_WITH_DIRS) --clean --nodeps $(SPECFILE)

help:
	@echo "Usage: make <target>"
	@echo
	@echo "get-sources      Download kernel sources from kernel.org"
	@echo "verify-sources"
	@echo
	@echo "prep             Just do the prep"	
	@echo "rpms             Build rpms"
	@echo "rpms-nobuild     Skip the build stage (for testing)"
	@echo "rpms-just-build  Skip packaging (just test compilation)"
	@echo "srpm             Create an srpm"
	@echo
	@echo "make update-repo-current  -- copy newly generated rpms to qubes yum repo"
	@echo "make update-repo-current-testing  -- same, but to -current-testing"
	@echo "make update-repo-unstable -- same, but to -unstable repo"
