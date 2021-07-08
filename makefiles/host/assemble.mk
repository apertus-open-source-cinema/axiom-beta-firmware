# This makefile creates images for the Apertus AXIOM cameras

include rootfs.mk

SHELL := /bin/bash

# define the layout of the image
IMGSIZE = 3800MiB
BOOTSIZE = 50MiB
ROOTSIZE = 3700MiB
LABEL_ID = f37043ff

define SFDISK_SCRIPT
label: dos
label-id: $(LABEL_ID)
part1 : size= $(BOOTSIZE), Id=  c 
part2 : Id= 83
endef
export SFDISK_SCRIPT


build/$(IMAGE): build/boot.part build/root.part
	+echo "building image for AXIOM $(DEVICE) with $$(nproc) cores (not nesscessarily jobs)"

	# create the image file
	rm -rf $@
	fallocate -l $(IMGSIZE) $@

	# write the partition table
	echo "$$SFDISK_SCRIPT"
	sfdisk $@ <<<"$$SFDISK_SCRIPT"

	# assemble the partitions into the full image
	dd if=build/boot.part of=$@ bs=512 seek=$$(sfdisk -l build/$(IMAGE) -o start -q | sed -n "2p" | sed 's/ //g') conv=sparse,notrunc
	dd if=build/root.part of=$@ bs=512 seek=$$(sfdisk -l build/$(IMAGE) -o start -q | sed -n "3p" | sed 's/ //g') conv=sparse,notrunc

build/boot.part: build/boot.fs/.install_stamp
	rm -f build/boot.part
	fallocate -l $(BOOTSIZE) build/boot.part
	mkfs.vfat -n "BOOT" -F 32 build/boot.part
	mcopy -i build/boot.part build/boot.fs/* ::

build/root.part: build/root.fs/.install_stamp
	rm -f build/root.part
	fallocate -l $(ROOTSIZE) build/root.part
	mkfs.btrfs build/root.part
	mkdir -p build/root_mount
	mount build/root.part build/root_mount
	btrfs subvolume create build/root_mount/@golden
	rsync -a build/root.fs/ build/root_mount/@golden/
	btrfs property set build/root_mount/@golden ro true
	btrfs subvolume snapshot build/root_mount/@golden build/root_mount/@user
	umount build/root_mount
