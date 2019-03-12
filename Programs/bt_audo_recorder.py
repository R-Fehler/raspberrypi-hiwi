#!/usr/bin/env python3

##
#  This Script will record sound from the default audio source.
#  
#  
##

#Imports
import os
import sys
import pyaudio
import wave
import logging
import time
import signal

logging.basicConfig(level=logging.DEBUG,
                    format='[%(levelname)s] (%(threadName)-10s) %(message)s',
                    )

# default recording settings
CHUNK_SIZE = 1024
SAMPLERATE = 44100
CHANNELS = 1
#recording time per file in sec
RECTIME_PER_FILE=60*5 #5min

class Recorder(object):
    """
    A recorder class for recording audio to a WAV file.
    Records in mono by default.
    """

    def __init__(self, channels=CHANNELS, rate=SAMPLERATE, frames_per_buffer=CHUNK_SIZE):
        self.p = pyaudio.PyAudio()
        self.channels = channels
        self.format = self.p.get_format_from_width(2) #pyaudio.paInt16
        self.rate = rate
        self.frames_per_buffer = frames_per_buffer
        self.stream = None
        self.wavefile = None
        self.__rectime = 0
        self.stoprec = False
        self.__running_index = 0
        self.__file_time = [0,0]
        self.path_is_set = False

    def list_devices(self):
        # List all audio input devices
        logging.debug("-"*20)
        for i in range( self.p.get_device_count() ):
            dev = self.p.get_device_info_by_index(i)
            logging.debug (str(i)+'. '+str(dev['defaultSampleRate'])+
                           ' in:'+str(dev['maxInputChannels'])+
                           ' out:'+str(dev['maxOutputChannels'])+
                           ' '+dev['name'])

    def get_device_number(self):
        # return valid device number
        for i in range( self.p.get_device_count() ):
            dev = self.p.get_device_info_by_index(i)
            if "pulse" in dev['name'] :
              return i
        return None

    def __record_nonblocking(self, device):
        # open stream based on device number
        # if no special number needed, put 'None' in it.
        logging.debug("use device: "+str(device))
        self.stream = self.p.open(format=self.format,
                           channels=self.channels,
                           rate=self.rate,
                           input=True,
                           frames_per_buffer=self.frames_per_buffer,
                           input_device_index = device,
                           stream_callback=self._nonblocking_callback())

    def record_start(self, device):
        if not self.path_is_set:
            logging.error('Please Set Path deatils before starting recording.')
            return False
        self.frames = 0
        self.stream_broken = 0
        self.timestamp = time.time()
        logging.debug("start recording with chunk length of "+str(self.__rectime/60)+" min.")
        #logging.debug("-"*40)
        self.wavefile = self._prepare_file()
        if not self.wavefile:
            # if opening a new file is not possible, dont start class
            return
        # prevent stream from writing to early into self.wavefile
        print("self.wavefile: object: "+str(self.wavefile))
        self.__record_nonblocking(device)
        self.stream.start_stream()
