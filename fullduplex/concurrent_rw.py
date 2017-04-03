#!/usr/bin/python
import struct
import thread
import time

def write_rep(count=1000):
	start = 0
	with open("/dev/hidg1", "wb") as fout:
		for i in range(count):
			report= struct.pack("64s", "Number " + str(i))
			fout.write(report)
			if (i == 0):
				start = time.time()
	duration = time.time() - start
	KBps = count * 64 / 1024 / duration
	print "Count " + str(count) + " reports written in " + str(duration) + " seconds (" + str(KBps) + " KB/s)"

def read_rep(count=1000):
	start = 0
	with open("/dev/hidg1", "rb") as fin:
		for i in range(count):
			inbytes = fin.read(64)
			report= struct.unpack("64s", inbytes)
			# print report
			if (i == 0):
				start = time.time()
	duration = time.time() - start
	KBps = count * 64 / 1024 / duration
	print "Count " + str(count) + " reports read in " + str(duration) + " seconds (" + str(KBps) + " KB/s)"


in_count=16*1024
out_count=16*1024

# blocking read as trigger
read_rep(1)


thread.start_new_thread(write_rep, (out_count, ))
read_rep(in_count-1) # one report has been read ahead as trigger
