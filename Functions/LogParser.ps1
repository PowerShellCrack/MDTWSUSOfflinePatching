

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