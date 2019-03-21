#!/usr/bin/python
# test der sshfs funktion
import RPi.GPIO as GPIO
import time
import os
import subprocess
from subprocess import Popen
from sense_hat import SenseHat
import sys

# init sense hat
sense = SenseHat()
red = (255, 0, 0)
green = (0, 255, 0)
blue = (0, 0, 255)

pin1 = 17
pin2 = 22
record_on = False

# GPIO initialisieren
GPIO.setmode(GPIO.BCM)
# GPIO.setup(pin2, GPIO.IN, pull_up_down=GPIO.PUD_UP)  # Pin pin2 als Pullup
# GPIO.setup(pin1, GPIO.IN, pull_up_down=GPIO.PUD_UP)  # Pin pin1 ...

# internen Pullup-Widerstand aktivieren.
GPIO.setup(pin2, GPIO.IN, pull_up_down=GPIO.PUD_DOWN)  # pulldown
# GPIO.setup(pin1, GPIO.IN, pull_up_down=GPIO.PUD_DOWN)

# Callback fuer GPIO pin1


def isrpin1_single(channel):
    global record_on
    if (record_on == False):
        record_on = True
        print("starte Aufnahme, wenn BL verbunden:..")
        print "record on : " , record_on
        Popen(['./startrecord.sh'], shell=True)
        sense.clear(green)
        
    else:
        print("beende Aufnahme...")
        os.system("./killrecord.sh")
        record_on = False
        print "record on : " , record_on 
        sense.clear(red)
        


# Callback fuer GPIO 18



# Interrupts aktivieren
# Vorteil : debounced button (weniger falsch betaetigung)

# GPIO.add_event_detect(pin2, GPIO.FALLING, callback=isrpin1, bouncetime=200)
# GPIO.add_event_detect(pin1, GPIO.FALLING, callback=isrpin2, bouncetime=200)
GPIO.add_event_detect(pin2, GPIO.FALLING,
                      callback=isrpin1_single, bouncetime=400)


sense.clear(blue)
try:
    if(len(sys.argv)==2):
        if (str(sys.argv[1])=="startnow"):
            record_on = True
            print("starte Aufnahme, wenn BL verbunden:..")
            print "record on : " , record_on
            Popen(['./startrecord.sh'], shell=True)
            sense.clear(green)
        if (str(sys.argv[1])=="--help"):
            print "arguments for :",str(sys.argv[0]),"\nstartnow: startet Aufnahme sofort (nicht auf GPIO Button) "
            print "press long Button for Start of Record"
    while True:
        print "press long Button for Start/Stop of Record"

        time.sleep(100)
    # string = subprocess.check_output("./check-record-service.sh")
    # print string
    # if(string == ""):
    #     sense.clear(red)
    # else:
    #     sense.clear(green)

    # while True:
    #     GPIO.wait_for_edge(pin1, GPIO.FALLING)
    #     os.system("./startrecord.sh")
    #     print("Starte Aufnahme: ...")
    #     sense.clear(green)
    #     GPIO.wait_for_edge(pin2, GPIO.FALLING)
    #     os.system("./stoprecord.sh")
    #     print ("beende Aufnahme ...")
    #     sense.clear(red)


except KeyboardInterrupt:
    GPIO.cleanup()
    sense.clear()
    os.system("./killrecord.sh")
    print("\nstopped record via Ctrl+C / SIGINT.")
except:
    GPIO.cleanup()
    sense.clear()
    os.system("./killrecord.sh")
    print("ERROR: Proramm hat ein Problem")