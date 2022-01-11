#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <assert.h>
#include <errno.h>
#include <inttypes.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>

#include <err.h>

#include <ext2fs.h>
#include <com_err.h>

static int real_main(const char *filesystem, const char *uname,
                     bool mark_immutable);

static void process_dirent(ext2_filsys const fs,
                           const char *const path,
                           ext2_ino_t const inode,
                           int const name_len,
                           const char *const name,
                           const char *const selinux_label,
                           bool force_mutable);

static int dir_iterate_callback(ext2_ino_t dir __attribute__((unused)),
                                int entry __attribute__((unused)),
                                struct ext2_dir_entry *dirent,
                                int offset __attribute__((unused)),
                                int blocksize __attribute__((unused)),
                                char *buf __attribute__((unused)),
                                void *priv_data);

static void set_label(ext2_filsys const fs,
                      const char *const path,
                      ext2_ino_t const inode,
                      int const name_len,
                      const char *const name,
                      const char *const selinux_label);

__attribute__((format(printf, 2, 3)))
_Noreturn static void genfs_err(const errcode_t err, const char *const fmt, ...) {
    va_list args;
    va_start(args, fmt);
    com_err_va(program_invocation_name, err, fmt, args);
    va_end(args);
    exit(EXIT_FAILURE);
}

_Noreturn static void genfs_err_inode(errcode_t const err,
                                      const char *const msg,
                                      const char *const name,
                                      ext2_ino_t const ino,
                                      int const dirent_namelen,
                                      const char *const dirent_name) {
    genfs_err(err, "while %s of inode %" PRIu32 " (name %s/%.*s)", msg,
              ino, name, dirent_namelen, dirent_name);
}

static errcode_t qubes_write_inode_full(ext2_filsys fs, ext2_ino_t ino,
                                        struct ext2_inode_large *inode) {
    return ext2fs_write_inode_full(fs, ino, ext2fs_inode(inode), sizeof *inode);
}

static errcode_t qubes_read_inode_full(ext2_filsys fs, ext2_ino_t ino,
                                       struct ext2_inode_large *inode) {
    return ext2fs_read_inode_full(fs, ino, ext2fs_inode(inode), sizeof *inode);
}

static const char *const label_modules_object = "system_u:object_r:modules_object_t:s0";
static const char *const label_modules_dep = "system_u:object_r:modules_dep_t:s0";
static const char *const label_usr = "system_u:object_r:usr_t:s0";
static const char *const label_lib = "system_u:object_r:lib_t:s0";

int main(int argc, char **argv) {
    initialize_ext2_error_table();
    bool mark_immutable = false;
    if (argc == 4) {
        if (!strcmp("immutable=yes", argv[3]))
            mark_immutable = true;
        else if (strcmp("immutable=no", argv[3]))
            errx(1, "Invalid \"immutable=\" value (expected \"yes\" or \"no\")");
    } else if (argc != 2)
        errx(1, "Usage: genfs FILESYSTEM [UNAME immutable=[yes|no]]");
    const char *const filesystem = argv[1], *const uname = argv[2];
    return real_main(filesystem, uname, mark_immutable);
}

struct qubes_genfs_data {
    ext2_filsys fs;
    const char *const uname_or_label;
};

static int recursive_relabel(ext2_ino_t dir __attribute__((unused)),
                             int entry __attribute__((unused)),
                             struct ext2_dir_entry *dirent,
                             int offset __attribute__((unused)),
                             int blocksize __attribute__((unused)),
                             char *buf __attribute__((unused)),
                             void *priv_data);

