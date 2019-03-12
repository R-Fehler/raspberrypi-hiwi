#!/bin/bash

# Installing raspberry pi
#
#
#

SCRIPT_DIR=$(dirname $(readlink -f $0))
RPI_CFG_PATH="${SCRIPT_DIR}/../rpi_config.cfg"
INSTALLER_CFG_PATH="${SCRIPT_DIR}/../systemfiles/installer_config.cfg"
# enable firmware flashing/update while installing with "true"

echo "Script is in ${SCRIPT_DIR} ."
source ${INSTALLER_CFG_PATH}
source ${RPI_CFG_PATH}
VARIABLES=$(grep '^[[:upper:]].*=' ${RPI_CFG_PATH} | cut -d= -f1)
# export all variables automatically, but only them with capital letters at the beginning of the line
export $VARIABLES
# or save all variables in one file
#VARIABLES="\\\$${VARIABLES//[[:space:]]/,\\$}"

APT_GET_INSTALL() {
# installation will actualy be done while creating image
echo "installation of apt-packages will be done while creating image."
#sudo apt-get install -y --no-install-recommends $@
}

# change for using OBD2
install_OBD=0

custom_kernel_check () {
    #check if there is a custom kernel command in /boot/config.txt
    grep -q "kernel=.*-new.img" /boot/config.txt
    if [ $? -eq 0 ]; then
        echo "true"
    else
        echo "false"
    fi
}

# use: writeout_file pathname [nosubst append]
writeout_file () {
    # options for tee
    local option=""
    if [[ "${@:2}" == *"append"* ]];then
        option="$option -a"
    fi
    if [[ "${@:2}" == *"nosubst"* ]];then
        # dont substitute variables
        echo "########################## $1 ##########################"
        cat ${BASE_INSTALL_SOURCE_DIR}/$(basename $1) | sudo tee ${option} $1
    else
        # substitute variables. this requires, that all necessary variables are exported.
        echo "########################## $1 ##########################"
        #envsubst "${VARIABLES}" < ${BASE_INSTALL_SOURCE_DIR}/$(basename $1) | sudo tee ${option} $1
        # use exported variables
        #envsubst < ${BASE_INSTALL_SOURCE_DIR}/$(basename $1) | sudo tee ${option} $1

        # this perl snippet will do replacement of variables depending on exported variables, but respect escaped Variables.
        # https://stackoverflow.com/questions/2914220/bash-templating-how-to-build-configuration-files-from-templates-with-bash/25019138#25019138
        perl -pe 's;(\\*)(\$([a-zA-Z_][a-zA-Z_0-9]*)|\$\{([a-zA-Z_][a-zA-Z_0-9]*)\})?;substr($1,0,int(length($1)/2)).($2&&length($1)%2?$2:$ENV{$3||$4});eg' ${BASE_INSTALL_SOURCE_DIR}/$(basename $1) | sudo tee ${option} $1
    fi
}

base_install () {
###################Things for a better environment########################
#set password
sudo chpasswd <<<"${PI_USER}:${PI_PW}"

sudo apt-get update
sudo apt-get -y upgrade
APT_GET_INSTALL screen htop expect git cifs-utils smbclient rsync # network-manager
# "\e[5~": history-search-backward
# "\e[6~": history-search-forward
sudo sed -i 's_# "\\e\[5~": h_"\\e\[5~": h_' /etc/inputrc
sudo sed -i 's_# "\\e\[6~": h_"\\e\[6~": h_' /etc/inputrc

# locale:
# http://www.jaredwolff.com/blog/raspberry-pi-setting-your-locale/
# generate locale
sudo sed -i 's|# \(.*en_US.UTF-8.*\)|\1|' /etc/locale.gen
sudo locale-gen "en_US.UTF-8"
# set locale
sudo update-locale en_US.UTF-8
# set /etc/environment hard to locale
writeout_file "/etc/environment" nosubst

# Force TimeZone UTC
sudo rm /etc/localtime 
sudo ln -s /usr/share/zoneinfo/UTC /etc/localtime

writeout_file "/home/${PI_USER}/.bash_profile" append nosubst

echo "###############################################################################"
echo "################################NETWORK########################################"
echo "###############################################################################"
# Name hostname
sudo sed -i "s/raspberrypi/${HOSTNAME}/" /etc/hosts
#WLAN WPA supplicant
#Roaming:
#https://www.debuntu.org/how-to-wifi-roaming-with-wpa-supplicant/
writeout_file "/etc/wpa_supplicant/wpa_supplicant.conf"
writeout_file "/etc/network/interfaces"

# Link IMU ini file
sudo ln -s "${REPO_DIR}/systemfiles/LSM9DS1.ini" "${REPO_DIR}/../LSM9DS1.ini"
sudo chmod -w "${REPO_DIR}/systemfiles/LSM9DS1.ini"

# RC.local startup file
writeout_file "/etc/rc.local"
}

