#!/usr/bin/python
import struct
import thread
import time
import os
import struct
import Queue
import time


class LinkLayer:
	def __init__(self, devfile_in, devfile_out):
		self.state={}
		self.state["qout"] = Queue.Queue()
		self.state["qin"] = Queue.Queue()
		self.state["MAX_OUT_QUEUE"]=32 # how many packets are allowed to be pening in output queue (without ACK received)
	
		# last sequence number used in sending 
		# Note:	care has to be taken for the fact that the host side begins sending
		# 	and thus an initial ack is received, but a sequence number has never been sent
		#	This is a corner case on first packet exchange (an ACK flag wouldn't be set on the first 
		#	packet sent by the host if this would be TCP, but we don't introduce a flag for a corner case)
		# this could be solved, by doing an initial read to trigger commincation, but 
		# wouldn't be robust on reconnection after link interrupt (e.g. PowerShell client is restarted)
		self.state["last_seq_used"]=-1 # placeholder, gets overwritten on syncing
		self.state["last_valid_ack_rcvd"]=-1  # placeholder, gets overwritten on syncing
		self.state["resend_request_rcvd"]=False
		self.state["peer_state_changed"]=False
		self.fin = devfile_in
		self.fout = devfile_out

	def start(self):
		#sync linklayer (Send with SEQ till correct ACK received)
		self.sync_link()

		# start write thread
		print "Starting write thread"
		thread.start_new_thread(self.write_rep, ( ))

		# start read thread
		print "Starting read thread"
		thread.start_new_thread(self.read_rep, ( ) )



	def write_rep(self):
		DEBUG=False
	
		MAX_SEQ = self.state["MAX_OUT_QUEUE"] # length of output buffer (32)
		next_seq = 0 # holding next sequence number to use
		qout = self.state["qout"] # reference to outbound queue
		outbuf = [None]*MAX_SEQ # output buffer array
		last_seq_used = self.state["last_seq_used"]
		
		# fill outbuf with empty heartbeat reports (to have a valid initial state)
		for i in range(MAX_SEQ):
			# fill initial output buffer with heartbeat packets
			SEQ = i
			payload = ""
			outbuf[i] = struct.pack('!BB62s', len(payload), SEQ, payload )
	
		# start write loop
		while True:
#			time.sleep(0.5) # test delay, to slow down thread (try to produce errors)

#			last_seq = self.state["last_seq_used"]
			next_seq = last_seq_used + 1
			# cap sequence number to maximum (avoid modulo)
			if next_seq >= MAX_SEQ:
				next_seq -= MAX_SEQ
			last_valid_ack_rcvd = self.state["last_valid_ack_rcvd"]


			is_resend = self.state["resend_request_rcvd"]


#			print "Windows peer state changed " + str(self.state["peer_state_changed"])
			if self.state["peer_state_changed"]:
				self.state["peer_state_changed"] = False # state changed is handled one time here
			else:
				continue # CPU consuming "do nothing"			


			# calculate outbuf start / ebd, fill region start/end and (re)send start/end
			outbuf_start = last_valid_ack_rcvd + 1
			if outbuf_start >= MAX_SEQ:
				outbuf_start -= MAX_SEQ
			outbuf_end = outbuf_start + MAX_SEQ - 1

			outbuf_fill_start = last_seq_used + 1
			if outbuf_fill_start < outbuf_start:
				outbuf_fill_start += MAX_SEQ
			elif  outbuf_fill_start > outbuf_end:
				outbuf_fill_start -= MAX_SEQ
			outbuf_fill_end = outbuf_end 
			# corner case, if resend of whole buffer is requested it mustn't be refilled
			if is_resend and (next_seq == outbuf_fill_start):
				outbuf_fill_start = outbuf_fill_end

			outbuf_send_start = outbuf_fill_start
			if is_resend:
				outbuf_send_start = outbuf_start
			outbuf_send_end = outbuf_end

			usable_send_slots = outbuf_fill_end - outbuf_fill_start

			if DEBUG:
				print "===================== Writer stats ===================================================="
				print "Writer: Last valid ACK " + str(last_valid_ack_rcvd)
				print "Writer: Last SEQ used " + str(last_seq_used)
				if is_resend:
					print "Writer: Answering RESEND "
				print "Writer: OUTBUF position from " + str(outbuf_start) + " to " + str(outbuf_end)
				print "Writer: OUTBUF fill position from " + str(outbuf_fill_start) + " to " + str(outbuf_fill_end)
				print "Writer: OUTBUF send position from " + str(outbuf_send_start) + " to " + str(outbuf_send_end)
				print "Writer: OUTBUF usable send slots " + str(usable_send_slots)
				print "======================================================================================="

			# fill usable send slots in outbuf
			for seq in range(outbuf_fill_start, outbuf_fill_end):
				# sequence number to use in slot
				current_seq = seq
				# clamp sequence number to valid range
				if current_seq >= MAX_SEQ:
					current_seq -= MAX_SEQ

