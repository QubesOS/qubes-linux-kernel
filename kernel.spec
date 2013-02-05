# A spec file for building xenlinux Dom0 kernel for Qubes
# Based on the Open SUSE kernel-spec & Fedora kernel-spec.
#

#%define _unpackaged_files_terminate_build 0
%define variant %{build_flavor}.qubes
%define plainrel %(cat rel-%{build_flavor})
%define rel %{plainrel}.%{variant}
%define version %(cat version-%{build_flavor})

%define _buildshell /bin/bash
%define build_xen	1

%global cpu_arch x86_64
%define cpu_arch_flavor %cpu_arch/%build_flavor

%define kernelrelease %(echo %{version} | sed 's/3\\.[0-9]\\+$/\\0.0/')-%rel.%cpu_arch
%define my_builddir %_builddir/%{name}-%{version}

%define build_src_dir %my_builddir/linux-%version
%define src_install_dir /usr/src/kernels/%kernelrelease
%define kernel_build_dir %my_builddir/linux-obj
%define vm_install_dir /var/lib/qubes/vm-kernels/%version-%{plainrel}

%(chmod +x %_sourcedir/{guards,apply-patches,check-for-config-changes})

%define install_vdso 1

Name:           kernel
Summary:        The Xen Kernel
Version:        %{version}
Epoch:          1000
Release:        %{rel}
License:        GPL v2 only
Group:          System/Kernel
Url:            http://www.kernel.org/
AutoReqProv:    on
BuildRequires:  coreutils module-init-tools sparse
BuildRequires:  qubes-core-libs-devel
Provides:       multiversion(kernel)
Provides:       %name = %version-%kernelrelease

Provides:       kernel-xen-dom0
Provides:       kernel-qubes-dom0
Provides:       kernel-qubes-dom0-%{build_flavor}
Provides:       kernel-drm = 4.3.0
Provides:       kernel-drm-nouveau = 16
Provides:       kernel-modules-extra = %kernelrelease
Provides:       kernel-modeset = 1

Requires:       xen >= 3.4.3
Requires(post): /sbin/new-kernel-pkg
Requires(preun):/sbin/new-kernel-pkg

Requires(pre):  coreutils gawk
Requires(post): dracut binutils

Conflicts:      sysfsutils < 2.0
# root-lvm only works with newer udevs
Conflicts:      udev < 118
Conflicts:      lvm2 < 2.02.33
Provides:       kernel = %kernelrelease
Provides:       kernel-uname-r = %kernelrelease

Source0:        linux-%version.tar.bz2
Source14:       series-%{build_flavor}.conf
Source16:       guards
Source17:       apply-patches
Source33:       check-for-config-changes
Source100:      config-%{build_flavor}
# FIXME: Including dirs this way does NOT produce proper src.rpms
Source200:      patches.arch
Source201:      patches.drivers
Source202:      patches.fixes
Source203:      patches.rpmify
Source204:      patches.suse
Source205:      patches.xen
Source207:      patches.kernel.org
Source300:      patches.qubes
Source301:      u2mfn
Source302:      vm-initramfs-pre-udev
BuildRoot:      %{_tmppath}/%{name}-%{version}-build
ExclusiveArch:  x86_64

%description
Qubes Dom0 kernel.

%prep
if ! [ -e %_sourcedir/linux-%version.tar.bz2 ]; then
    echo "The %name-%version.nosrc.rpm package does not contain the" \
	 "complete sources. Please install kernel-source-%version.src.rpm."
    exit 1
fi

SYMBOLS="xen-dom0 %{build_flavor}"

# Unpack all sources and patches
%setup -q -c -T -a 0

mkdir -p %kernel_build_dir

cd linux-%version

if [ -r %_sourcedir/series-%{version}-%{build_flavor}.conf ]; then
    %_sourcedir/apply-patches %_sourcedir/series-%{version}-%{build_flavor}.conf %_sourcedir $SYMBOLS
