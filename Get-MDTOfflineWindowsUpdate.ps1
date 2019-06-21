<#
    .SYNOPSIS
        Download updates for Offline installation

    .DESCRIPTION
        Required Internet access. Grabs a list of updates from last imaged system from MDT's ZTIWindowsUpdate.log and downloads them into a folder in a organized structure
        Works in conjuntion with a modified ZTIWindowsUpdate.wsf and Apply-MDTOfflineWindowsUpdates.ps1 (not created yet)

    .EXAMPLE
        powershell.exe -ExecutionPolicy Bypass -file "Get-MDTOfflineWindowsUpdate.ps1"

    .NOTES
        This script was designed with offline or limited bandwidth imaging in mind mainly for windows and office patches. The goal is to uas an online MDT server to pull patches, 
        then copy those patches to office applications updates folder. So when the next system images, it pulls patches locally first. 

    .INFO
        Script:         Get-MDTOfflineWindowsUpdate.ps1    
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
        SHALL THE AUTHOR OR ANY AFFILATES BE HELD LIABLE FOR ANY DAMAGES WHATSOEVER RESULTING FROM USING OR DISTRIBUTION OF THIS SCRIPT, INCLUDING,
        WITHOUT LIMITATION, ANY SPECIAL, CONSEQUENTIAL, INCIDENTAL OR OTHER DIRECT OR INDIRECT DAMAGES. BACKUP UP ALL DATA BEFORE PROCEEDING. 
    
    .CHANGE LOG
        1.1.0 - Jun 20, 2019 - Updated log entry functions; cleaned up script   
        1.0.0 - Feb 11, 2016 - initial 
#> 
#==================================================
# FUNCTIONS
#==================================================
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

Function Get-ScriptPath {
    # Makes debugging from ISE easier.
    if ($PSScriptRoot -eq "")
    {
        if (Test-IsISE)
        {
            $psISE.CurrentFile.FullPath
            #$root = Split-Path -Parent $psISE.CurrentFile.FullPath
        }
        else
        {
            $context = $psEditor.GetEditorContext()
            $context.CurrentFile.Path
            #$root = Split-Path -Parent $context.CurrentFile.Path
        }
    }
    else
    {
        #$PSScriptRoot
        $PSCommandPath
        #$MyInvocation.MyCommand.Path
    }
}


Function Format-ElapsedTime($ts) {
    $elapsedTime = ""
    if ( $ts.Minutes -gt 0 ){$elapsedTime = [string]::Format( "{0:00} min. {1:00}.{2:00} sec", $ts.Minutes, $ts.Seconds, $ts.Milliseconds / 10 );}
    else{$elapsedTime = [string]::Format( "{0:00}.{1:00} sec", $ts.Seconds, $ts.Milliseconds / 10 );}
    if ($ts.Hours -eq 0 -and $ts.Minutes -eq 0 -and $ts.Seconds -eq 0){$elapsedTime = [string]::Format("{0:00} ms", $ts.Milliseconds);}
    if ($ts.Milliseconds -eq 0){$elapsedTime = [string]::Format("{0} ms", $ts.TotalMilliseconds);}
    return $elapsedTime
}

Function Format-DatePrefix {
    [string]$LogTime = (Get-Date -Format 'HH:mm:ss.fff').ToString()
	[string]$LogDate = (Get-Date -Format 'MM-dd-yyyy').ToString()
    return ($LogDate + " " + $LogTime)
}

