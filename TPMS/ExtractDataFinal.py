#!/usr/bin/env python
# -*- coding: UTF-8 -*-
 
#Shebang-Zeile: Interpreter-Programm python
#Zeichen utf-8 kodiert


#Überprüfen, ob Datei schon existiert
#Falls nicht -> Neue Datei erstellen + 1. Zeile hineinschreiben
def fileexisting(filename):
    if(os.path.isfile('/home/pi/Desktop/Aufzeichnungen/' + filename + '.csv') == False):
        with open('/home/pi/Desktop/Aufzeichnungen/' + filename + '.csv','w') as file:
            file.write("Datum + Uhrzeit, Sensor ID, Nachrichtennummer, Druck [mbar], Temperatur [°C], RSSI [dB]\n")


#Umwandeln der Bytewerte in Dezimalzahlen
def strtodez(liste):
    dez = []
    for zeichen in liste:
        dez.append(ord(zeichen))
    return dez

#Ermittle die aktuelle Zeit und formatiere sie in das Format dd.mm.yyyy - hh:mm:ss
def gettime():
    actualtime = time.localtime()
    ftime = time.strftime("%d.%m.%Y - %H:%M:%S", actualtime)
    return ftime

#Konvertiere die Bytes zu der dezimalen sensorID (Wert * (256^x))
def convertid(sensorIDlist):
    sensorIDdez = 0
    counter = 3
    for element in sensorIDlist:
        sensorIDdez += element * (256 ** (counter))
        counter -= 1
    return sensorIDdez

#Konvertiere dezimale Bytewerte in echte Werte
def converttovalues(dezdata, counter):
    print(dezdata[counter-3:counter+9])
    sensorIDdez = "%s" %(convertid(dezdata[(counter):(counter+4)]))
    messagenr = "%s" %(dezdata[counter-1])
    pressure = "%s" %((dezdata[counter+4]*14)+1024)
    temperature = "%s" %(dezdata[counter+6]-50)
    rssi = "%s" %(((dezdata[counter+7]*256) + dezdata[counter+8])/10)
    return [sensorIDdez, messagenr, pressure, temperature, rssi]

#Schreibe Daten in Datei
def writetofile(convertedvalues, timestamp):
    with open('/home/pi/Desktop/Aufzeichnungen/' + 'Aufzeichnung-' + timestamp[0:10] + '.csv','a') as file:
        file.write(timestamp + "," + convertedvalues[0] + "," + convertedvalues[1] + "," + convertedvalues[2] + "," + convertedvalues[3] + "," + convertedvalues[4] + "\n")

#Nach ID filtern -> filteredidpos (list with tuples)
def filterid(dezdata):
        print(dezdata)
        filteredidpos = []
        idstartpos = []
        idcounter = 0
        try:
            counter = -1
            while 1:
                counter = dezdata.index(12, counter+1)
                idstartpos.append(counter)
        except ValueError:
            print("ValueError")
            pass
        for idstart in range(0,len(SENSORIDS),4):
            idcounter += 1
            messcounter = 1
            for dezstart in idstartpos:
                if((dezdata[dezstart + 1] == SENSORIDS[idstart + 1]) and (dezdata[dezstart + 2] == SENSORIDS[idstart + 2]) and (dezdata[dezstart + 3] == SENSORIDS[idstart + 3])):
                    key = "ID" + str(idcounter) + "_" + str(messcounter)
                    startidtuple = (key,dezstart)
                    filteredidpos.append(startidtuple);
                messcounter += 1
        return filteredidpos

#Wähle nur ein Startpunkt pro ID aus
def chooseonestartposperid(idpos, dezdata):
        idcount = int(((idpos[0])[0])[2]) - 1
        tupleonemessperid = []
        for element in idpos:
                if(int((element[0])[2]) != idcount):
                        try:
                                if(dezdata[element[1]-3] == 35 and dezdata[element[1]+9] == 35):
                                        idcount += 1
                                        tupleonemessperid.append(element)
                        except IndexError:
                                pass
        return tupleonemessperid