static int root_iterate_callback(ext2_ino_t dir __attribute__((unused)),
                                 int entry __attribute__((unused)),
                                 struct ext2_dir_entry *dirent,
                                 int offset __attribute__((unused)),
                                 int blocksize __attribute__((unused)),
                                 char *buf __attribute__((unused)),
                                 void *priv_data) {
    struct qubes_genfs_data *data = priv_data;
    int const name_len = ext2fs_dirent_name_len(dirent);
    errcode_t err;
    const char *label = label_modules_object;
    assert(name_len >= 0);
    if (name_len <= 2 && !memcmp(dirent->name, "..", name_len)) {
        return 0;
    } else if (memchr(dirent->name, '\0', (size_t)name_len)) {
        errx(1, "Inode %" PRIx64 " has a NUL in its name", (uint64_t)dirent->inode);
    } else if (!strncmp(dirent->name, "firmware", (size_t)name_len)) {
        struct qubes_genfs_data relabel_data = {
            .fs = data->fs,
            .uname_or_label = label = label_lib,
        };
        if ((err = ext2fs_dir_iterate2(data->fs, dirent->inode, 0, NULL,
                                       recursive_relabel, &relabel_data)))
            genfs_err(err, "during recursive relabel");
    } else if (!strncmp(dirent->name, data->uname_or_label, (size_t)name_len)) {
        if ((err = ext2fs_dir_iterate2(data->fs, dirent->inode, 0, NULL, dir_iterate_callback, data)))
            genfs_err(err, "processing %s", data->uname_or_label);
    } else if (strncmp(dirent->name, "vmlinuz", (size_t)name_len) &&
               strncmp(dirent->name, "lost+found", (size_t)name_len) &&
               strncmp(dirent->name, "initramfs", (size_t)name_len)) {
        errx(1, "Unexpected inode %.*s found in root of file system", name_len, dirent->name);
    }

    process_dirent(data->fs, "", dirent->inode, name_len, dirent->name, label,
                   false);
    return 0;
}

static int dir_iterate_callback(ext2_ino_t dir __attribute__((unused)),
                                int entry __attribute__((unused)),
                                struct ext2_dir_entry *dirent,
                                int offset __attribute__((unused)),
                                int blocksize __attribute__((unused)),
                                char *buf __attribute__((unused)),
                                void *priv_data) {
    struct qubes_genfs_data *data = priv_data;
    int name_len = ext2fs_dirent_name_len(dirent);
    assert(name_len >= 0 && name_len < EXT2_NAME_LEN);
    if (name_len == 5 && !memcmp(dirent->name, "build", 5)) {
        if (ext2fs_dirent_file_type(dirent) != EXT2_FT_DIR)
            errx(1, "File %s/%.*s is not a directory", data->uname_or_label, name_len, dirent->name);
        process_dirent(data->fs, data->uname_or_label, dirent->inode, name_len, dirent->name,
                       label_usr, true);
        struct qubes_genfs_data relabel_data = {
            .fs = data->fs,
            .uname_or_label = label_usr,
        };
        errcode_t err;
        if ((err = ext2fs_dir_iterate2(data->fs, dirent->inode, 0, NULL,
                                       recursive_relabel, &relabel_data)))
            genfs_err(err, "during recursive relabel");
    } else if (name_len >= 8 && !memcmp(dirent->name, "modules.", 8)) {
        if (ext2fs_dirent_file_type(dirent) != EXT2_FT_REG_FILE)
            errx(1, "File %s/%.*s is not a regular file", data->uname_or_label, name_len,
                 dirent->name);
        process_dirent(data->fs, data->uname_or_label, dirent->inode, name_len, dirent->name,
                       label_modules_dep, true);
    }
    return 0;
}

static int recursive_relabel(ext2_ino_t dir __attribute__((unused)),
                             int entry __attribute__((unused)),
                             struct ext2_dir_entry *dirent,
                             int offset __attribute__((unused)),
                             int blocksize __attribute__((unused)),
                             char *buf __attribute__((unused)),
                             void *priv_data) {
    struct qubes_genfs_data *data = priv_data;
    int name_len = ext2fs_dirent_name_len(dirent);
    assert(name_len >= 0 && name_len < EXT2_NAME_LEN);
    /* Avoid recursion through . or .. */
    if (name_len <= 2 && !memcmp(dirent->name, "..", name_len))
        return 0;
    process_dirent(data->fs, "", dirent->inode, name_len, dirent->name,
                   data->uname_or_label, false);
    errcode_t err;
    if (ext2fs_dirent_file_type(dirent) == EXT2_FT_DIR &&
        (err = ext2fs_dir_iterate2(data->fs, dirent->inode, 0, NULL,
                                   recursive_relabel, data)))
        genfs_err(err, "during recursive relabel");
    return 0;
}