network_install() {
echo "###############################################################################"
echo "###############################Samba###########################################"
echo "###############################################################################"
#http://jankarres.de/2013/11/raspberry-pi-samba-server-installieren/
#ollen keinen server, sondern client
#http://geeks.noeit.com/mount-an-smb-network-drive-on-raspberry-pi/

APT_GET_INSTALL cifs-utils #samba samba-common-bi

#Configure Samba share
writeout_file "/etc/.smbcredentials"
sudo chmod 600 /etc/.smbcredentials

#generate mountpoint
sudo mkdir -p ${SAMBA_MOUNT_DIR}

#Add samba entry in fstab
writeout_file "/etc/fstab" append
}

imu_logging_install() {
#//fast-lff-vm05.fast.kit.edu/jh_ma_data/ /media/localdate cifs credentials=/etc/.smbcredentials,noauto,_netdev,sec=ntlm 0 0
echo "###############################################################################"
echo "##############################Logging##########################################"
echo "###############################################################################"
sudo mkdir -p $LOGGINGDIRECTORY
sudo chown -R $PI_USER:$PI_USER $LOGGINGDIRECTORY
APT_GET_INSTALL python3-smbus python3 librtimulib-utils librtimulib7 python3-rtimulib pbzip2 python3-pip cmake python3-serial i2c-tools python3-dev
writeout_file "/etc/systemd/system/${SENSORRECORDER_SYSTEMD_SERVICE}"
sudo systemctl enable ${SENSORRECORDER_SYSTEMD_SERVICE}
sudo systemctl daemon-reload
srv=(${SENSORRECORDER_SYSTEMD_SERVICE/./ })
sudo systemctl status $srv

if [ "$install_OBD" == "1" ]; then
echo "###############################################################################"
echo "#################################Packages for OBD##############################"
echo "###############################################################################"

echo "OBD: Nothing to do"

fi

echo "###############################################################################"
echo "#################################GPS###########################################"
echo "###############################################################################"

APT_GET_INSTALL gpsd gpsd-clients

#https://learn.adafruit.com/adafruit-ultimate-gps-hat-for-raspberry-pi/pi-setup
sudo killall gpsd

#	configure gps before gpsd is running via udev event
#TODO does not work at the moment
#sudo sed -i "/gpsdctl/ i \ \ \ \ python3 ${GPS_CONFIG_SCRIPT}" /lib/udev/gpsd.hotplug

sudo gpsd /dev/ttyAMA0 -F /var/run/gpsd.sock
#/set GPS to 10Hz and 38400 baud
python3 ${GPS_CONFIG_SCRIPT}

echo '***********Um GPS zu testen "cgps -s" (falls timeout --> mehrmals versuchen)**********************'

#autostart gpsd on startup
writeout_file "/etc/default/gpsd" nosubst
# python3 gps3 is already installed, but should be updated.
sudo pip3 install --upgrade gps3
}

ntp_via_gps_install() {
echo "###############################################################################"
echo "################################NTP############################################"
echo "###############################################################################"

APT_GET_INSTALL ntp pps-tools libcap-dev libssl-dev ntpdate
if $CUSTOM_KERNEL_USED ; then

# http://www.catb.org/gpsd/gpsd-time-service-howto.html
# test pps with 'sudo ppstest /dev/pps0'

#Rule for Udev for pps
writeout_file "/etc/udev/rules.d/99-com.rules" append nosubst
# /etc/modules already appended while i2c installing
# here we should need to reboot normaly

#sudo rm /etc/dhcp/dhclient-exit-hooks.d/ntp
#sudo rm /etc/dhcp3/dhclient-exit-hooks.d/ntp

writeout_file "/etc/ntp.conf" nosubst
fi
}

