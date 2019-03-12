#!/bin/bash
#This script is only for creating a SDcard with custom kernel.
#The script needs about a half hour
#start at path: ~/Documents/git/RaspberryKernelCrosscompile/
#start like :
# cd ~/Documents/git/RaspberryKernelCrosscompile/
# bash ~/Documents/git/${REPOSITORY}/KernelCrossCompile/kernel_img_push-to-SDCard.sh [help|-h|compile]



###########
# INSTALL #
###########
# sudo apt-get install debootstrap curl git qemu-user-static bc
#
SCRIPT_DIR=$(dirname $(readlink -f $0))
sourcefile="${SCRIPT_DIR}/../rpi_config.cfg"
source ${sourcefile}

startingDir=${PWD}
linuxdir=${PWD}/linux
config_file=${startingDir}/mod_image.cfg
raspirootmount=${PWD}/mnt
raspidirext4=${raspirootmount}
raspidirfat32=${raspirootmount}/boot
raspiloop=/dev/loop2
raspibootloop=${raspiloop}p1
raspirootloop=${raspiloop}p2

#######################Compile##########################
get_image_url(){
    # list directory and grep all href links
    DIR_NAME=$(curl -s "https://downloads.raspberrypi.org/raspbian_lite/images/" | sed -n 's/.*href="\([^"]*\).*/\1/p' | tail -1)
    # sort all by size, asc
    FILE_NAME=$(curl -s "https://downloads.raspberrypi.org/raspbian_lite/images/${DIR_NAME}?C=S;O=A" | sed -n 's/.*href="\([^"]*\).*/\1/p' | tail -1)
    DOWNLOAD_URL="https://downloads.raspberrypi.org/raspbian_lite/images/${DIR_NAME}${FILE_NAME}"
    ret_val=(
             ${DOWNLOAD_URL}
             ${FILE_NAME/.zip/}
            )
    printf "%s\n" "${ret_val[@]}"
}

