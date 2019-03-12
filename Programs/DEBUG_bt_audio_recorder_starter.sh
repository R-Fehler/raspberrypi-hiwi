#!/bin/bash
#
# ONLY FOR TESTING not for final version
#
#
SCRIPT_DIR=$(dirname $(readlink -f $0))
source ${SCRIPT_DIR}/../rpi_config.cfg

DEBUG_LOGGING=${LOGGINGDIRECTORY}/bt_debug
# mac from 'music' source, read from config
mac=$(echo "${BC127_MAC//:/_}" | tr '[:lower:]' '[:upper:]' )
# generate bluez device name
bluez_dev="bluez_source.$mac"
echo "source should be: ${bluez_dev}"

mkdir ${DEBUG_LOGGING}

# if there is no pulseaudio start it
pa_status=$(systemctl is-active pulseaudio)
echo "Pulseaudio is: $pa_status"
if [ "$pa_status" != "active" ]; then
  sudo service pulseaudio start
  sleep 2 # hopefuly pulseaudio is started after 2s
fi

# connect by hand
echo "Connect to BT Device ${BC127_MAC}"
echo "connect ${BC127_MAC}" | bluetoothctl
echo "Should now connected."
# check if connection is established and a audio source is available
sourceslist=$(pactl list sources short | grep "$bluez_dev" )
if [ -n "$sourceslist" ]; then
  echo "the correct source: <$sourceslist>. was created."
  sleep 1
  # Set volume level to 100 percent
  pactl set-source-volume $bluez_dev 100%
  pacmd set-default-source $bluez_dev
  pactl list sources short
  sourceinfo=$(pactl info | grep "Default Source:")
  echo "pactl info: ${sourceinfo}"
  # check for default source
  if [ "$sourceinfo" = "Default Source: $bluez_dev" ]; then
    # get serial console on bluetooth device
    sudo rfcomm bind ${RF_TTY} ${BC127_MAC}
    # communicate via serial with BT device and start sending mic data
    # feature: saving file with battery status and signal strength.
    ${BT_SPP_SCRIPT} "MUSIC 11 PLAY" | tee "${DEBUG_LOGGING}/mic_status_$(date +%s).status"
    sudo rfcomm unbind ${RF_TTY}
    # start program for recording mic.
    python3 ${SAVEAUDIO_SCRIPT} ${DEBUG_LOGGING} 2>&1
    du -h ${DEBUG_LOGGING}
    #su "$PI_USER" -c "${BT_SPP_SCRIPT} \"MUSIC 11 STOP\""
  else
    echo "No Bluetooth-Device to pulseaudio connected-.-"
  fi
else
  echo "There was no Bluetooth audio source."
fi