else
    %_sourcedir/apply-patches %_sourcedir/series-%{build_flavor}.conf %_sourcedir $SYMBOLS
fi

cd %kernel_build_dir

if [ -f %_sourcedir/config-%{version}-%{build_flavor} ]; then
    cp %_sourcedir/config-%{version}-%{build_flavor} .config
else
    cp %_sourcedir/config-%{build_flavor} .config
fi

%build_src_dir/scripts/config \
	--set-str CONFIG_LOCALVERSION -%release.%cpu_arch \
	--disable CONFIG_DEBUG_INFO
#	--enable  CONFIG_DEBUG_INFO
# Enabling CONFIG_DEBUG_INFO produces *huge* packages!

MAKE_ARGS="$MAKE_ARGS -C %build_src_dir O=$PWD"
if test -e %_sourcedir/TOLERATE-UNKNOWN-NEW-CONFIG-OPTIONS; then
    yes '' | make oldconfig $MAKE_ARGS
else
    cp .config .config.orig
    make silentoldconfig $MAKE_ARGS < /dev/null
    %_sourcedir/check-for-config-changes .config.orig .config
    rm .config.orig
fi

make prepare $MAKE_ARGS
make scripts $MAKE_ARGS
make scripts_basic $MAKE_ARGS
krel=$(make -s kernelrelease $MAKE_ARGS)

if [ "$krel" != "%kernelrelease" ]; then
    echo "Kernel release mismatch: $krel != %kernelrelease" >&2
    exit 1
fi

make clean $MAKE_ARGS

rm -f source
find . ! -type d -printf '%%P\n' > %my_builddir/obj-files

%build

cd %kernel_build_dir

# If the %jobs macro is defined to a number, make will spawn that many jobs.
# There are several ways how to define it:
# With plain rpmbuild:
#     rpmbuild -ba --define 'jobs N' kernel-$flavor.spec
# To spawn as many jobs as there are cpu cores:
#     rpmbuild -ba --define "jobs 0$(grep -c ^processor /proc/cpuinfo)" \
#         kernel-$flavor.spec
make %{?jobs:-j%jobs} all $MAKE_ARGS CONFIG_DEBUG_SECTION_MISMATCH=y

# Build u2mfn module
make -C %kernel_build_dir SUBDIRS=%_builddir/u2mfn modules

%install

# get rid of /usr/lib/rpm/brp-strip-debug
# strip removes too much from the vmlinux ELF binary
export NO_BRP_STRIP_DEBUG=true
export STRIP_KEEP_SYMTAB='*/vmlinux-*'

# /lib/modules/%kernelrelease-%build_flavor/build will be a stale symlink until the
# kernel-devel package is installed. Don't check for stale symlinks
# in the brp-symlink check:
export NO_BRP_STALE_LINK_ERROR=yes

cd %kernel_build_dir

mkdir -p %buildroot/boot
cp -p System.map %buildroot/boot/System.map-%kernelrelease
if [ "%{build_flavor}" == "xenlinux" ]; then
    cp -p arch/x86/boot/vmlinuz %buildroot/boot/vmlinuz-%kernelrelease
else
    cp -p arch/x86/boot/bzImage %buildroot/boot/vmlinuz-%kernelrelease
fi
cp .config %buildroot/boot/config-%kernelrelease

%if %install_vdso
# Install the unstripped vdso's that are linked in the kernel image
make vdso_install $MAKE_ARGS INSTALL_MOD_PATH=%buildroot
%endif

# Create a dummy initramfs with roughly the size the real one will have.
# That way, rpm will know that this package requires some additional
# space in /boot.
dd if=/dev/zero of=%buildroot/boot/initramfs-%kernelrelease.img \
	bs=1M count=20

gzip -c9 < Module.symvers > %buildroot/boot/symvers-%kernelrelease.gz

