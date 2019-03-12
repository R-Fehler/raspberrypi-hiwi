#!/bin/bash
# Script to start a Program to record sound.
# it will reconfigure pulseaudio for pyaudio
# and activate playing 'music' at the source.

# disown from udev, starting program with no controlling terminal
#if [ "$1" != "fo_real" ]; then
#  /usr/bin/setsid $0 fo_real $ACTION "$@" &
#  exit
#fi

# Do some internal stuff and aquire some system data
# get config
SCRIPT_DIR=$(dirname $(readlink -f $0))
source ${SCRIPT_DIR}/../rpi_config.cfg

# Redirect stdout ( > ) into a named pipe ( >() ) running "tee"
# moreutils for ts (timestamp)  
exec &> >(ts >> ${LOGFILE_BLUETOOTH_UDEV} 2>&1)
exec 2>&1  # add sterr to stdout
date
echo "Executing bluetooth script... with PID:$$"
# prevent script from running twice a time
#pidfile="/tmp/${0##*/}.pidfile"
#if [ -f "$pidfile" ] && kill -0 $(cat $pidfile) 2>/dev/null; then
#    echo "Old PID for bluetooth_recorder_starter is running. quit."
#    exit 1
#fi
#echo $$ > $pidfile

# check if user ${PI_USER} is logged in. Try for 30s
#c_max=30
#is_succ="false"
#for i in $(seq 1 $c_max); do
#  sleep 1
#  res=$(who | cut -d' ' -f1 | grep "${PI_USER}" | wc -l)
#  if [ "$res" -ge "1" ]; then
#    echo "User ${PI_USER} is logged in after $i sec, going forward."
#    is_succ="true"
#    break
#  fi
#done

# If user is not logged in, give up and quit.
#if [ "${is_succ}" = "false" ]; then
#  echo "Exit script, user pi is not logged in."
#  exit 0
#fi

# mac from 'music' source, read from config
mac=$(echo "${BC127_MAC//:/_}" | tr '[:lower:]' '[:upper:]' )
# generate bluez device name
bluez_dev="bluez_source.$mac"
echo "source should be: ${bluez_dev}"

echo "user is :$PI_USER" # from config

# if there is no pulseaudio start it
pa_status=$(systemctl is-active pulseaudio)
echo "Pulseaudio is: $pa_status"
if [ "$pa_status" != "active" ]; then
  service pulseaudio start
  sleep 2 # hopefuly pulseaudio is started after 2s
fi

# Connect the bluetooth source to the default sink.
# wait a maximum of 30 seconds for creation of audio source
is_succ="false"
c_max=40
for i in $(seq 1 $c_max); do
# try to connect every 5 cycles.
  if [ "$((${i}%10))" -eq "0" ]; then
    echo "try to manually connect."
#    service bluetooth restart
    #killall pulseaudio
    echo "connect ${BC127_MAC}" | bluetoothctl
    sleep 5
    su "${PI_USER}" -c "pactl list sources short"
  fi
  sourceslist=$(su "${PI_USER}" -c "pactl list sources short" | grep "$bluez_dev" )
  if [ -n "$sourceslist" ]; then
    echo "the correct source: <$sourceslist>. was created after $i seconds."
    is_succ="true"
    break
  fi
  sleep 1
done

# after connecting the audio source, start the recording program
if [ "${is_succ}" = "true" ]; then
  sleep 1
  # Set volume level to 100 percent
  su "${PI_USER}" -c "pactl set-source-volume $bluez_dev 100%"
  su "${PI_USER}" -c "pacmd set-default-source $bluez_dev"
  su "${PI_USER}" -c "pactl list sources short"
  sourceinfo=$(su "${PI_USER}" -c "pactl info" | grep "Default Source:")
  echo "pactl info: ${sourceinfo}"
  # check for default source
  if [ "$sourceinfo" = "Default Source: $bluez_dev" ]; then
    # get serial console on bluetooth device
    rfcomm bind ${RF_TTY} ${BC127_MAC}
    # communicate via serial with BT device and start sending mic data
    # feature: saving file with battery status and signal strength.
    su "$PI_USER" -c "${BT_SPP_SCRIPT} \"MUSIC 11 PLAY\"" | tee "${LOGGINGDIRECTORY}/mic_status_$(date +%s).status"
    rfcomm unbind ${RF_TTY}
    # start program for recording mic.
    su "$PI_USER" -c "python3 ${SAVEAUDIO_SCRIPT} ${LOGGINGDIRECTORY}" 2>&1
    #su "$PI_USER" -c "${BT_SPP_SCRIPT} \"MUSIC 11 STOP\""
  else
    echo "No Bluetooth-Device to pulseaudio connected-.-"
  fi
else
  echo "There was no Bluetooth audio source."
fi
echo "finished bluetooth_recorder_starter.sh"
#rm $pidfile
exit 0

