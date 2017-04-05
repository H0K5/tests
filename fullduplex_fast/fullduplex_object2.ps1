##############################
# Build methods to create filestream to HID device (stage 1 work)
#################################################################

$cs =@"
using System;
using System.Collections.Generic;
using System.Text;
using System.IO;
//using System.ComponentModel;
using System.Runtime.InteropServices;



using Microsoft.Win32.SafeHandles;

//using System.Runtime;


namespace mame
{
    public class HID40
    {
        /* invalid handle value */
        public static IntPtr INVALID_HANDLE_VALUE = new IntPtr(-1);

        // kernel32.dll
        public const uint GENERIC_READ = 0x80000000;
        public const uint GENERIC_WRITE = 0x40000000;
        public const uint FILE_SHARE_WRITE = 0x2;
        public const uint FILE_SHARE_READ = 0x1;
        public const uint FILE_FLAG_OVERLAPPED = 0x40000000;
        public const uint OPEN_EXISTING = 3;
        public const uint OPEN_ALWAYS = 4;
        
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr CreateFile([MarshalAs(UnmanagedType.LPStr)] string strName, uint nAccess, uint nShareMode, IntPtr lpSecurity, uint nCreationFlags, uint nAttributes, IntPtr lpTemplate);
        
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool CloseHandle(IntPtr hObject);

        [DllImport("hid.dll", SetLastError = true)]
        public static extern void HidD_GetHidGuid(out Guid gHid);

        [DllImport("hid.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern Boolean HidD_GetManufacturerString(IntPtr hFile, StringBuilder buffer, Int32 bufferLength);

        [DllImport("hid.dll", CharSet = CharSet.Auto, SetLastError = true)]
        internal static extern bool HidD_GetSerialNumberString(IntPtr hDevice, StringBuilder buffer, Int32 bufferLength);
        
        [DllImport("hid.dll", SetLastError = true)]
        protected static extern bool HidD_GetPreparsedData(IntPtr hFile, out IntPtr lpData);

        [DllImport("hid.dll", SetLastError = true)]
        protected static extern int HidP_GetCaps(IntPtr lpData, out HidCaps oCaps);

        [DllImport("hid.dll", SetLastError = true)]
        protected static extern bool HidD_FreePreparsedData(ref IntPtr pData);

        // setupapi.dll

        public const int DIGCF_PRESENT = 0x02;
        public const int DIGCF_DEVICEINTERFACE = 0x10;

        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        public struct DeviceInterfaceData
        {
            public int Size;
            public Guid InterfaceClassGuid;
            public int Flags;
            public IntPtr Reserved;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        public struct DeviceInterfaceDetailData
        {
            public int Size;
            
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 512)]
            public string DevicePath;
        }
        
        //We need to create a _HID_CAPS structure to retrieve HID report information
        //Details: https://msdn.microsoft.com/en-us/library/windows/hardware/ff539697(v=vs.85).aspx
        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        protected struct HidCaps
        {
            public short Usage;
            public short UsagePage;
            public short InputReportByteLength;
            public short OutputReportByteLength;
            public short FeatureReportByteLength;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 0x11)]
            public short[] Reserved;
            public short NumberLinkCollectionNodes;
            public short NumberInputButtonCaps;
            public short NumberInputValueCaps;
            public short NumberInputDataIndices;
            public short NumberOutputButtonCaps;
            public short NumberOutputValueCaps;
            public short NumberOutputDataIndices;
            public short NumberFeatureButtonCaps;
            public short NumberFeatureValueCaps;
            public short NumberFeatureDataIndices;
        }
        

        [DllImport("setupapi.dll", SetLastError = true)]
        public static extern IntPtr SetupDiGetClassDevs(ref Guid gClass, [MarshalAs(UnmanagedType.LPStr)] string strEnumerator, IntPtr hParent, uint nFlags);

        [DllImport("setupapi.dll", SetLastError = true)]
        public static extern bool SetupDiEnumDeviceInterfaces(IntPtr lpDeviceInfoSet, uint nDeviceInfoData, ref Guid gClass, uint nIndex, ref DeviceInterfaceData oInterfaceData);

