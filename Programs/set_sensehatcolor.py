#!/usr/bin/env python3

import wiringpi
import sys
import time

OUTPUT = 1
#pinred = 22
#pinblue = 26
#pingreen = 21
pinred = 6
pinblue = 12
pingreen = 5

red = [255,0,0]
orange = [255,127,0]
yellow = [255,255,0]
white = [255,255,255]
green = [0,255,0]
blue = [0,0,255]
i = [75,0,130]
v = [159,0,255]
black = [0,0,0]

wiringpi.wiringPiSetupGpio()
wiringpi.pinMode(pinred,   OUTPUT) # as output
wiringpi.softPwmCreate(pinred,0,255) # Setup PWM using Pin, Initial Value and Range parameters
wiringpi.pinMode(pingreen, OUTPUT) # as output
wiringpi.softPwmCreate(pingreen,0,255) # Setup PWM using Pin, Initial Value and Range parameters
wiringpi.pinMode(pinblue,  OUTPUT) # as output
wiringpi.softPwmCreate(pinblue,0,255) # Setup PWM using Pin, Initial Value and Range parameters

color = black
if sys.argv[1]:
  farbe = str(sys.argv[1])
  brightness = int(100)
  try:
      print(len(sys.argv))
      if len(sys.argv) > 2:
          brightness = int(sys.argv[2])
  except ValueError:
      pass
#  print (farbe)
  if farbe == "black":
    color = black
  elif farbe == "red":
    color = red 
  elif farbe == "green":
    color = green 
  elif farbe == "blue":
    color = blue 
  elif farbe == "yellow":
    color = yellow
  elif farbe == "white":
    color = white
  elif farbe == "orange":
    color = orange

print(int(brightness)/100)
color = [int(c * int(brightness)/100) for c in color]
print(color)
wiringpi.softPwmWrite(pinred,color[0])
wiringpi.softPwmWrite(pingreen,color[1])
wiringpi.softPwmWrite(pinblue,color[2])
time.sleep(1)
sys.exit(0)




