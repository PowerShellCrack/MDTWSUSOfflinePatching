<#
.SYNOPSIS
    Downloads Updates using CliXml

.DESCRIPTION
    Downloads Updates using CliXml export and stores them locally

.PARAMETER ImportFile
    MANDATORY: Specifies the location of XML export file.

.PARAMETER ExportUpdatesPath
    Defaults to .\Updates

.PARAMETER ExpandCabs
    SWITCH: Extracts CAB files (Useful when downloading Office patches)
    Extracts to <download folder>\Expanded

.NOTES
    Author		: Dick Tracy II <richard.tracy@microsoft.com>
	Source		: https://github.com/PowerShellCrack/MDTWSUSOfflinePatching
    Version		: 2.0.0
    #Requires -Version 3.0

.EXAMPLE
    .\Download-UpdatesFromXmlExport.ps1 -ImportFile c:\exports\updates.xml

.EXAMPLE
    .\Download-UpdatesFromXmlExport.ps1 -ExportUpdatesPath c:\Updates

.EXAMPLE
    .\Download-UpdatesFromXmlExport.ps1 -ImportFile c:\exports\updates.xml -ExpandCabs

#>


Param(
    [Parameter(Mandatory,
            ValueFromPipeline = $true,
            Position = 0)]
    [string]$ImportFile,
    [string]$ExportUpdatesPath,
    [switch]$ExpandCabs
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


$RelativeLogPath = Join-Path -Path $scriptDirectory -ChildPath 'Logs'
$FunctionsPath = Join-Path $scriptDirectory -ChildPath 'Functions'

##*========================================================================
##* Additional Runtime Function - REQUIRED
##*========================================================================
. "$FunctionsPath\Logging.ps1"
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
#Create Paths
If($ExportUpdatesPath){
    $UpdatesPath = $ExportUpdatesPath
}Else{
    $UpdatesPath = Join-Path $scriptDirectory -ChildPath 'Updates'
}

If($ImportFile){
    $Updates = Import-Clixml $ImportFile
}Else{
    Write-LogEntry ("File not specified [{0}]" -f $ImportFile) -Severity 0 -Source $scriptName -Outhost
    Exit
}
<#TEST

$Updates = Import-Clixml "$scriptDirectory\updates.xml"
$Updates = Import-Clixml "$scriptDirectory\InstalledUpdates.xml"
#>
$i=0
#TEST $update = $Updates[0]
foreach ($update in $updates)
{
    $i++
    $ProductType = $update.Type -join '-'
    $productPath = Join-Path $UpdatesPath -ChildPath $ProductType
    New-Item $productPath -ItemType Directory -Force | Out-Null

    $Filename = Split-Path $update.DownloadURL -Leaf
    $Filedestination = Join-path $productPath -ChildPath $Filename

    Show-ProgressStatus -Message ("Downloading [KB{0}] from [{1}]" -f $update.KB,$Update.DownloadURL) -Step $i -MaxStep $Updates.Count
    If(-Not(Test-Path $Filedestination)){
        Write-LogEntry ("Downloading [KB{0}] from [{1}]" -f $update.KB,$Update.DownloadURL) -Source $scriptName -Outhost
        Try{
            Initialize-FileDownload -Name $update.Title -Url $Update.DownloadURL -TargetDest $Filedestination
            Write-LogEntry ("Succesfully downloaded [{0}] to [{1}]" -f $update.Title,$productPath) -Severity 0 -Source $scriptName -Outhost
        }
        Catch{
            Write-LogEntry ("Failed downloading [{0}] to [{1}]: {2}" -f $update.Title,$productPath,$_.Exception.Message) -Severity 3 -Source $scriptName -Outhost
        }
    }Else{
        Write-LogEntry ("File found [{0}]. Ignoring download" -f $Filename) -Severity 0 -Source $scriptName -Outhost
    }
}


If($ExpandCabs){
    $CabUpdates = Get-childitem $UpdatesPath -recurse -Filter *.cab
    $i=0
    #TEST $CabFile = $CabUpdates[0]
    Foreach($CabFile in $CabUpdates)
    {
        $i++
        $ExpandPath = Join-Path (Split-Path $CabFile.FullName -Parent) -ChildPath 'Expanded'
    
        If($CabFile.Extension -eq '.cab')
        {
            Show-ProgressStatus -Message ("Expanding [{0}] to [{1}]" -f $CabFile.Name,$ExpandPath) -Step $i -MaxStep $CabUpdates.Count
            Try{
                Write-LogEntry ("Expanding [{0}] to [{1}]" -f $CabFile.Name,$ExpandPath) -Source $scriptName -Outhost
                Start-Process cmd.exe -ArgumentList "/c C:\Windows\System32\expand.exe -F:* `"$($CabFile.FullName)`" `"$ExpandPath`"" -Wait -WindowStyle Hidden
            }Catch{
                Write-LogEntry ("Failed to expand [{0}] to [{1}]: {2}" -f $CabFile.Name,$ExpandPath,$_.Exception.Message) -Severity 3 -Source $scriptName -Outhost
            }
        }

    }
}
