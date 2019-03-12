#!/bin/bash

# UPLOAD Recorded Data and get WIFI

SCRIPT_DIR=$(dirname $(readlink -f $0))
source ${SCRIPT_DIR}/../rpi_config.cfg

# 0: disable debugging
# 1: enable debugging
debug=1
# 0: do not update git
# 1: update git
update_git=1
# Subdirectory an remote server
REMOTE_SUB_DIR=${HOSTNAME}
# 0: leave files as is
# 1: using Bzip compression
USE_BZIP=0
# supported filename extensions for upload
FNAME_EXT='gz wav~ csv~ status'
# logfile
LOGFILE=$LOGFILE_WIFICRONJOB

# expand braces http://wiki.bash-hackers.org/syntax/expansion/brace
set -B

# Log all to Logfile (ts: timestamp)
exec &> >(ts >> ${LOGFILE_WIFICRONJOB} 2>&1)

# Lockfile
SCRIPTNAME=$(basename $0)
PIDFILE=/var/run/${SCRIPTNAME}.pid

if [ -f ${PIDFILE} ]; then
   #verify if the process is actually still running under this pid
   OLDPID=$(cat ${PIDFILE})
   RESULT=$(ps -ef | grep ${OLDPID} | grep ${SCRIPTNAME})

   if [ -n "${RESULT}" ]; then
     echo "Script already running! Exiting"
     exit 255
   fi
fi

#grab pid of this process and update the pid file with it
PID=$(ps -ef | grep ${SCRIPTNAME} | head -n1 |  awk ' {print $2;} ')
echo ${PID} > ${PIDFILE}

# finish function for clean up all necessary parts of the script.
function finish {
    sleep 0.5
    if [ $1 -eq 0 ]; then
        echo "finished with status $2"
    else
        echo "error: $2"
    fi
    capacity=$(/opt/susvd/susv -capbat 0 | head -1 | cut -d . -f1)
    echo "Capacity is ${capacity}%"
    kill ${pid_batstat}
    kill ${pid_rsync}
    sync
    if [ -f ${PIDFILE} ]; then
        rm ${PIDFILE}
    fi
    echo "removed lockfile."
    umount ${SAMBA_MOUNT_DIR}
    if [[ $(/opt/susvd/susv -status | grep OFFLINE | wc -l) -eq 0 ]]; then
      echo "Power is available"
      # start audio recorder script via trigger.
      #sudo /usr/bin/udevadm trigger --action=add --subsystem-match=bluetooth --property-match=address="${BC127_MAC,,}"
      if [ -x ${UDEV_BLUETOOTH_STARTER} ]; then # is executable file
        echo "start bt-logger ${UDEV_BLUETOOTH_STARTER}."
        nohup sudo ${UDEV_BLUETOOTH_STARTER} &
      fi
      sudo service sensorrecorder start
      #if [ -x ${LOGGING_STARTER_SCRIPT} ]; then # is executable file
      #  echo "start logger ${LOGGING_STARTER_SCRIPT}."
      #  # https://unix.stackexchange.com/questions/3886/difference-between-nohup-disown-and
      #  nohup ${LOGGING_STARTER_SCRIPT} &
      #fi
    else
      echo "Power is not available, shutdown."
      # shutdown after 1 minute.
      shutdown -h +1
    fi
    exit $1
}

# trap "finish" EXIT
# http://www.tutorialspoint.com/unix/unix-signals-traps.htm
trap "finish 1 \"trap:SIGHUP\"" SIGHUP
trap "finish 1 \"trap:SIGINT\"" SIGINT
trap "finish 1 \"trap:SIGQUIT\"" SIGQUIT
trap "finish 1 \"trap:SIGPIPE\"" SIGPIPE
#trap "finish 1 \"trap:SIGALARM\"" SIGALARM
#trap "finish 1 \"trap:SIGTERM\"" SIGTERM
trap "echo \"trap:SIGTERM, Do nothing!\"" SIGTERM
trap "finish 1 \"trap:SIGTRAP\"" SIGTRAP

#trap "finish 1 \"trap\"" 1 2 3 8 9 14 15