Function Write-LogEntry {
    param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        [Parameter(Mandatory=$false,Position=2)]
		[string]$Source = '',
        [parameter(Mandatory=$false)]
        [ValidateSet(0,1,2,3,4)]
        [int16]$Severity,

        [parameter(Mandatory=$false, HelpMessage="Name of the log file that the entry will written to")]
        [ValidateNotNullOrEmpty()]
        [string]$OutputLogFile = $Global:LogFilePath,

        [parameter(Mandatory=$false)]
        [switch]$Outhost
    )
    Begin{
        [string]$LogTime = (Get-Date -Format 'HH:mm:ss.fff').ToString()
        [string]$LogDate = (Get-Date -Format 'MM-dd-yyyy').ToString()
        [int32]$script:LogTimeZoneBias = [timezone]::CurrentTimeZone.GetUtcOffset([datetime]::Now).TotalMinutes
        [string]$LogTimePlusBias = $LogTime + $script:LogTimeZoneBias
        
    }
    Process{
        # Get the file name of the source script
        Try {
            If ($script:MyInvocation.Value.ScriptName) {
                [string]$ScriptSource = Split-Path -Path $script:MyInvocation.Value.ScriptName -Leaf -ErrorAction 'Stop'
            }
            Else {
                [string]$ScriptSource = Split-Path -Path $script:MyInvocation.MyCommand.Definition -Leaf -ErrorAction 'Stop'
            }
        }
        Catch {
            $ScriptSource = ''
        }
        
        
        If(!$Severity){$Severity = 1}
        $LogFormat = "<![LOG[$Message]LOG]!>" + "<time=`"$LogTimePlusBias`" " + "date=`"$LogDate`" " + "component=`"$ScriptSource`" " + "context=`"$([Security.Principal.WindowsIdentity]::GetCurrent().Name)`" " + "type=`"$Severity`" " + "thread=`"$PID`" " + "file=`"$ScriptSource`">"
        
        # Add value to log file
        try {
            Out-File -InputObject $LogFormat -Append -NoClobber -Encoding Default -FilePath $OutputLogFile -ErrorAction Stop
        }
        catch {
            Write-Host ("[{0}] [{1}] :: Unable to append log entry to [{1}], error: {2}" -f $LogTimePlusBias,$ScriptSource,$OutputLogFile,$_.Exception.Message) -ForegroundColor Red
        }
    }
    End{
        If($Outhost -or $Global:OutTohost){
            If($Source){
                $OutputMsg = ("[{0}] [{1}] :: {2}" -f $LogTimePlusBias,$Source,$Message)
            }
            Else{
                $OutputMsg = ("[{0}] [{1}] :: {2}" -f $LogTimePlusBias,$ScriptSource,$Message)
            }

            Switch($Severity){
                0       {Write-Host $OutputMsg -ForegroundColor Green}
                1       {Write-Host $OutputMsg -ForegroundColor Gray}
                2       {Write-Warning $OutputMsg}
                3       {Write-Host $OutputMsg -ForegroundColor Red}
                4       {If($Global:Verbose){Write-Verbose $OutputMsg}}
                default {Write-Host $OutputMsg}
            }
        }
    }
}


Function Show-ProgressStatus {
    <#
    .SYNOPSIS
        Shows task sequence secondary progress of a specific step
    
    .DESCRIPTION
        Adds a second progress bar to the existing Task Sequence Progress UI.
        This progress bar can be updated to allow for a real-time progress of
        a specific task sequence sub-step.
        The Step and Max Step parameters are calculated when passed. This allows
        you to have a "max steps" of 400, and update the step parameter. 100%
        would be achieved when step is 400 and max step is 400. The percentages
        are calculated behind the scenes by the Com Object.
    
    .PARAMETER Message
        The message to display the progress
    .PARAMETER Step
        Integer indicating current step
    .PARAMETER MaxStep
        Integer indicating 100%. A number other than 100 can be used.
    .INPUTS
         - Message: String
         - Step: Long
         - MaxStep: Long
    .OUTPUTS
        None
    .EXAMPLE
        Set's "Custom Step 1" at 30 percent complete
        Show-ProgressStatus -Message "Running Custom Step 1" -Step 100 -MaxStep 300
    
    .EXAMPLE
        Set's "Custom Step 1" at 50 percent complete
        Show-ProgressStatus -Message "Running Custom Step 1" -Step 150 -MaxStep 300
    .EXAMPLE
        Set's "Custom Step 1" at 100 percent complete
        Show-ProgressStatus -Message "Running Custom Step 1" -Step 300 -MaxStep 300
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string] $Message,
        [Parameter(Mandatory=$true)]
        [int]$Step,
        [Parameter(Mandatory=$true)]
        [int]$MaxStep,
        [string]$SubMessage,
        [int]$IncrementSteps,
        [switch]$Outhost
    )

    Begin{

        If($SubMessage){
            $StatusMessage = ("{0} [{1}]" -f $Message,$SubMessage)
        }
        Else{
            $StatusMessage = $Message

        }
    }
    Process
    {
        If($Script:tsenv){
            $Script:TSProgressUi.ShowActionProgress(`
                $Script:tsenv.Value("_SMSTSOrgName"),`
                $Script:tsenv.Value("_SMSTSPackageName"),`
                $Script:tsenv.Value("_SMSTSCustomProgressDialogMessage"),`
                $Script:tsenv.Value("_SMSTSCurrentActionName"),`
                [Convert]::ToUInt32($Script:tsenv.Value("_SMSTSNextInstructionPointer")),`
                [Convert]::ToUInt32($Script:tsenv.Value("_SMSTSInstructionTableSize")),`
                $StatusMessage,`
                $Step,`
                $Maxstep)
        }
        Else{
            Write-Progress -Activity "$Message ($Step of $Maxstep)" -Status $StatusMessage -PercentComplete (($Step / $Maxstep) * 100) -id 1
        }
    }
    End{
        Write-LogEntry $Message -Severity 1 -Outhost:$Outhost
    }
}


