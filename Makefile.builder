ifeq ($(PACKAGE_SET),dom0)
RPM_SPEC_FILES := kernel.spec
else ifeq ($(PACKAGE_SET),vm)

ifdef UPDATE_REPO
# If DIST_DOM0 defined, copy kernel-devel from there
ifneq ($(DIST_DOM0),)
# Include kernel-devel packages in VM repo - dummy spec file
RPM_SPEC_FILES := kernel-devel.spec
OUTPUT_DIR = pkgs/$(DIST_DOM0)
endif
endif

endif