check_batterystat () {
  # Check if Battery Status falls under ${MIN_PERCENTAGES_BATTERY}
  times=0
  while true; do
    capacity=$(/opt/susvd/susv -capbat 0 | head -1 | cut -d . -f1)
    if [ ${capacity} -le ${MIN_PERCENTAGES_BATTERY} ]; then
      times=$times + 1
      if [[ "$times" -gt "3" ]]; then
        echo "Battery Capacity is less than ${MIN_PERCENTAGES_BATTERY}%"
        return ${MIN_PERCENTAGES_BATTERY}
        break;
      fi
    fi
    sleep 5
  done
}

# important: only check if result is "1"
wlan_stat() {
    #essid=\$(nmcli dev wifi list | sed -n "s/^'\([^']*\)'.*yes\s*$/\1/p")
    essid=$(iwgetid -r)
    if [ "${essid}" == "${WLAN_SSID}" ]; then
        echo "1"
        return
    fi
    echo "Not connected to ${WLAN_SSID}, try to restart WLAN."
    # restart wlan.
    ifdown wlan0
    ifup wlan0
    sleep 2
    # check again
    essid=$(iwgetid -r)
    if [ "${essid}" == "${WLAN_SSID}" ]; then
        echo "1"
        return
    fi
    echo "0"
}

check_wlanstat () {
  # Check if wireless fails while sending data.
  times=0
  while true; do
    wlan_status=$(wlan_stat)
    if [ "${wlan_status}" != "1" ]; then
      times=$times + 1
      if [[ "$times" -gt "3" ]]; then
        echo "Wireless is not available."
        return "0"
        break;
      fi
    fi
    sleep 5
  done
}


# Stop Script $1:
script_killer () {
    # check if script is executable
    if [ -x $1 ]; then
        echo "Kill $1."
        KILL_PID1=$( pgrep -f $1 | head -n 1)
        KILL_PID2=$( pgrep -f $1 | head -2 | tail -1)
        ps aux | grep $1 | grep bash
        echo "kill -s USR1 ${KILL_PID1} ..."
        echo "kill -s USR1 ${KILL_PID2} ..."
        kill -s USR1 ${KILL_PID1}
        kill -s USR1 ${KILL_PID2}
        echo "Hopefully Killed..."
        #time to stop logger
        sleep 3
        ps aux | grep $1 | grep bash
    else
        echo "Not Killed, $1 is no executable..."
    fi
}

echo "start logging $0"

echo "################################################################################"
echo "#########started wifi upload script at $(date)#############"
echo "################################################################################"

# sleep 10s to check if it is only a short power outage
sleep 10

if [[ $(/opt/susvd/susv -status | grep OFFLINE | wc -l) -eq 0 ]]; then
    echo "Only short Power Outage."
    exit -10
fi



echo "check Wireless"

max_wifi_iter=2 # minimum of 2
for i in $(seq 1 $max_wifi_iter); do
    wifi_available=$(wlan_stat)
    echo "Wireless status is ${wifi_available}"
    # only retry, if there is no wireless
    if [ "${wifi_available}" == "1" ]; then
        break;
    fi
done

# Pull Git, if there is wireless.
if [ "${wifi_available}" == "1" ] && [ "${update_git}" == "1" ]; then
    # update git
    echo "Get GIT Repo Update."
    cd ${REPO_DIR}
    GIT_HTTPS_STRING=$(GET_GIT_HTTPS_STRING)

    #su pi -c "git add ."
    #su pi -c "git reset --hard HEAD"
    su pi -c "git reset --hard"
    su pi -c "git clean -ffdx"
    su pi -c "git config --global user.name RaspberryPi"
    #su pi -c "git fetch ${GIT_HTTPS_STRING} jessie"

    # check for complications
    su pi -c "git pull ${GIT_HTTPS_STRING} jessie"

    # execute updatescript
    ${UPDATE_GIT_SCRIPT}
    python3 ${SET_COLOR_SCRIPT} yellow
fi



# Stop SensorRecorder:
sudo service sensorrecorder stop
#script_killer ${LOGGING_STARTER_SCRIPT}
# Stop Audio_logger
script_killer ${SAVEAUDIO_SCRIPT}