##Removes all the SMS-specific stuff like [LOG, component, etc
##Get-SccmClientLog passes all potential output to this cmdlet
Filter Format-SccmClientLogData ($aLogData) {
    try {
        $aFilteredLog = @();
        foreach ($sLine in $aLogData) {
	        $reLine = ([regex]'<!\[LOG\[(.*)]LOG]!><time="(.+)" date="(.+)" component').matches($sLine)
	        foreach ($oLine in $reLine) {
		        $aSplit = ($oLine.Groups[2].Value).Split('.');
		        [datetime]$sDateTime = "$($oLine.Groups[3].Value) $($aSplit[0])";
		        $oLog = New-Object System.Object;
		        $oLog | Add-Member -type NoteProperty -name DateTime -value $sDateTime;
		        $oLog | Add-Member -type NoteProperty -name Message -value  $oLine.Groups[1].Value;
		        $oLog = $oLog | Sort-Object 'DateTime'
		        #$aFilteredLog += $oLog;
		        $oLog;
	        }
        }
        
    } 
    catch [System.Exception] {
	    Write-Debug "$($MyInvocation.MyCommand.Name): $($_.Exception.Message)";
	    return $false;
    }
}


##Used in the pipeline to take SMSTS log data and only pick out the interesting lines
Filter Parse-WindowsUpdates($LogLine) {
    try {
        $aInterestingLines = @('INSTALL - ');
        
        $aInterestingData = @();
        foreach ($sLine in $aInterestingLines) {
            if ($oTsLogLine.Message -like "$sLine*") {
	            $oLog = New-Object System.Object;
	            $oLog | Add-Member -type NoteProperty -name DateTime -value $oTsLogLine.DateTime;
	            $oLog | Add-Member -type NoteProperty -name Message -value  $oTsLogLine.Message;
	            
                if ($oTsLogLine.Message -like '*Error*') {
		            $oLog | Add-Member -type NoteProperty -name LineResult -value 'Red';
	            }
                else {
		            $oLog | Add-Member -type NoteProperty -name LineResult -value 'Green';
	            }
	            $oLog;
            }
        }
    } 
    catch [System.Exception] {
        Write-Debug "$($MyInvocation.MyCommand.Name): $($_.Exception.Message)";
        return $false;
    }
}#

