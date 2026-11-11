$proc = Get-Process -Name "aa_roas" -ErrorAction Stop
$dumpPath = Join-Path $PSScriptRoot "..\..\dump.dmp"
$fileStream = [System.IO.File]::Create($dumpPath)

$typeDef = @"
using System;
using System.Runtime.InteropServices;
public class Dbg {
    [DllImport("dbghelp.dll")]
    public static extern bool MiniDumpWriteDump(IntPtr hProcess, int ProcessId, IntPtr hFile, int DumpType, IntPtr ExpParam, IntPtr UserStreamParam, IntPtr CallbackParam);
}
"@
Add-Type -TypeDefinition $typeDef
[Dbg]::MiniDumpWriteDump($proc.Handle, $proc.Id, $fileStream.SafeFileHandle.DangerousGetHandle(), 2, [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero)
$fileStream.Close()
Write-Host "Dump created successfully, size: $((Get-Item $dumpPath).Length)"
