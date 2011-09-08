/*
 * The Qubes OS Project, http://www.qubes-os.org
 *
 * Copyright (C) 2010  Rafal Wojtczuk  <rafal@invisiblethingslab.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 *
 */

#include <linux/module.h>
#include <linux/version.h>
#include <linux/proc_fs.h>
#include <linux/fs.h>
#include <linux/mm.h>
#include <linux/sched.h>
#ifndef FOREIGN_FRAME_BIT
#include <xen/page.h>
#endif
#include <linux/highmem.h>
#include "/usr/include/u2mfn-kernel.h"


#if LINUX_VERSION_CODE < KERNEL_VERSION(3,0,0)
static inline unsigned long virt_to_phys(volatile void *address)
{
	return __pa((unsigned long) address);
}
#endif

#ifdef virt_to_mfn
#define VIRT_TO_MFN virt_to_mfn
#else
extern unsigned long *phys_to_machine_mapping;
static inline unsigned long VIRT_TO_MFN(void *addr)
{
	unsigned int pfn = virt_to_phys(addr) >> PAGE_SHIFT;
	return phys_to_machine_mapping[pfn] & ~FOREIGN_FRAME_BIT;
}
#endif

/// User virtual address to mfn translator
/**
    \param cmd ignored
    \param data the user-specified address
    \return mfn corresponding to "data" argument, or -1 on error
*/
static long u2mfn_ioctl(struct file *f, unsigned int cmd,
		       unsigned long data)
{
	struct page *user_page;
	void *kaddr;
	int ret;

	if (_IOC_TYPE(cmd) != U2MFN_MAGIC) {
		printk("Qubes u2mfn: wrong IOCTL magic");
		return -ENOTTY;
	}

	switch (cmd) {
	case U2MFN_GET_MFN_FOR_PAGE:
		down_read(&current->mm->mmap_sem);
		ret = get_user_pages
		    (current, current->mm, data, 1, 1, 0, &user_page, 0);
		up_read(&current->mm->mmap_sem);
		if (ret != 1) {
			printk("U2MFN_GET_MFN_FOR_PAGE: get_user_pages failed, ret=0x%x\n", ret);
			return -1;
		}
		kaddr = kmap(user_page);
		ret = VIRT_TO_MFN(kaddr);
		kunmap(user_page);
		put_page(user_page);
		break;

	case U2MFN_GET_LAST_MFN:
		if (f->private_data)
			ret = VIRT_TO_MFN(f->private_data);
		else
			ret = 0;
		break;

	default:
		printk("Qubes u2mfn: wrong ioctl passed!\n");
		return -ENOTTY;
	}


	return ret;
}

static int u2mfn_mmap(struct file *f, struct vm_area_struct *vma)
{
	int ret;
	char *kbuf;
	long length = vma->vm_end - vma->vm_start;
	printk("u2mfn_mmap: entering, private=%p\n", f->private_data);
	if (f->private_data)
		return -EBUSY;
	if (length != PAGE_SIZE)
		return -EINVAL;
	kbuf = (char *) __get_free_page(GFP_KERNEL);
	if (!kbuf)
		return -ENOMEM;

	f->private_data = kbuf;

	ret = remap_pfn_range(vma, vma->vm_start,
			      virt_to_phys(kbuf) >> PAGE_SHIFT,
			      length, vma->vm_page_prot);

	printk("u2mfn_mmap: calling remap return %d\n", ret);
	if (ret)
		return ret;


	return 0;
}

static int u2mfn_release(struct inode *i, struct file *f)
{
	printk("u2mfn_release, priv=%p\n", f->private_data);
	if (f->private_data)
		__free_page(f->private_data);
	f->private_data = NULL;
	return 0;
}

static struct file_operations u2mfn_fops = {
	.unlocked_ioctl = u2mfn_ioctl,
	.mmap = u2mfn_mmap,
	.release = u2mfn_release
};

/// u2mfn module registration
/**
    tries to register "/proc/u2mfn" pseudofile
*/
static int u2mfn_init(void)
{
	struct proc_dir_entry *u2mfn_node =
	    proc_create_data("u2mfn", 0600, NULL,
			     &u2mfn_fops, 0);
	if (!u2mfn_node)
		return -1;
	return 0;
}

static void u2mfn_exit(void)
{
	remove_proc_entry("u2mfn", 0);
}

module_init(u2mfn_init);
module_exit(u2mfn_exit);
MODULE_LICENSE("GPL");
