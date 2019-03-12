#!/usr/bin/env python3

##
#
# Logs measurements from IMU and GPS and Buttons to file in $LOGGINGDIRECTORY
#
##

import os
import sys
import time
import math
import glob
import csv
import signal
import logging
import serial
import datetime

# execute only, if this script is not imported as module (for testing purposes)
if __name__ == '__main__':
    import RTIMU
    #import mpu6050
    from gps3 import gps3
    from multiprocessing import Process, Manager, Value
    try:
        import RPi.GPIO as GPIO
    except RuntimeError:
        logging.debug("Error importing RPi.GPIO!  This is probably because you need superuser privileges. You can achieve this by using 'sudo' to run your script")

# Maximum time to record in one file till next file should begin
Maxtime = 60*5 # in sec

# Sensor initialization MPU_6050
address1 = 0x68
address2 = 0x69
#Number (x) is /dev/i2c-x
#bus = 1 # only when using costum i2c-gpio
filename = 'IMUData'
PIN_SCHLAGLOCH1 = 22
PIN_SCHLAGLOCH2 = 17

class TPMSRecorder():
    def __init__(self, writerobj):
        self.finished_init = False
        self.serial_callback = self.TPMSdecoder
        # microsecond: 0.000001
        # millisecond: 0.001
        self.serial_sleep_time = 0.001*1 # milliseconds
        #Sensor IDs in big endian
        self.SENSORIDS = {'ID1': 205912271, #[12, 70, 172, 166]
                          'ID2': 205958310, #[12, 69, 251, 131]
                          'ID3': 205912963, #[12, 69, 248, 207]
                          'ID4': 205958517} #[12, 70, 173, 117]
        # get list of serial ports
        ports = glob.glob('/dev/ttyUSB*');
        if not ports:
            logging.error("No Serialport available for TPMSRecorder.")
            return
        logging.warning("Following serial ports are avialabe: %s"%str(ports))
        # Try every possible serial Port and hope will get the correct one.
        # This will fail if another UART to USB Adapter is used at the same system.
        for port in ports:
            try:
                # serial connection to TPMS via /dev/ttyUSB* 9600,8,N,1
                self.ser_con = serial.Serial(port, timeout=0)
                #logging.debug(self.ser_con)
                try: # pyserial > 3.0
                    status = self.ser_con.is_open
                except: # pyserial < 3.0
                    status = self.ser_con.isOpen()
                if status:
                    logging.info("Successfully opened serialport %s."%port)
                    break
            except serial.serialutil.SerialException:
                self.ser_con = None
                logging.info("Open serialport %s was not possible. By Exception."%port)
        if not self.ser_con:
            logging.error("Was not able to open serialport. Stop TPMS recording.")
            return

        if writerobj:
            writerobj.add_headrow(['tpms_rel_time', 'tpms_messenger_nummer', 'tpms_id', 'tpms_pressure', 'tpms_temperature', 'tpms_rssi'])
        else:
            logging.warning("Running in debug mode.")
        self.finished_init = True
        logging.info("successful finished init of TPMS.")

    def cleanup(self):
        self.finished_init = False
        self.ser_con.close()

    # get serial data and convert hexstring to int.
    # after timeout: call serial_callback. This should guarantee,
    # that only one packet of data will be handled once
    def run(self, queue, name):
        if self.finished_init  is False:
            logging.error("TPMS not initialized.")
            return
        #name.value = "TPMS"
        no_data_counter = 0
        ser_data = list()
        data_available = False
        time_start = datetime.datetime.now()
        # flush rx data to get the latest data
        try: # pyserial > 3.0
            self.ser_con.reset_input_buffer()
        except: # pyserial < 3.0
            self.ser_con.flushInput()
        while True:
            if not self.finished_init:
                logging.error("Shutdown TPMS.")
                return
            try:
                serial_data_in = self.ser_con.read(1)
            except serial.serialutil.SerialException:
                logging.debug("Reading failed, stop recording TPMS.")
                break
            if serial_data_in:
                # convert string to their ascii int representation
                string = ord(serial_data_in)
                ser_data.append(string)
                #print("added data: time: %i"%int((time_start-datetime.datetime.now()).microseconds))
                data_available = True
                no_data_counter = 0
            elif data_available: # dont need to process, if no data is avilable
                no_data_counter += self.serial_sleep_time
                # 12 milliseconds time to receive data at 9600,8,N,1
                if data_available and no_data_counter > self.serial_sleep_time*6: # data is there and noch change since 12 microseconds
                    # run callback if data is there
                    logging.debug(ser_data)
                    self.serial_callback(ser_data, queue)
                    # reset variables
                    data_available = False
                    no_data_counter = 0
                    ser_data = list()
            time.sleep(self.serial_sleep_time)

    # test function for testing the decoder
    def testrun(self):
        dataset2 = [[35, 18, 129, 12, 70, 173, 117, 2, 0, 75, 2, 17],
                    [35, 18, 130, 12, 70, 173, 117, 2, 0, 75, 2, 17],
                    [35, 18, 131, 12, 70, 173, 117, 2, 0, 75, 2, 17],
                    [35, 18, 1,   12, 70, 173, 117, 2, 0, 75, 2, 17],
                    [35, 18, 2,   12, 70, 173, 117, 2, 0, 75, 2, 17],
                    [35, 18, 3,   12, 70, 173, 117, 2, 0, 75, 2, 17],
                    # data from ExtractDataFinal.py
                    [35, 18, 1,   12, 69, 251, 131, 1, 0, 71, 2, 41],
                    [35, 18, 1,   12, 69, 248, 207, 2, 0, 70, 2, 41],
                    [35, 18, 2,   12, 70, 172, 166, 2, 0, 72, 2, 39],
                    [35, 18, 3,   12, 70, 172, 166, 2, 0, 72, 2, 39],
                    [35, 18, 2,   12, 69, 251, 131, 1, 0, 71, 2, 37] ]
        logging.debug( "SensorID's: %s"%str(self.SENSORIDS))
        for data in dataset2:
            logging.debug(data)
            self.serial_callback(data, None)

    # data description 12 byte UART stream:
    # Data part  ; byte; unit; range     ; calculation;
    # Preamble   ; 0   ;     ;           ; 0x23 '#'
    # MSG-Nr     ; 1-2 ;     ; 0-2^16    ; big endian
    # ID         ; 3-6 ;     ; 32 Bit    ; Unique ID, big endian
    # Pressure   ; 7   ; mbar; 1024-4608 ; x*14+1024
    # Reserved   ; 8   ;     ; 0         ; ?
    # Temperature; 9   ; °C  ; -50-206   ; x-50
    # RSSI       ; 10-11; dBm ; 0-6553,5  ; (x[8]*256+x[9])/10
    #
    # #  DC2 [MSG][------ID--------][Pr]  [tem] [-rssi-]
    #[35, 18, 3,   12, 70, 173, 117, 2,  0, 75,   2,17 ]
    # data will be send every 15s while sensor is in motion

    # get data converted from hex-string to int in a list of ints
    #
    # Return value:
    # messenger_nummer  # string  # 0-2^16
    # id                # string  # 32 Bit unique id
    # pressure          # string  # 1024-4608 mbar
    # temperature       # string  # -50 - 206 °C
    # rssi              # string  # 0-6553.5  dBm

    # Decoding the incoming list of integers
    def TPMSdecoder(self, data, queue):
        # check if data has the minimum length.
        # TODO check if all items of list are integers
        if len(data) >= 12:
            # check if data starts with preamble
            if data[0] == 0x23: # '#'
                tpms_sensor_id = int.from_bytes(data[3:6+1], 'big')
                """
                # check if ID is in SENSORIDS, prevent other ID's from beeing logged
                if not tpms_sensor_id in self.SENSORIDS.values():
                    logging.info("SensorID \"%i\" is not in list."%(tpms_sensor_id))
                    return
                """
                res = dict()
                res['tpms_rel_time'] = str(time.perf_counter())
                res['tpms_messenger_nummer'] = str(int.from_bytes(data[1:2+1], 'big'))
                res['tpms_pressure'] = str(data[7]*14+1024)
                res['tpms_temperature'] = str(data[9]-50)
                res['tpms_rssi'] = str(((data[10]<<8) + data[11])/10)
                # debug bit 8: don't know what it does, probably reserved for later use
                if data[8]:
                    logging.debug('Data at bit 8: %s'%str(data[8]))
                # get ID Name by list of ints. (Reverse dict lookup)
                try:
                    res['tpms_id'] = list(self.SENSORIDS.keys())[list(self.SENSORIDS.values()).index(tpms_sensor_id)]
                except ValueError:
                    res['tpms_id'] = str(tpms_sensor_id)
                # add data to csvWriter
                if queue:
                    queue.put(res, True, 1.0/20.0) # block for maximum of 50ms
                logging.debug(res)
            else:
                logging.debug("No Preamble: %s"%str(data))
        else:
            logging.debug("Not the correct data length: %s"%str(data))