function Convert-Size {            
    [cmdletbinding()]            
    param(            
        [validateset("Bytes","KB","MB","GB","TB")]            
        [string]$From,            
        [validateset("Bytes","KB","MB","GB","TB")]            
        [string]$To,            
        [Parameter(Mandatory=$true)]            
        [double]$Value,            
        [int]$Precision = 4            
    )            
    switch($From) {            
        "Bytes" {$value = $Value }            
        "KB" {$value = $Value * 1024 }            
        "MB" {$value = $Value * 1024 * 1024}            
        "GB" {$value = $Value * 1024 * 1024 * 1024}            
        "TB" {$value = $Value * 1024 * 1024 * 1024 * 1024}            
    }            
            
    switch ($To) {            
        "Bytes" {return $value}            
        "KB" {$Value = $Value/1KB}            
        "MB" {$Value = $Value/1MB}            
        "GB" {$Value = $Value/1GB}            
        "TB" {$Value = $Value/1TB}            
            
    }            
            
    return [Math]::Round($value,$Precision,[MidPointRounding]::AwayFromZero)            
            
}

function Get-CMTraceLog
{
    <#
    .SYNOPSIS
        Parses logs for System Center Configuration Manager.
    .DESCRIPTION
        Accepts a single log file or array of log files and parses them into objects.  Shows both UTC and local time for troubleshooting across time zones.
    .PARAMETER Path
        Specifies the path to a log file or files.
    .INPUTS
        Path/FullName.  
    .OUTPUTS
        PSCustomObject.  
    .EXAMPLE
        C:\PS> Get-CMTraceLog -Path Sample.log
        Converts each log line in Sample.log into objects
        UTCTime   : 7/15/2013 3:28:08 PM
        LocalTime : 7/15/2013 2:28:08 PM
        FileName  : sample.log
        Component : TSPxe
        Context   : 
        Type      : 3
        TID       : 1040
        Reference : libsmsmessaging.cpp:9281
        Message   : content location request failed
    .EXAMPLE
        C:\PS> Get-ChildItem -Path C:\Windows\CCM\Logs | Select-String -Pattern 'failed' | Select -Unique Path | Get-CMTraceLog
        Find all log files in folder, create a unique list of files containing the phrase 'failed, and convert the logs into objects
        UTCTime   : 7/15/2013 3:28:08 PM
        LocalTime : 7/15/2013 2:28:08 PM
        FileName  : sample.log
        Component : TSPxe
        Context   : 
        Type      : 3
        TID       : 1040
        Reference : libsmsmessaging.cpp:9281
        Message   : content location request failed
    .LINK
        http://blog.richprescott.com
    #>


    param(
    [Parameter(Mandatory=$true,
               Position=0,
               ValueFromPipelineByPropertyName=$true)]
    [Alias("FullName")]
    $Path
    )

    PROCESS
    {
        foreach ($File in $Path)
        {
            $FileName = Split-Path -Path $File -Leaf

            Get-Content -Path $File | %{
                $_ -match '\<\!\[LOG\[(?<Message>.*)?\]LOG\]\!\>\<time=\"(?<Time>.+)(?<TZAdjust>[+|-])(?<TZOffset>\d{2,3})\"\s+date=\"(?<Date>.+)?\"\s+component=\"(?<Component>.+)?\"\s+context="(?<Context>.*)?\"\s+type=\"(?<Type>\d)?\"\s+thread=\"(?<TID>\d+)?\"\s+file=\"(?<Reference>.+)?\"\>' | Out-Null
                [pscustomobject]@{
                    UTCTime = [datetime]::ParseExact($("$($matches.date) $($matches.time)$($matches.TZAdjust)$($matches.TZOffset/60)"),"MM-dd-yyyy HH:mm:ss.fffz", $null, "AdjustToUniversal")
                    LocalTime = [datetime]::ParseExact($("$($matches.date) $($matches.time)"),"MM-dd-yyyy HH:mm:ss.fff", $null)
                    FileName = $FileName
                    Component = $matches.component
                    Context = $matches.context
                    Type = $matches.type
                    TID = $matches.TID
                    Reference = $matches.reference
                    Message = $matches.message
                }
            }
        }
    }
}

