# syncronous troughput test for two HID device functions (one with input, one with output report)

# The script is meant to be used by echoing back data from the other side (to get the input thread on load)
# In case of P4wnP1 with the following command:
#   $ sudo bash -c 'cat /dev/hidg2 > /dev/hidg1'

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
    public class HID35
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
        public static FileStream[] Open(string tSerial, string tMan)
        {
            FileStream devFileIn = null;
            FileStream devFileOut = null;
            FileStream[] retVal = new FileStream[2];
        
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
                            
                            //if input device
                            if (inp == 65)
                            {
                                devFileIn = new FileStream(shandle, FileAccess.Read, 32, true);
                            }
                            
                            //if input device
                            if (outp == 65)
                            {
                                devFileOut = new FileStream(shandle, FileAccess.Write, 32, true);
                            }
                            
                            //bot devices found, break loop
                            //if (devFileIn != null && devFileOut != null) break;
                        }        
                        
                        
                    }
                
                }
            
                
                               
                

                index++;
            }
            SetupDiDestroyDeviceInfoList(hInfoSet);
            retVal[0] = devFileIn;
            retVal[1] = devFileOut;
            return retVal;
        }
    }
}
"@
Add-Type -TypeDefinition $cs  -Language CsharpVersion3

$devfiles = [mame.HID35]::Open("deadbeefdeadbeef", "MaMe82")
$HIDin = $devfiles[0]
$HIDout = $devfiles[1]
$reportsize = 65 # report payload is 64 bytes, as no report IDs are used a 0x00 has to be prepended on every report

# normal script block, should be packed into thread later on
$HIDinThread = {
    $inbytes = New-Object Byte[] (65)
    
    while ($true)
    {
        $cr = $HIDin.Read($inbytes,0,65)
        # convert byte[] to UTF8 (includes ASCII)
        $utf8 = [System.Text.Encoding]::UTF8.GetString($inbytes)
        # print to console !! time consuming IO task !!!!
        $hostui.WriteLine($utf8)
    }
}

# normal script block, should be packed into thread later on
$HIDoutThread = {
    $hostui.WriteLine("Writing 1000 reports with synchronous 'Write'")

    $outbytes = New-Object Byte[] (65)
 
    $msg=[system.Text.Encoding]::ASCII.GetBytes("Hello World")
    for ($i=0; $i -lt $msg.Length; $i++) { $outbytes[$i + 1] = $msg[$i] }

    for ($i=0; $i -lt 1000; $i++)
    {
        $HIDout.Write($outbytes,0,65)
    }
    
}


$HIDoutThread8Reports = {
    $hostui.WriteLine("Writing 1000 reports with async 'BeginWrite', 8 concurrent writes")

    $outbytes = New-Object Byte[] (65)
 
    $msg=[system.Text.Encoding]::ASCII.GetBytes("Hello World")
    for ($i=0; $i -lt $msg.Length; $i++) { $outbytes[$i + 1] = $msg[$i] }
    
    $AsyncHandles = @{} 
    $AsyncHandlesRemove = @{} 
    $maxConcurrentWrites = 8 # how many reports should be written concurrent (8 should be possible with HID on USB 2.0, outfile has OVERLAPPED flag)
    
    
    
        for ($i=0; $i -lt 1000; $i++)
        {
            # wait for free write slot (max Handles)
            while ($AsyncHandles.Count -ge $maxConcurrentWrites)
            {
                foreach ($AsyncHandleEnum in $AsyncHandles.GetEnumerator())
                {
                    $handle_hash = $AsyncHandleEnum.Name
                    $handle = $AsyncHandleEnum.Value
                    if ($handle.IsCompleted) 
                    {
                        # end write
                        $HIDout.EndWrite($handle)
                        # mark for remove from current handle from hashtable (thanks to PS mechnics, this couldn't be done during iterating, even more overhead)
                        $AsyncHandlesRemove[$handle_hash] = $handle
                    }
                }
                
                # remove uneeded handles, the messy way
                foreach ($AsyncHandleEnum in $AsyncHandlesRemove.GetEnumerator())
                {
                    $handle_hash = $AsyncHandleEnum.Name
                    $handle = $AsyncHandleEnum.Value # value isn't of interest
                    $AsyncHandles.Remove($handle_hash)
                }
                
                # clear remove markers
                $AsyncHandlesRemove.Clear()
            }
            
            $new_handle = $HIDout.BeginWrite($outbytes, 0 , 65, $null, $null)
            $AsyncHandles[$new_handle.GetHashCode()] = $new_handle
            
        }
    
}

