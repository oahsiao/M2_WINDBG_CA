param(
    [Parameter(Mandatory=$true)]
    [string]$DumpPath,

    [Parameter(Mandatory=$true)]
    [ValidateSet('phase0','phase1','phase2')]
    [string]$Phase
)

# 1. confirm dump exists
if (-not (Test-Path $DumpPath)) {
    Write-Error "Dump not found: $DumpPath"
    exit 1
}

$dumpDir = Split-Path $DumpPath -Parent

# 2. find cdb.exe
$dbg = (Get-AppxPackage Microsoft.WinDbg.Fast -ErrorAction SilentlyContinue).InstallLocation
if ($dbg) { $dbg = Join-Path $dbg 'amd64\cdb.exe' }
if (-not $dbg -or -not (Test-Path $dbg)) {
    $dbg = (Get-AppxPackage Microsoft.WinDbg.Slow -ErrorAction SilentlyContinue).InstallLocation
    if ($dbg) { $dbg = Join-Path $dbg 'amd64\cdb.exe' }
}
if (-not $dbg -or -not (Test-Path $dbg)) {
    Write-Error "WinDbg not found. Please install WinDbg.Next from Microsoft Store."
    exit 1
}
Write-Output "Using debugger: $dbg"

# 3. symbol path
$sym = 'srv*C:\symbols*http://symweb;srv*C:\symbols*https://msdl.microsoft.com/download/symbols;srv*C:\symbols*\\desmo\release\Symbols;srv*C:\symbols*https://artifacts.dev.azure.com/msftdevices/_apis/symbol/symsrv;srv*C:\symbols*\\desmo\WDS\Devices\Tinos\SWFW\Symbols;srv*C:\symbols*\\desmo\release\UEFI-Intel\Symbols'

# 4. define wds lines per phase
$traceFile = Join-Path $dumpDir "TRACE_${Phase}.txt"
$wdsFile   = Join-Path $dumpDir "${Phase}.wds"

switch ($Phase) {
    'phase0' {
        $lines = @(
            '.chain',
            'vertarget',
            '.bugcheck',
            'q'
        )
    }
    'phase1' {
        $lines = @(
            '.reload /f',
            '!analyze -v',
            'q'
        )
    }
    'phase2' {
        $lines = @(
            '!sysinfo machineid',
            '!sysinfo cpuinfo',
            '!running',
            '!irql',
            '!stacks 2',
            'lm t n',
            '!blackboxbsd',
            '!blackboxntfs',
            '!blackboxpnp',
            '!blackboxwinlogon',
            'q'
        )
    }
}

# 5. write wds: no BOM, LF-only line endings (cdb $$>< parser requires LF, not CRLF)
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$fs = New-Object System.IO.FileStream($wdsFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
$writer = New-Object System.IO.StreamWriter($fs, $utf8NoBom)
$writer.NewLine = "`n"
foreach ($line in $lines) {
    $writer.WriteLine($line)
}
$writer.Close()
$fs.Close()

# 6. verify: no semicolons, correct line count
$wdsContent = Get-Content $wdsFile -Raw
if ($wdsContent -match ';') {
    Write-Error ".wds file contains semicolons - generation failed. Aborting."
    exit 1
}
$lineCount = (Get-Content $wdsFile).Count
Write-Output (".wds written: $wdsFile (" + $lineCount + " lines, no semicolons, no BOM)")

# 7. run cdb - use -cf to load command file (more reliable than $$>< in -c string)
& $dbg -y $sym -z $DumpPath -loga $traceFile -cf $wdsFile