#				print "Writer: Setting outbuf slot " + str(current_seq)


				payload = None
				if qout.qsize() > 0:
					payload = qout.get()
				else:
					# this means we send reports, even if outbound queue is empty (heartbeat)
					payload = "" # receiver ignores packets with empty payload

				report = struct.pack('!BB62s', len(payload), current_seq, payload )

#				print "Payload: " + payload
					
				# put report into current slot in outbuf
				outbuf[current_seq] = report

			# fill usable send slots in outbuf
			for seq in range(outbuf_send_start, outbuf_send_end):
				# sequence number to use in slot
				current_seq = seq
				# clamp sequence number to valid range
				if current_seq >= MAX_SEQ:
					current_seq -= MAX_SEQ


				# write report to device (outbuf would only be needed for resending)
				# at this point, resending of lost reports should take place, which isn't implemented
				# right now, as we don't send more reports than the number which could be buffered on receivers end (32 reports)
				written = self.fout.write(outbuf[current_seq])

				# update last used sequence number in state
				last_seq_used = current_seq
					
				# DEBUG
#				print "Writer: Written with seq " + str(current_seq) + " payload " + outbuf[current_seq][4:]

			self.fout.flush() # push written data to device file
			
			# update last used sequence number in state
			#last_seq_used = outbuf_send_end - 1
			#if last_seq_used >= MAX_SEQ:
			#	last_seq_used -= MAX_SEQ

#			print "Last SEQ used after write loop finish " + str(last_seq_used)
#			self.state["last_seq_used"] = last_seq_used

			self.state["resend_request_rcvd"] = False # disable resend if it was set
	
	

	def read_rep(self):
		MAX_OUT_QUEUE = self.state["MAX_OUT_QUEUE"]
	
		# state values to detect SENDER state changes across repeated reports
		last_BIT7_FIN = 0	
		last_BIT6_RESEND = 0
		last_ACK = -1
	
		qin = self.state["qin"] # reference to inbound queue
	
		while True:
#			time.sleep(1.5) # slow down loop, try to produce errors

			inbytes = self.fin.read(64)
			#report = struct.unpack('!BBBB60s', inbytes)
			report = struct.unpack('!BB62s', inbytes)
			
			BIT7_FIN = report[0] & 128
			BIT6_RESEND = report[0] & 64
			LENGTH = report[0] & 63
			ACK = report[1] & 63

			# if length > 0 (no heartbeat) push to input queue
			if LENGTH > 0:
				qin.put(report[2])
	

			# as state change of the other peer is detected by comparing header fields from the last received report to the current received
			# as reports are flowing coninuosly (with or without payload), the same state could be reported by the other peer repetively
			# Example: 	The other peer misses a packet (out-of-order HID input report SEQ number)
			#		this would lead to a situation, where the other peer continuosly sends RESEND REQUEST
			#		till a packet with a valid sequence number is received.
			#		The resend should take place only once, thus follow up resend requests have to be ignored.
			#		This is achieved by tracking the peer sate, based on received HID output report headers (ACK field and flags)
			#		to detect changes. Only a change in these fields will result in an action taken by this endpoint.
			#		So the first request readen here, carrying a RESEND REQUEST will enable the "peer_state_changed" state.
			#		The writer thread (creating input reports) disables "peer_state_changed" again, after the needed action
			#		has been performed (in this example RESENDING of the packets missed).
			#
			# The "peer_sate_change" has to be enabled by this thread if needed, but mustn't be disable by this thread (task of the writer thread
			# after taking needed action)

			# This isn't an optimal solution, because if the same packet is lost two times, the receiver peer would answer with the
			# same RESEND request, although the action has already been taken by this peer (writing the missed HID inpurt reports again)
			# Thus the writer thread, which is responsible for disabeling the "peer_state_change" request, should reset last_* variables
			# to some initial values, to force a new state change if something goes wrong (not implemented, re-occuring report loss is unlikely
			# as the maximum number of pending reports written, should be less than the reports cachable on the input buffer of the other peer)
			
			if last_BIT7_FIN != BIT7_FIN or last_BIT6_RESEND != BIT6_RESEND or last_ACK != ACK:
				self.state["peer_state_changed"] = True
				last_BIT7_FIN = BIT7_FIN
				last_BIT6_RESEND = BIT6_RESEND 
				last_ACK = ACK
#			else:
#				self.state["peer_state_changed"] = False
		
			if (BIT6_RESEND):
#				print "Reader: received resend request, starting from SEQ " + str(ACK) + " len " + str(report[0]) 

				self.state["resend_request_rcvd"] = True
				ACK=ACK-1 # ACKs ar valid up to predecessor report of resend request
				if ACK < 0:
					ACK += MAX_OUT_QUEUE # clamp to valid range
				self.state["last_valid_ack_rcvd"]=ACK
			else:
#				print "Reader: received ACK " + str(ACK)
				self.state["last_valid_ack_rcvd"]=ACK
				self.state["resend_request_rcvd"] = False


			
	# alternating read/write till SEQ/ack are in sync		
	def sync_link(self):
		SEQ = 0 # start sequence number for syncing to ACK
		ACK = 0 # gets overwritten, declare variable in scope
		print "Trying to sync link layer..."
		while True:
			inbytes = self.fin.read(64)
			report = struct.unpack('!BB62s', inbytes)
			ACK = report[1] & 63
			if ACK == SEQ:
				# we are in sync
				break
			outbytes = struct.pack('!BB62s', 0, SEQ, "" )
			self.fout.write(outbytes)
			SEQ += 1
		# if we are here, we are in sync, next valid sequence number is in SEQ
		print "Sync done, next valid SEQ " + str(SEQ) + ", last valid ACK " + str(ACK)
		self.state["last_valid_ack_rcvd"]=ACK # set correct ACK into state
		self.state["last_seq_used"] = SEQ




##############
## test of link layer
########

# open device file read/write binary
#devfile=open("/dev/hidg1", "r+b")
#HIDin = devfile
#HIDout = devfile

# !!! Caution !!! open the output and input files with a single FD as shown in the code above, halves the speed (caused by synchronization on file ?)
HIDin = open("/dev/hidg1", "rb")
HIDout = open("/dev/hidg1", "wb")


ll = LinkLayer(HIDin, HIDout)


# fetch handle to output report queue
q_rep_out = ll.state["qout"]
# fetch handle to output report queue
q_rep_in = ll.state["qin"]

ll.start()

# Fill outbound queue with test data (payload max length of underlying layer has to be accounted to)
for i in range(17*1024):
	payload = "report nr. " + str(i)
	q_rep_out.put(payload)


# test loop printing out every input received
while True:
	if q_rep_in.qsize() > 0:
		print q_rep_in.get()
	else:
		time.sleep(0.05) # 5 ms sleep to lower load
	

#devfile.close()
HIDout.close()
HIDin.close()