make modules_install $MAKE_ARGS INSTALL_MOD_PATH=%buildroot
make -C %kernel_build_dir SUBDIRS=%_builddir/u2mfn modules_install $MAKE_ARGS INSTALL_MOD_PATH=%buildroot

mkdir -p %buildroot/%src_install_dir

rm -f %buildroot/lib/modules/%kernelrelease/build
rm -f %buildroot/lib/modules/%kernelrelease/source
mkdir -p %buildroot/lib/modules/%kernelrelease/build
(cd %buildroot/lib/modules/%kernelrelease ; ln -s build source)
# dirs for additional modules per module-init-tools, kbuild/modules.txt
mkdir -p %buildroot/lib/modules/%kernelrelease/extra
mkdir -p %buildroot/lib/modules/%kernelrelease/updates
mkdir -p %buildroot/lib/modules/%kernelrelease/weak-updates

pushd %build_src_dir
cp --parents `find  -type f -name "Makefile*" -o -name "Kconfig*"` %buildroot/lib/modules/%kernelrelease/build
cp -a scripts %buildroot/lib/modules/%kernelrelease/build
cp -a --parents arch/x86/include/asm %buildroot/lib/modules/%kernelrelease/build/
if [ "%{build_flavor}" == "xenlinux" ]; then
    cp -a --parents arch/x86/include/mach-xen %buildroot/lib/modules/%kernelrelease/build/
fi
cp -a include %buildroot/lib/modules/%kernelrelease/build/include
popd

cp Module.symvers %buildroot/lib/modules/%kernelrelease/build
cp System.map %buildroot/lib/modules/%kernelrelease/build
if [ -s Module.markers ]; then
cp Module.markers %buildroot/lib/modules/%kernelrelease/build
fi

rm -rf %buildroot/lib/modules/%kernelrelease/build/Documentation
cp .config %buildroot/lib/modules/%kernelrelease/build

rm -f %buildroot/lib/modules/%kernelrelease/build/scripts/*.o
rm -f %buildroot/lib/modules/%kernelrelease/build/scripts/*/*.o

cp -a scripts/* %buildroot/lib/modules/%kernelrelease/build/scripts/
cp -a include/* %buildroot/lib/modules/%kernelrelease/build/include
if [ "%{build_flavor}" != "xenlinux" ]; then
    cp -a --parents arch/x86/include/generated %buildroot/lib/modules/%kernelrelease/build/
fi

# Make sure the Makefile and version.h have a matching timestamp so that
# external modules can be built
touch -r %buildroot/lib/modules/%kernelrelease/build/Makefile %buildroot/lib/modules/%kernelrelease/build/include/linux/version.h
touch -r %buildroot/lib/modules/%kernelrelease/build/.config %buildroot/lib/modules/%kernelrelease/build/include/linux/autoconf.h
# Copy .config to include/config/auto.conf so "make prepare" is unnecessary.
cp %buildroot/lib/modules/%kernelrelease/build/.config %buildroot/lib/modules/%kernelrelease/build/include/config/auto.conf

if test -s vmlinux.id; then
cp vmlinux.id %buildroot/lib/modules/%kernelrelease/build/vmlinux.id
else
echo >&2 "*** WARNING *** no vmlinux build ID! ***"
fi

#
# save the vmlinux file for kernel debugging into the kernel-debuginfo rpm
#
mkdir -p %buildroot%{debuginfodir}/lib/modules/%kernelrelease
cp vmlinux %buildroot%{debuginfodir}/lib/modules/%kernelrelease

find %buildroot/lib/modules/%kernelrelease -name "*.ko" -type f >modnames

# mark modules executable so that strip-to-file can strip them
xargs --no-run-if-empty chmod u+x < modnames

# Generate a list of modules for block and networking.

fgrep /drivers/ modnames | xargs --no-run-if-empty nm -upA |
sed -n 's,^.*/\([^/]*\.ko\):  *U \(.*\)$,\1 \2,p' > drivers.undef

