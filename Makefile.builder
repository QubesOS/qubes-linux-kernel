ifeq ($(PACKAGE_SET),dom0)
RPM_SPEC_FILES := kernel.spec
NO_ARCHIVE := 1

INCLUDED_SOURCES = dummy-psu dummy-backlight linux-utils
SOURCE_COPY_IN := $(INCLUDED_SOURCES)

$(INCLUDED_SOURCES): PACKAGE=$@
$(INCLUDED_SOURCES): VERSION=$(shell git -C $(ORIG_SRC)/$(PACKAGE) rev-parse --short HEAD)
$(INCLUDED_SOURCES):
	$(BUILDER_DIR)/scripts/create-archive $(CHROOT_DIR)/$(DIST_SRC)/$(PACKAGE) $(PACKAGE)-$(VERSION).tar.gz $(PACKAGE)/
	mv $(CHROOT_DIR)/$(DIST_SRC)/$(PACKAGE)/$(PACKAGE)-$(VERSION).tar.gz $(CHROOT_DIR)/$(DIST_SRC)
	sed -i "s#@$(PACKAGE)@#$(PACKAGE)-$(VERSION).tar.gz#" $(CHROOT_DIR)/$(DIST_SRC)/kernel.spec.in
endif