        [DllImport("setupapi.dll", SetLastError = true)]
        public static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr lpDeviceInfoSet, ref DeviceInterfaceData oInterfaceData, ref DeviceInterfaceDetailData oDetailData, uint nDeviceInterfaceDetailDataSize, ref uint nRequiredSize, IntPtr lpDeviceInfoData);

        [DllImport("setupapi.dll", SetLastError = true)]
        public static extern bool SetupDiDestroyDeviceInfoList(IntPtr lpInfoSet);

        //public static FileStream Open(string tSerial, string tMan)
        public static FileStream Open(string tSerial, string tMan)
        {
            FileStream devFile = null;
            
            Guid gHid;
            HidD_GetHidGuid(out gHid);
            
            // create list of HID devices present right now
            var hInfoSet = SetupDiGetClassDevs(ref gHid, null, IntPtr.Zero, DIGCF_DEVICEINTERFACE | DIGCF_PRESENT);
            
            var iface = new DeviceInterfaceData(); // allocate mem for interface descriptor
            iface.Size = Marshal.SizeOf(iface); // set size field
            uint index = 0; // interface index 

            // Enumerate all interfaces with HID GUID
            while (SetupDiEnumDeviceInterfaces(hInfoSet, 0, ref gHid, index, ref iface)) 
            {
                var detIface = new DeviceInterfaceDetailData(); // detailed interface information
                uint reqSize = (uint)Marshal.SizeOf(detIface); // required size
                detIface.Size = Marshal.SizeOf(typeof(IntPtr)) == 8 ? 8 : 5; // Size depends on arch (32 / 64 bit), distinguish by IntPtr size
                
                // get device path
                SetupDiGetDeviceInterfaceDetail(hInfoSet, ref iface, ref detIface, reqSize, ref reqSize, IntPtr.Zero);
                var path = detIface.DevicePath;
                
                System.Console.WriteLine("Path: {0}", path);
            
                // Open filehandle to device
                
                var handle = CreateFile(path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, IntPtr.Zero);
                
                                
                if (handle == INVALID_HANDLE_VALUE) 
                { 
                    System.Console.WriteLine("Invalid handle");
                    index++;
                    continue;
                }
                
                IntPtr lpData;
                if (HidD_GetPreparsedData(handle, out lpData))
                {
                    HidCaps oCaps;
                    HidP_GetCaps(lpData, out oCaps);    // extract the device capabilities from the internal buffer
                    int inp = oCaps.InputReportByteLength;    // get the input...
                    int outp = oCaps.OutputReportByteLength;    // ... and output report length
                    HidD_FreePreparsedData(ref lpData);
                    System.Console.WriteLine("Input: {0}, Output: {1}",inp, outp);
                
                    // we have report length matching our input / output report, so we create a device file in each case
                    if (inp == 65 || outp == 65)
                    {
                        // check if manufacturer and serial string are matching
                    
                        //Manufacturer
                        var s = new StringBuilder(256); // returned string
                        string man = String.Empty; // get string
                        if (HidD_GetManufacturerString(handle, s, s.Capacity)) man = s.ToString();
                
                        //Serial
                        string serial = String.Empty; // get string
                        if (HidD_GetSerialNumberString(handle, s, s.Capacity)) serial = s.ToString();
                                
                        if (tMan.Equals(man, StringComparison.Ordinal) && tSerial.Equals(serial, StringComparison.Ordinal))
                        {
                            //Console.WriteLine("Device found: " + path);
                    
                            var shandle = new SafeFileHandle(handle, false);
                            
                            devFile = new FileStream(shandle, FileAccess.Read | FileAccess.Write, 32, true);
                                                        
                            
                            break;
                        }        
                        
                        
                    }
                
                }
            
                
                               
                

                index++;
            }
            SetupDiDestroyDeviceInfoList(hInfoSet);
            return devFile;
        }
    }
}
"@
Add-Type -TypeDefinition $cs  -Language CsharpVersion3