class GPSRecorder():
    def __init__(self, writerobj):
        self.finished_init = False
        # ----------------- init GPS ---------------------
        # set GPS to 10 Hz.
        #
        #os.system('sudo python3 /home/pi/git/raspberry/Programs/gpsconfig.py')

        # U-Blox USB GPS
        #os.system('sudo gpsd /dev/ttyACM0 -F /var/run/gpsd.sock')

        # Ultimate UART GPS
        #os.system('sudo gpsd /dev/ttyAMA0 -F /var/run/gpsd.sock')

        # Ultimate USB TTY GPS
        #os.system('sudo gpsd /dev/ttyUSB0 -F /var/run/gpsd.sock')

        self.gps3_conn = gps3.GPSDSocket()
        self.gps3_stream = gps3.DataStream()
        # needed in new versions!!! because of exception handling
        self.gps3_conn.connect()
        self.gps3_conn.watch()

        writerobj.add_headrow([ 'gps_timestamp', 'lat', 'lon', 'speed', 'alt', 'climb', 'error_longitude', 'error_latitude', 'gdop' ])
        logging.info("finished init of gps.")
        self.finished_init = True
        # Wait till gps fix is there
        for new_data in self.gps3_conn:
            if new_data:
                return
            time.sleep(1/2)

    def cleanup(self):
        self.gps3_conn.close()
        self.finished_init = False

    def run(self, queue, name):
        if self.finished_init  is False:
            logging.error("GPS not initialized.")
            return
        name.value = "GPS"
        logging.warning("start running gps")
        for new_data in self.gps3_conn:
            if not self.finished_init:
                logging.info("Shutdown GPS.")
                return
            if new_data:
                self.gps3_stream.unpack(new_data)
                if not isinstance(self.gps3_stream.TPV['speed'], str):  # lat/lon might be a better determinate of when data is 'valid'
                    # http://www.catb.org/gpsd/gpsd_json.html
                    speed           = self.gps3_stream.TPV['speed']
                    latitude        = self.gps3_stream.TPV['lat']
                    longitude       = self.gps3_stream.TPV['lon']
                    error_longitude = self.gps3_stream.TPV['epx']
                    error_latitude  = self.gps3_stream.TPV['epy']
                    gps_timestamp   = self.gps3_stream.TPV['time']
                    climb           = self.gps3_stream.TPV['climb']
                    gdop            = self.gps3_stream.SKY['gdop'] # Geometric DOP ( Geometric error )
                    if isinstance(self.gps3_stream.TPV['alt'], str):  # 'track' frequently is missing and returns as 'n/a'
                        altitude = self.gps3_stream.TPV['alt']
                    else:
                        altitude = abs(self.gps3_stream.TPV['alt'])  # absolute Kludge because sometimes altitude becomes submarine/subterrarian

                    #if isinstance(self.gps3_stream.TPV['track'], str):  # 'track' frequently is missing and returns as 'n/a'
                    #    heading = self.gps3_stream.TPV['track']
                    #else:
                    #    heading = round(self.gps3_stream.TPV['track'])  # and heading percision in hundreths is just clutter.

                    data = { 'gps_timestamp'  : str(gps_timestamp),
                             'lat'            : str(latitude),
                             'lon'            : str(longitude),
                             'speed'          : str(speed),
                             'alt'            : str(altitude),
                             'climb'          : str(climb),
                             'error_longitude': str(error_longitude),
                             'error_latitude' : str(error_latitude),
                             'gdop'           : str(gdop) }
                    queue.put(data, True, 1.0/20.0) # block for maximum of 50ms
            else:
                #TODO 10 Hz rate
                time.sleep(1/20)  # default GE refresh rate is 4 seconds, therefore no refresh older than 1 second from itself.