#if no wifi is available, exec script
if [ "${wifi_available}" != "1" ]; then
    python3 ${SET_COLOR_SCRIPT} orange
    finish 1 "no wireless"
fi


# if the wifi adapter does not automatically connect to the wireless network, try using wpa-roam or wicd-cli
echo "Connected to WIFI, now Mounting Samba Share."

## TODO one folder per day?
mount ${SAMBA_MOUNT_DIR}
if [ $? -ne 0 ]; then # dont got samba mounted -> break
    echo "Mounting Samba share ${SAMBA_MOUNT_DIR} failed."
else # got mounted
    echo "Mounting Samba share ${SAMBA_MOUNT_DIR} successful."
    # copy some logs to server
    sync
    # zip via pbzip
    if [ $USE_BZIP -ne 0 ]; then
        cd ${LOGGINGDIRECTORY}
        echo "Start Compressing with pbzip2."
        pbzip2 *.csv &
        pid_bzip=$!
        check_batterystat &
        pid_batstat=$!
        # if one process is halting, both will be killed.
        # wireless checking is not needed, because this part dont needs wireless
        while true; do
            # check if rsync and Batstat is running
            if [ "$(ps h ${pid_bzip}|cut -c1-5)" == "" ]; then

                kill ${pid_batstat}
                wait ${pid_batstat}
                echo "Bzip2 finished with status $?">> ${LOGFILE} 2>&1; 
                break
            fi
            if [ "$(ps h ${pid_batstat}|cut -c1-5)" == "" ]; then
                kill ${pid_bzip}
                wait ${pid_bzip}
                echo "Battery Capacity to low.">> ${LOGFILE} 2>&1
                echo "Bzip2 killed with status $?">> ${LOGFILE} 2>&1;
                finish 1 "BZIP: Capacity low"
                break
            fi
            sleep 1
        done
        FNAME_EXT='bz2'
    fi

    # generate all includes
    FNAME=$(printf " --include=\"*.%s\" " ${FNAME_EXT})

    echo "rsync -rtvh --partial --stats --remove-source-files --include="*/" ${FNAME} --exclude="*" ${LOGGINGDIRECTORY} ${SAMBA_MOUNT_DIR}/${REMOTE_SUB_DIR}"
    # eval because of $FNAME
    # sync all data to server
    eval rsync -rtvh --partial --stats --remove-source-files --include="*/" ${FNAME} --exclude="*" ${LOGGINGDIRECTORY} ${SAMBA_MOUNT_DIR}/${REMOTE_SUB_DIR} &
    pid_rsync=$!
    check_batterystat &
    pid_batstat=$!
    check_wlanstat &
    pid_wlanstat=$!
    echo "PID RSYNC: ${pid_rsync}, Batstat: ${pid_batstat}."
    jobs -l
    while true; do
        # check if rsync and Batstat is running
        if [ "$(ps h ${pid_rsync}|cut -c1-5)" == "" ]; then
            kill ${pid_wlanstat}
            kill ${pid_batstat}
            wait ${pid_wlanstat}
            wait ${pid_batstat}
            echo "Rsync finished with status $?">> ${LOGFILE} 2>&1; 
            break
        fi
        if [ "$(ps h ${pid_batstat}|cut -c1-5)" == "" ]; then
            kill ${pid_wlanstat}
            kill ${pid_rsync}
            wait ${pid_wlanstat}
            wait ${pid_rsync}
            echo "Battery Capacity to low.">> ${LOGFILE} 2>&1
            echo "Rsync killed with status $?">> ${LOGFILE} 2>&1;
            finish 1 "RSYNC: Capacity low"
            break
        fi
        if [ "$(ps h ${pid_wlanstat}|cut -c1-5)" == "" ]; then
            kill ${pid_batstat}
            kill ${pid_rsync}
            wait ${pid_batstat}
            wait ${pid_rsync}
            echo "Wireless was not available.">> ${LOGFILE} 2>&1
            echo "Rsync killed with status $?">> ${LOGFILE} 2>&1;
            finish 1 "RSYNC: No Wlan"
            break
         fi
        sleep 1
    done
    sync
    umount ${SAMBA_MOUNT_DIR}
fi
python3 ${SET_COLOR_SCRIPT} white

finish 0 "successful"