static void process_dirent(ext2_filsys const fs,
                           const char *const path,
                           ext2_ino_t const inode,
                           int const name_len,
                           const char *const name,
                           const char *const selinux_label,
                           bool force_mutable) {
    errcode_t err;
    struct ext2_inode_large inode_contents;

    set_label(fs, path, inode, name_len, name, selinux_label);
    if ((err = qubes_read_inode_full(fs, inode, &inode_contents)))
        genfs_err_inode(err, "reading inode", path, inode, name_len, name);
    if (force_mutable)
        inode_contents.i_flags &= ~EXT2_IMMUTABLE_FL;
    if ((err = qubes_write_inode_full(fs, inode, &inode_contents)))
        genfs_err_inode(err, "writing inode", path, inode, name_len, name);
}

static void set_label(ext2_filsys const fs,
                      const char *const path,
                      ext2_ino_t const inode,
                      int const name_len,
                      const char *const name,
                      const char *const selinux_label) {
    errcode_t err;
    struct ext2_xattr_handle *handle = NULL;
    size_t count = 0;
    if ((err = ext2fs_xattrs_open(fs, inode, &handle)) || !handle)
        genfs_err_inode(err, "opening xattrs", path, inode, name_len, name);
    if ((err = ext2fs_xattrs_read(handle)))
        genfs_err_inode(err, "reading extended attributes", path, inode, name_len, name);
    if ((err = ext2fs_xattr_set(handle, "security.selinux", selinux_label, strlen(selinux_label))))
        genfs_err_inode(err, "setting SELinux label", path, inode, name_len, name);
    if ((err = ext2fs_xattrs_count(handle, &count)))
        genfs_err_inode(err, "obtaining xattr count", path, inode, name_len, name);
    if (count != 1)
        errx(1, "wrong number of xattrs inode %" PRIu32 "(path %s/%.*s)", inode, path, name_len, name);
    if ((err = ext2fs_xattrs_close(&handle)))
        genfs_err_inode(err, "closing xattrs", path, inode, name_len, name);
}