class CsvWriter:
    def __init__(self, pathname, filename, debug=False):
        logging.debug("start init csvWriter.")
        self.__debug = debug
        self.__filename = filename
        self.__pathname = pathname
        self.__headrow_fixed = [] # fixed for actual file
        self.__headrow = []
        self.__csvwriter1 = None
        self.__complete_filename = ""
        self.__start_timestamp = 0
        self.__time_measurement = list()
        self.__loop_list_measurement = list()
        self.__file = None
        # get actual index of folder.
        self.__running_index = 0

        # dict for basis writeout data.
        # should be the most often updated sensor.
        self.base_sensor_name = "IMU"

        for file in os.listdir(self.__pathname):
            if file.endswith("_id_" + self.__filename): #only *_id_$filename files
                #remove all after index. read only till first '_'
                number = int(file.split('_')[0])
                if number > self.__running_index:
                    self.__running_index = number
        if self.__running_index > 0:
            os.system("rm " + os.path.join(self.__pathname, "*_id_" + self.__filename))
            os.system("touch " + os.path.join(self.__pathname, str(self.__running_index) + "_id_" + self.__filename))
        logging.info("Index for filenames is now: " + str(self.__running_index))
        sys.stdout.flush()
        self.finished_init = True

    # add headrow from all sensors
    def add_headrow(self, data):
        self.__headrow = self.__headrow + data

    def run(self, queue, names):
        if not self.finished_init:
            logging.debug("CSV-Writer is not initialized.")
            return
        __loop_measurement = 0
        # get base queue to check which musst be full to get data
        # rest will go to other_sensors_queue
        other_sensors_queue = []
        base_sensor_queue = None
        for q,n in zip(queue, names):
            # TODO instead of use a fixed base sensor, get speed of every sensor and decide for the fastest one.
            if n.value == self.base_sensor_name:
                base_sensor_queue = q
            else:
                other_sensors_queue.append(q)
        if base_sensor_queue is None:
            logging.error("base_sensor_queue is not available, stop recording.")
            return

        while (True):
            if not self.finished_init:
                logging.warning("Shutdown CSV-Writer.")
                return
            if self.__debug:
                __loop_measurement +=1
                __timestamp_measurement = time.time()

            # if base_sensor_queue is not empty, get data
            if not base_sensor_queue.empty():
                updated_dicts = dict(base_sensor_queue.get(True, 1.0/100.0))
                for q in other_sensors_queue:
                    if not q.empty():
                        # https://gist.github.com/treyhunner/f35292e676efa0be1728
                        #updated_dicts = {**updated_dicts, **dict(q.get(True, 1.0/20.0)) # really faster(x2) if Python 3.5 is avialable...
                        updated_dicts = dict(updated_dicts, **dict(q.get(True, 1.0/100.0))) # block for maximum of 10ms
            else:
                # retry in the loop
                continue

            # there will be always data, if program reaches this point
            if self.__debug:
                # loop cycles measurement
                self.__loop_list_measurement.append(__loop_measurement - 1)
                __loop_measurement = 0
                if len(self.__loop_list_measurement) >= 100:
                    logging.debug("writeout needs: {:,.2f}".format(sum(self.__loop_list_measurement)/float(len(self.__loop_list_measurement)))+" loops before success.")
                    self.__loop_list_measurement = list()

                # time measurement
                self.__time_measurement.append(float(time.time() - __timestamp_measurement))
                __timestamp_measurement = 0
                if len(self.__time_measurement) >= 100:
                    logging.debug("writeout_time needs: {:,.2f}".format(sum(self.__time_measurement)/float(len(self.__time_measurement))*1000)+"ms.")
                    self.__time_measurement = list()

            #filter keys to ensure that there are no keys that are not in headrow:
            updated_dicts2 = {key: value for key, value in updated_dicts.items() if key in self.__headrow}
            # all keys not in data, but in headrow should be NaN. At the moment were will be nothing written out

            # FIXME really dangerous, because if IMU is not present, there will be no timestamp
            # TODO propably let every program write same timedata to struct. the thn will be merged.
            # if so, you musst reverse order when mergeing the dicts and add primary dict/queue as last.
            t_stamp = int((updated_dicts2['rel_counter']).split('.',1)[0])
            self.__writeout(updated_dicts2, t_stamp, Maxtime)
            #sys.stdout.flush()

    #Save to csv File
    def __writeout(self, data, actual_timestamp, maxtime):
        # check if there is a need of a new file
        nextfile = False
        if int(actual_timestamp - self.__start_timestamp) > maxtime:
            nextfile = True

        # when a file finished, close file and compress it.
        if nextfile and self.__file:
            self.__file.close() # terminate file descriptor
            os.rename(self.__complete_filename + "~", self.__complete_filename)
            #Compress file directly
            os.system("gzip " + self.__complete_filename + " &")
            #logging.debug("Compressed file, starting new file.")

        # start a new file
        if  nextfile or not self.__file:
            self.__start_timestamp = actual_timestamp
            if self.__debug:
                logging.debug("nextfile:" + str(nextfile) + ", csvwriter:" + str(self.__csvwriter1))
            self.__running_index = self.__running_index + 1
            #filename = pathname / running_index _ filename .csv
            self.__complete_filename = self.__pathname + self.__filename + "_" + str(self.__running_index) + "_%.2f" % self.__start_timestamp + ".csv"

            logging.debug("new filename: " + str(self.__complete_filename) + "~")
            self.__headrow_fixed = self.__headrow # use actual headrow
            if self.__debug:
            #    logging.debug("headrow: " + str(self.__headrow_fixed))
                logging.debug("touch " + self.__pathname + str(self.__running_index) + "_id_" + self.__filename)
            os.system("touch " + self.__pathname + str(self.__running_index) + "_id_" + self.__filename)
            self.__file = open(self.__complete_filename + "~", 'w', newline='')
            self.__csvwriter1 = csv.DictWriter(self.__file, delimiter=',',
                                   quotechar='|', quoting=csv.QUOTE_MINIMAL, fieldnames=self.__headrow_fixed,
                                   extrasaction='raise')#ignore
            if self.__debug:
                logging.debug("csvwriter:" + str(self.__csvwriter1))

            self.__csvwriter1.writeheader()
            nextfile = False

        self.__csvwriter1.writerow(data) #write gpsdata and 9 axis data and button data

    def cleanup(self):
        #self.__file.close()
        self.finished_init = False
        #del self.__csvwriter1
        self.close

    def close(self):
        #Close file correctly and rename

        #FIXME: hack -.-

        # get actual index of folder.
        self.__running_index = 0
        for file in os.listdir(self.__pathname):
            if file.endswith("_id_" + self.__filename): #only *_id_$filename files
                #remove all after index. read only till first '_'
                number = int(file.split('_')[0])
                if number > self.__running_index:
                    self.__running_index = number
        if self.__running_index > 0:
            os.system("rm " + self.__pathname + "*_id_" + self.__filename)
            os.system("touch " + self.__pathname + str(self.__running_index) + "_id_" + self.__filename)
        #logging.debug("index: " + str(self.__running_index))
        filename = self.__filename + "_" + str(self.__running_index)
        #logging.debug("filename_search: " + filename)
        for file in os.listdir(self.__pathname):
            if filename in file: # and file.endswith("*.csv~"):
                filename = self.__pathname + file
                break
        logging.warning("Renamed file to " + filename[:-1] + ".")
        os.rename(filename, filename[:-1])
        if self.__file:
            self.__file.close()
        # zip file
        os.system("gzip " + filename)
        #logging.debug(str(vars(self)))
        sys.stdout.flush()



