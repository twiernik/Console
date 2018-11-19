﻿Import-Module -Name SPE -Force

$protocolHost = "https://spe.dev.local"

$watch = [System.Diagnostics.Stopwatch]::StartNew()
$session = New-ScriptSession -Username "sitecore\admin" -Password "b" -ConnectionUri $protocolHost

for($i = 0; $i -lt 10; $i++) {
    Invoke-RemoteScript -Session $session -ScriptBlock { 
        Get-Location
    }
}

$watch.Stop()
$watch.ElapsedMilliseconds / 1000

Stop-ScriptSession -Session $session