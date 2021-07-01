<#
    .SYNOPSIS
        Download updates for Offline installation

    .DESCRIPTION
        Required Internet access. Grabs a list of updates from last imaged system from MDT's ZTIWindowsUpdate.log and downloads them into a folder in a organized structure
        Works in conjunction with a modified ZTIWindowsUpdate.wsf and Apply-MDTOfflineWindowsUpdates.ps1 (not created yet)

    .PARAMETER DeploymentShareLogPath
        Specify path deploymentshare log folder to parse ZTIWindowsUpdate.log

    .PARAMETER WindowsUpdateFilter
        filter on a deployment log. Useful if your testing the latest OS, but yet you need Older OS and office patches; use pipe "|"" to separate words
        Defaults to 'Windows 10|Office 2016|Office 2013'

    .PARAMETER UpdateExportPath
        Path to download update to
        Defaults to .\Updates

    .PARAMETER FilterByDays
        Filter on number of days to check for last log used. Incase deployment hasn't ran in a while
        Defaults to 30 days

    .NOTES
        This script was designed with offline or limited bandwidth imaging in mind mainly for windows and office patches. The goal is to uas an online MDT server to pull patches,
        then copy those patches to office applications updates folder. So when the next system images, it pulls patches locally first.

        Script:         Get-UpdatesFromZTIWindowsUpdate.ps1
        Author:         Richard Tracy
        Email:          richard.tracy@hotmail.com
        Twitter:        @rick2_1979
        Website:        www.powershellcrack.com
        Last Update:    06/20/2019
        Version:        1.1.0
        Thanks to:      Kirill Nikolaev,richprescott,Matt Benninge

    .LINK
        https://github.com/exchange12rocks/WU/tree/master/Get-WUFilebyID
        http://blog.richprescott.com

    .DISCLOSURE
        THE SCRIPT IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
        OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. BY USING OR DISTRIBUTING THIS SCRIPT, YOU AGREE THAT IN NO EVENT
        SHALL THE AUTHOR OR ANY AFFILIATES BE HELD LIABLE FOR ANY DAMAGES WHATSOEVER RESULTING FROM USING OR DISTRIBUTION OF THIS SCRIPT, INCLUDING,
        WITHOUT LIMITATION, ANY SPECIAL, CONSEQUENTIAL, INCIDENTAL OR OTHER DIRECT OR INDIRECT DAMAGES. BACKUP UP ALL DATA BEFORE PROCEEDING.

    .EXAMPLE
       .\Get-UpdatesFromZTIWindowsUpdate.ps1
#>


Param(
    $DeploymentShareLogPath = "C:\DeploymentShare\Logs",

    $WindowsUpdateFilter = 'Windows 10|Office 2016|Office 2013',

    $UpdateExportPath,

    $FilterByDays = 30
)
#==================================================
# FUNCTIONS
#==================================================
#region FUNCTION: Check if running in WinPE
Function Test-WinPE{
    return Test-Path -Path Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlset\Control\MiniNT
}
#endregion

#region FUNCTION: Check if running in ISE
Function Test-IsISE {
    # try...catch accounts for:
    # Set-StrictMode -Version latest
    try {
        return ($null -ne $psISE);
    }
    catch {
        return $false;
    }
}
#endregion

#region FUNCTION: Check if running in Visual Studio Code
Function Test-VSCode{
    if($env:TERM_PROGRAM -eq 'vscode') {
        return $true;
    }
    Else{
        return $false;
    }
}
#endregion

#region FUNCTION: Find script path for either ISE or console
Function Get-ScriptPath {
    <#
        .SYNOPSIS
            Finds the current script path even in ISE or VSC
        .LINK
            Test-VSCode
            Test-IsISE
    #>
    param(
        [switch]$Parent
    )

    Begin{}
    Process{
        if ($PSScriptRoot -eq "")
        {
            if (Test-IsISE)
            {
                $ScriptPath = $psISE.CurrentFile.FullPath
            }
            elseif(Test-VSCode){
                $context = $psEditor.GetEditorContext()
                $ScriptPath = $context.CurrentFile.Path
            }Else{
                $ScriptPath = (Get-location).Path
            }
        }
        else
        {
            $ScriptPath = $PSCommandPath
        }
    }
    End{

        If($Parent){
            Split-Path $ScriptPath -Parent
        }Else{
            $ScriptPath
        }
    }

}
#endregion

##*===========================================================================
##* DYNAMIC VARIABLES
##*===========================================================================
# Use function to get paths because Powershell ISE and other editors have differnt results
$scriptPath = Get-ScriptPath
[string]$scriptDirectory = Split-Path $scriptPath -Parent
[string]$scriptName = Split-Path $scriptPath -Leaf
[string]$scriptBaseName = [System.IO.Path]::GetFileNameWithoutExtension($scriptName)

#Create Paths
$FunctionsPath = Join-Path $scriptDirectory -ChildPath 'Functions'

##*========================================================================
##* Additional Runtime Function - REQUIRED
##*========================================================================
. "$FunctionsPath\Get-WUFileByID.ps1"
. "$FunctionsPath\Logging.ps1"
. "$FunctionsPath\LogParser.ps1"
. "$FunctionsPath\Environment.ps1"

