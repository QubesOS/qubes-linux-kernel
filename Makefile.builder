ifeq ($(PACKAGE_SET),dom0)
RPM_SPEC_FILES := kernel.spec
else ifeq ($(PACKAGE_SET),vm)
ifdef UPDATE_REPO
# Include kernel-devel packages in VM repo - dummy spec file
RPM_SPEC_FILES := kernel-devel.spec
endif
endif
