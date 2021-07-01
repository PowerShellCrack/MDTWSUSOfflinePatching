<#
.SYNOPSIS
    Exports Window updates to a XML list

.DESCRIPTION
    Exports Window updates using the Windows Updates Agent to a XML list

.PARAMETER ExportFile
    Specifies the location of XML export file.
    If not specified, it output object in window

.PARAMETER GetAllUpdates
    SWITCH: Grabs all updates no mater if its installed or not
    DEFAULTS to grabbing only what is installed on OS

.PARAMETER OnlyDrivers
    SWITCH: Only pulls updates for drivers

.NOTES
    Author		: Dick Tracy II <richard.tracy@microsoft.com>
	Source		: https://github.com/PowerShellCrack/MDTWSUSOfflinePatching
    Version		: 2.0.0
    #Requires -Version 3.0

.EXAMPLE
    .\Get-UpdatesFromWUALog.ps1 -ExportFile c:\exports\updates.xml

.EXAMPLE
    .\Get-UpdatesFromWUALog.ps1 -GetAllUpdates

.EXAMPLE
    .\Get-UpdatesFromWUALog.ps1 -ExportFile c:\exports\updates.xml -OnlyDrivers

.EXAMPLE
    .\Get-UpdatesFromWUALog.ps1 -ExportFile c:\exports\updates.xml -GetAllUpdates -OnlyDrivers
#>

param(
    [string]$ExportFile,
    [switch]$GetAllUpdates,
    [switch]$OnlyDrivers
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



If($OnlyDrivers){
    $UpdateType = 'Driver'
}Else{
    $UpdateType = 'Software'
}

If($GetAllUpdates){
    [string]$Filter = "IsInstalled = 0 and Type = '$UpdateType'"
}Else{
    [string]$Filter = "IsInstalled = 1 and Type = '$UpdateType'"
}

$Updates = @()

$objSession = New-Object -ComObject "Microsoft.Update.Session"

foreach($update in $objSession.CreateUpdateSearcher().Search($Filter).Updates)
{
    foreach($bundledUpdate in $update.BundledUpdates)
    {
        foreach($content in $bundledUpdate.DownloadContents)
        {
            if ($content.IsDeltaCompressedContent)
            {
                write-verbose "Ignore Delta Compressed Content: $($Update.Title)"
                continue
            }

            if ( $content.DownloadURL.toLower().EndsWith(".exe") )
            {
                write-verbose "Ignore Exe Content: $($Update.Title)"
                #continue
            }

            $obj = [pscustomobject] @{
                ID = $update.Identity.UpdateID
                KB = $update.KBARticleIDs| %{ $_ }
                URL = $update.MoreInfoUrls| %{ $_ }
                Type = $Update.Categories | ?{ $_.Parent.CategoryID -ne "6964aab4-c5b5-43bd-a17d-ffb4346a8e1d" } | %{ $_.Name }
                Title = $update.Title
                Size = $bundledUpdate.MaxDownloadSize
                DownloadURL = $content.DownloadURL
                Auto = $update.autoSelectOnWebSites
            }
            $Updates += $obj
        }
    }
}

If($ExportFile){
    $Updates | Export-Clixml $ExportFile -Force
}