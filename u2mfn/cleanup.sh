#!/bin/sh
make -C /lib/modules/`uname -r`/build/ SUBDIRS=`pwd` clean