collect_modules_list()
{
  sed -r -n -e "s/^([^ ]+) \\.?($2)\$/\\1/p" drivers.undef |
  LC_ALL=C sort -u > %buildroot/lib/modules/%kernelrelease/modules.$1
}

collect_modules_list networking \
			 'register_netdev|ieee80211_register_hw|usbnet_probe'
collect_modules_list block \
			 'ata_scsi_ioctl|scsi_add_host|scsi_add_host_with_dma|blk_init_queue|register_mtd_blktrans|scsi_esp_register|scsi_register_device_handler'
collect_modules_list drm \
			 'drm_open|drm_init'
collect_modules_list modesetting \
			 'drm_crtc_init'

# detect missing or incorrect license tags
rm -f modinfo
while read i
do
  echo -n "${i#%buildroot/lib/modules/%kernelrelease/} " >> modinfo
  /sbin/modinfo -l $i >> modinfo
done < modnames

egrep -v \
	  'GPL( v2)?$|Dual BSD/GPL$|Dual MPL/GPL$|GPL and additional rights$' \
	  modinfo && exit 1

rm -f modinfo modnames

# Move the devel headers out of the root file system
mkdir -p %buildroot/usr/src/kernels
mv %buildroot/lib/modules/%kernelrelease/build/* %buildroot/%src_install_dir/
mv %buildroot/lib/modules/%kernelrelease/build/.config %buildroot/%src_install_dir
rmdir %buildroot/lib/modules/%kernelrelease/build
ln -sf %src_install_dir %buildroot/lib/modules/%kernelrelease/build

# Abort if there are any undefined symbols
msg="$(/sbin/depmod -F %buildroot/boot/System.map-%kernelrelease \
     -b %buildroot -ae %kernelrelease 2>&1)"

if [ $? -ne 0 ] || echo "$msg" | grep  'needs unknown symbol'; then
exit 1
fi

if [ "%{build_flavor}" == "pvops" ]; then
    mv  %buildroot/lib/firmware %buildroot/lib/firmware-all
    mkdir -p %buildroot/lib/firmware
    mv  %buildroot/lib/firmware-all %buildroot/lib/firmware/%kernelrelease
fi

# Prepare initramfs for Qubes VM
mkdir -p %buildroot/%vm_install_dir
/sbin/dracut --nomdadmconf --nolvmconf \
    --kmoddir %buildroot/lib/modules/%kernelrelease \
    --include %_sourcedir/vm-initramfs / \
    -d "xenblk xen-blkfront cdrom ext4 jbd2 crc16 dm_snapshot" \
    %buildroot/%vm_install_dir/initramfs %kernelrelease

if [ "%{build_flavor}" == "xenlinux" ]; then
    cp -p arch/x86/boot/vmlinuz %buildroot/%vm_install_dir/vmlinuz
else
    cp -p arch/x86/boot/bzImage %buildroot/%vm_install_dir/vmlinuz
fi

# Modules for Qubes VM
mkdir -p %buildroot%vm_install_dir/modules
cp -a %buildroot/lib/modules/%kernelrelease %buildroot%vm_install_dir/modules/
mkdir -p %buildroot%vm_install_dir/modules/firmware
cp -a %buildroot/lib/firmware/%kernelrelease %buildroot%vm_install_dir/modules/firmware/

# remove files that will be auto generated by depmod at rpm -i time
for i in alias alias.bin ccwmap dep dep.bin ieee1394map inputmap isapnpmap ofmap pcimap seriomap symbols symbols.bin usbmap
do
  rm -f %buildroot/lib/modules/%kernelrelease/modules.$i
done

%post

INITRD_OPT="--mkinitrd --dracut"

/sbin/new-kernel-pkg --package %{name}-%{kernelrelease}\
        $INITRD_OPT \
        --depmod --kernel-args="max_loop=255"\
        --multiboot=/boot/xen.gz --mbargs="console=none" \
        --banner="Qubes"\
        --make-default --install %{kernelrelease}

if [ -e /boot/grub/grub.conf ]; then
# Make it possible to enter GRUB menu if something goes wrong...
sed -i "s/^timeout *=.*/timeout=3/" /boot/grub/grub.conf 
fi

