param(
  [Parameter(Mandatory=$true)][string]$PortName,
  [int]$Baud = 115200,
  [string]$OutFile = 'C:\Windows\Temp\com6-mdio-once.log'
)

$ErrorActionPreference = 'Stop'
$serial = New-Object System.IO.Ports.SerialPort $PortName,$Baud,'None',8,'One'
$serial.ReadTimeout = 150
$serial.WriteTimeout = 150
$serial.DtrEnable = $true
$serial.RtsEnable = $true
$serial.Open()
$sw = [System.IO.StreamWriter]::new($OutFile, $false, [System.Text.Encoding]::ASCII)
$start = Get-Date
$rx = ''
$lastSpace = Get-Date
$commands = @(
  'help mdio',
  'mdio list',
  'mdio read ethernet@5030000 0 2',
  'mdio read ethernet@5030000 0 3',
  'mdio read ethernet@5030000 1 2',
  'mdio read ethernet@5030000 2 2',
  'mdio read ethernet@5030000 3 2',
  'mdio read ethernet@5030000 4 2',
  'mdio read ethernet@5030000 5 2',
  'mdio read ethernet@5030000 6 2',
  'mdio read ethernet@5030000 7 2'
)
$cmdIndex = 0
$lastPromptCount = 0
$lastProgress = Get-Date

function Drain-Port {
  param($Port, $Writer)
  try {
    $data = $Port.ReadExisting()
    if ($data) {
      $script:rx += $data
      $Writer.Write($data)
      $Writer.Flush()
    }
  } catch {}
}

function Send-Slow {
  param($Port, [string]$Text, [int]$DelayMs = 24)
  foreach ($ch in $Text.ToCharArray()) {
    $Port.Write([string]$ch)
    Start-Sleep -Milliseconds $DelayMs
  }
  $Port.Write("`r")
}

function Get-PromptCount {
  param([string]$Text)
  return ([regex]::Matches($Text, '(?m)^=> ')).Count
}

while (((Get-Date) - $start).TotalSeconds -lt 50) {
  $t = ((Get-Date) - $start).TotalSeconds

  Drain-Port $serial $sw

  $needInterrupt = ($rx -match 'Autoboot in .*press <Space> to stop') -or
                   (($rx -match 'U-Boot 20') -and -not ($rx -match '(?m)^=> '))
  if ($needInterrupt -and (((Get-Date) - $lastSpace).TotalMilliseconds -ge 160)) {
    $serial.Write(' ')
    $lastSpace = Get-Date
  }

  $promptCount = Get-PromptCount $rx
  if ($promptCount -gt $lastPromptCount) {
    $lastPromptCount = $promptCount
    $lastProgress = Get-Date
    if ($cmdIndex -lt $commands.Count) {
      $cmd = $commands[$cmdIndex]
      $sw.WriteLine("=== CMD === $cmd")
      $sw.Flush()
      Send-Slow $serial $cmd
      $cmdIndex++
    }
  }

  if ($cmdIndex -ge $commands.Count -and (((Get-Date) - $lastProgress).TotalSeconds -ge 4)) {
    break
  }

  Start-Sleep -Milliseconds 120
}

Drain-Port $serial $sw
$sw.Close()
$serial.Close()
Write-Output $OutFile
