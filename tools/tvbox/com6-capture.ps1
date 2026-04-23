param(
  [Parameter(Mandatory=$true)][string]$PortName,
  [int]$Baud = 115200,
  [int]$Seconds = 20,
  [string]$OutFile = 'C:\Windows\Temp\com6-capture.log'
)

$ErrorActionPreference = 'Stop'
$serial = New-Object System.IO.Ports.SerialPort $PortName,$Baud,'None',8,'One'
$serial.ReadTimeout = 300
$serial.WriteTimeout = 300
$serial.DtrEnable = $true
$serial.RtsEnable = $true
$serial.Open()
$sw = [System.IO.StreamWriter]::new($OutFile, $false, [System.Text.Encoding]::ASCII)
$deadline = (Get-Date).AddSeconds($Seconds)
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Milliseconds 200
  try {
    $data = $serial.ReadExisting()
    if ($data) {
      $sw.Write($data)
      $sw.Flush()
    }
  } catch {}
}
$sw.Close()
$serial.Close()
Write-Output $OutFile
