ARCH = arm

LINUX_VERSION = v5.8.1
LINUX_SOURCE = build/linux-$(LINUX_VERSION).git

UBOOT_VERSION = v2020.07
UBOOT_SOURCE = build/u-boot-$(UBOOT_VERSION).git

build/boot.fs/.install_stamp: $(LINUX_SOURCE)/arch/arm/boot/zImage $(UBOOT_SOURCE)/u-boot.img $(UBOOT_SOURCE)/spl/boot.bin build/boot.fs/devicetree.dtb \
			   boot/axiom-$(DEVICE)/uEnv.txt build/boot.fs/devicetree.dts build/boot.fs/boot.scr
	mkdir -p $(@D)

ifeq ($(DEVICE),micro)
	cp -a boot/axiom-micro/bitstream.bit $(@D)/bitstream.bit
endif

	cp boot/axiom-$(DEVICE)/uEnv.txt $(UBOOT_SOURCE)/u-boot.img $(UBOOT_SOURCE)/spl/boot.bin $(LINUX_SOURCE)/arch/arm/boot/zImage $(@D)

	touch $@


### Kernel
KERNEL_MAKE = $(MAKE) -C $(LINUX_SOURCE) CROSS_COMPILE=$(CROSS) ARCH=$(ARCH)
LINUX_PATCHES = $(wildcard patches/linux/*.patch)

$(LINUX_SOURCE): $(LINUX_PATCHES)
	@mkdir -p $(@D)
	rm -rf $@
	git clone --branch $(LINUX_VERSION) --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git $@

	./makefiles/host/patch_wrapper.sh $@ $(LINUX_PATCHES)
	# remove + at end of kernel version (indicates dirty tree)
	touch $@/.scmversion


$(LINUX_SOURCE)/arch/arm/boot/zImage: boot/kernel.config $(LINUX_SOURCE)
	# first configure the kernel
	cp $< $(LINUX_SOURCE)/.config
	+$(KERNEL_MAKE) olddefconfig

	# then build the kernel
	+$(KERNEL_MAKE)
	+$(KERNEL_MAKE) modules

	# finally install the kernel modules
	mkdir -p build/kernel_modules.fs
	+$(KERNEL_MAKE) INSTALL_MOD_PATH=../kernel_modules.fs modules_install

	touch $@

# u-boot
U_BOOT_MAKE = $(MAKE) -C $(UBOOT_SOURCE) CROSS_COMPILE=$(CROSS) ARCH=$(ARCH)
U_BOOT_PATCHES = $(wildcard patches/u-boot/*.patch)
$(UBOOT_SOURCE)/.config: export DEVICE_TREE = $(U_BOOT_DEVICE_TREE)
$(UBOOT_SOURCE)/.config: $(U_BOOT_PATCHES)
	@mkdir -p $(@D)
	rm -rf $(@D)
	git clone --branch $(UBOOT_VERSION) --depth 1 https://gitlab.denx.de/u-boot/u-boot.git $(@D)

	./makefiles/host/patch_wrapper.sh $(@D) $(U_BOOT_PATCHES)
	# remove -dirty from version
	touch $(@D)/.scmversion

	# configure u-boot
	+$(U_BOOT_MAKE) xilinx_zynq_virt_defconfig
	touch $@

$(UBOOT_SOURCE)/u-boot.img: export DEVICE_TREE = $(U_BOOT_DEVICE_TREE)
$(UBOOT_SOURCE)/u-boot.img: $(UBOOT_SOURCE)/.config
	+$(U_BOOT_MAKE) u-boot.img
	touch $@

$(UBOOT_SOURCE)/spl/boot.bin: export DEVICE_TREE = $(U_BOOT_DEVICE_TREE)
$(UBOOT_SOURCE)/spl/boot.bin: $(UBOOT_SOURCE)/.config $(UBOOT_SOURCE)/u-boot.img
	+$(U_BOOT_MAKE) spl/boot.bin
	touch $@

build/boot.fs/boot.scr: boot/sdboot.cmd $(UBOOT_SOURCE)/spl/boot.bin
	./$(UBOOT_SOURCE)/tools/mkimage -c none -A arm -T script -d $< $@

build/boot.fs/devicetree.dtb: boot/axiom-$(DEVICE)/devicetree.dts
	@mkdir -p $(@D)
	dtc -@ -I dts -O dtb -o $@ $<

build/boot.fs/devicetree.dts: boot/axiom-$(DEVICE)/devicetree.dts
	@mkdir -p $(@D)
	cp $< $@

ARM_SYSROOT = build/arm_sysroot

$(ARM_SYSROOT):
	mkdir -p $@

UTIL_LINUX_VERSION = 2.35.2
UTIL_LINUX_SOURCE = build/util-linux-$(UTIL_LINUX_VERSION)
CURL = curl -L
CROSS_SETUP = export CPP="arm-buildroot-linux-musleabihf-gcc -E" CC=arm-buildroot-linux-musleabihf-gcc RANLIB=arm-buildroot-linux-musleabihf-ranlib AR=arm-buildroot-linux-musleabihf-ar

$(UTIL_LINUX_SOURCE):
	rm -rf $@
	(cd build; $(CURL) https://mirrors.edge.kernel.org/pub/linux/utils/util-linux/v2.35/util-linux-$(UTIL_LINUX_VERSION).tar.xz | tar xJ)

$(UTIL_LINUX_SOURCE)/.install_stamp: $(UTIL_LINUX_SOURCE) $(ARM_SYSROOT)
	(cd $(@D); PKG_CONFIG=/root/armv7-eabihf--musl--bleeding-edge-2020.02-2/bin/pkg-config ./configure --host=arm-buildroot-linux-musleabihf --disable-shared --disable-backtrace --enable-static --disable-documentation --disable-all-programs --enable-libblkid --enable-libuuid --prefix=$$(realpath ../../$(ARM_SYSROOT)))
	+$(MAKE) -C $(@D)
	+$(MAKE) -C $(@D) install
	touch $@

LZO_VERSION = 2.10
LZO_SOURCE = build/lzo-$(LZO_VERSION)

$(LZO_SOURCE):
	rm -rf $@
	(cd build; $(CURL) http://www.oberhumer.com/opensource/lzo/download/lzo-$(LZO_VERSION).tar.gz | tar xz)

$(LZO_SOURCE)/.install_stamp: $(LZO_SOURCE) $(ARM_SYSROOT)
	(cd $(@D); $(CROSS_SETUP); ./configure --host arm-buildroot-linux --prefix=$$(realpath ../../$(ARM_SYSROOT)))
	+$(MAKE) -C $(@D)
	+$(MAKE) -C $(@D) install
	touch $@


ZSTD_VERSION = 1.4.5
ZSTD_SOURCE = build/zstd-$(ZSTD_VERSION)

$(ZSTD_SOURCE):
	rm -rf $@
	(cd build; $(CURL) https://github.com/facebook/zstd/releases/download/v$(ZSTD_VERSION)/zstd-$(ZSTD_VERSION).tar.gz | tar xz)

$(ZSTD_SOURCE)/.install_stamp: $(ZSTD_SOURCE) $(ARM_SYSROOT)
	+(cd $(@D); $(CROSS_SETUP); $(MAKE) PREFIX=$$(realpath ../../$(ARM_SYSROOT)) install)
	touch $@


ZLIB_VERSION = 1.2.11
ZLIB_SOURCE = build/zlib-$(ZLIB_VERSION)

$(ZLIB_SOURCE):
	rm -rf $@
	(cd build; $(CURL) https://zlib.net/zlib-$(ZLIB_VERSION).tar.gz | tar xz)

$(ZLIB_SOURCE)/.install_stamp: $(ZLIB_SOURCE) $(ARM_SYSROOT)
	+(cd $(@D); $(CROSS_SETUP); ./configure --static --prefix=$$(realpath ../../$(ARM_SYSROOT)); $(MAKE); $(MAKE) install)
	touch $@


BTRFS_PROGS_VERSION = v5.6.1
BTRFS_PROGS_SOURCE = build/btrfs-progs-$(BTRFS_PROGS_VERSION).git

$(BTRFS_PROGS_SOURCE):
	rm -rf $@
	git clone --branch $(BTRFS_PROGS_VERSION) --depth 1 git://git.kernel.org/pub/scm/linux/kernel/git/kdave/btrfs-progs.git $@

$(BTRFS_PROGS_SOURCE)/.install_stamp: $(BTRFS_PROGS_SOURCE) $(ARM_SYSROOT) $(ZLIB_SOURCE)/.install_stamp $(ZSTD_SOURCE)/.install_stamp $(LZO_SOURCE)/.install_stamp $(UTIL_LINUX_SOURCE)/.install_stamp
	(cd $(@D); ./autogen.sh; PKG_CONFIG_SYSROOT_DIR="/" CFLAGS=-I../../$(ARM_SYSROOT)/include LDFLAGS=-L../../$(ARM_SYSROOT)/lib PKG_CONFIG_PATH=$$(realpath ../../$(ARM_SYSROOT))/lib/pkgconfig PKG_CONFIG=/root/armv7-eabihf--musl--bleeding-edge-2020.02-2/bin/pkg-config ./configure --host=arm-buildroot-linux-musleabihf --disable-shared --disable-backtrace --enable-static --disable-documentation --disable-convert)
	+$(MAKE) -C $(@D) static
	touch $@

INITRAMFS_SOURCE = build/initramfs

BUSYBOX_VERSION = 1.31.1
BUSYBOX_SOURCE = build/busybox-$(BUSYBOX_VERSION)

$(BUSYBOX_SOURCE):
	rm -rf $@
	(cd build; $(CURL) https://busybox.net/downloads/busybox-$(BUSYBOX_VERSION).tar.bz2 | tar xj)

$(BUSYBOX_SOURCE)/.install_stamp: $(BUSYBOX_SOURCE)
	+$(MAKE) -C $(@D) ARCH=arm CROSS_COMPILE=arm-buildroot-linux-musleabihf- defconfig
	sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' $(BUSYBOX_SOURCE)/.config
	+$(MAKE) -C $(@D) ARCH=arm CROSS_COMPILE=arm-buildroot-linux-musleabihf-
	touch $@

INITRAMFS_SOURCE = build/initramfs

$(INITRAMFS_SOURCE)/.install_stamp: $(BTRFS_PROGS_SOURCE)/.install_stamp $(BUSYBOX_SOURCE)/.install_stamp
	rm -rf $(@D)
	mkdir -p $(@D)
	cp $(BTRFS_PROGS_SOURCE)/btrfs.static $(@D)/btrfs
	arm-buildroot-linux-musleabihf-strip $(@D)/btrfs
	cp $(BUSYBOX_SOURCE)/busybox $(@D)/busybox
	touch $@
