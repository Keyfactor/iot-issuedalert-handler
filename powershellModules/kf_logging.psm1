# Copyright 2021 Keyfactor
# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions
# and limitations under the License.

function Add-InfoLog {
    <#
    .SYNOPSIS
    Adds the $message to the logfile as it's own line marked as [I] to be used for information,
    Also displays the message on the screen
    .PARAMETER OutputLog - boolean value, true to log, false to not log
    .PARAMETER LogFilePath - file path to where the log file is
    .PARAMETER message - the string contents to write to the file
    #>
param(
    [boolean]$OutputLog, 
    $LogFilePath, 
    $message)
if ($OutputLog) {
    $outMsg = (Get-Date -Format "hh:mm") + "[I] $message"
    Add-Content -Path $LogFilePath -Value $outMsg
    Write-Host $outMsg -ForegroundColor white
}
}
Export-ModuleMember -Function Add-InfoLog
function Add-ErrorLog {
    <#
    .SYNOPSIS
    Adds the $message to the logfile as it's own line marked as [E] to be used as an Error Message,
    Also displays the message on the screen in red
    .PARAMETER OutputLog - boolean value, true to log, false to not log
    .PARAMETER LogFilePath - file path to where the log file is
    .PARAMETER message - the string contents to write to the file
    #>
param(
    [boolean]$OutputLog, 
    $LogFilePath, 
    $message)
if ($OutputLog) {
    $outMsg = (Get-Date -Format "hh:mm") + "[E] $message"
    Add-Content -Path $LogFilePath -Value $outMsg
    Write-Host $outMsg -ForegroundColor red
}
}
Export-ModuleMember -Function Add-ErrorLog
function Add-WarningLog {
    <#
    .SYNOPSIS
    Adds the $message to the logfile as it's own line marked as [W] to be used as a Warning Message,
    Also displays the message on the screen in yellow
    .PARAMETER OutputLog - boolean value, true to log, false to not log
    .PARAMETER LogFilePath - file path to where the log file is
    .PARAMETER message - the string contents to write to the file
    #>
param(
    [boolean]$OutputLog, 
    $LogFilePath, 
    $message)
if ($OutputLog) {
    $outMsg = (Get-Date -Format "hh:mm") + "[W] $message"
    Add-Content -Path $LogFilePath -Value $outMsg
    Write-Host $outMsg -ForegroundColor Yellow
}
}
Export-ModuleMember -Function Add-WarningLog
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
    $LogFileName = $LogFilePath + "/" + $LogFilePrefix + (Get-Date -UFormat "%Y%m%d") + ".txt" #one log file per day
    if (!(Test-Path $LogFileName)) {#if file doesnt exist, create it
        $null = New-Item -ItemType file $LogFileName
    }

    $LogFormat = $LogFilePrefix + "*.txt"
    $existingLogs = [System.IO.Directory]::GetFiles("$LogFilePath", "$LogFormat") | Sort-Object -Descending #want newest to be first
    if ($existingLogs.Count -gt $MaxFileCount) {
        #keep only the $MaxFileCount latest log files
        for ($i = $MaxFileCount; $i -lt $existingLogs.Count; $i++) {
            Add-InfoLog $OutputLog $LogFileName "Deleting expired Logfile: $existingLogs[$i]"
            [System.IO.File]::Delete($existingLogs[$i])
        }
    }
    return $LogFileName
}
Export-ModuleMember -Function 'Initialize-KFLogs'
