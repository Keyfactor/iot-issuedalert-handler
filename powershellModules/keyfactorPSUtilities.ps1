# Copyright 2023 Keyfactor
# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions
# and limitations under the License.

function Add-KFTraceLog {
    <#
    .SYNOPSIS
    Adds the $message to the logfile as it's own line marked as [T] to be used for Tracing,
    Also displays the message on the screen
    .PARAMETER OutputLog - boolean value, true to log, false to not log
    .PARAMETER LogFilePath - file path to where the log file is
    .PARAMETER message - the string contents to write to the file
    .PARAMETER session - the (optional) string unique session value to prepend to the messages
    #>
    param(
        [boolean]$OutputLog,
        $LogFilePath,
        $message, $session)
    if ($null -eq $LogFilePath) {
        throw "trace log file path required"
    }
    if ($OutputLog) {
        $outMsg = (Get-Date -Format "hh:mm") + "[T$session] $message"
        Add-Content -Path $LogFilePath -Value $outMsg
        Write-Host $outMsg -ForegroundColor white
    }
}
function Add-KFInfoLog {
    <#
    .SYNOPSIS
    Adds the $message to the logfile as it's own line marked as [I] to be used for information,
    Also displays the message on the screen
    .PARAMETER OutputLog - boolean value, true to log, false to not log
    .PARAMETER LogFilePath - file path to where the log file is
    .PARAMETER message - the string contents to write to the file
    .PARAMETER session - the (optional) string unique session value to prepend to the messages
    #>
    param(
        [boolean]$OutputLog,
        $LogFilePath,
        $message, $session)
    if ($null -eq $LogFilePath) {
        throw "info log file path required"
    }
    if ($OutputLog) {
        $outMsg = (Get-Date -Format "hh:mm") + "[I$session] $message"
        Add-Content -Path $LogFilePath -Value $outMsg
        Write-Host $outMsg -ForegroundColor white
    }
}
function Add-KFErrorLog {
    <#
    .SYNOPSIS
    Adds the $message to the logfile as it's own line marked as [E] to be used as an Error Message,
    Also displays the message on the screen in red
    .PARAMETER OutputLog - boolean value, true to log, false to not log
    .PARAMETER LogFilePath - file path to where the log file is
    .PARAMETER message - the string contents to write to the file
    .PARAMETER session - the (optional) string unique session value to prepend to the messages
    #>
    param(
        [boolean]$OutputLog,
        $LogFilePath,
        $message, $session)
    if ($null -eq $LogFilePath) {
        throw "Error log file path required"
    }
    if ($OutputLog) {
        $outMsg = (Get-Date -Format "hh:mm") + "[E$session] $message"
        Add-Content -Path $LogFilePath -Value $outMsg
        Write-Host $outMsg -ForegroundColor red
    }
}
function Add-KFWarningLog {
    <#
    .SYNOPSIS
    Adds the $message to the logfile as it's own line marked as [W] to be used as a Warning Message,
    Also displays the message on the screen in yellow
    .PARAMETER OutputLog - boolean value, true to log, false to not log
    .PARAMETER LogFilePath - file path to where the log file is
    .PARAMETER message - the string contents to write to the file
    .PARAMETER session - the (optional) string unique session value to prepend to the messages
    #>
    param(
        [boolean]$OutputLog,
        $LogFilePath,
        $message, $session)
    if ($null -eq $LogFilePath) {
        throw "Warning log file path required"
    }
    if ($OutputLog) {
        $outMsg = (Get-Date -Format "hh:mm") + "[W$session] $message"
        Add-Content -Path $LogFilePath -Value $outMsg
        Write-Host $outMsg -ForegroundColor Yellow
    }
}

