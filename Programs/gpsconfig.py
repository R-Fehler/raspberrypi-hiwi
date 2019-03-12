#!/usr/bin/env python3

import io,serial,time
import operator,functools


def nema_checksum(sentence):
    nmeadata = sentence.strip('\n')
    calc_cksum = functools.reduce(operator.xor, (ord(s) for s in nmeadata), 0)
    return "$" + nmeadata + "*" + str(format(calc_cksum, 'X'))

ser = serial.Serial(
  port='/dev/ttyAMA0',
  baudrate=38400,
  parity=serial.PARITY_NONE,
  stopbits=serial.STOPBITS_ONE,
  bytesize=serial.EIGHTBITS,
  interCharTimeout=1,
  timeout=1
)

try: 
    ser.close()
    ser.open()              # open serial port
except (Exception):
    print ("Error open serial port.")
    exit()

ser_io = io.TextIOWrapper(io.BufferedRWPair(ser,ser, 1),  
                             newline = '\r\n',
                             line_buffering = True)
                             
outStr = []

#old
#outStr = '$PMTK605*31\r\n' # Query the firmware release information. 
#outStr = '$PMTK447*35\r\n' # Query current Nav Speed threshold setting. 
#outStr = '$PMTK220,100*2F\r\n'
#outStr = '$PMTK220,200*2C\r\n'
#outStr = '$PMTK220,1000*1F\r\n'
#outStr = '$PMTK220,10000*2F\r\n'
#outStr = '$PMTK314,1,1,1,1,1,5,0,0,0,0,0,0,0,0,0,0,0,0,0*2C\r\n'

# Baudrate einstellen
# PMTK251, Baudrate
# Baudrate setting : 4800,9600,14400,19200,38400,57600,115200
outStr.append("PMTK251,38400")
# Set updaterate per sentence
# Set NMEA sentence output frequencies
outStr.append("PMTK314,1,1,1,5,5,5,0,0,0,0,0,0,0,0,0,0,0,2,5")
# Set updaterate to 10Hz
# Set NMEA port update rate
outStr.append("PMTK220,100")
#ser.setBaudrate(115200) # live change baud rate

if ser.isOpen():
    try:
        ser.flushInput() #flush input buffer, discarding all its contents
        ser.flushOutput()#flush output buffer, aborting current output 
        #and discard all that is in buffer
        #write data

        ser.setBaudrate(9600) # live change baud rate
        for out in outStr[:1]:
            ser_io.write(nema_checksum(out) + '\r' + '\n')      # write a string
            time.sleep(0.1)
            print("write data: " + nema_checksum(out))
        time.sleep(2)
        print('Switch Baudrate.')
        #Brute Force Baudrate
        ser.setBaudrate(38400) # live change baud rate
        time.sleep(2)
        for out in outStr[1:]:
            ser_io.write(nema_checksum(out) + '\r' + '\n')      # write a string
            time.sleep(0.1)
            print("write data: " + nema_checksum(out))

        ser.close()

    except (Exception, e1):
        print ("error communicating...: " + str(e1))
else:
    print ("cannot open serial port ")
 
 
#Doku

#PMTK314:

#Supported NMEA Sentences
#0 NMEA_SEN_GLL, // GPGLL interval ‐ Geographic Position ‐ Latitude longitude
#1 NMEA_SEN_RMC, // GPRMC interval ‐ Recommended Minimum Specific GNSS Sentence
#2 NMEA_SEN_VTG, // GPVTG interval ‐ Course over Ground and Ground Speed
#3 NMEA_SEN_GGA, // GPGGA interval ‐ GPS Fix Data
#4 NMEA_SEN_GSA, // GPGSA interval ‐ GNSS DOPS and Active Satellites
#5 NMEA_SEN_GSV, // GPGSV interval ‐ GNSS Satellites in View
#6     //Reserved
#7     //Reserved
#13    //Reserved
#14    //Reserved
#15    //Reserved
#16    //Reserved
#17    NMEA_SEN_ZDA, // GPZDA interval – Time & Date
#18 NMEA_SEN_MCHN, // PMTKCHN interval – GPS channel status

#Supported Frequency Setting
#0 - Disabled or not supported sentence
#1 - Output once every one position fix
#2 - Output once every two position fixes
#3 - Output once every three position fixes
#4 - Output once every four position fixes
#5 - Output once every five position fixes