Function Get-CMTraceLogProperties{
    param(
    [Parameter(Mandatory=$true,
               Position=0,
               ValueFromPipelineByPropertyName=$true)]
    [string[]]$Data,
    [switch]$Consolidate,
    [switch]$ConvertToVariables
    )
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process{
        $Properties = @()
        #loop thorugh all lines in data
        Foreach($item in $Data){
            #search properties:
            If($item -match "^Property"){
                #Build property and value
                $property = ($item -split " ")[1]
                $value = ($item -split "=")[1] 
                Write-Verbose "$property = $value"

                $object = [pscustomobject]@{
                    Property = $property
                    Value = $value 
                }

                #merge properties that are the same
                If($Consolidate){
                
                    If($Properties | Where-Object{$_.Property -eq $object.Property}){
                        Write-Verbose "Consolidating $property = $value"
                        $Properties | %{$property = $_[$value]}
                    }
                    Else{
                         $Properties += $object
                    }
                }
                #grab all properties
                Else{
                    $Properties += $object
                }
            }
        }#End loop
    }
    End{
        If($ConvertToVariables){
            #grab each property and if the value is not empty set value
            $Properties | %{If($null -ne $_.Value -and $_.Value -ne '<empty>'){Set-Variable $_.Property -Value $_.Value -Force -Verbose}}
        }
        return $Properties
    }
}