class NineAxisRecorder():
    def __init__(self, sensor_id, debug, Settingsfile, writerobj):
        self.finished_init = False
        self.poll_interval = 100
        #Filename without extension, then we can add timestamp

        self.sensor_id = sensor_id

        logging.info("Using settings file " + Settingsfile)
        if not os.path.exists(Settingsfile):
          logging.error("Settings file does not exist, will be created")

        self.s = RTIMU.Settings(os.path.splitext(Settingsfile)[0])
        self.imu = RTIMU.RTIMU(self.s)

        logging.info("IMU Name: " + self.imu.IMUName())

        if (not self.imu.IMUInit()) or (self.imu.IMUName() == "Null IMU"):
            logging.error("IMU " + str(sensor_id) + " Init failed")
            return
        else:
            logging.warning("IMU " + str(sensor_id) + " Init success")

        # this is a good time to set any fusion parameters

        self.imu.setSlerpPower(0.02)
        self.imu.setGyroEnable(True)
        self.imu.setAccelEnable(True)
        self.imu.setCompassEnable(True)

        self.poll_interval = self.imu.IMUGetPollInterval()
        logging.warning("Recommended Poll Interval: %dmS\n" % self.poll_interval)
        if self.poll_interval < 1:
            self.poll_interval = 0.01
        self.timestamp  = time.time()
        self.time_index = 0
        self.time_sumup = 0
        writerobj.add_headrow(['timestamp', 'sensor_id',
                               'x-accel'  , 'y-accel'  , 'z-accel',
                               'x-gyro'   , 'y-gyro'   , 'z-gyro',
                               'rel_counter'#,
                               #'x-comp'   , 'y-comp'   , 'z-comp',
                               #'w-quat'   , 'x-quat'   , 'y-quat', 'z-quat',
                               #'yaw'      , 'pitch'    , 'roll',
                               #'x-compensation', 'y-compensation', 'z-compensation']
                               ])
        self.debug = debug
        logging.warning("finished init of nineAxis.")
        self.finished_init = True
        sys.stdout.flush()

    def cleanup(self):
        self.finished_init = False

    def run(self, queue, name):
      if not self.finished_init:
          logging.warning("NineAxis not initialized.")
          return
      logging.debug('queue:'+str(queue))
      name.value = "IMU"
      logging.warning("start running nineAxis with sleep time: "+str(self.poll_interval*1.0/1000.0))
      loops_before_success = 0
      time_before_success=list([list(),list()])
      last_time_before_success = time.time()

      while True:
          if not self.finished_init:
              logging.warning("Shut down NineAxis.")
              return
          last_time_before_success = (time.time())
          loops_before_success += 1
          if self.imu.IMURead():
              time_before_success[0].append(loops_before_success-1)
              time_before_success[1].append(time.time()-last_time_before_success)
              # x, y, z = imu.getFusionData()
              # logging.debug("%f %f %f" % (x,y,z))
              data = self.imu.getIMUData()

              #rollpitchyaw = data["fusionPose"]
              #quaternions  = data["fusionQPose"]
              #compass_data = data["compass"]
              accel_data   = data["accel"]
              gyro_data    = data["gyro"]

              # element-wise calculation of DCM from attitude quaternion

              #dcm_13 = 2 * ((quaternions[1] * quaternions[3]) - (quaternions[0] * quaternions[2]))
              #dcm_23 = 2 * ((quaternions[2] * quaternions[3]) + (quaternions[0] * quaternions[1]))
              #dcm_33 = (2* math.pow(quaternions[0],2)) - 1  + (2 *  math.pow(quaternions[3],2))

              # element-wise calculation of gravity-compensated accel data
              # caution with the sign of the dcm_element, because it depends on the convention that is used for the gravity vector, in this case(07-01-2016) g = -1
              # also keep in mind wether attitude quaternion describes rotation from inertial to body frame or otherwise

              #a_comp_x = math.copysign(1, accel_data[0]) * (math.fabs(accel_data[0]) - math.fabs(dcm_13)* 1.0077);
              #a_comp_y = math.copysign(1, accel_data[1]) * (math.fabs(accel_data[1]) - math.fabs(dcm_23)* 1.0077);
              #a_comp_z = math.copysign(1, accel_data[2]) * (math.fabs(accel_data[2]) - math.fabs(dcm_33)* 1.0077);

              time_x = time.time()
              self.timediff   = time_x -  self.timestamp
              self.timestamp  = time_x

              self.time_index = self.time_index + 1
              self.time_sumup = self.time_sumup + self.timediff

              loops_before_success = 0
              if (self.time_index >= 100) and (self.debug == True) :
                  logging.debug(self.sensor_id + ":: rate: {:,.1f}".format(self.time_index/self.time_sumup) + \
                        "Hz. warteloops: {:,.2f}".format(sum(time_before_success[0]) / float(len(time_before_success[0])))+ \
                        " max: "+str(max(time_before_success[0]))+ \
                        " -if condition- -time: {:,.2f}".format(sum(time_before_success[1]) / float(len(time_before_success[1]))*1000.0)+ " ms.") #only waiting loops
                  time_before_success=list([list(),list()])
                  self.time_index = 0
                  self.time_sumup = 0
                  sys.stdout.flush()
              #Write data to csv-File
              dict_ = { 'timestamp' : str(self.timestamp),  'sensor_id' : str(self.sensor_id),
                        'x-accel'   : str(accel_data[0]),   'y-accel'   : str(accel_data[1]),   'z-accel' : str(accel_data[2]),
                        'x-gyro'    : str(gyro_data[0]),    'y-gyro'    : str(gyro_data[1]),    'z-gyro'  : str(gyro_data[2]),
                        'rel_counter': str(time.perf_counter())#,
                        #'x-comp'    : str(compass_data[0]), 'y-comp'    : str(compass_data[1]), 'z-comp'  : str(compass_data[2]),
                        #'w-quat'    : str(quaternions[0]),  'x-quat'    : str(quaternions[1]),  'y-quat'  : str(quaternions[2]), 'z-quat' : str(quaternions[3]),
                        #'yaw'       : str(rollpitchyaw[2]), 'pitch'     : str(rollpitchyaw[1]), 'roll'    : str(rollpitchyaw[0]),
                        #'x-compensation' : str(a_comp_x), 'y-compensation' : str(a_comp_y), 'z-compensation' : str(a_comp_z)
                      }
              queue.put(dict_, True, 1.0/100.0) # block for maximum of 10ms
          #last_time_before_success = (time.time())
          time.sleep(self.poll_interval*1.0/1000.0/50.0)