%posttrans
/sbin/new-kernel-pkg --package %{name}-%{kernelrelease} --rpmposttrans %{kernelrelease}

%preun
/sbin/new-kernel-pkg --rminitrd --rmmoddep --remove %{kernelrelease}

%files
%defattr(-, root, root)
%ghost /boot/initramfs-%{kernelrelease}.img
/boot/System.map-%{kernelrelease}
/boot/config-%{kernelrelease}
/boot/symvers-%kernelrelease.gz
%attr(0644, root, root) /boot/vmlinuz-%{kernelrelease}
/lib/firmware/%{kernelrelease}
/lib/modules/%{kernelrelease}

%package devel
Summary:        Development files necessary for building kernel modules
License:        GPL v2 only
Group:          Development/Sources
Provides:       multiversion(kernel)
Provides:       %name-devel = %kernelrelease
Provides:       kernel-devel-uname-r = %kernelrelease
AutoReqProv:    on

%description devel
This package contains files necessary for building kernel modules (and
kernel module packages) against the %build_flavor flavor of the kernel.

%post devel
if [ -f /etc/sysconfig/kernel ]
then
    . /etc/sysconfig/kernel || exit $?
fi
if [ "$HARDLINK" != "no" -a -x /usr/sbin/hardlink ]
then
    (cd /usr/src/kernels/%{kernelrelease} &&
     /usr/bin/find . -type f | while read f; do
       hardlink -c /usr/src/kernels/*.fc*.*/$f $f
     done)
fi


%files devel
%defattr(-,root,root)
/usr/src/kernels/%{kernelrelease}


%package qubes-vm
Summary:        The Xen Kernel
Version:        %{version}
Release:        %{rel}
License:        GPL v2 only
Group:          System/Kernel
Url:            http://www.kernel.org/
AutoReqProv:    on
BuildRequires:  coreutils module-init-tools sparse
Provides:       multiversion(kernel-qubes-vm)

Provides:       kernel-xen-domU
Provides:       kernel-qubes-domU

Requires(pre):  coreutils gawk
Requires(post): dracut

Conflicts:      sysfsutils < 2.0
# root-lvm only works with newer udevs
Conflicts:      udev < 118
Conflicts:      lvm2 < 2.02.33
Provides:       kernel-qubes-vm = %version-%kernelrelease

%description qubes-vm
Qubes domU kernel.

%post qubes-vm

mkdir /tmp/qubes-modules-%kernelrelease
truncate -s 200M /tmp/qubes-modules-%kernelrelease.img
mkfs -t ext3 -F /tmp/qubes-modules-%kernelrelease.img > /dev/null
mount /tmp/qubes-modules-%kernelrelease.img /tmp/qubes-modules-%kernelrelease -o loop
cp -a -t /tmp/qubes-modules-%kernelrelease %vm_install_dir/modules/%kernelrelease
mkdir /tmp/qubes-modules-%kernelrelease/firmware
cp -a -t /tmp/qubes-modules-%kernelrelease/firmware %vm_install_dir/modules/firmware/%kernelrelease
umount /tmp/qubes-modules-%kernelrelease
rmdir /tmp/qubes-modules-%kernelrelease
mv /tmp/qubes-modules-%kernelrelease.img %vm_install_dir/modules.img

qubes-prefs --set default-kernel %version-%plainrel

%files qubes-vm
%defattr(-, root, root)
%ghost %attr(0644, root, root) %vm_install_dir/modules.img
%attr(0644, root, root) %vm_install_dir/initramfs
%attr(0644, root, root) %vm_install_dir/vmlinuz
%vm_install_dir/modules


%changelog