Function Parse-CMTraceLog{
    <#
    .SYNOPSIS
      Function for reading CM logs in powershell
    .DESCRIPTION
      <Brief description of script>
    .PARAMETER path
      Sets one or more paths to load logfiles from
    .PARAMETER LogLevel
        Sets the Minimum level for log level that will be displayed, default is everything.
    .PARAMETER Gridview
        Opens the output in a gridview windows
    .PARAMETER passthru
        Outputs the array directly without any formating for further use.
    .INPUTS
      None
    .OUTPUTS
      Array of logentries
    .NOTES
      Version:        1.0
      Author:         Mattias Benninge
      Creation Date:  2017-05-04
      Purpose/Change: Initial script development
    .EXAMPLE
        Gets all warnings and errors from multiple logfiles
        .\Parse-CMTraceLog -path C:\Windows\CCM\logs\DcmWmiProvider.log,C:\Windows\CCM\logs\ccmexec.log -LogLevel Warning
    .EXAMPLE
        Gets multiple logfiles and present in a GridView
        .\Parse-CMTraceLog -path C:\Windows\CCM\logs\DcmWmiProvider.log,C:\Windows\CCM\logs\ccmexec.log -Gridview
    #>
    
    param(
    [Parameter(Mandatory=$true,
               Position=0,
               ValueFromPipelineByPropertyName=$true)]
    [Alias("FullName")]
    $Path
    )

    $result = $null
    $result = @()
    Foreach($path in $paths){
        $cmlogformat = $false
        $cmslimlogformat = $false
        # Use .Net function instead of Get-Content, much faster.
        $file = [System.io.File]::Open($path, 'Open', 'Read', 'ReadWrite')
        $reader = New-Object System.IO.StreamReader($file)
        [string]$LogFileRaw = $reader.ReadToEnd()
        $reader.Close()
        $file.Close()

        $pattern = "LOG\[(.*?)\]LOG(.*?)time(.*?)date"
        $patternslim = '\$\$\<(.*?)\>\<thread='
        
        if(([Regex]::Match($LogFileRaw, $pattern)).Success -eq $true){ $cmlogformat = $true}
        elseif(([Regex]::Match($LogFileRaw, $patternslim)).Success -eq $true){ $cmslimlogformat = $true}
        
        If($cmlogformat){
                
            # Split each Logentry into an array since each entry can span over multiple lines
            $logarray = $LogFileRaw -split "<!"

            foreach($logline in $logarray){
                
                If($logline){            
                    # split Log text and meta data values
                    $metadata = $logline -split "><"

                    # Clean up Log text by stripping the start and end of each entry
                    $logtext = ($metadata[0]).Substring(0,($metadata[0]).Length-6).Substring(5)
            
                    # Split metadata into an array
                    $metaarray = $metadata[1] -split '"'

                    # Rebuild the result into a custom PSObject
                    $result += $logtext |select-object @{Label="LogText";Expression={$logtext}}, @{Label="Type";Expression={[LogType]$metaarray[9]}},@{Label="Component";Expression={$metaarray[5]}},@{Label="DateTime";Expression={[datetime]::ParseExact($metaarray[3]+($metaarray[1]).Split("-")[0].Split("+")[0].ToString(), "MM-dd-yyyyHH:mm:ss.fff", $null)}},@{Label="Thread";Expression={$metaarray[11]}}
                }        
            }
        }

        If($cmslimlogformat){
       
        # Split each Logentry into an array since each entry can span over multiple lines
        $logarray = $LogFileRaw -split [System.Environment]::NewLine
              
        foreach($logline in $logarray){
            
            If($logline){  

                    # split Log text and meta data values
                    $metadata = $logline -split '\$\$<'

                    # Clean up Log text by stripping the start and end of each entry
                    $logtext = $metadata[0]
            
                    # Split metadata into an array
                    $metaarray = $metadata[1] -split '><'
                    If($logtext){
                        # Rebuild the result into a custom PSObject
                        If($metaarray[1] -match '\+'){
                            $result += $logtext |select-object @{Label="LogText";Expression={$logtext}}, @{Label="Type";Expression={[LogType]0}},@{Label="Component";Expression={$metaarray[0]}},@{Label="DateTime";Expression={[datetime]::ParseExact(($metaarray[1]).Substring(0, ($metaarray[1]).Length - (($metaarray[1]).Length - ($metaarray[1]).LastIndexOf("+"))), "MM-dd-yyyy HH:mm:ss.fff", $null)}},@{Label="Thread";Expression={($metaarray[2] -split " ")[0].Substring(7)}}
                        }
                        else{
                            $result += $logtext |select-object @{Label="LogText";Expression={$logtext}}, @{Label="Type";Expression={[LogType]0}},@{Label="Component";Expression={$metaarray[0]}},@{Label="DateTime";Expression={[datetime]::ParseExact(($metaarray[1]).Substring(0, ($metaarray[1]).Length - (($metaarray[1]).Length - ($metaarray[1]).LastIndexOf("-"))), "MM-dd-yyyy HH:mm:ss.fff", $null)}},@{Label="Thread";Expression={($metaarray[2] -split " ")[0].Substring(7)}}
                        }
                    }
                }
            }
        }
    }

    
    $result #return data
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
$Module = Join-Path $scriptDirectory -ChildPath 'PSModules'
$destRootPath = Join-Path $scriptDirectory -ChildPath 'Updates'
$RelativeLogPath = Join-Path -Path $scriptDirectory -ChildPath 'Logs'

#build log name
[string]$FileName = $scriptBaseName +'.log'
#build global log fullpath
$Global:LogFilePath = Join-Path $RelativeLogPath -ChildPath $FileName
#clean old log
if(Test-Path $Global:LogFilePath){remove-item -Path $Global:LogFilePath -ErrorAction SilentlyContinue | Out-Null}

Write-Host "Logging to file: $LogFilePath" -ForegroundColor Cyan

##*===========================================================================
##* VARIABLES - ONLY CHANGE THESE
##*===========================================================================
#filter on a deployment log. Useful if your testing the latest OS, but yet you need Older OS and office patches
$MDTTaskSequenceLogFilter = "Windows 10 Enterprise|Office 2016"

#Filter on number of days to check for last log used. Incase deployment hsan't ran in a while
$MDTDayFilter = 30

#location to get MDT logs
$MDTDeploymentShare = "D:\DeploymentShare\Logs"

##*===========================================================================
##* MAIN
##*===========================================================================

#import modules 
. "$Module\Get-WUFileByID.ps1"

#Scan logs for latest LiteTouch.log within the speificed day filter
#Parse each log until you fine one that matches the task sequence filter
$LiteTouchLogs = Get-ChildItem $MDTDeploymentShare -Filter LiteTouch.log -Recurse | where {$_.lastwritetime -gt (get-date).adddays(-$MDTDayFilter)} | sort LastWriteTime -Descending
$WindowsUpdatesLog = $null
$LogData = $null
Foreach ($Log in $SMSTSLogs){
    $LogData = Get-CMTraceLogProperties (Get-CMTraceLog $Log.FullName).Message -Consolidate
    If($LogData | Where{$_.Value -match $MDTTaskSequenceLogFilter}){
        $LogData.Property
        $LogRootPath = Split-Path $Log.FullName -Parent
        $WindowsUpdatesLog = Get-ChildItem $LogRootPath -Filter ZTIWindowsUpdate.log
        Break
    }
}

If($WindowsUpdatesLog){
    #load messages from ZTIWindowsUpdates.log
    Write-LogEntry ("Using Log file from {0}" -f $WindowsUpdatesLog.FullName) -Outhost
    $data = Get-CMTraceLog $WindowsUpdates.FullName
    $allmessages = $data.Message
}
Else{
    Write-LogEntry ("No Log file found that meets filter [{0}]. Refine filter if needed" -f $MDTTaskSequenceLogFilter) -Outhost
    Exit
}

#Process the log looking for updates
$updates = @();
$updates = foreach ($msg in $allmessages) {
    if ($msg.Message -like "INSTALL - *") {
        Try{
            #Write-Host $msg.Message
            $splitmsg = ($msg.Message -split '\s+-\s+')
            $GUID = $splitmsg[1]
            $size = $splitmsg[3]
            $classification = ($splitmsg[2] -split 'for',2)[0].Trim()
            $product = ($splitmsg[2] -split 'for',2)[1].Split('(')[0].Trim()
            $findarch = ($splitmsg[2]).Split(')')[1].Trim() | Where {$_ -match '\d{2}'} | Out-null
            If($matches[0] -eq '32'){$arc = 'x86'}Else{$arc = 'x64'}
            $msg.Message -match ".?\((.*?)\).*" | Out-Null
            $kb = $matches[1]

            $oLog = New-Object System.Object;
	        $oLog | Add-Member -type NoteProperty -name GUID -value $GUID;
            $oLog | Add-Member -type NoteProperty -name Kb -value $kb;    
            $oLog | Add-Member -type NoteProperty -name Classification -value $classification;
            $oLog | Add-Member -type NoteProperty -name Product -value $product;
            $oLog | Add-Member -type NoteProperty -name Arc -value $arc;
            $oLog | Add-Member -type NoteProperty -name Size -value $size;
      
	        $oLog;
        }
        catch [System.Exception] {
            #Write-Host "$($MyInvocation.MyCommand.Name): $($_.Exception.Message)";
            #return $false;
        }      
    }    
}#end update loop

foreach ($update in $updates) {
    $productPath = Join-Path $destRootPath -ChildPath $update.Product
    New-Item $productPath -ItemType Directory -Force | Out-Null
    Get-WUFileByID -GUID $update.guid -DestinationFolder $productPath
}