i2c_install() {
echo "###############################################################################"
echo "###############################standard i2c####################################"
echo "###############################################################################"

# set i2c speed to 400kHz
if $CUSTOM_KERNEL_USED ; then
  #Accelerometer: We need to compile i2c-gpio-param -> GITDIR/KernelCrossCompile/kernel_img_push-to-SDCard.sh
  sudo cp ${GIT_DIR}/raspberrypi/KernelCrossCompile/i2c-gpio-param.ko /lib/modules/`uname -r`/kernel/drivers/i2c/busses/
else
  writeout_file "/boot/config.txt" append nosubst
  writeout_file "/etc/modules" append nosubst
fi

# allow non root user to use i2c
writeout_file "/etc/udev/rules.d/90-i2c.rules" nosubst
writeout_file "/etc/modprobe.d/i2c.conf" nosubst
sudo modprobe i2c-dev
sudo modprobe i2c-bcm2708

### deactivate i2c_bcm2708
#writeout_file "/etc/modprobe.d/raspi-blacklist.conf" append nosubst

# for debugging:
#i2cdetect -l
#i2cdetect -y 1
#activate accelerometer
#activate_i2c.sh add

#APT_GET_INSTALL i2c-tools python-smbus
#Use I2C without root
sudo adduser ${PI_USER} i2c
echo "Mit \"sudo i2cdetect -y 1\" müsste ein Tabelle angezeigt werden wenn alles richtig eingerichtet ist"
sudo i2cdetect -y 1
}

usv_rtc_install(){
echo "###############################################################################"
echo "################################USV and syncing via wifi#######################"
echo "###############################################################################"

cd ${GIT_DIR}
curl http://www.s-usv.de/files/software/susvd-en-2.1-systemd-all.tar.gz -o 'susv.tar.gz'
#curl http://www.s-usv.de/files/software/susvd-en-1.31-all.tar.gz -o 'susv.tar.gz'
#wget http://www.s-usv.de/files/software/susvd-en-1.31-all.tar.gz --output-document='susv.tar.gz'
deb_file=$(tar -xvzf susv.tar.gz)
rm susv.tar.gz
sudo dpkg -i $deb_file  # installed to  /opt/susvd
rm $deb_file
sudo ${SUSV_DIR}/susvd -start
TIME_TO_SHUTDOWN=5 # in sec, -1 for deactivating
#sudo ${SUSV_DIR}/susv -timer ${TIME_TO_SHUTDOWN}
sudo ${SUSV_DIR}/susv -timer -1
sudo ${SUSV_DIR}/susv -mail 1
sudo ${SUSV_DIR}/susv -auto 1 # 1: autostart on boot; standard
#sudo ${SUSV_DIR}/susv -chrgpwr <300/500/1000>
sudo ${SUSV_DIR}/susv -chrgpwr 1000 # 3Ah akku
sudo ${SUSV_DIR}/susvd -restart
#percentage of battery:
#capacity=$(sudo ${SUSV_DIR}/susv -capbat 0 | head -1 | cut -d . -f1)

#set rtc from usv.
#and set time
sudo modprobe rtc-ds1307
echo ds1307 0x68 | sudo tee /sys/class/i2c-adapter/i2c-1/new_device
# check time of ds1307
sudo hwclock --show -u
# set time
sudo hwclock --systohc -u
# check time of ds1307
sudo hwclock --show -u
#at to startup modules
# /etc/modules already appended during i2c install

#add cronjob for updateing hwclk
writeout_file "/etc/crontab" append
SUSV_MAIL=${SUSV_DIR}/scripts/mail.py
mv ${SUSV_MAIL} ${SUSV_MAIL}_backup

writeout_file "${SUSV_MAIL}" # mail.py
chmod +x ${SUSV_MAIL}

# update firmware
  curl http://www.s-usv.de/files/firmware/susv_fw_21.tar.gz -o 'susv_fw.tar.gz'
#  curl http://www.s-usv.de/files/firmware/susv_fw_132.tar.gz -o 'susv_fw.tar.gz'  
  hex_file=$(tar -xvzf susv_fw.tar.gz)
  sudo ${SUSV_DIR}/susv -flash $hex_file
  rm $hex_file
  rm susv_fw.tar.gz
}
###############################################################################
###################################### Bluetooth ##############################
###############################################################################
bt_audio_install()
{
#Installation:
echo "Installing pyaudio for python3 via apt"
APT_GET_INSTALL pulseaudio pulseaudio-utils pulseaudio-module-bluetooth bluez-tools python3-pyaudio moreutils
# moreutils for ts (timestamp)
writeout_file "/etc/bluetooth/audio.conf" nosubst

writeout_file "/etc/bluetooth/main.conf" nosubst append
echo "Allowing pulseaudio to use bluetooth:"
echo 'resample-method=trivial' | sudo tee -a /etc/pulse/daemon.conf

echo "using interrupt methode in udev:"
sudo sed -i 's/load-module module-udev-detect/load-module module-udev-detect tsched=0/g' /etc/pulse/system.pa

#load additional modules for bluetooth
writeout_file "/etc/pulse/system.pa" append nosubst
writeout_file "/etc/systemd/system/pulseaudio.service"

# allow autoconnect via a2dp
#writeout_file "/etc/pulse/default.pa" append nosubst

#rfcomm bind rfcomm0 <dev_id> 
#rfcomm unbind rfcomm0 

#pacat --record -d bluez_source.20_FA_BB_03_7C_4A | sox -t raw -r 44100 -e signed-integer -L -b 16 -c 2 - "output.wav"
# https://github.com/ev3dev/ev3dev/issues/198
# https://bitbucket.org/ehsmaes/raspberry-pi-audio-receiver-install

#restart pulseaudio
sudo systemctl daemon-reload
# enable for run on bootup
sudo systemctl enable pulseaudio.service
sudo systemctl start pulseaudio.service

echo "In die richtige Gruppe hinzufügen"
# will need normally one relogin
sudo usermod -a -G pulse,pulse-access,audio root
sudo usermod -a -G pulse,pulse-access,audio,lp $PI_USER
#or
#$ sudo usermod -a -G lp $PI_USER

writeout_file "/etc/udev/rules.d/10-bluetooth.rules" nosubst

#echo "Reload udev rules"
sudo udevadm control --reload-rules
#sudo service bluetooth restart
#sudo service udev restart
}