##
# Prepare Threads
###

$iss = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault()

# read HID thread
$rs_hid_in = [runspacefactory]::CreateRunspace($iss)
$rs_hid_in.Open()
$rs_hid_in.SessionStateProxy.SetVariable("HIDin", $HIDin) # FileStream to HID input report device
$rs_hid_in.SessionStateProxy.SetVariable("hostui", $Host.UI) # Allow thread accesing stdout of $host


$ps_hid_in = [powershell]::Create()
$ps_hid_in.Runspace = $rs_hid_in
[void]$ps_hid_in.AddScript($HIDinThread)

# write HID thread
$rs_hid_out = [runspacefactory]::CreateRunspace($iss)
$rs_hid_out.Open()
$rs_hid_out.SessionStateProxy.SetVariable("HIDout", $HIDout) # FileStream to HID output report device
$rs_hid_out.SessionStateProxy.SetVariable("hostui", $Host.UI) # Allow thread accesing stdout of $host
$ps_hid_out = [powershell]::Create()
$ps_hid_out.Runspace = $rs_hid_out
[void]$ps_hid_out.AddScript($HIDoutThread)


# write HID thread with 8 concurrent writes
$rs_hid_out8 = [runspacefactory]::CreateRunspace($iss)
$rs_hid_out8.Open()
$rs_hid_out8.SessionStateProxy.SetVariable("HIDout", $HIDout) # FileStream to HID output report device
$rs_hid_out8.SessionStateProxy.SetVariable("hostui", $Host.UI) # Allow thread accesing stdout of $host
$ps_hid_out8 = [powershell]::Create()
$ps_hid_out8.Runspace = $rs_hid_out8
[void]$ps_hid_out8.AddScript($HIDoutThread8Reports)



try
{
    ####
    # start threads
    ####

    # start HID input handling thread
    $handle_hid_in = $ps_hid_in.BeginInvoke()

    # start HID out thread, idle loop till finish    
    $handle_hid_out = $ps_hid_out.BeginInvoke()
    $timetaken = Measure-Command {
        # idle loop in main process  
        while (-not $handle_hid_out.IsCompleted)
        {
            Start-Sleep -Milliseconds 100
        }
    }
    [Console]::WriteLine("HID out thread finfished, time taken {0} seconds", $timetaken.TotalSeconds)
    
    # start concurrent HID out thread, idle loop till finish
    $handle_hid_out8 = $ps_hid_out8.BeginInvoke()
    $timetaken = Measure-Command {
        # idle loop in main process  
        while (-not $handle_hid_out8.IsCompleted)
        {
            Start-Sleep -Milliseconds 100
        }
    }
    [Console]::WriteLine("HID concurrent output thread finfished, time taken {0} seconds", $timetaken.TotalSeconds)
}
finally
{
    [Console]::WriteLine("Killing remaining threads")
   
    # end threads, close files
    
    $ps_hid_in.Stop() # The ps_hid_in thread blocks stopping, until the internal blocking HIDin.read() call receives data (BeginRead would result in CPU consuming loop)
    $ps_hid_in.Dispose()
    $ps_hid_out.Stop()
    $ps_hid_out.Dispose()
    $ps_hid_out8.Stop()
    $ps_hid_out8.Dispose()
    $HIDin.Close()
    $HIDin.Dispose()   
    $HIDout.Close()
    $HIDout.Dispose()
    
    [Console]::WriteLine("Godbye")
}