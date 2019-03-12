#!/bin/bash
SCRIPT_DIR=$(dirname $(readlink -f $0))
source ${SCRIPT_DIR}/../rpi_config.cfg

# Redirect stdout ( > ) into a named pipe ( >() ) running "tee"
# moreutils for ts (timestamp)
exec &> >(sudo ts >> ${LOGFILE_start_recorder} 2>&1)
exec 2>&1  # add sterr to stdout
date
echo "Executing Sensor Recorder script... with PID:$$"

#LOGFILE="/dev/null"
echo "##############starting ${0} at $(date)##############"
pid_logger=0

finish(){
    python3 ${SET_COLOR_SCRIPT} $3
    echo "set color $3"
    echo "quitting via $2"
    echo "kill pid: ${pid_logger}"
    kill ${pid_logger}
    echo "exitstatus: $1"
    exit $1
}


trap "finish 0 \"SIGUSR\" blue" SIGUSR1
trap "finish 1 \"SIGHUP/SIGHINT/SIGTERM\" red" SIGHUP SIGINT SIGTERM

echo "start logger."
python3 ${LOGGER_SCRIPT} >> /home/pi/logging_data/SensorRecorder_log 2>&1 &
pid_logger=$!
python3 ${SET_COLOR_SCRIPT} green

while true
do
    if [[ -z "$(ps h ${pid_logger}|cut -c1-5)" ]]; then
        echo "script terminated."
        python3 ${SET_COLOR_SCRIPT} red
        break
    fi
    sleep 1
done