$devfile = [mame.HID40]::Open("deadbeefdeadbeef", "MaMe82")



###################################################
# Create LinkLayer Custom Object (Stage 2 work)
###################################################

$LinkLayerProperties = @{
    globalstate =  [hashtable]::Synchronized(@{}) # Thread global data (synchronized hashtable for state)
    iss = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault() # initial seesion state for threads (runspaces)

    rs_hid_in = [runspacefactory]::CreateRunspace($iss) # RunSpace for HIDin thread (reading HID input reports)
    ps_hid_in = [powershell]::Create() # powershell subrocess running HIDin thread
    rs_hid_out = [runspacefactory]::CreateRunspace($iss) # RunSpace for HIDout thread (writing HID output reports)
    ps_hid_out = [powershell]::Create() # powershell subrocess running HIDout thread
}

$LinkLayer = New-Object PSCustomObject -Property $LinkLayerProperties
# Create construcort / init method
$LinkLayer | Add-Member -MemberType ScriptMethod -Name "Init" -Value {
    param(

        [Parameter(Mandatory=$true, Position=0)]
        [System.IO.FileStream]
        $HIDin,

        [Parameter(Mandatory=$true, Position=1)]
        [System.IO.FileStream]
        $HIDout

    )
    

    # as the mandatory attribute isn't working with Add-Member ScriptMethod, we check manually
    if (!$HIDin -or !$HIDout) { throw [System.ArgumentException]"FileStream for HIDin and HIDout have to be provided as argument (both FileStreams could be the same if access is bot, read and write!"}


    $reportsize = 65
    
    ########################
    # declare script block for HID input thread (reading input reports)
    #########################
    # works with incoming sequence number, as reports could be lost if this host is reading to slow
    # report layout for incoming reports
    #    0: REPORT ID
    #    1: LEN: BIT7 = fin flag, BIT6 = unused, BIT5...BIT0 = Payload Length (Payload length 0 to 62)
    #    2: SEQ: BIT7 = unused, BIT6 = unused, BIT5...BIT0 = SEQ: Sequence number used by the sender (0..31)
    #    3..64: Payload
    $HIDinThread = {
        $hostui.WriteLine("Starting thread to continuously read HID input reports")
    
        $inbytes = New-Object Byte[] (65)
        $MAX_SEQ = 32 # how many sequence numbers are used by sender (largest possible SEQ number + 1)
        $hostui.WriteLine("Global seq number readen {0}" -f $state.last_seq_received)

        while ($true)
        {
            $cr = $HIDin.Read($inbytes,0,65)

        
            # extract header data
            ########################
            $LEN = $inbytes[1] -band 63
            $BIT7_FIN = $false # if this bit is set, this means the report is the last one in a fragemented STREAM
            # if this bit isn't set $inbytes[2] contains the SEQ number, 
            # if thi bit is set $inbytes[2] contains the SEQ number of a retransmission - invalidating all reports received after this SEQ number (unused right now)
            $BIT6 = $false 
        
            if ($inbytes[1] -band 128) {$BIT7_FIN=$true}
            if ($inbytes[1] -band 64) {$BIT6=$true}
        
            $RECEIVED_SEQ = $inbytes[2] -band 63 # remove flag bits from incoming SEQ number
        
            # calculate next valid SEQ number
            $next_valid_seq = $state.last_valid_seq_received + 1
            if ($next_valid_seq -ge $MAX_SEQ) { $next_valid_seq -= $MAX_SEQ } # clamp next_valid_seq to MAX_SEQ range
        
#$hostui.WriteLine("Reader: Received SEQ: $RECEIVED_SEQ, next valid SEQ: $next_valid_seq")     
        
            # check if received SEQ is valid (in order)
            if ($RECEIVED_SEQ -eq $next_valid_seq)
            {
                # received report has valid SEQ: 
                # - push report to input queue
                # - update last_valid_seq_received
        
                if ($LEN -gt 0) # only handle packets with payload length > 0 (no heartbeat)
                {
                    $state.report_in_queue.Enqueue($inbytes.Clone()) # enqueue copy of read buffer    
                }
    #            else
    #            {
    #                $hostui.WriteLine("Reader: Ignoring report with SEQ $SEQ, as payload is empty")
    #            }
            
                $state.last_valid_seq_received = $next_valid_seq
                $state.invalid_seq_received = $false
            }
            else
            {
                # out of order report received
                # - ignore report (don't push report to input queue) 
                # - DON'T update last_valid_seq_received 
                # - inform output thread, that a report with invalid sequence has be received (to trigger a RESEND REQUEST from write thread)
            
#$hostui.WriteLine("Reader: Received invalid (out-of-order) report")
        
                $state.invalid_seq_received = $true
            }
                
            # promote received SEQ number to thread global state
            $state.last_seq_received = $inbytes[2]

#Start-Sleep -m 200 # try to miss reports

        }
    } # end of HIDin script block




    ########################
    # declare script block for HID outpput thread (writing output reports)
    #########################
    # works with outgoing acknoledge number, as reports could be lost if this host is reading to slow
    # valid (in-order) reports are propagated back to the sender with an acknowledge number (ACK) 
    # Sender has to stop sending after a maximum of 32 reports if the corresponding ACK for the
    # 32th packet isn't received
    # ACKs are accumulating, this means if SEQ 0, 1, 2 are read by the HIDin Thread, without writing an 
    # output report containing the needed ACKs (for example, caused by to much processing overhead in output 
    # loop for example), the next ACK written will be 2 (omitting 0 and 1).
    # To allow the other peer to still detect report loss, without receiving an ack for every single report,
    # a flag is introduced to fire resend request. If this flag is set, this informs the other peer to resend 
    # every report, beginning from the sucessor of the ACK number in the ACK field (this allows to acknowledge additional
    # reports while requesting missed ones).
    
    # report layout for outgoing reports
    #    0: REPORT ID
    #    1: LEN: BIT7 = fin flag, BIT6 = unused, BIT5...BIT0 = Payload Length (Payload length 0 to 62)
    #    2: SEQ: BIT7 = unused, BIT6 = RESEND REQUEST, BIT5...BIT0 = ACK: Acknowledge number holding last valid SEQ number received by reader thread
    #    3..64: Payload
    $HIDoutThread = {
        $MAX_SEQ = 32 # how many sequence numbers are used by sender (largest possible SEQ number + 1)
    
        $hostui.WriteLine("Starting write loop continously sending HID ouput report")

        $empty = New-Object Byte[] (65)
        $outbytes = New-Object Byte[] (65)
 
        #$msg=[system.Text.Encoding]::ASCII.GetBytes("Hello World")
        #for ($i=0; $i -lt $msg.Length; $i++) { $empty[$i + 3] = $msg[$i] }
        #$empty[1] = $msg.Length
        
    
        while ($true)   
        {
            # dequeue pending output reports, use empty (heartbeat) otherwise
            if ($state.report_out_queue.Count -gt 0)
            {
                $outbytes = $state.report_out_queue.Dequeue()
            }
            else
            {
                $outbytes = $empty
            }
        
            # build header
            ################
            $LEN = $outbytes[1] -band 63 # should already be defined from upper layer
            $BIT7_FIN = $false # if this bit is set, this means the report is the last one in a fragemented STREAM
        
            # if this bit isn't set $inbytes[2] contains the SEQ number, 
            # if thi bit is set $inbytes[2] contains the SEQ number of a retransmission - invalidating all reports received after this SEQ number (unused right now)
            $BIT6_RESEND_REQUEST = $state.invalid_seq_received # set resend bit, if last report read has been invalid (out of order)
        
         
            if ($BIT6_RESEND_REQUEST)
            { 
                $outbytes[1] = $outbytes[1] -bor 64 # set resend flag if necessary
                $next_needed = $state.last_valid_seq_received + 1 # Request resending, beginning from the successor report of the last in-order-report received
                if ($next_needed -ge $MAX_SEQ) { $next_needed -= $MAX_SEQ }
                $outbytes[2] = $next_needed
            }
            else 
            { 
                $outbytes[1] = $outbytes[1] -band -bnot 64 # unset resend flag if necessary
                $outbytes[2] = $state.last_valid_seq_received # acknowledge last valid SEQ number received
            }
        
# slow down loop to mimic overload on output data processing
#Start-Sleep -m 500 # try to write less than read
        
# DEBUG
#$as = $outbytes[2] 
#if ($BIT6_RESEND_REQUEST)
#{ $hostui.WriteLine("Writer: Send resend request beginning from SEQ $as") }
#else
#{ $hostui.WriteLine("Writer: Send report with ACK $as") }
       
            $HIDout.Write($outbytes,0,65)
        }
    }



    ##############################
    # init state shared among read and write thread
    ##############################
    $this.globalstate.last_seq_received = 31 # last seq number read !! has to be exchanged between threads, thus defined in global RunSpace threadsafe hashtable
    $this.globalstate.last_valid_seq_received = 31 # last seq number which has been valid (arrived in sequential order)
    $this.globalstate.invalid_seq_received = $true # last SEQ number received, was invalid if this flag is set, the sender is informed about this with a resend request
    $this.globalstate.report_in_queue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
    $this.globalstate.report_out_queue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))


    ##
    # Prepare Threads
    ###

    # read HID thread
    $this.rs_hid_in.Open()
    $this.rs_hid_in.SessionStateProxy.SetVariable("HIDin", $HIDin) # FileStream to HID input report device
    $this.rs_hid_in.SessionStateProxy.SetVariable("hostui", $Host.UI) # Allow thread accesing stdout of $host
    $this.rs_hid_in.SessionStateProxy.SetVariable("state", $this.globalstate) # state shared between threads

    
    $this.ps_hid_in.Runspace = $this.rs_hid_in
    [void] $this.ps_hid_in.AddScript($HIDinThread)

    # write HID thread
    $this.rs_hid_out.Open()
    $this.rs_hid_out.SessionStateProxy.SetVariable("HIDout", $HIDout) # FileStream to HID output report device
    $this.rs_hid_out.SessionStateProxy.SetVariable("hostui", $Host.UI) # Allow thread accesing stdout of $host
    $this.rs_hid_out.SessionStateProxy.SetVariable("state", $this.globalstate) # state shared between threads

    $this.ps_hid_out.Runspace = $this.rs_hid_out
    [void] $this.ps_hid_out.AddScript($HIDoutThread)


} # end of init method

