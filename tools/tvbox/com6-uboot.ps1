param(
  [Parameter(Mandatory=$true)][string]$PortName,
  [int]$Baud = 115200,
  [int]$CharDelayMs = 18,
  [int]$WaitLoops = 32,
  [int]$WaitMs = 250,
  [switch]$Interrupt,
  [string[]]$Commands
)

$ErrorActionPreference = 'Stop'
$serial = New-Object System.IO.Ports.SerialPort $PortName,$Baud,'None',8,'One'
$serial.ReadTimeout = 300
$serial.WriteTimeout = 300
$serial.DtrEnable = $true
$serial.RtsEnable = $true
$serial.Open()
Start-Sleep -Milliseconds 300

function Read-Burst([int]$loops,[int]$waitMs) {
  $out = ''
  for ($i = 0; $i -lt $loops; $i++) {
    Start-Sleep -Milliseconds $waitMs
    try { $out += $serial.ReadExisting() } catch {}
  }
  return $out
}

function Send-Slow([string]$cmd) {
  $serial.DiscardInBuffer()
  foreach ($ch in $cmd.ToCharArray()) {
    $serial.Write([string]$ch)
    Start-Sleep -Milliseconds $CharDelayMs
  }
  $serial.Write("`r")
  $resp = Read-Burst -loops $WaitLoops -waitMs $WaitMs
  Write-Output ("=== CMD === {0}" -f $cmd)
  if ($resp) { Write-Output $resp }
}

if ($Interrupt) {
  $serial.Write([string][char]3)
  Start-Sleep -Milliseconds 200
  $serial.Write("`r")
  Start-Sleep -Milliseconds 300
  try { $initial = $serial.ReadExisting() } catch { $initial = '' }
  if ($initial) {
    Write-Output '=== INTERRUPT ==='
    Write-Output $initial
  }
}

foreach ($cmdBlock in $Commands) {
  foreach ($cmd in ($cmdBlock -split "`r?`n")) {
    if (-not [string]::IsNullOrWhiteSpace($cmd)) {
      Send-Slow $cmd
    }
  }
}

$serial.Close()
