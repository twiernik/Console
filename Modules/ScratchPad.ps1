$Username = "admin"
$Password = "b"
$Source = "https://spe.dev.local"
$Destination = "http://sc827"

$localSession = New-ScriptSession -user $Username -pass $Password -conn $Source
$remoteSession = New-ScriptSession -user $Username -pass $Password -conn $Destination

$sourceScript = {
    param(
        $Session,
        $RootId
    )

    $parentId = $RootId
    Invoke-RemoteScript -ScriptBlock {
            
        $parentItem = Get-Item -Path "master:" -ID $using:parentId

        $parentYaml = $parentItem | ConvertTo-RainbowYaml

        $children = $parentItem.GetChildren() | Select-Object -ExpandProperty ID
        $childIds = $children -join "|"

        $builder = New-Object System.Text.StringBuilder
        $builder.Append($parentYaml) > $null
        $builder.Append("<#split#>") > $null
        $builder.Append($childIds) > $null

        $builder.ToString()
            
    } -Session $Session -Raw
}

$watch = [System.Diagnostics.Stopwatch]::StartNew()
$rootId = "{37D08F47-7113-4AD6-A5EB-0C0B04EF6D05}"

$queue = [System.Collections.Queue]::Synchronized( (New-Object System.Collections.Queue) )
$queue.Enqueue($rootId)
Clear-Host

$threads = 10

$pool = [RunspaceFactory]::CreateRunspacePool(1, [int]$env:NUMBER_OF_PROCESSORS+1)
$pool.ApartmentState = "MTA"
$pool.Open()
$runspaces = [System.Collections.ArrayList]@()

while ($runspaces.Count -gt 0 -or $queue.Count -gt 0) {

    if($runspaces.Count -eq 0 -and $queue.Count -gt 0) {
        $parentId = $Queue.Dequeue()
        if(![string]::IsNullOrEmpty($parentId)) {
            Write-Host "Adding runspace for $($parentId)" -ForegroundColor Green
            $runspace = [PowerShell]::Create()
            $runspace.AddScript($sourceScript) > $null
            $runspace.AddArgument($LocalSession) > $null
            $runspace.AddArgument($parentId) > $null
            $runspace.RunspacePool = $pool

            $runspaces.Add([PSCustomObject]@{ Pipe = $runspace; Status = $runspace.BeginInvoke() }) > $null
        }
    }

    $currentRunspaces = $runspaces.ToArray()
    $currentRunspaces | ForEach-Object { 
        $currentRunspace = $_
        if($currentRunspace.Status.IsCompleted) {
            if($queue.Count -gt 0) {
                $parentId = $Queue.Dequeue()
                if(![string]::IsNullOrEmpty($parentId)) {
                    Write-Host "Adding runspace for $($parentId)" -ForegroundColor Green
                    $runspace = [PowerShell]::Create()
                    $runspace.AddScript($sourceScript) > $null
                    $runspace.AddArgument($LocalSession) > $null
                    $runspace.AddArgument($parentId) > $null
                    $runspace.RunspacePool = $pool

                    $runspaces.Add([PSCustomObject]@{ Pipe = $runspace; Status = $runspace.BeginInvoke() }) > $null
                }
            }
            $response = $currentRunspace.Pipe.EndInvoke($currentRunspace.Status)
            
            if(![string]::IsNullOrEmpty($response)) {
                $split = $response -split "<#split#>"
             
                $parentYaml = $split[0]              
                $childIds = $split[1].Split("|", [System.StringSplitOptions]::RemoveEmptyEntries)

                foreach($childId in $childIds) {
                    Write-Host "- Enqueue id $($childId)"
                    $Queue.Enqueue($childId)
                }
            }

            $currentRunspace.Pipe.Dispose()
            $runspaces.Remove($currentRunspace)
        }
    }
}


$pool.Close() 
$pool.Dispose()

Write-Host "All jobs completed!"
$watch.Stop()
$watch.ElapsedMilliseconds / 1000