$LinkLayer | Add-Member -MemberType ScriptMethod -Name "Start" -Value {
    # start threads
    # start HID input handling thread
    $handle_hid_in = $LinkLayer.ps_hid_in.BeginInvoke()

    # start HID out thread, idle loop till finish    
    $handle_hid_out = $LinkLayer.ps_hid_out.BeginInvoke()
}

$LinkLayer | Add-Member -MemberType ScriptMethod -Name "Stop" -Value {
    # stop threads
    $this.ps_hid_in.Stop() # The ps_hid_in thread blocks stopping, until the internal blocking HIDin.read() call receives data (BeginRead would result in CPU consuming loop)
    $this.ps_hid_in.Dispose()
    $this.ps_hid_out.Stop()
    $this.ps_hid_out.Dispose()
}

# method to get current input report queue size
$LinkLayer | Add-Member -MemberType ScriptMethod -Name "PendingInputReportCount" -Value {
    $this.globalstate.report_in_queue.Count
}

# method to get last input report from queue
$LinkLayer | Add-Member -MemberType ScriptMethod -Name "PopInputReport" -Value {
    $this.globalstate.report_in_queue.Dequeue()
}

# method to get last input report from queue
$LinkLayer | Add-Member -MemberType ScriptMethod -Name "ParseReport" -Value {
   param(
        [Parameter(Mandatory=$true, Position=0)]
        [Object[]]
        $report
    )
    

    # as the mandatory attribute isn't working with Add-Member ScriptMethod, we check manually
    if (!$report) { throw [System.ArgumentException]"Report has to be provided in order to parse"}

    $parsed=@{}
    $parsed.len = $report[1] -band 63
    $parsed.payload = New-Object Byte[] ($parsed.len)
    [Array]::Copy($report, 3, $parsed.payload, 0, $parsed.len)
    $parsed.BIT_FIN = $false
    if ($report[1] -band 128) {$parsed.BIT_FIN = $true}
    $parsed.BIT6_UNUSED = $false            
    if ($report[1] -band 64) {$parsed.BIT6_UNUSED = $true}
    $parsed.seq = $report[2] -band 63
    
    # return
    $parsed
}

