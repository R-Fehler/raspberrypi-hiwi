#!/bin/bash

#https://raspberrypi.stackexchange.com/questions/9791/how-can-i-automatically-update-the-hwclock-with-ntp-when-i-have-internet-connect/9862#9862
# Location of logfile
LOGFILE="/var/log/ntp_to_hwclk.log"
SCRIPT_DIR=$(dirname $(readlink -f $0))
source ${SCRIPT_DIR}/../rpi_config.cfg
# Set the maximum allowed difference in seconds between Hw-Clock and Sys-Clock
#maxDiffSec="2"

msgNoConnection="No connection to time-server"
msgConnection="Connection to time-server"

# Check for NTP connection
#if ( ntpq -p | grep -q "^*"  ); then
if [ "$(ntpq -p | cut -c1-1 | grep "*")" == "*" ] ; then
        echo $msgConnection
        #Get HW Clock time
        secHwClock=$(sudo hwclock --debug | grep "^Hw clock time" | awk '{print $(NF-3)}')
        echo "HwClock: $secHwClock sec"
        #get SysClktime ( hopefully synced via ntp)
        secSysClock=$(date +"%s")
        #calc difference
        secDiff=$(($secHwClock-$secSysClock))
        # Compute absolute value
        if ( echo $secDiff | grep -q "-" ); then
            secDiff=$(($secDiff *(-1)))
        fi
        echo "Difference: $secDiff sec"
        msgDiff="HwClock difference: $secDiff sec"
        if [ "$secDiff" -gt "$maxDiffSec" ] ; then
                #if diffrence ist to big.
                echo "The difference between Hw- and Sys-Clock is more than $maxDiffSec sec."
                echo "Hw-Clock will be updated"

                # Update hwclock from system clock
                sudo hwclock -w
                msgDiff="$msgDiff --> HW-Clock updated."
        fi
        echo $(date)": "$msgConnection". "$msgDiff >> $LOGFILE
else
        # No NTP connection
        echo $(date)": $msgNoConnection" >> $LOGFILE
fi


