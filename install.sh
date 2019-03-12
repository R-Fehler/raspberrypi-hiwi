#!/bin/bash

# Dieser Installer funktioniert nur mit Raspbian Jessie/bluez5
# Getestet mit Raspbian Jessie Version 18.03.2016
# Der Installer muss auf jedem Gerät einzeln ausgeführt werden. Einfaches Kopieren der SD-Karte ist nicht möglich !! Dadurch werden die Mac-Addressen der beteiligten Geräte falsch.
# Nur die Paketinstallation kann parallelisiert werden.

SCRIPT_DIR=$(dirname $(readlink -f $0))
source ${SCRIPT_DIR}/rpi_config.cfg
#source "/home/pi/git/raspberrypi/rpi_config.cfg"

do_error() {
if ! [ $1 -eq 0 ]; then
  echo "error: exit: "
  echo $1
  sleep 10
  exit 5
fi
}

# Repo Clonen
# Sich via ssh-key anmelden ist extrem unpraktisch....

cd ${GIT_DIR}
echo "Get GIT REPO"
#git config --global credential.helper cache
if [ -d "${GIT_DIR}/${GIT_REPO}" ]; then
#  git pull "${GIT_HTTPS_STRING}" master
#  do_error $?
  echo "Git is already there"
else
  echo "Git clone"
  git clone "${GIT_HTTPS_STRING}"
  do_error $?
fi

#sudo apt-get update
#sudo apt-get install -y cifs-utils smbclient  #samba samba-common-bi
# Connection to fast-lff-vm05.fast.kit.edu failed (Error NT_STATUS_UNSUCCESSFUL)

## create credential file
#smbcredfile="${USER_DIR}/.smbcred"
#cat <<EOT > ${smbcredfile}
#username=${SAMBA_USER}
#password=${SAMBA_PWD}
#domain=${SAMBA_REMOTE}
#EOT
#samba_options=" --authentication-file=${smbcredfile} ${SAMBA_REMOTE}"
#remote_hosts_filename="config\hosts"
## get hostname list.
#in_hostnames=$(smbclient ${samba_options} -c "get ${remote_hosts_filename} -" 2>/dev/null)
## get first one and put back the rest
#my_hostname=$(echo ${in_hostnames} |cut -d' '  -f1)
## if there is no name, set an emergency hostname
#if ! [[ ${my_hostname} ]]; then
#    my_hostname="problem_getting_hostfname_from_file"
#fi
## replace __HOSTNAME__ by hostname in main config
## or create new file, which main config directs to
#echo "# Config file for device dependend settings\n" | tee ${USER_CONFIG_FILE}
#echo "HOSTNAME=${my_hostname}" | tee ${USER_CONFIG_FILE}
## rewrite hostnames-file on server, without first entry
#echo ${in_hostnames} |cut -d' ' -f2- | tr ' ' '\n\r' | smbclient ${samba_options} -c "put - ${remote_hosts_filename}"
##create home_directory
#smbclient ${samba_options} -c "mkdir ${my_hostname}"
## remove credential file
#rm ${smbcredfile}

# während der installation das funkmodul via ****USB zu Serial-Adapter**** anschliessen
# (am besten als ttyUSB0, sonst muss man den Pfad in der config ändern.)
echo "sudo installer"
time sudo bash ${INSTALL_SCRIPT} 2>&1 | tee ~/installlog.log
do_error $?


exit 0
