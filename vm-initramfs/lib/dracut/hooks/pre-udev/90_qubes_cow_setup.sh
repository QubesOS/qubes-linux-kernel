#
# This file should be places in pre-mount directory in dracut's initramfs
#

#!/bin/sh
echo "Qubes initramfs script here:"

if [ -e /dev/mapper/dmroot ] ; then 
    die "Qubes: FATAL error: /dev/mapper/dmroot already exists?!"
fi

modprobe xenblk || modprobe xen-blkfront || echo "Qubes: Cannot load Xen Block Frontend..."

echo "Waiting for /dev/xvda* devices..."
while ! [ -e /dev/xvda ]; do sleep 0.1; done

if [ `cat /sys/block/xvda/ro` = 1 ] ; then
	echo "Qubes: Doing COW setup for AppVM..."

	while ! [ -e /dev/xvdc ]; do sleep 0.1; done
	while ! [ -e /dev/xvdc2 ]; do sleep 0.1; done

	echo "0 `cat /sys/block/xvda/size` snapshot /dev/xvda /dev/xvdc2 N 16" | \
    		dmsetup create dmroot || { echo "Qubes: FATAL: cannot create dmroot!"; }
	echo Qubes: done.
else
	echo "Qubes: Doing R/W setup for TemplateVM..."
	echo "0 `cat /sys/block/xvda/size` linear /dev/xvda 0" | \
    		dmsetup create dmroot || { echo "Qubes: FATAL: cannot create dmroot!"; exit 1; }
	echo Qubes: done.
fi