function LogHelper {
    #TODO (sukhyung) finish+use this instead of duplicating the same stuff 4x
    param(
        [boolean]$OutputLog,
        $LogFilePath,
        $message,
        $type)
    if ($null -eq $LogFilePath) {
        throw "$type log file path required"
    }
    if ($OutputLog) {
        $outMsg = (Get-Date -Format "hh:mm") + "$type $message"
        Add-Content -Path $LogFilePath -Value $outMsg
        #switch ($type) {
        #condition {  }
        #Default {}
        #}
        #Write-Host $outMsg -ForegroundColor $Color
    }
}
function Initialize-KFLogs {
    <#
    .SYNOPSIS
    Initializes logging for a given filepath.  creates the file is not already present, one per day of the year (e.g. run the initialize
    twice in the same day, it will append the first file).  It will also ensure that only the latest $MaxFileCount log files are present.
    .PARAMETER OutputLog - boolean value, true to log, false to not log
    .PARAMETER LogFilePath - file path to where the log file is/should be (YYMMDD.txt is appended to this as the filename
    .PARAMETER LogFilePrefix - the string the log file should be named.
    .PARAMETER MaxFileCount - the maximum number of log files to keep in the $LogFilePath
    .OUTPUTS
    System.String. Intialize-KFLogs returns the path to the log file that should be used.
    #>
    param(
        [boolean]$OutputLog,
        $LogFilePath,
        $LogFilePrefix,
        [int] $MaxFileCount
    )
    #todo validate arguments?
    $LogFileName = $LogFilePath + "\" + $LogFilePrefix + (Get-Date -UFormat "%Y%m%d") + ".txt" #one log file per day
    if (!(Test-Path $LogFileName)) {
        #if file doesnt exist, create it
        $null = New-Item -ItemType file $LogFileName
    }

    $LogFormat = $LogFilePrefix + "*.txt"
    $existingLogs = [System.IO.Directory]::GetFiles("$LogFilePath", "$LogFormat") | Sort-Object -Descending #want newest to be first

    if ($existingLogs.Count -gt $MaxFileCount) {
        #keep only the $MaxFileCount latest log files
        for ($i = $MaxFileCount; $i -lt $existingLogs.Count; $i++) {
            Add-KFInfoLog $OutputLog $LogFileName "Deleting expired Logfile: $($existingLogs[$i])"
            [System.IO.File]::Delete($existingLogs[$i])
        }
    }
    return $LogFileName
}

function Initialize-KFLogs-Directory {
    <#
    .SYNOPSIS
    Initializes logging for a given filepath.  creates the file is not already present, one per day of the year (e.g. run the initialize
    twice in the same day, it will append the first file).  It will also ensure that only the latest $MaxFileCount log files are present.
    .PARAMETER OutputLog - boolean value, true to log, false to not log
    .PARAMETER LogFolderPath - file path to where the log folder is/should be (YYMMDD.txt is appended to this as the filename
    .PARAMETER LogFolderPrefix - the string the log directories should be named.
    .PARAMETER MaxFolderCount - the maximum number of log directories to keep in the $LogFilePath
    .OUTPUTS
    System.String. Intialize-KFLogs returns the path to the log file that should be used.
    #>
    param(
        [boolean]$OutputLog,
        $LogFolderPath,
        $logFolderPrefix,
        $IssuedCN,
        [int] $maxFolderCount
    )
    $myFolderPath = $LogFolderPath + "\" + $logFolderPrefix + "-" + (Get-Date -UFormat "%Y%m%d")
    if (!(Test-Path $myFolderPath)) { #if directory doesn't exist, create it
        New-Item -ItemType Directory -Path $myFolderPath
    }
    $myFilePath = $myFolderPath + "\" + $logFolderPrefix + "-" + $IssuedCN + ".txt"
    if (!(Test-Path $myFilePath)) { #same for file
        New-Item -ItemType File $myFilePath
    }
    $existingDirs = (Get-ChildItem -Path $LogFolderPath | Where-Object {$_.PSIsContainer -and $_.Name.Contains($logFolderPrefix+"-")} | Sort-Object -Descending) #only count folders named appropriatelyj
    if ($existingDirs.Count -gt $maxFolderCount) { #we have too many
            Add-KFInfoLog $OutputLog $myFilePath "$i, $($existingDirs.Count), $maxFolderCount"
        for ($i = $maxFolderCount; $i -lt $existingDirs.Count; $i++) {
            Add-KFInfoLog $OutputLog $myFilePath "deleting $i-th oldest log file folder: $($existingDirs[$i])"
            Remove-Item $existingDirs[$i].PSPath -Recurse #this will also delete all the contents
        }
    }
    return $myFilePath
}

Function Get-MeAMutex {
    param([Parameter(Mandatory = $true)][string] $MutexUniqueName)
    try {
        $myMutex = New-Object System.Threading.Mutex $false, $MutexUniqueName

        while (-not $myMutex.WaitOne(7000)) {
            Add-KFWarningLog $outputLog $logFile "no mutex, sleeping 7s "
            Start-Sleep -s 7
        }
        return $myMutex
    }
    catch [System.Threading.AbandonedMutexException] {
        $myMutex = New-Object System.Threading.Mutex $false, $MutexUniqueName
        Add-KFWarningLog $outputLog $logFile "mutex exception: $_ "
        return Get-MeAMutex -MutexId $MutexUniqueName
    }
}

Function Invoke-GcpJsonAuth {
    param([Parameter(Mandatory = $true)] $keyPath,
    $timeoutSec)
    $authJob = Start-Job -ScriptBlock {
        gcloud-ps auth activate-service-account --key-file="$($args[0])" 2>&1
    } -ArgumentList "$keyPath"
    Wait-Job $authJob -Timeout $timeoutSec
    if ($($authJob.State) -like "Completed") {
        $resp = Receive-Job $authJob
    } else {
        $resp = "GCP Authentication timed out after [$timeoutSec]"
        Remove-Job $authJob #cleanup
    }
    return $resp
}

Function Invoke-GcpConfigsUpdate {
    param ($clientMachine, $projectId, $projectRegion, $projectRegistry, $facilityNumOnly, $timeoutSec)
    $configJob = Start-Job -ScriptBlock {
        gcloud iot devices update "$($args[0])" --project="$($args[1])" --region="$($args[2])" --registry="$($args[3])" --metadata="FACILITY_NUMBER=$($args[4])" 2>&1
    } -ArgumentList $clientMachine, $projectId, $projectRegion, $projectRegistry, $facilityNumOnly
    Wait-Job $configJob -Timeout $timeoutSec
    if ($($configJob.State) -like "Completed") {
        $resp = Receive-Job $configJob
    } else {
        $resp = "GCP config update of $clientMachine to $facilityNumOnly timed out after [$timeoutSec]"
        Remove-Job $configJob #cleanup
    }
    return $resp
}