configureBTModul()
{
# pair Bluetooth
# syntax: bt_pair_BC127.exp Config_file_for_writing_MAC console for BC127
touch ${USER_CONFIG_FILE}
${INSTALL_BT_SCRIPT} ${USER_CONFIG_FILE} ${SERIAL_AUDIO_CONSOLE}
if [ $? -ne 0 ]; then
    return
fi

#resource file:
source ${USER_CONFIG_FILE}
#----->autostart recording on connect------
echo "Autostart Recording when Bluetooth device gets connected."
#http://www.instructables.com/id/Turn-your-Raspberry-Pi-into-a-Portable-Bluetooth-A/
writeout_file "/etc/udev/rules.d/99-input.rules"
sudo udevadm control --reload-rules

echo "RF_TTY=\"rfcomm0\"" >> ${USER_CONFIG_FILE}
writeout_file "/etc/bluetooth/rfcomm.conf"
writeout_file "/etc/systemd/system/${BT_SYSTEMD_SERVICE}" 
sudo systemctl enable ${BT_SYSTEMD_SERVICE}
sudo systemctl daemon-reload
srv=(${BT_SYSTEMD_SERVICE/./ })
sudo systemctl status $srv
}

get_samba_subdir()
{
###############################################################################
######################SAMBA SUBDIR#############################################
###############################################################################
sudo mount ${SAMBA_MOUNT_DIR}
if [ $? -ne 0 ]; then # dont got samba mounted, break
  echo "Mounting Samba share ${SAMBA_MOUNT_DIR} failed."
else # got mounted
  echo "Mounting Samba share ${SAMBA_MOUNT_DIR} successful."
  hostfile="${SAMBA_MOUNT_DIR}/config/hosts"
  # get fist line
  my_hostname="$(head -n +1 $hostfile)"
  echo "Host is $my_hostname"
  # make directory
  sudo mkdir -p "${SAMBA_MOUNT_DIR}/$my_hostname"
  # save hostname in config file
  echo "HOSTNAME=${my_hostname}" | sudo tee -a ${USER_CONFIG_FILE}
  # delete first line
  echo "$(tail -n +2 $hostfile)" | sudo tee $hostfile
fi

sudo umount ${SAMBA_MOUNT_DIR}
# resource file:
source ${USER_CONFIG_FILE}
# Name hostname
sudo sed -i "s/raspberrypi/${HOSTNAME}/" /etc/hosts
}

disable_dhcpcd(){
sudo systemctl disable dhcpcd.service
}

###############################################################################
######################### MAIN ################################################
###############################################################################
echo "Base install"
CUSTOM_KERNEL_USED=$(custom_kernel_check)
base_install
network_install
imu_logging_install
ntp_via_gps_install
i2c_install
usv_rtc_install

# BT with BC127
bt_audio_install
echo "Configuring BT-module"
configureBTModul
#echo "***********************************************"
#echo "Please Restart the Raspberry and the BT-Module. "
#echo "The Device will then automatically connect and record via the microphone."
#echo "***********************************************"
get_samba_subdir

echo "Disable DCHPCD to avoid boot delay"
disable_dhcpcd

echo "Exit Script"

exit 0