class ButtonRecorder():
    # Array of dicts : [{'desc': 'unique description', 'number': 'integer for raspi pins', 'sense_state': GPIO.HIGH or GPIO.LOW},{...}]
    def __init__(self, Pins, writerobj):
        self.headrow = []
        self.Pins = Pins
        GPIO.setmode(GPIO.BCM)
        for pin in self.Pins:
            if pin['sense_state'] is GPIO.HIGH:
                GPIO.setup(pin['number'], GPIO.IN, pull_up_down=GPIO.PUD_DOWN) # Pulldown -> Warte auf 3.3V
            else:
                GPIO.setup(pin['number'], GPIO.IN, pull_up_down=GPIO.PUD_UP) # Pullup -> Warte auf 0V
            #add to global headrow
            writerobj.add_headrow([pin['desc']])
        self.finished_init = True
        sys.stdout.flush()
        self.__running_number = 0

    def cleanup(self):
        self.finished_init = False

    def run(self, queue, name):
        if not self.finished_init:
            logging.debug("Buttons not initialized.")
            return
        name.value = "Button"
        logging.debug("Buttons initialized. Running While loop.")
        while True:
            if not self.finished_init:
                logging.warning("Shutdown Buttons.")
                return
            self.__running_number += 1
            data = { }
            for pin in self.Pins:
                if GPIO.input(pin['number']) == pin['sense_state']:
                    data[pin['desc']] = 1
                else:
                    data[pin['desc']] = 0
            queue.put(data, True, 1.0/20.0) # block for maximum of 50ms
            time.sleep(1/10.0)
        sys.stdout.flush()

