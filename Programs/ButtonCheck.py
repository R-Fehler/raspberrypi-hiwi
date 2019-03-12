import time
import os
import RPi.GPIO as GPIO
from sense_hat import SenseHat
import shlex
import subprocess
import sys
import signal
import datetime
from datetime import datetime
import time

# Variablen
PIN_TOGGLE_RESTART = 22
PIN_SHUTDOWN = 22

# ------ GPIO Initialiseren -------
GPIO.setmode(GPIO.BCM)
GPIO.setup(PIN_TOGGLE_RESTART, GPIO.IN, pull_up_down=GPIO.PUD_DOWN)
GPIO.setup(PIN_SHUTDOWN, GPIO.IN, pull_up_down=GPIO.PUD_DOWN)

while True:
	if GPIO.input(PIN_SHUTDOWN) == GPIO.HIGH:
		print("Button had been pressed")