#Konvertiere die Temperatur für PWM (erlaubte return-Werte: 0 bis 1024)
def converttempforpwm(convertedtemp):
        if(convertedtemp > -21 and convertedtemp < 106):
                return ((int(convertedtemp) + 21) * 8)
        elif(convertedtemp <= -21):
                return 0
        else:
                return 1016


#Lade benötigte Module
import csv
#import serial
import os.path
import time
#import wiringpi2 as wiringpi

###################DEFINES################
#Sensor IDs müssen mit 12 beginnen
SENSORIDS = [12, 70, 172, 166, 12, 69, 251, 131, 12, 69, 248, 207, 12, 70, 173, 117]
#Sleep Time (Waiting for all characters)
WAITFORBYTESTIME = 0.5
#Bytes einer Nachricht(in float)
LENGTHOFONEMESSAGE = 12.0
#PWM pin physical (for hardware pwm)
PWM_PIN = 12
#PWM Start Duty Cycle
PWM_START = 1024
#LED pin physical
LED_PIN = 3

#konfiguriere + öffne den USB Port
#ser = serial.Serial(
#    port = "/dev/ttyUSB0",
#    baudrate = 9600,
#    parity = serial.PARITY_NONE,
#    stopbits = serial.STOPBITS_ONE,
#    bytesize = serial.EIGHTBITS,
#    timeout = None)

#Global Variables
data = []
timestamp = ""
ledvar = 0

#configure PWM
#PWM Mode (0 = input , 1 = output, 2 = alternative function (PWM))
#wiringpi.wiringPiSetupPhys()
#wiringpi.pinMode(PWM_PIN,2)
#wiringpi.pwmWrite(PWM_PIN,PWM_START)

#configure LED-Mode
#wiringpi.pinMode(LED_PIN, 1)


#################MAIN LOOP#################
#Zeichen im Empfangsbuffer?
#Ja? -> in Liste speichern (data)
#Nein? -> Liste mit Daten? -> Ja? -> Startbits suchen, konvertieren + umrechnen
#schreibe Werte in Datei und setze Variablen zurück
while(1):
#    if(ser.inWaiting() != 0):
        #timestamp = gettime()
        #time.sleep(WAITFORBYTESTIME)
        #while(ser.inWaiting() != 0):
        #    data.append(ser.read())
        #    datadez = strtodez(data)
            #print data
        #print datadez
        datadez = [35, 18, 1, 12, 69, 251, 131, 1, 0, 71, 2, 41,
                   35, 18, 1, 12, 69, 248, 207, 2, 0, 70, 2, 41,
                   35, 18, 2, 12, 70, 172, 166, 2, 0, 72, 2, 39,
                   35, 18, 3, 12, 70, 172, 166, 2, 0, 72, 2, 39,
                   35, 18, 2, 12, 69, 251, 131, 1, 0, 71, 2, 37]
        idpostuplelist = filterid(datadez)
        print("idpostuplelist: %s"%str(idpostuplelist))
        if((len(idpostuplelist) != 0)):
            #Tag,Monat,Jahr vergleichen
            #fileexisting('Aufzeichnung-' + timestamp[0:10])
            newstartidpostuple = chooseonestartposperid(idpostuplelist, datadez)
            print("newstartidpostuple: %s"%str(newstartidpostuple))
            #print newstartidpostuple
            print("convertedvalues: sensorIDdez, messagenr, pressure, temperature, rssi")
            for counter in range(0,len(newstartidpostuple)):
                idstartpos = int((newstartidpostuple[counter])[1])
                print("idstartpos: %s"%str(idstartpos))
                convertedvalues = converttovalues(datadez, idstartpos)
                print("convertedvalues: %s"%str(convertedvalues))
                #print(convertedvalues)
                #writetofile(convertedvalues, timestamp)
                #if(counter == (len(newstartidpostuple) - 1)):
                    #wiringpi.pwmWrite(PWM_PIN, converttempforpwm(int(convertedvalues[3])))
                    #if(ledvar == 0):
                    #    wiringpi.digitalWrite(LED_PIN,1)
                    #    ledvar = 1
                    #else:
                    #    wiringpi.digitalWrite(LED_PIN,0)
                    #    ledvar = 0
        data = []
        timestamp = ""
        break



