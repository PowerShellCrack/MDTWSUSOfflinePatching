<#
.SYNOPSIS
    Install Updates from Export

.DESCRIPTION
    Install updates from local storage

.PARAMETER UpdateExportedPath
    Specify path to updates folder
    Defaults to .\Updates

.PARAMETER UpdateFilter
    Can be filtered using certain key words.

.NOTES
    Author		: Dick Tracy II <richard.tracy@microsoft.com>
	Source		: https://github.com/PowerShellCrack/MDTWSUSOfflinePatching
    Version		: 2.0.0
    #Requires -Version 3.0

.EXAMPLE
    .\Install-UpdatesFromWUAExport.ps1 -UpdateFilter Windows

.EXAMPLE
    .\Install-UpdatesFromWUAExport.ps1 -UpdateExportedPath c:\Updates

.EXAMPLE
    .\Install-UpdatesFromWUAExport.ps1 -UpdateExportedPath c:\Updates -UpdateFilter Office

#>

Param(
    #location of updates
    [string]$UpdateExportedPath,
    [validateset('Windows','Office','Office 2016','Office 2013','Office 2019','Office 365')]
    [string]$UpdateFilter
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
#Create Paths
If($UpdateExportedPath){
    $UpdatesPath = $UpdateExportedPath
}Else{
    $UpdatesPath = Join-Path $scriptDirectory -ChildPath 'Updates'
}

$OfficeNames = @('Office 2013','Office 2016','Office 2019','Office 365')
$OfficeNamesRegex = $OfficeNames -join '|'

#grab all possible installer extensions
If(Test-Path $UpdatesPath)
{
    $MsuFiles = Get-ChildItem $UpdatesPath -Filter *.msu -Recurse
    $CabFiles = Get-ChildItem $UpdatesPath -Filter *.cab -Recurse
    $ExeFiles = Get-ChildItem $UpdatesPath -Filter *.exe -Recurse
    $MspFiles = Get-ChildItem $UpdatesPath -Filter *.msp -Recurse
    $MsiFiles = Get-ChildItem $UpdatesPath -Filter *.msi -Recurse
}
Else{
    Write-LogEntry ("Path not found [{0}]" -f $UpdatesPath) -Severity 3 -Source $scriptName -Outhost
    Exit -3
}

#filter cabs based on Type (if specified)
If($UpdateFilter -eq 'Office'){
    $CabFiles = $CabFiles | Where {$_.FullName -match $OfficeNamesRegex}
    $MspFiles = $MspFiles | Where {$_.FullName -match $OfficeNamesRegex}
}

ElseIf($UpdateFilter -in $OfficeNames){
    $CabFiles = $CabFiles | Where {$_.FullName -match $UpdateFilter}
    $MspFiles = $MspFiles | Where {$_.FullName -match $UpdateFilter}
}

ElseIf($UpdateFilter -eq 'Windows'){
    $CabFiles = $CabFiles | Where {$_.FullName -notmatch $OfficeNamesRegex}
    $MspFiles = $MspFiles | Where {$_.FullName -notmatch $OfficeNamesRegex}
}

$i = 0
$MSUFiles | foreach {
    $i++
    If($_.Extension -eq '.msu')
    {
        Show-ProgressStatus -Message ("[{0} of {1}]: Applying update: {2}" -f $i,$MsuFiles.Count,$_.Name) -Step $i -MaxStep $MsuFiles.Count
        Try{
            Write-LogEntry ("Installing [{0}] from [{1}]" -f $_.Name,(Split-Path $_.FullName -Parent)) -Source $scriptName -Outhost
            Start-Process wusa -ArgumentList "`"$($_.FullName)`" /quiet /norestart" -Wait -WindowStyle Hidden
        }
        Catch{
            Write-LogEntry ("Failed to install [{0}] from [{1}]: {2}" -f $_.Name,(Split-Path $_.FullName -Parent),$_.Exception.Message) -Severity 3 -Source $scriptName -Outhost
        }
    }
}


$i = 0
$CabFiles | foreach {
    $i++
    If($_.Extension -eq '.cab')
    {
        Show-ProgressStatus -Message ("[{0} of {1}]: Adding package: {2}" -f $i,$CabFiles.Count,$_.Name) -Step $i -MaxStep $CabFiles.Count
        Try{
            Write-LogEntry ("Installing [{0}] from [{1}]" -f $_.Name,(Split-Path $_.FullName -Parent)) -Source $scriptName -Outhost
            Start-Process dism -ArgumentList "/Online /Add-Package /PackagePath:`"$($_.FullName)`" /NoRestart" -Wait -WindowStyle Hidden
        }
        Catch{
            Write-LogEntry ("Failed to install [{0}] from [{1}]: {2}" -f $_.Name,(Split-Path $_.FullName -Parent),$_.Exception.Message) -Severity 3 -Source $scriptName -Outhost
        }
    }
}


$i = 0
$MspFiles | foreach {
    $i++
    If($_.Extension -eq '.msp')
    {
        Show-ProgressStatus -Message ("[{0} of {1}]: Applying patch: {2}" -f $i,$MspFiles.Count,$_.Name) -Step $i -MaxStep $MspFiles.Count
        Try{
            Write-LogEntry ("Installing [{0}] from [{1}]" -f $_.Name,(Split-Path $_.FullName -Parent)) -Source $scriptName -Outhost
            Start-Process msiexec -ArgumentList "/p `"$($_.FullName)`" REINSTALLMODE=oums REINSTALL=ALL /qn /norestart" -Wait -WindowStyle Hidden
        }
        Catch{
            Write-LogEntry ("Failed to install [{0}] from [{1}]: {2}" -f $_.Name,(Split-Path $_.FullName -Parent),$_.Exception.Message) -Severity 3 -Source $scriptName -Outhost
        }
    }
}


$i = 0
$MsiFiles | foreach {
    $i++
    If($_.Extension -eq '.msi')
    {
        Show-ProgressStatus -Message ("[{0} of {1}]: Installing msi: {2}" -f $i,$MsiFiles.Count,$_.Name) -Step $i -MaxStep $MsiFiles.Count
        Try{
            Write-LogEntry ("Installing [{0}] from [{1}]" -f $_.Name,(Split-Path $_.FullName -Parent)) -Source $scriptName -Outhost
            Start-Process msiexec -ArgumentList "/i `"$($_.FullName)`" /qn /norestart" -Wait -WindowStyle Hidden
        }
        Catch{
            Write-LogEntry ("Failed to install [{0}] from [{1}]: {2}" -f $_.Name,(Split-Path $_.FullName -Parent),$_.Exception.Message) -Severity 3 -Source $scriptName -Outhost
        }
    }
}

$i = 0
$ExeFiles | foreach {
    $i++
    If($_.Extension -eq '.exe')
    {
        Switch -Wildcard ($_.BaseName){
            'silverlight*'{$Argument = '/q /doNotRequireDRMPrompt /noupdate'} #eg. silverlight_x64.exe
            'am-delta*'   {$Argument = 'antimalware /q'} #eg. am_delta_0a521746220017faedf7d6239e5c1bec8df41735.exe
            'vstor*'      {$Argument = '/q /norestart'} #eg. vstor_redist_ddecb05a9db2654ad29577b363f5f8e040f59012.exe
            'vcredist*'   {$Argument = '/q /norestart'} #eg. vcredist_x86.exe
            default       {$Argument = '/quiet /norestart'}
        }

        Show-ProgressStatus -Message ("[{0} of {1}]: Executing: {2}" -f $i,$ExeFiles.Count,$_.Name) -Step $i -MaxStep $ExeFiles.Count
        Try{
            Write-LogEntry ("Installing [{0}] from [{1}]" -f $_.Name,(Split-Path $_.FullName -Parent)) -Source $scriptName -Outhost
            Start-Process cmd -ArgumentList "/c `"$($_.FullName)`" $Argument" -Wait -WindowStyle Hidden
        }
        Catch{
            Write-LogEntry ("Failed to install [{0}] from [{1}]: {2}" -f $_.Name,(Split-Path $_.FullName -Parent),$_.Exception.Message) -Severity 3 -Source $scriptName -Outhost
        }
    }
}