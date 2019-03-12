#!/bin/bash

#
# If i2c_gpio_param is used, you can activate i2c on diffrent gpios.
# this script will manage the (un-)registration of the i2c busses via gpio.
#

# bus
BUS1='2'
# gpio's
SDA1='2'
SCL1='3'
# speed
SPEED1='1'

BUS2='3'
SDA2='17'
SCL2='27'
SPEED2='1'

ACTION=$1
# for debugging:
#i2cdetect -l
#i2cdetect -y 1

#sudo insmod 
if [ "$ACTION" == "add" ]; then
#https://github.com/kadamski/i2c-gpio-param
  sudo insmod "../KernelCrossCompile/i2c-gpio-param.ko" 
# echo busid sda scl [udelay] [timeout] [sda_od] [scl_od] [scl_oo] | sudo tee
  echo ${BUS1} ${SDA1} ${SCL1} ${SPEED1} | sudo tee /sys/class/i2c-gpio/add_bus
  echo ${BUS2} ${SDA2} ${SCL2} ${SPEED2} | sudo tee /sys/class/i2c-gpio/add_bus
  #echo ${BUS} ${SDA} ${SCL} | sudo tee /sys/class/i2c-gpio/add_bus

elif [ "$ACTION" == "remove" ]; then
# echo busid | sudo tee
  echo ${BUS1} | sudo tee /sys/class/i2c-gpio/remove_bus
  echo ${BUS2} | sudo tee /sys/class/i2c-gpio/remove_bus
  #echo ${BUS} | sudo tee /sys/class/i2c-gpio/remove_bus

else
  echo "Usage: "$0" [remove|add]"
fi
echo 'Done.'

