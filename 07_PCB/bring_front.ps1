Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Win {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int s);
}
'@
$procs = Get-CimInstance Win32_Process -Filter "Name like '%lceda%'" |
         Where-Object { $_.CommandLine -notlike '*--type=*' }
foreach ($p in $procs) {
  $proc = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
  if ($proc) {
    Write-Output ("PID " + $proc.Id + "  hwnd=" + $proc.MainWindowHandle + "  title=" + $proc.MainWindowTitle)
    if ($proc.MainWindowHandle -ne 0) {
      [Win]::ShowWindow($proc.MainWindowHandle, 9) | Out-Null
      [Win]::SetForegroundWindow($proc.MainWindowHandle) | Out-Null
      Write-Output "  -> brought to front"
    }
  }
}
