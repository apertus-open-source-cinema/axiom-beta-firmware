#!/bin/bash
set -xeuo pipefail
DEVICE=$(cat /etc/hostname)

cd /opt/axiom-firmware


# configure pacman & do sysupdate
sed -i 's/^CheckSpace/#CheckSpace/g' /etc/pacman.conf
sed -i 's/#IgnorePkg   =/IgnorePkg = linux linux-*/' /etc/pacman.conf
# use fixed mirror, because the alarm loadbalancing and some mirrors are broken
echo 'Server = http://de3.mirror.archlinuxarm.org/$arch/$repo' > /etc/pacman.d/mirrorlist
pacman-key --init
pacman-key --populate archlinuxarm
pacman --noprogressbar --noconfirm --needed -Syu
pacman --noprogressbar --noconfirm -R linux-zedboard || true

# install dependencies
pacman --noprogressbar --noconfirm --needed -S $(grep -vE "^\s*#" makefiles/in_chroot/requirements_pacman.txt | tr "\n" " ")
pip install wheel
pip install --progress-bar off -r makefiles/in_chroot/requirements_pip.txt

# setup users
if ! grep "dont log in as root" /root/.profile; then
    echo 'echo -e "\033[31municorns dont log in as root\033[0m"' >> /root/.profile
fi

PASS=axiom
USERNAME=operator
if ! [ -d /home/$USERNAME ]; then
    useradd -p $(openssl passwd -1 $PASS) -d /home/"$USERNAME" -m -g users -s /bin/bash "$USERNAME"
    echo "$USERNAME      ALL=(ALL) PASSWD: ALL" >> /etc/sudoers
    rm -f /home/$USERNAME/.bashrc
fi

# add empty ~/.ssh/authorized_keys (see #80)
function add_authorized_keys_file() {
    SSH_AUTHORIZED_KEYS=/home/$1/.ssh/authorized_keys
    mkdir -p -m 700 $(dirname $SSH_AUTHORIZED_KEYS)
    chown $1:users $(dirname $SSH_AUTHORIZED_KEYS)
    touch $SSH_AUTHORIZED_KEYS
    chown $1:users $SSH_AUTHORIZED_KEYS
    chmod 600 $SSH_AUTHORIZED_KEYS
}

add_authorized_keys_file $USERNAME
add_authorized_keys_file "root"

# remove default arch linux arm user
userdel -r -f alarm || true

# configure ssh
grep 'PermitRootLogin' /etc/ssh/sshd_config && sed -i 's/^.*PermitRootLogin.*$/PermitRootLogin without-password/' /etc/ssh/sshd_config
grep 'PermitRootLogin' /etc/ssh/sshd_config || echo "PermitRootLogin without-password" >> /etc/ssh/sshd_config
grep -x 'X11Forwarding yes' /etc/ssh/sshd_config || echo "X11Forwarding yes" >> /etc/ssh/sshd_config

# build all the tools
function cdmake () {
    [[ -d "$1" ]] && make -C "$1" && make -C "$1" install
}

mkdir -p /usr/axiom/bin/
for dir in $(ls -d software/sensor_tools/*/); do cdmake "$dir"; done
for dir in $(ls -d software/processing_tools/*/); do cdmake "$dir"; done
cdmake software/memtool

mkdir -p /usr/axiom/script/
for script in $(cat <(ls software/scripts) software/scripts/bringup_scripts.list | sort | uniq -u | grep -E  '\.sh$|\.py$'); do ln -sf $(pwd)/software/scripts/$script /usr/axiom/script/$script; chmod a+x $(pwd)/software/scripts/$script; done

mkdir -p /usr/axiom/bringup-script/
for script in $(cat software/scripts/bringup_scripts.list); do ln -sf $(pwd)/software/scripts/$script /usr/axiom/bringup-script/$script; chmod a+x $(pwd)/software/scripts/$script; done

# TODO: find a better solution for this
echo 'PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/axiom/bin:/usr/axiom/script' >> /etc/environment
echo 'PYTHONPATH=/opt/axiom-firmware/software/scripts' >> /etc/environment
echo 'BASH_ENV=/etc/profile.d/apertus.sh' >> /etc/environment


# install nctrl (the central control-daemon)
mkdir -p /axiom-api/
if [ -f /etc/axiom-yml ]; then
    unlink /etc/axiom-yml
fi
if [[ $DEVICE == 'micro' ]]; then
    ln -s /opt/axiom-firmware/software/nctrl/camera_descriptions/micro_r2/micro_r2.yml /etc/axiom-yml
else
    ln -s /opt/axiom-firmware/software/nctrl/camera_descriptions/beta/beta.yml /etc/axiom-yml
fi
cp software/configs/nctrl.service /etc/systemd/system/
systemctl enable nctrl

# install the webui
(cd software/webui; yarn install --production)
unlink software/webui/nctrl_mountpoint
ln -s /axiom-api/ software/webui/nctrl_mountpoint
cp software/configs/webui.service /etc/systemd/system/
systemctl enable webui


