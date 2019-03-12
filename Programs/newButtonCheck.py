import RPi.GPIO as GPIO
import time

# Variablen
PIN_TOGGLE_RESTART = 17
PIN_SHUTDOWN = 22

# ------ GPIO Initialiseren -------
GPIO.setmode(GPIO.BCM)
GPIO.setup(PIN_TOGGLE_RESTART, GPIO.IN, pull_up_down=GPIO.PUD_DOWN)
GPIO.setup(PIN_SHUTDOWN, GPIO.IN, pull_up_down=GPIO.PUD_DOWN)

while True:
    if GPIO.input(PIN_SHUTDOWN) == GPIO.HIGH:
        first_toggle=1
    else:
        first_toggle=0
    if GPIO.input(PIN_TOGGLE_RESTART)==GPIO.HIGH:
        second_toggle=1
    else:
        second_toggle=0
    time.sleep(0.5)
    if first_toggle==1:
        print("Button had been pressed")
    if second_toggle==1:
        print("Button had been pressed")
