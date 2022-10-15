Qubes package for Linux kernel
==============================

Building release candidate kernels
----------------------------------

1. Write kernel version into `version` file, for example 6.0-rc7.
2. Write hash of `linux-*.tar` file (the uncompressed source tarball) into `linux-*.tar.sha256` file.
3. Comment out "normal" tarball section in `.qubesbuilder` and uncomment the one for rc kernel.


As for getting the trustworthy tarball hash, it can be via signed git tag:

```
version=6.0-rc7
git clone -n --depth=1 https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git -b v$version linux-rc
cd linux-rc
git verify-tag v$version
# should be signed by Linus, you can find key in kernel.org-1-key.asc
git archive --prefix=linux-$version/ v$version | sha256sum
```

