ifeq ($(PACKAGE_SET),dom0)
RPM_SPEC_FILES := kernel.spec
NO_ARCHIVE := 1

INCLUDED_SOURCES = dummy-psu dummy-backlight linux-utils v4l2loopback
SOURCE_COPY_IN := $(INCLUDED_SOURCES)

$(INCLUDED_SOURCES): SRC_SUBDIR=$@
$(INCLUDED_SOURCES): VERSION=$(shell git -C $(ORIG_SRC)/$(SRC_SUBDIR) rev-parse --short HEAD)
$(INCLUDED_SOURCES):
	$(BUILDER_DIR)/scripts/create-archive $(CHROOT_DIR)/$(DIST_SRC)/$(SRC_SUBDIR) $(SRC_SUBDIR)-$(VERSION).tar.gz $(SRC_SUBDIR)/
	mv $(CHROOT_DIR)/$(DIST_SRC)/$(SRC_SUBDIR)/$(SRC_SUBDIR)-$(VERSION).tar.gz $(CHROOT_DIR)/$(DIST_SRC)
	sed -i "s#@$(SRC_SUBDIR)@#$(SRC_SUBDIR)-$(VERSION).tar.gz#" $(CHROOT_DIR)/$(DIST_SRC)/kernel.spec.in
endif