resize_pi() { # argument in MB
if [[ -n ${input//[0-9]/} ]]; then
  echo "Contains letters! Musst be the added imagesize in MB"
fi
if [ "$1" -gt "1024" ]; then
  echo "to big size to add. unit is MB"
fi
echo "Add $1 MB to image."
# resize root partition of image
blocksize=512
bytes=$(du --bytes "${startingDir}/${MOD_IMAGE_NAME}"| cut -f1)
append=$((1024*1024* $1/$blocksize)) # adding 10MB to image
dd if=/dev/zero of="${startingDir}/${MOD_IMAGE_NAME}" obs=$blocksize count=$append seek=$(($bytes/$blocksize))

sudo losetup --partscan "${raspiloop}" "${startingDir}/${MOD_IMAGE_NAME}"
if [ $? -ne 0 ]; then echo "not successful losetup, exit."; return 1 ;fi
sudo e2fsck -f "${raspirootloop}"
start_block=$(partx -sgn 2 "${startingDir}/${MOD_IMAGE_NAME}" | cut -d " " -f3)
# http://elinux.org/RPi_Resize_Flash_Partitions#Manually_resizing_the_SD_card_on_Raspberry_Pi
# https://superuser.com/questions/332252/creating-and-formating-a-partition-using-a-bash-script
# to create the partitions programatically (rather than manually)
# we're going to simulate the manual input to fdisk
# The sed script strips off all the comments so that we can 
# document what we're doing in-line with the actual commands
# Note that a blank line (commented as "defualt" will send a empty
# line terminated with a newline to take the fdisk default.
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | sudo fdisk ${raspiloop}
  p # primary partition
  d # delete
  2 # partition number 2
  n # new partition
  p # primary partition
  2 # partion number 2
  $start_block # default, start immediately after preceding partition
    # default, extend partition to end of disk
  p # print the in-memory partition table
  w # write the partition table
  q # and we're done
EOF
# resize ext4
sudo resize2fs ${raspirootloop}
# check fs
sudo e2fsck -fy ${raspirootloop}
sudo losetup -d ${raspiloop}
# Save a copy of image before updating Software on it.
#cp "${startingDir}/${MOD_IMAGE_NAME}" "${startingDir}/${MOD_IMAGE_NAME}_backup.img"
}

chroot_pi() {
  mount_pi mount
  if [ $? -ne 0 ]; then echo "not successful mounted, unmount."; mount_pi umount; return 1 ;fi
  echo "chroot-dir: $raspirootmount. "
  #If you use systemd, it will kill your system because autofs mounts
  #under /dev created by systemd can't be bind mounted; well, they can,
  #they are just broken and umountable, and all the processes in your
  #system will slowly enter D state!
  # https://raspberrypi.stackexchange.com/questions/855/is-it-possible-to-update-upgrade-and-install-software-before-flashing-an-image
  #sudo apt-get install -y binfmt-support qemu qemu-user-static unzip
  #sudo apt-get install -y binutils debootstrap
  sudo cp /usr/bin/qemu-arm-static ${raspirootmount}/usr/bin/
  sudo mv ${raspirootmount}/etc/network/interfaces ${raspirootmount}/etc/network/interfaces.old
  sudo mv ${raspirootmount}/etc/resolv.conf ${raspirootmount}/etc/resolv.conf.old
  sudo cp /etc/network/interfaces ${raspirootmount}/etc/network/interfaces
  sudo cp /etc/resolv.conf ${raspirootmount}/etc/resolv.conf
  sudo sed -i 's/^/#/' ${raspirootmount}/etc/ld.so.preload
  #sudo mount --rbind /dev     ${raspirootmount}/dev
  #sudo mount --bind /dev     ${raspirootmount}/dev
  #sudo mount --bind /dev/mqueue     ${raspirootmount}/dev/mqueue
  #sudo mount --bind /dev/hugepages     ${raspirootmount}/dev/hugepages
  #sudo mount --bind /dev/shm     ${raspirootmount}/dev/shm
  #sudo mount --bind /dev/pts     ${raspirootmount}/dev/pts
  sudo mount -t proc none     ${raspirootmount}/proc
  sudo mount -o bind /sys     ${raspirootmount}/sys
  
  packages=$(grep "APT_GET_INSTALL " "$INSTALL_SCRIPT" | sed 's/APT_GET_INSTALL//' | sed "s/#.*//" | tr -d '\n')
  install_str="apt-get install -y $packages" # --no-install-recommends 
  echo "You need to install:"
  echo $install_str
  
  # chroot directly in this image.
  sudo chroot ${raspirootmount} /bin/bash -x << EOF
apt-get update
apt-get -y upgrade
apt-get clean
eval ${install_str}
apt-get clean
pip3 install wiringpi2
pip3 install RPi.GPIO
# Do console autologin for user pi!
systemctl set-default multi-user.target
ln -fs /etc/systemd/system/autologin@.service /etc/systemd/system/getty.target.wants/getty@tty1.service

echo "to finish script, type 'exit'"
EOF
  # to finish chroot, type 'exit'
  sudo chroot ${raspirootmount}
  # finish
  echo "finished chroot."
  # kill remaining processes after quitting chroot
  pids_to_kill=$(sudo lsof +tD ${raspirootmount})
  if [ ! -z "$pids_to_kill" ]; then
    sudo kill -9 $pids_to_kill
  fi
  echo "chroot-dir: $raspirootmount. "
  sudo sed -i 's/^.//' ${raspirootmount}/etc/ld.so.preload
  sudo rm ${raspirootmount}/usr/bin/qemu-arm-static
  sudo rm ${raspirootmount}/etc/network/interfaces
  sudo rm ${raspirootmount}/etc/resolv.conf
  sudo mv ${raspirootmount}/etc/network/interfaces.old ${raspirootmount}/etc/network/interfaces
  sudo mv ${raspirootmount}/etc/resolv.conf.old ${raspirootmount}/etc/resolv.conf
  #sudo umount ${raspirootmount}/dev/mqueue
  #sudo umount ${raspirootmount}/dev/hugepages
  #sudo umount ${raspirootmount}/dev/shm
  #sudo umount ${raspirootmount}/dev/pts
  #sudo umount ${raspirootmount}/dev
  sudo umount ${raspirootmount}/proc
  sudo umount ${raspirootmount}/sys
  mount_pi umount
}

check_installed_progs() {
DEPS=0
if [ ! -f `which debootstrap` ] ; then
	echo '(!!)  Missing dependency: debootstrap'
	DEPS="${DEPS}1"
fi
if [ ! -f `which qemu-debootstrap` ] ; then
	echo '(!!)  Missing dependency: qemu-debootstrap (package: qemu-user-static)'
	DEPS="${DEPS}1"
fi
if [ ! -f `which curl` ] ; then
	echo '(!!)  Missing dependency: curl'
	DEPS="${DEPS}1"
fi
if [ ! -f `which git` ] ; then
	echo '(!!)  Missing dependency: git'
	DEPS="${DEPS}1"
fi
if [ ! -f `which qemu-arm-static` ] ; then
	echo '(!!)  Missing dependency: qemu-user-static (package: qemu-user-static)'
	DEPS="${DEPS}1"
fi
if [ ! -f `which bc` ] ; then
	echo '(!!)  Missing dependency: bc'
	DEPS="${DEPS}1"
fi

if [ "$DEPS" != 0 ] ; then
  echo && echo 'Cannot continue, please install the missing dependencies.'
  echo "check: ldd tools/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian/bin/arm-linux-gnueabihf-as"
  echo "sudo apt-get install lib32z1"
  echo
  exit 1
fi
}

mount_pi() {
if [ "$1" == "mount" ]; then
  error=0
  sudo losetup --partscan "${raspiloop}" "${startingDir}/${MOD_IMAGE_NAME}"
  if [ $? -ne 0 ]; then echo "Failed on losetup"; return 1 ;fi
  sudo e2fsck -fy "${raspirootloop}"
  #mount working copy
  mkdir -p ${raspirootmount}
  if [ $? -ne 0 ]; then echo "Failed on mkdir /" ;fi
  mkdir -p ${raspirootmount}/boot
  if [ $? -ne 0 ]; then echo "Failed on mkdir /boot" ;fi
  sudo mount ${raspirootloop} ${raspirootmount}
  if [ $? -ne 0 ]; then echo "Failed on mount /"; read -p "Play 1."; return 1 ;fi
  sudo mount ${raspibootloop} ${raspirootmount}/boot
  if [ $? -ne 0 ]; then echo "Failed on mount /boot"; read -p "Play 1."; return 1 ;fi
  lsblk | grep "loop"
  return 0

elif [ "$1" == "umount" ]; then
  sudo umount -f ${raspirootmount}/boot
  if [ $? -ne 0 ]; then echo "Failed on umount /boot"; fi
  sudo umount -f ${raspirootmount}
  if [ $? -ne 0 ]; then echo "Failed on umount /"; fi
  sudo losetup --detach ${raspiloop}
  if [ $? -ne 0 ]; then echo "Failed on rm losetup"; fi
  #cleanup
  sudo rm -rf ${raspirootmount}
  lsblk | grep "loop"
  return 0
fi
}


compile(){
# compile like:
# https://www.raspberrypi.org/documentation/linux/kernel/building.md
# make array
# https://stackoverflow.com/questions/25291347/how-to-return-an-array-from-a-script-in-bash
readarray -t url < <(get_image_url)
echo "Url[0]: ${url[0]}"
echo "Url[1]: ${url[1]}"
echo "${startingDir}/${url[1]}.img"
if [[ (( "${url[1]}" -eq "" )) && (( -s "${startingDir}/${IMAGE_NAME}" )) ]] || [[ -s "${startingDir}/${url[1]}.img" ]];then
  # probably non internet connection, but img file is already there
  # use data from config file.
  echo "Use image file from disk."
  if [[ (( "${url[1]}.img" -ne "${IMAGE_NAME}" )) && (( "${url[1]}" -ne "" )) ]]; then
    # update name, if IMAGE_NAME is wrong.
    sed -i "0,/IMAGE_NAME=*/{s/IMAGE_NAME.*/IMAGE_NAME=${image_name}.img/}" "$config_file"
    source "$config_file"
  fi
elif [[ "${url[1]}" -ne "" ]] && [[ ! -s "${startingDir}/${url[1]}.img" ]]; then
  echo "Downloading Raspbian Jessie"
  image_name=${url[1]}
  # replace only first occurence
  sed -i "0,/IMAGE_NAME=*/{s/IMAGE_NAME.*/IMAGE_NAME=${image_name}.img/}" "$config_file"
  source "$config_file"
  # wget https://downloads.raspberrypi.org/raspbian_latest
  echo "  curl -L ${url[0]} -o ${startingDir}/raspbian_latest"
  curl -L ${url[0]} -o ${startingDir}/raspbian_latest
  unzip ${startingDir}/raspbian_latest
  rm ${startingDir}/raspbian_latest
else
  echo "There was an error receiving the newest image file."
  return 1
fi

cd ${startingDir}
echo "start kernel update."
echo "receive git repos"
git clone --depth=1 https://github.com/raspberrypi/tools
cd tools
git pull
cd ..
git clone --depth=1 https://github.com/raspberrypi/linux --branch ${kernel_branch}
cd linux
git fetch origin
git checkout ${kernel_branch}
git pull
cd ..
git clone --depth=1 https://github.com/kadamski/i2c-gpio-param
cd i2c-gpio-param
git pull
cd ..

if [[ $(uname -m) -eq "x86_64" ]]; then
    # 64 Bit system
    COMPILER=${PWD}/tools/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian-x64/bin
elif [[ $(uname -m) -eq "" ]]; then
    # 32 Bit system
    COMPILER=${PWD}/tools/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian/bin
else
    echo "No compiler for this architecture available."
    exit 1
fi

cd linux
make -j5 ARCH=arm CROSS_COMPILE=${COMPILER}/arm-linux-gnueabihf- bcm2709_defconfig
#Change Config
cat <<'EOT' | tee -a .config
CONFIG_I2C_GPIO=m
CONFIG_PPS=y
CONFIG_PPS_DEBUG=m
CONFIG_PPS_CLIENT_KTIMER=n
CONFIG_NTP_PPS=m
CONFIG_PPS_CLIENT_LDISC=y
CONFIG_PPS_CLIENT_GPIO=y
CONFIG_GPIO_SYSFS=y
EOT
make -j5 ARCH=arm CROSS_COMPILE=${COMPILER}/arm-linux-gnueabihf- prepare
make -j5 ARCH=arm CROSS_COMPILE=${COMPILER}/arm-linux-gnueabihf- zImage modules dtbs
cd ../i2c-gpio-param
#do a Makefile backup
cp Makefile Makefile.old
#Change Kernelsources dir
sed -i "0,/KDIR/ { /KDIR/ s/^/#/;}" Makefile
sed -i "1 a KDIR ?= ${linuxdir}" Makefile
make -j5 ARCH=arm CROSS_COMPILE=${COMPILER}/arm-linux-gnueabihf-

cd ${linuxdir}

#read -p "Press [Enter] key to start copying the new kernel."

#Make a working copy
rm "${startingDir}/${MOD_IMAGE_NAME}"
cp "${startingDir}/${IMAGE_NAME}" "${startingDir}/${MOD_IMAGE_NAME}"

mount_pi mount

sudo make -j5 ARCH=arm CROSS_COMPILE=${COMPILER}/arm-linux-gnueabihf- INSTALL_MOD_PATH=${raspirootmount} modules_install
sudo cp ${raspirootmount}/boot/$KERNEL.img ${raspirootmount}/boot/$KERNEL-backup.img
sudo ${linuxdir}/scripts/mkknlimg ${linuxdir}/arch/arm/boot/zImage ${raspirootmount}/boot/${KERNEL}-new.img
sudo cp ${linuxdir}/arch/arm/boot/dts/*.dtb ${raspirootmount}/boot/
sudo cp ${linuxdir}/arch/arm/boot/dts/overlays/*.dtb* ${raspirootmount}/boot/overlays/
sudo cp ${linuxdir}/arch/arm/boot/dts/overlays/README ${raspirootmount}/boot/overlays/


cat <<EOF | sudo tee -a ${raspirootmount}/boot/config.txt
# 'dtoverlay=' will supress loading sense hat eeproms
# https://www.raspberrypi.org/documentation/configuration/device-tree.md Kap. 3.4
dtoverlay=
#dtdebug=1
kernel=${KERNEL}-new.img
# i2c is an alias for i2c_arm
dtparam=i2c_arm=on
dtparam=i2c1=on
dtparam=i2c1_baudrate=400000
dtoverlay=pps-gpio,gpiopin=4
# https://github.com/cyoung/stratux/issues/393#issuecomment-212393947
#dtoverlay=pi3-miniuart-bt
EOF

cat <<'EOT' | sudo tee ${raspirootmount}/etc/modules
# /etc/modules: kernel modules to load at boot time.
#
# This file contains the names of kernel modules that should be loaded
# at boot time, one per line. Lines beginning with "#" are ignored.
# Parameters can be specified after the module name.

snd-bcm2835
i2c-dev
#spi-bcm2835
i2c-bcm2708 #baudrate=400000
#default i2c is normal i2c-pins
#i2c-gpio-param busid=0 sda=2 scl=3 udelay=3x
EOT

#Because the GPS Module writes so much out, raspberry thinks, that there is a sysrequest
#[  245.174107] sysrq: SysRq : HELP : loglevel(0-9) reboot(b) crash(c) terminate-all-tasks(e) memory-full-oom-kill(f) kill-all-tasks(i) thaw-filesystems(j) sak(k) show-backtrace-all-active-cpus(l) show-memory-usage(m) nice-all-RT-tasks(n) poweroff(o) show-registers(p) show-all-timers(q) unraw(r) sync(s) show-task-states(t) unmount(u) show-blocked-tasks(w) dump-ftrace-buffer(z) 

cat <<'EOT' | sudo tee ${raspirootmount}/boot/cmdline.txt
dwc_otg.lpm_enable=0 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline fsck.mode=force fsck.repair=yes rootwait
EOT

# Update Nov2016 : Disabled SSH by default. -> Enable ssh by generating file /boot/ssh.
sudo touch "${raspirootmount}/boot/ssh"

#sudo sed -i "/T0:23:/s/^/#/;" ${raspirootmount}/etc/inittab
# disable x on startup: -> headless mode
sudo rm ${raspirootmount}/lib/systemd/system/default.target
sudo ln -s multi-user.target ${raspirootmount}/lib/systemd/system/default.target

# autologin user
sudo mkdir -pv ${raspirootmount}/etc/systemd/system/getty@tty2.service.d
cat <<EOF | sudo tee ${raspirootmount}/etc/systemd/system/getty@tty2.service.d/autologin.conf
[Service]
ExecStart=-/sbin/agetty --autologin ${PI_USER} --noclear %I 38400 linux
EOF

#####################################################
cat <<'EOFF' | sudo tee ${raspirootmount}/etc/profile.d/raspi-config.sh >/dev/null
#!/bin/bash
#if [[ $EUID -ne 0 ]]; then
#   echo "This script must be run as root" 1>&2
#   exit 1
#fi
#first boot: expand filesystem
sudo systemctl disable lightdm.service
sudo systemctl set-default multi-user.target
sudo raspi-config --expand-rootfs
if [ -e /etc/profile.d/raspi-config.sh ]; then
  cat <<'EOF' | sudo tee /etc/profile.d/install.sh
#!/bin/bash
# second boot install all
#if [[ $EUID -ne 0 ]]; then
#   echo "This script must be run as root" 1>&2
#   exit 1
#fi
echo "Start install."
sleep 5

_CONFIG_

do_error() {
if ! [ $1 -eq 0 ]; then
  echo "error: exit: "
  echo $1
  sleep 25
  sudo shutdown 0
fi
}

#sudo apt-get update
#sudo apt-get -y install git
rm -rf "${GIT_DIR}"
mkdir "${GIT_DIR}"
chmod -R 777 "${GIT_DIR}"
chown -R pi:pi "${GIT_DIR}"
cd "${GIT_DIR}"
pwd
echo "start GIT clone."
GIT_HTTPS_STRING=$(GET_GIT_HTTPS_STRING)
echo "git clone ${GIT_HTTPS_STRING}"
#su pi -c "git clone ${GIT_HTTPS_STRING}"
git clone --depth=1 ${GIT_HTTPS_STRING} --branch ${GIT_MAIN_BRANCH}
do_error $?
echo "Start installscript"
#su pi -c "bash ${GIT_DIR}/${GIT_REPO}/install.sh"
bash ${GIT_DIR}/${GIT_REPO}/install.sh
do_error $?
echo "Finished installation"
#only remove install.sh, if install was sucessful
if [ -e /etc/profile.d/install.sh ]; then
  #sudo sed -i /etc/inittab \
  #  -e "s/^#\(.*\)#\s*RPICFG_TO_ENABLE\s*/\1/" \
  #  -e "/#\s*RPICFG_TO_DISABLE/d"
  sudo rm -f /etc/profile.d/install.sh
  sleep 10
  sudo reboot
fi
EOF
  sudo chmod 755 /etc/profile.d/install.sh
  sudo chown root:root /etc/profile.d/install.sh
  sudo rm -f /etc/profile.d/raspi-config.sh
fi
#if [[ $EUID -ne 0 ]]; then
#   echo "This script must be run as root" 1>&2
#   exit 1
#fi
sleep 5
sudo reboot
EOFF

echo "#############################################################"
#ADD GIT Config from sourced file
start_marker="####################GIT_DATA--start--#######################"
end_marker="#####################GIT_DATA--end--########################"
#https://stackoverflow.com/questions/4857424/extract-lines-between-2-tokens-in-a-text-file-using-bash
CONFIG_GIT_DATA=$(sed -n "/${start_marker}/{:a;n;/${end_marker}/b;p;ba}" ${sourcefile})
#https://stackoverflow.com/questions/9576031/substituting-a-single-line-with-multiple-lines-of-text
cat <<EOF >${startingDir}/temp.txt
${CONFIG_GIT_DATA}
EOF
sudo sed -i -e "/_CONFIG_/r ${startingDir}/temp.txt" -e "//d" ${raspirootmount}/etc/profile.d/raspi-config.sh
rm ${startingDir}/temp.txt

cat ${raspirootmount}/etc/profile.d/raspi-config.sh

sudo chmod 755 ${raspirootmount}/etc/profile.d/raspi-config.sh
sudo chown root:root ${raspirootmount}/etc/profile.d/raspi-config.sh
#####################################################

mount_pi umount

}

#####################Compress Image########################
compress_image() {
  echo "commpressing image."
  gzip -c "${startingDir}/${MOD_IMAGE_NAME}" > "${startingDir}/${MOD_IMAGE_NAME}.gz" 
  echo "Compressed image is now: ${startingDir}/${MOD_IMAGE_NAME}.gz"
}

#####################Flash SDCard########################
flash_SDCARD()
{
  if [ ! -f "${startingDir}/${MOD_IMAGE_NAME}" ]; then
    # no image present, abort
    echo "No Image for transfer is present."
    return 1
  fi
  lsblk
  echo "Will use mmcblk0 as SDCard"
  read -p "Press [ENTER] to write image to SDCard."

  test_=`lsblk|grep "mmcblk0"|wc -l`
  if (( test_ > 0 )); then
    echo "SDCard is present."
  else
    echo "SDCard is NOT present, please insert and retry"
    return
  fi
  #install pv if not installed
  command -v pv >/dev/null 2>&1 || {  sudo apt-get install pv; }
  sudo umount /dev/mmcblk0p*
  echo "starting upload to sdcard"
  #sudo dd bs=4M if=${startingDir}/${MOD_IMAGE_NAME} of=/dev/mmcblk0
  #dd bs=4M if=${startingDir}/${MOD_IMAGE_NAME} | pv | sudo dd bs=4M of=/dev/mmcblk0
  pv "${startingDir}/${MOD_IMAGE_NAME}" | sudo dd bs=4M of=/dev/mmcblk0
  echo "now starting to sync"
  time sync
  echo "finished copying to sdcard."
  read -p "Remove SDcard and then press [Enter] key."
}

##################help#################################
help_()
{
  echo "Usage:"
  echo "cd [FOLDER_to_Compile_Kernel]"
  echo "bash [Path_to_File]/kernel_img_push-to-SDCard.sh [help|compile|compress|flash|update_sw|check|resize|all]"
}
###############MAIN####################################

if [ ! -f "$config_file" ]; then
# init conifig file
cat <<'EOF' >"$config_file"
KERNEL="kernel7"
kernel_branch="rpi-4.5.y"
mod_extension="_custom-kernel"
IMAGE_NAME=""
MOD_IMAGE_NAME="${IMAGE_NAME//.img/}${mod_extension}${kernel_branch}.img"
EOF
fi
# get config file
source "$config_file"

if [ "$1" == "help" ] || [ "$1" == "-h" ]; then
  help_

elif [ "$1" == "check" ]; then
  check_installed_progs
  echo "check was successful."

elif [ "$1" == "resize" ]; then
  resize_pi 50

elif [ "$1" == "update_sw" ]; then
  check_installed_progs
  chroot_pi

elif [ "$1" == "compile" ]; then
  check_installed_progs
  compile

elif [ "$1" == "compress" ]; then
  compress_image

elif [ "$1" == "all" ]; then
  check_installed_progs
  compile
  if [ $? -ne 0 ]; then echo "Failed while compiling"; exit 1 ;fi
  resize_pi 650
  chroot_pi
  #compress_image
  flash_SDCARD

elif [ "$1" == "flash" ] || [ "$1" == "" ]; then
  flash_SDCARD

else
  help_

fi


