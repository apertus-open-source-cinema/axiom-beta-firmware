#!/bin/bash
set -xeuo pipefail

GADGET_PATH="/sys/kernel/config/usb_gadget/g1"

modprobe libcomposite
mkdir $GADGET_PATH

echo 0x1209 > $GADGET_PATH/idVendor
echo 0x0001 > $GADGET_PATH/idProduct
mkdir $GADGET_PATH/strings/0x409/  # us amarican strings are the most often used ones
echo "Apertus" > $GADGET_PATH/strings/0x409/manufacturer
echo "AXIOM $(cat /etc/hostname)" > $GADGET_PATH/strings/0x409/product
echo "firmware v2" > $GADGET_PATH/strings/0x409/serialnumber

mkdir $GADGET_PATH/configs/c.1
mkdir $GADGET_PATH/functions/ecm.usb0
ln -s $GADGET_PATH/functions/ecm.usb0/ $GADGET_PATH/configs/c.1/
echo ci_hdrc.0 > $GADGET_PATH/UDC

ip link set up dev usb0
nmcli device set usb0 autoconnect yes managed yes