#build log name
[string]$FileName = $scriptBaseName +'.log'
#build global log fullpath
If(Test-SMSTSENV){
    $Global:LogFilePath = Join-Path (Test-SMSTSENV -ReturnLogPath -Verbose) -ChildPath $FileName
}Else{
    $RelativeLogPath = Join-Path -Path $scriptDirectory -ChildPath 'Logs'
}

Write-Host "Logging to file: $LogFilePath" -ForegroundColor Cyan

##*===========================================================================
##* MAIN
##*===========================================================================
If($UpdateExportPath){
    $UpdatesPath = $UpdateExportPath
}Else{
    $UpdatesPath = Join-Path $scriptDirectory -ChildPath 'Updates'
}


$WindowsUpdatesLog = $null
$LogData = $null

#Scan logs for latest LiteTouch.log within the specified day filter
#Parse each log until you fine one that matches the task sequence filter
$LiteTouchLogs = Get-ChildItem $DeploymentShareLogPath -Filter LiteTouch.log -Recurse | where {$_.lastwritetime -gt (get-date).adddays(-$FilterByDays)} | sort LastWriteTime -Descending

#TEST $Log = $LiteTouchLogs[0]
Foreach ($Log in $LiteTouchLogs){
    $LogData = Get-CMTraceLogProperties (Get-CMTraceLog $Log.FullName).Message -Consolidate
    If( ($LogData | Where Property -eq TaskSequenceName).value.Trim() -match $WindowsUpdateFilter ){
        #$LogData.Property
        $WorkingLogPath = Split-Path $Log.FullName -Parent
        $WindowsUpdatesLog = Get-ChildItem $WorkingLogPath -Filter ZTIWindowsUpdate.log
        Break
    }
}

If($WindowsUpdatesLog){
    #load messages from ZTIWindowsUpdates.log
    Write-LogEntry ("Using Log file from {0}" -f $WindowsUpdatesLog.FullName) -Outhost
    $data = Get-CMTraceLog $WindowsUpdatesLog.FullName
    $allmessages = $data.Message
}
Else{
    Write-LogEntry ("No Log file found that meets filter [{0}]. Refine filter if needed" -f $WindowsUpdateFilter) -Outhost
    Exit
}

#Process the log looking for updates
$updates = @()
foreach ($msg in $allmessages) {
    if ($msg -like "INSTALL - *") {

        Try{
            #Write-Host $msg.Message
            $splitmsg = ($msg -split '\s+-\s+')
            $GUID = $splitmsg[1]
            $size = $splitmsg[3]
            $classification = ($splitmsg[2] -split 'for',2)[0].Trim()
            $product = ($splitmsg[2] -split 'for',2)[1].Split('(')[0].Trim()
            $findarch = ($splitmsg[2]).Split(')')[1].Trim() | Where {$_ -match '\d{2}'} | Out-null
            If($matches[0] -eq '32'){$arc = 'x86'}Else{$arc = 'x64'}
            $msg -match ".?\((.*?)\).*" | Out-Null
            $kb = $matches[1]



            If($kb -notin $updates.kb){
                Try{
                   $link = Get-WUFileByID -GUID $GUID -ErrorAction Stop -LinksOnly
                }
                Catch{
                   $link = Get-WUFileByID -KB ($kb.replace('KB','')) -SearchCriteria $Product -Platform $arc -LinksOnly
                }

                $oLog = New-Object System.Object;
	            $oLog | Add-Member -type NoteProperty -name GUID -value $GUID
                $oLog | Add-Member -type NoteProperty -name Kb -value $kb
                $oLog | Add-Member -type NoteProperty -name Classification -value $classification
                $oLog | Add-Member -type NoteProperty -name Product -value $product
                $oLog | Add-Member -type NoteProperty -name Arc -value $arc
                $oLog | Add-Member -type NoteProperty -name Size -value $size
                $oLog | Add-Member -type NoteProperty -name Link -value $link

	            $updates += $oLog
            }
        }
        catch [System.Exception] {
            #Write-Host "$($MyInvocation.MyCommand.Name): $($_.Exception.Message)"
            #return $false;
        }

    }
}#end update loop


#TEST $update = $updates[0]
foreach ($update in $updates) {
    $productPath = Join-Path $UpdateExportPath -ChildPath $update.Product
    New-Item $productPath -ItemType Directory -Force | Out-Null

    $MSUFilename = Split-Path $update.link -Leaf
    $FileExists = Get-ChildItem $productPath -filter $MSUFilename
    If(!$FileExists){
        Write-LogEntry ("Downloading: {0}" -f $update.kb) -Outhost
        Try{
            Get-WUFileByID -GUID $update.guid -DestinationFolder $productPath -ErrorAction Stop
        }
        Catch{
            Get-WUFileByID -KB ($update.kb).replace('KB','') -SearchCriteria $update.Product -DestinationFolder $productPath -Platform $update.Arc
        }
    }Else{
        Write-LogEntry ("Already Downloaded: {0}" -f $FileExists.Name ) -Outhost
    }
}