#########################
# test of link layer
#########################

$HIDin = $devfile
$HIDout = $devfile

$LinkLayer.Init($HIDin, $HIDout)

try
{
    
    $REPORTS_TO_FETCH = 16384 # 1MB payload data
    $SNIP_OUTPUT = $true
    
    $sw = New-Object Diagnostics.Stopwatch
    $sw.Start()

    $LinkLayer.Start()
    
    $qout = $LinkLayer.globalstate.report_out_queue
    
    # fill out queue with some test data
    for ($i = 0; $i -lt 2000; $i++)
    {
        $utf8_msg = "Report Nr. $i"
        # convert to bytes (interpret as UTF8)
        $payload =[system.Text.Encoding]::UTF8.GetBytes($utf8_msg)
        $length = [byte] $payload.Length
        
        # build report
        $report = New-Object Byte[] (65)
        # byte 0 = report ID (zero, nothing to do)
        # byte 1 = length
        $report[1] = $length
        # byte 2 = SEQ (filled by link layer, nothing to do)
        # byte 3 and following = fill in payload (padded with 0x00)
        $payload.CopyTo($report, 3)
        
        # enque report
        $qout.Enqueue($report)
    }

    # loop while input queue has less than 16384 reports received (= 1MB data, as one report is 64 bytes)
    while ($LinkLayer.PendingInputReportCount() -lt $REPORTS_TO_FETCH) 
    {
        Start-Sleep -Milliseconds 50 # small sleep to lower CPU load, could change overall time measurement by 50 ms
    }

    $sw.Stop() # all reports are received, so we stop time and print theam out (additional reports are received meanwhile, which we ignore)

    # print out payload part of all reports to assure no packet is lost
    for ($i = 0; $i -lt $REPORTS_TO_FETCH; $i++) # only up to REPORTS_TO_FETCH, ignore newer reports from in queue
    {
        $report = $LinkLayer.PopInputReport()
        $parsed = $LinkLayer.ParseReport($report) # test report parser
        # convert parsed report to UTF8
        $utf8 = ([System.Text.Encoding]::UTF8.GetString($parsed.payload))
    
        if ($SNIP_OUTPUT)
        {    
            # only print first and last ten reports
            if ($i -lt 10) { $host.UI.WriteLine("MainThread: received report: $utf8") }
            if ($i -eq 11) { $host.UI.WriteLine("...snip...") }
            if ($i -gt $REPORTS_TO_FETCH-10) { $host.UI.WriteLine("MainThread: received report: $utf8") }
        }
        else
        {
            $host.UI.WriteLine("MainThread: received report: $utf8") # use this to print all reports and check for loss
        }
        
    }
    
    
    $ttaken = $sw.Elapsed.TotalSeconds
    [Console]::WriteLine("Total time in seconds $ttaken")
    $throughput_in = 62*$real_report_count / $ttaken # only calculates netto payload data (62 bytes per report, only none-empty reports pushed to input queue) 
    [Console]::WriteLine("Throughput in {0} bytes/s netto payload date (excluding report loss and resends)" -f $throughput_in)
    
    #$throughput_out = $report_count_out * 62 / $ttaken
    #[Console]::WriteLine("Throughput out in the same time {0} bytes/s netto output ({1} reports)" -f ($throughput_out, $report_count_out))


}
finally
{
    [Console]::WriteLine("Killing remaining threads")
   
    # end threads
    $LinkLayer.Stop() # HIDin thread keeps running, till the blocking read on deivcefile receives a report
    
    $devfile.Close()
    
    [Console]::WriteLine("Goodbye")
}