def sigterm_handler(_signo, _stack_frame):
    # Raises SystemExit(0):
    global sensorobj
    global writerobj
    logging.debug("Killing Threads...")
    for sobj in sensorobj:
        sobj.cleanup()
    time.sleep(2)
    writerobj.cleanup()

logfile = os.path.join("/home/pi/logging_data/","SensorRecorder_log")
logging.basicConfig(level=logging.WARNING,
#                    filename=logfile,
#                    filemode='a', # append to file
                    format='[%(levelname)s] (%(threadName)-10s) %(message)s',
                    )

if __name__ == '__main__':
    global sensorobj
    global writerobj
    # Enable SIGTERM Handler
    signal.signal(signal.SIGTERM, sigterm_handler)
    logging.warning("start at " + os.path.dirname(sys.argv[0]) + "/")
    logging.warning("argv: "+ sys.argv[0])
    # try to get logging directory from cmd line arg
    try:
        logging.warning("settingsfile is: " + sys.argv[1])
        LSM9DS1_settingsfile = os.path.normpath(os.path.expanduser(sys.argv[1]))
    except:
        LSM9DS1_settingsfile = os.path.expanduser("/home/pi/git/LSM9DS1.ini")
    global pathname
    try:
        logging.warning("base logpath is: " + sys.argv[2])
        pathname = os.path.normpath(os.path.expanduser(sys.argv[2]))
    except:
        pathname = '/home/pi/logging_data/'
    # logging