#        # wait for stream to finish (5)
#        while self.stream.is_active():
#          time.sleep(10.0 / 100.0)
        sys.stdout.flush()

    def StopRecord(self):
        # stop_stream hungs
        #self.stream.stop_stream()
        if self.stream:
            self.stream.close()

    def last_update(self):
        return (time.time() - self.timestamp) / self.frames_per_buffer * self.rate

    # internal function
    def _nonblocking_callback(self):
        def callback(in_data, frame_count, time_info, status):
            #logging.debug("Got Callback.")
            # if Callback is not called during the whole time,
            # please check if the bluetooth decice connected to is playing music already.
            # if it is not playing, the script will terminate with an timeout.
            if self.stoprec is True:
                logging.debug("[Nonblocking-callback]: Stopping Recorder")
                return (None, pyaudio.paComplete)
            self.wavefile.writeframes(in_data)
            self.timestamp = time.time()
            #print(str(max(in_data)))
            if status != 0:
                logging.debug("status: " + status)
            self.frames += frame_count # 1 frame *frames per buffer
            if self.frames >= self.__rec_frames*self.frames_per_buffer: # \
                # or max(in_data) == 0: #correct rounding
                #missing_frames  = self.__rec_frames - self.frames/self.frames_per_buffer
                #self.stream_broken = missing_frames
                #logging.info("finished file, " + str(missing_frames) + " Frames missing.")
                self.wavefile.close()
                #rename File to mark it system wide as finished
                path = self._get_new_filename(setNewTime=False)
                if os.path.isfile(path + "~"):
                    os.rename(path + "~", path)
                # Zip file
                os.system("gzip " + path + " &")
                #if missing_frames: #rename file for correct duration
                #  oldpath = self._get_new_filename(broken = False, setNewTime=False)
                #  path = self._get_new_filename(broken = True, setNewTime=False, frames=self.frames/self.frames_per_buffer)
                #  os.rename(oldpath, path)
                #  logging.debug("Rename Path: " + path)
                #  return (None, pyaudio.paComplete) ## exit thread
                #else:
                # Resetting file name and other values for next file
                self.frames = 0
                self.wavefile = self._prepare_file()
                if not self.wavefile:
                    # if opening a new file is not possible, finish callback
                    return (None, pyaudio.paComplete)
                logging.debug("Path: " + path)
            return (None, pyaudio.paContinue) # in_data
        return callback

    def _prepare_file(self, mode='wb'):
        # get actual id
        self.__running_index = self.__running_index + 1
        # touch file with new id
        id_filename = str(self.__running_index) + "_id_" + self.__prefix
        os.system("touch %s" % os.path.join(self.__pathname, id_filename))
        logging.debug('id_fname: %s' % id_filename)
        # open new file for recording
        filename = self._get_new_filename() + "~"
        logging.debug('filename: %s' % filename)
        wavefile = wave.open(filename, mode)
        wavefile.setnchannels(self.channels)
        wavefile.setsampwidth(self.p.get_sample_size(pyaudio.paInt16))
        wavefile.setframerate(self.rate)
        if not wavefile:
            logging.debug("Creating a new wavefile failed. Stop recording.")
            return None
        return wavefile

    def SetPathDetails(self, rectime, directory, prefix='rec', suffix='wav'):
        self.__rectime    = rectime
        self.__pathname  = directory # with
        self.__prefix     = prefix
        self.__suffix     = suffix
        self.__rec_frames = int(self.rate * self.__rectime / self.frames_per_buffer)

        # get actual id in direcory self.__pathname
        for file in os.listdir(self.__pathname):
            if file.endswith("_id_" + self.__prefix): #only *_id_$prefix files
                #remove all after index. read only till first '_'
                number = int(file.split('_')[0])
                if number > self.__running_index:
                    self.__running_index = number
        if self.__running_index > 0:
            os.system("rm " + os.path.join(self.__pathname, "*_id_" + self.__prefix))
            os.system("touch " + os.path.join(self.__pathname, str(self.__running_index) + "_id_" + self.__prefix))
        logging.debug("Index for filenames is now: " + str(self.__running_index))
        # if all is correct, set to true
        self.path_is_set = True

    # broken: for renaming file if not all frames are received
    # noNewTime : if time from last path should be used
    # frames : how much frames are received (should be less than the maximum)
    def _get_new_filename(self, broken=False, setNewTime=True, frames=0):
        if setNewTime is True : #and self.__file_time != 0:
            self.__file_time[0] = time.perf_counter() #relative time from start # time.datetime.now()
            self.__file_time[1] = time.time()
        if broken is True:
          recorded_frames = frames
        else:
          recorded_frames = self.__rec_frames
        filename = '%(prefix)s_%(index)i_rel:%(rel_counter).2f_abs:%(abs_counter).2f-length:%(duration).2f.%(suffix)s' % \
                   {'prefix': self.__prefix, 'index': self.__running_index, 'rel_counter': self.__file_time[0], \
                    'abs_counter': float(self.__file_time[1]), \
                    'duration': (recorded_frames / self.rate * self.frames_per_buffer), 'suffix': self.__suffix}
        respath = os.path.join(self.__pathname, filename)
        return respath

    def CheckForFinished(self):
        # wait for stream to finish (5)
        if self.stream is None:
            #self.stream.stop_stream()
            return False
        elif self.stream.is_active() is False:
            return False
        else:
            return True

    def CleanAfterBrokenRecord(self):
        self.stoprec = True
        self.wavefile.close()
        oldpath = self._get_new_filename(broken = False, setNewTime=False) + "~"
        if self.frames/self.frames_per_buffer < 5:
            logging.error('There are only %i frames; dropping file.' % self.frames/self.frames_per_buffer)
            # remove file completely, if too less information
            os.remove(oldpath)
        else:
            missing_frames = self.__rec_frames - self.frames/self.frames_per_buffer
            logging.info("finished file, " + str(missing_frames) + " Frames missing.")
            path = self._get_new_filename(broken = True, setNewTime=False, frames=self.frames/self.frames_per_buffer)
            os.rename(oldpath, path)
            logging.debug("Rename Path: " + path)
            # Zip file
            os.system("gzip " + path)

def sigterm_handler(_signo, _stack_frame):
    # Raises SystemExit(0):
    global r
    logging.debug("ru into sigterm handler. start terminating.")
    # really? first exit and then cleaning?
    sys.exit(0)
    r.StopRecord()
    r.CleanAfterBrokenRecord()

if __name__ == '__main__':
    # init Recorder
    global r
    r=Recorder()
    signal.signal(signal.SIGTERM, sigterm_handler)
    logging.debug("start at " + os.path.dirname(sys.argv[0]) + "/")
    logging.debug("argv: " + sys.argv[0])
    # try to get logging directory from cmd line arg
    try:
        logging.debug("rec_saving to "+sys.argv[1])
        directory = os.path.normpath(os.path.expanduser(sys.argv[1]))
    except:
        directory = os.path.expanduser("~/rec_files/")

    logging.debug("rec_saving to " + directory)
    # create directory if not exsistent
    if not os.path.exists(directory):
      os.makedirs(directory)

    r.SetPathDetails(RECTIME_PER_FILE,directory)
    # list all possible devices
    r.list_devices()
    bind = r.get_device_number()
    if bind is None:
      logging.debug("No Microphone")
    else:
      r.record_start(device=bind)
#      while(True):
#        logging.debug("waiting for finishing file.")
#      while r.CheckForFinished(): # Waiting that Recording finished
      if r.CheckForFinished():
          while True:
            time.sleep(10.0 / 20.0)
            lu = r.last_update()
            # Timeout of bluetooth will be lu = 650 - 800
            if lu > 150 : # lu > 50 and lu < 30:
              logging.debug("Bluetooth-Connection possibly lost: %s*t_Callback."%(str(lu)))
              logging.debug("stop Recorder.")
              r.StopRecord()
              logging.debug("cleanup Files.")
              r.CleanAfterBrokenRecord()
              break
      else:
        logging.debug("Probably no stream was started -.-. Quitting")
      #if r.CheckForBroken():
      #  break #Terminate script, because stream is interrupted and BT device isn't any more available
    logging.debug("done bt_audio_recorder.py")