static int real_main(const char *const filesystem, const char *const uname,
                     const bool mark_immutable) {
    ext2_filsys fs = NULL;
    errcode_t err;
    const char *ptr = getenv("SOURCE_DATE_EPOCH");
    char *endptr = NULL;
    unsigned long long timestamp = 0;
    uint32_t epoch = 0, global_timestamp = 0;
    if (ptr) {
        if (*ptr < '1' || *ptr > '9')
            errx(1, "Invalid SOURCE_DATE_EPOCH: %s", ptr);
        timestamp = strtoull(ptr, &endptr, 10);
        if (*endptr)
            errx(1, "Invalid SOURCE_DATE_EPOCH (trailing garbage): %s", ptr);
        if (timestamp >= (1ULL << 34))
            errx(1, "SOURCE_DATE_EPOCH too large (%llu > %llu)", timestamp, (1ULL << 34) - 1);
        epoch = timestamp >> 32;
        global_timestamp = timestamp & UINT32_MAX;
    }
    ext2_inode_scan scan = NULL;
    if ((err = ext2fs_open(filesystem, EXT2_FLAG_RW, 0,
            0, unix_io_manager, &fs)) || !fs)
        genfs_err(err, "opening filesystem %s", filesystem);
    if (fs->super->s_first_error_time ||
        fs->super->s_last_error_time ||
        fs->super->s_first_error_time_hi ||
        fs->super->s_last_error_time_hi ||
        fs->super->s_first_error_ino)
        errx(1, "Filesystem has had an error in the past");
    if (fs->super->s_rev_level != EXT2_DYNAMIC_REV)
        errx(1, "Filesystem revision %" PRIu32 " not supported",
             fs->super->s_rev_level);
    if (fs->super->s_inode_size < sizeof(struct ext2_inode_large))
        errx(1, "Filesystem inode size %" PRIu16 " not supported (expected %zu)",
             fs->super->s_inode_size, sizeof(struct ext2_inode_large));
    if (!fs->super->s_lpf_ino) {
        if ((err = ext2fs_namei(fs, EXT2_ROOT_INO, EXT2_ROOT_INO, "lost+found", &fs->super->s_lpf_ino)))
            genfs_err(err, "obtaining lost+found inode");
        if (!fs->super->s_lpf_ino)
            errx(1, "no lost+found inode");
    }
    if (uname) {
        if ((err = ext2fs_open_inode_scan(fs, EXT2_INODE_SCAN_DEFAULT_BUFFER_BLOCKS, &scan)) || !scan)
            genfs_err(err, "scanning filesystem %s", filesystem);
        for (;;) {
            ext2_ino_t ino;
            struct ext2_inode_large inode;
            if ((err = ext2fs_get_next_inode_full(scan, &ino, ext2fs_inode(&inode), sizeof inode)))
                genfs_err(err, "obtaining next inode");

            // No inode means end of filesystem
            if (!ino)
                break;

            // Do not touch reserved inodes, except the root directory
            if (ino != EXT2_ROOT_INO && ino < fs->super->s_first_ino)
                continue;

            // Do not touch deleted inodes
            if (!inode.i_links_count)
                continue;

            if (timestamp) {
                inode.i_ctime = inode.i_mtime = inode.i_atime = inode.i_crtime = global_timestamp;
                inode.i_ctime_extra = inode.i_mtime_extra = inode.i_atime_extra = inode.i_crtime_extra = epoch;
            }
            inode.i_uid = inode.i_uid_high = 0;
            inode.i_gid = inode.i_gid_high = 0;
            const uint16_t perms = inode.i_mode & 07777;
            if (inode.i_mode & 07000)
                errx(1, "Inode %" PRIu32 " is setuid, setgid, or sticky (mode 0%04o)",
                     ino, (int)perms);
            if (!LINUX_S_ISLNK(inode.i_mode) && (inode.i_mode & (LINUX_S_IWGRP|LINUX_S_IWOTH)))
                errx(1, "Inode %" PRIu32 " is not a symlink and is group- or "
                        "world- writable (mode 0%04o)", ino, (int)perms);

            // /lost+found needs special handling
            const bool is_lpf_ino = ino == fs->super->s_lpf_ino;

            // Ensure all files have at least mode 0644 (read and write
            // to owner, read for others).  Since everything in this
            // directory is public anyway (published online) trying to
            // hide it is of no benefit.  Also ensure that all
            // directories are executable.
            //
            // Exception: the lost+found inode is 0700 because of POLA.
            if (LINUX_S_ISDIR(inode.i_mode))
                inode.i_mode = (is_lpf_ino ? 0700 : 0755) | (inode.i_mode & ~0777);
            else if (LINUX_S_ISREG(inode.i_mode) || LINUX_S_ISLNK(inode.i_mode))
                inode.i_mode |= 0644;
            else
                errx(1, "Inode %" PRIu32 " is neither a regular file, "
                        "directory, or symbolic link (mode 0%06o)", ino, (int)inode.i_mode);
            // If mark_immutable is set, mark regular files and /lost+found immutable
            if (mark_immutable &&
                (LINUX_S_ISREG(inode.i_mode) || (is_lpf_ino && LINUX_S_ISDIR(inode.i_mode))))
                inode.i_flags |= EXT2_IMMUTABLE_FL;
            else
                inode.i_flags &= ~EXT2_IMMUTABLE_FL;
            set_label(fs, "", ino, 0, "", label_modules_object);
            inode.osd1.linux1.l_i_version = inode.i_generation = 0;
            inode.i_version_hi = inode.i_projid = 0;
            if ((err = qubes_write_inode_full(fs, ino, &inode)))
                genfs_err(err, "writing inode %" PRIu32, ino);
        }
        ext2fs_close_inode_scan(scan);
        struct qubes_genfs_data data = {
            .fs = fs,
            .uname_or_label = uname,
        };
        process_dirent(fs, "", EXT2_ROOT_INO, 0, "", label_modules_object, true);
        if ((err = ext2fs_dir_iterate2(fs, EXT2_ROOT_INO, 0, NULL,
                                       root_iterate_callback, &data)))
            genfs_err(err, "processing /");
    }
    if (timestamp) {
        fs->now = timestamp;
        fs->super->s_mtime = fs->super->s_wtime = fs->super->s_mkfs_time =
            fs->super->s_lastcheck = global_timestamp;
        fs->super->s_mtime_hi = fs->super->s_wtime_hi =
            fs->super->s_mkfs_time_hi = fs->super->s_lastcheck_hi = epoch;
    }
    fs->super->s_checkinterval = 0;
    ext2fs_mark_super_dirty(fs);
    if ((err = ext2fs_close(fs)))
        genfs_err(err, "closing filesystem");
    return 0;
}