#    logfile = os.path.join(pathname,"SensorRecorder_log")
#    logging.basicConfig(level=logging.DEBUG,
##                        filename=logfile,
##                        filemode='a', # append to file
#                        format='[%(levelname)s] (%(threadName)-10s) %(message)s',
#                        )
    logging.warning("LogFile: "+str(logfile))
    # creating objects for the sensors the nineAxisSensors are the sensors with the highest update rate. so they writeout all data to csv.
    #filenameshould not contain underscores '_' and pathname should end with slash '/'
    sensorobj = []
    ######################################only adding HERE Sensor Object. rest will be done automatically! #######################################################
    logging.warning("Init Writer obj.")
    writerobj = CsvWriter(pathname,  filename + "2_sensor_LSM9DS1_9Achsen", debug = True)
    logging.warning("Start init TPMSRecorder.")
    sensorobj.append(TPMSRecorder    (writerobj=writerobj))
    logging.warning("Start init Buttons.")
    sensorobj.append(ButtonRecorder  ([{'desc': 'button1', 'number': PIN_SCHLAGLOCH1, 'sense_state': GPIO.HIGH},{'desc': 'button2', 'number': PIN_SCHLAGLOCH2, 'sense_state': GPIO.HIGH}], writerobj=writerobj ))
    logging.warning("Start init GPS.")
    sensorobj.append(GPSRecorder     (writerobj=writerobj))

    #sensorobj.append(NineAxisRecorder(pathname, filename + "0", "sensor_mpu6050_" + hex(address1), debug=False, Settingsfile="MPU6050_" + hex(address1)))
    #sensorobj.append(NineAxisRecorder(pathname, filename + "1", "sensor_mpu6050_" + hex(address2), debug=False, Settingsfile="MPU6050_" + hex(address2)))
    logging.warning("Start init IMU.")
    sensorobj.append(NineAxisRecorder('sensor_LSM9DS1_9Achsen', debug=True, Settingsfile=LSM9DS1_settingsfile, writerobj=writerobj))
    ######################################################end#####################################################################################################

    try:
        # multiprocess shared memory
        manager = Manager()
        queue = []
        names = []
        p = []
        for sobj in sensorobj[::-1]: # iterate in reverse
            queue.append(manager.Queue())
            names.append(manager.Value(' ', 0))
            p.append( Process(target=sobj.run, args=(queue[-1], names[-1])))
        #logging.debug('Queue all:'+str(queue))
        p.append(Process(target=writerobj.run, args=(queue, names)))

        for pp in p:
            logging.debug(str(pp)+".start")
            pp.start()
        for pp in p:
            logging.debug(str(pp)+".join")
            pp.join()
        logging.debug("names is :" + str(names))
        logging.debug("queue is :" + str(queue))

    # would occour in debugging mode with Ctrl+C or when sending SIGTERM
    finally:
        logging.warning("Killing Threads...")
        for sobj in sensorobj:
            sobj.cleanup()
        writerobj.cleanup()

        logging.warning("Done.\nExiting.")
        sys.stdout.flush()