# configure lighttpd
cp -f software/configs/lighttpd.conf /etc/lighttpd/lighttpd.conf
systemctl enable lighttpd

# configure NetworkManager
cp -f software/configs/Hotspot.nmconnection /etc/NetworkManager/system-connections/
chmod 600 /etc/NetworkManager/system-connections/Hotspot.nmconnection
cp -f software/configs/iptables.sh /etc/NetworkManager/dispatcher.d/
chmod 700 /etc/NetworkManager/dispatcher.d/iptables.sh
cp -f software/configs/dnsmasq-shared-hosts.conf /etc/NetworkManager/dnsmasq-shared.d/hosts.conf
systemctl enable NetworkManager

# build raw2dng
cdmake software/misc-tools-utilities/raw2dng

# copy prebuilt fpga binaries & select the default binary
# also convert the bitstreams to the format expected by the linux kernel
mkdir -p /opt/bitstreams/
for bit in peripherals/bitstreams/*.bit; do
    NAME=$(basename $bit)
    ln -sf $(pwd)/$bit /opt/bitstreams
    ./makefiles/in_chroot/to_raw_bitstream.py -f /opt/bitstreams/$NAME /opt/bitstreams/"$(basename ${NAME%.bit}).bin"
    ln -sf /opt/bitstreams/"${NAME%.bit}.bin" /lib/firmware
done

if [[ $DEVICE == 'micro' ]]; then
  ln -sf /opt/bitstreams/micro_main.bin /lib/firmware/axiom_fpga_main.bin
else
  ln -sf /opt/bitstreams/cmv_hdmi3_dual_60.bin /lib/firmware/axiom_fpga_main.bin
fi

cp software/scripts/axiom_start.service /etc/systemd/system/
if [[ $DEVICE == 'micro' ]]; then
    systemctl disable axiom_start
else
    systemctl disable axiom_start
fi

echo "i2c-dev" > /etc/modules-load.d/i2c-dev.conf
echo "ledtrig-heartbeat" > /etc/modules-load.d/ledtrig.conf

# configure bash & vim
cp software/configs/apertus.sh /etc/profile.d/apertus.sh
cp software/configs/bashrc /etc/bash.bashrc
cp software/configs/vimrc /etc/vimrc

# install overlay, if any is found
if [ -d overlay ]; then
    rsync -aK --exclude install.sh overlay/ /
    if [ -f overlay/install.sh ]; then
        bash overlay/install.sh
    fi
fi

# copy the full disclaimer to its place
DISCLAIMER_FILE=/etc/DISCLAIMER.txt
cp DISCLAIMER.txt $DISCLAIMER_FILE

# install /etc/issue generating service
cp software/configs/gen_etc_issue.service /etc/systemd/system/
systemctl enable gen_etc_issue.service

# install kernel messages disabling system service
cp software/configs/disable_kernel_messages.service /etc/systemd/system/
systemctl enable disable_kernel_messages.service

# systemd is being stupid:
sed -i 's/kernel.sysrq = 16/kernel.sysrq = 1/' /usr/lib/sysctl.d/50-default.conf

# generate the motd and indicate software version
echo -e "\033[97m$(tput bold)$(figlet "AXIOM ${DEVICE^}")  $(tput sgr0)" > /etc/motd
echo "Software version $(git describe --always --abbrev=8 --dirty). Last updated on $(date +"%d.%m.%y %H:%M UTC")" >> /etc/motd
echo "To update, run \"axiom-update\"." >> /etc/motd
echo "" >> /etc/motd
echo "$(tput setaf 1)This device and its software is provided without warranty of merchantability or fitness for any particular purpose. Be careful when doing anything potentially harmful to your camera. See full disclaimer in $DISCLAIMER_FILE $(tput sgr0)" >> /etc/motd
echo "" >> /etc/motd

# generate fstab
echo "PARTUUID=f37043ff-02 /     btrfs defaults,rw,subvol=@user 0 0"  > /etc/fstab
echo "PARTUUID=f37043ff-01 /boot vfat  defaults,rw              0 0" >> /etc/fstab

# Generate file list for integrity check
VERIFY_DIRECTORIES="/etc /usr /opt"
HASH_LOCATION="/opt/integrity_check"
mkdir -p $HASH_LOCATION
# delete hashes so they aren't included in the new files list
rm -f $HASH_LOCATION/hashes.txt; rm -f $HASH_LOCATION/files.txt
find $VERIFY_DIRECTORIES -type f > $HASH_LOCATION/files.txt
# also hash file list
echo "$HASH_LOCATION/files.txt" >> $HASH_LOCATION/files.txt
hashdeep -c sha256 -f $HASH_LOCATION/files.txt > $HASH_LOCATION/hashes.txt

echo "axiom-update finished. Software version is now $(git describe --always --abbrev=8 --dirty)."
