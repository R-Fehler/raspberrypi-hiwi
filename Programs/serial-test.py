import serial
import os
import sys

def main():
    print("start")
    port="/dev/ttyACM0"
    baud=9600
    ser=serial.Serial(port)
    ser.baudrate=baud
    f=open("log.txt","w+")
    i=0
    while i<10000:
        data = ser.readline()

        string=data.decode('UTF-8')
        # force=int(string)
        print(string)
        # for y in range(int(force/100000)) :
        #     print("|")
        # print("\n")
        f.write(string)
        f.flush()
        i=i+1

    print("ende")

main()
