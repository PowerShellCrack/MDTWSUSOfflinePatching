
#region FUNCTION: Attempt to connect to Task Sequence environment
Function Test-SMSTSENV{
    <#
        .SYNOPSIS
            Tries to establish Microsoft.SMS.TSEnvironment COM Object when running in a Task Sequence

        .REQUIRED
            Allows Set Task Sequence variables to be set

        .PARAMETER ReturnLogPath
            If specified, returns the log path, otherwise returns ts environment
    #>
    param(
        [switch]$ReturnLogPath
    )

    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $MyInvocation.MyCommand

        if ($PSBoundParameters.ContainsKey('Verbose')) {
            $VerbosePreference = $PSCmdlet.SessionState.PSVariable.GetValue('VerbosePreference')
        }
    }
    Process{
        try{
            # Create an object to access the task sequence environment
            $tsenv = New-Object -COMObject Microsoft.SMS.TSEnvironment
            If($DebugPreference){Write-LogEntry ("Task Sequence environment detected!") -Source ${CmdletName} -Severity 5}
        }
        catch{

            If($DebugPreference){Write-LogEntry ("Task Sequence environment NOT detected. Running with script environment variables") -Source ${CmdletName} -Severity 5}
            #set variable to null
            $tsenv = $null
        }
        Finally{
            #set global Logpath
            if ($tsenv){
                #grab the progress UI
                $TSProgressUi = New-Object -ComObject Microsoft.SMS.TSProgressUI

                # Convert all of the variables currently in the environment to PowerShell variables
                #$tsenv.GetVariables() | ForEach-Object { Set-Variable -Name "$_" -Value "$($tsenv.Value($_))" }

                # Query the environment to get an existing variable
                # Set a variable for the task sequence log path

                #Something like: C:\MININT\SMSOSD\OSDLOGS
                #[string]$LogPath = $tsenv.Value("LogPath")
                #Somthing like C:\WINDOWS\CCM\Logs\SMSTSLog
                [string]$LogPath = $tsenv.Value("_SMSTSLogPath")

            }
            Else{
                [string]$LogPath = $env:Temp
                $tsenv = $false
            }
        }
    }
    End{
        If($ReturnLogPath){
            return $LogPath
        }
        Else{
            return $tsenv
        }
    }
  }
  #endregion

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
        [int]$IncrementSteps
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

    }
}

Function Wait-FileUnlock {
    Param(
        [Parameter()]
        [IO.FileInfo]$File,
        [int]$SleepInterval=500
    )
    while(1){
        try{
           $fs=$file.Open('open','read', 'Read')
           $fs.Close()
            Write-Verbose "$file not open"
           return
           }
        catch{
           Start-Sleep -Milliseconds $SleepInterval
           Write-Verbose '-'
        }
	}
}

Function IsFileLocked {
    param(
        [Parameter(Mandatory=$true)]
        [string]$filePath
    )

    Rename-Item $filePath $filePath -ErrorVariable errs -ErrorAction SilentlyContinue
    return ($errs.Count -ne 0)
}

Function Get-FileSize{
    param(
        [Parameter(Mandatory=$true)]
        [string]$filePath
    )

    $result = Get-ChildItem $filePath | Measure-Object length -Sum | % {
        New-Object psobject -prop @{
            Size = $(
                switch ($_.sum) {
                    {$_ -gt 1tb} { '{0:N2}TB' -f ($_ / 1tb); break }
                    {$_ -gt 1gb} { '{0:N2}GB' -f ($_ / 1gb); break }
                    {$_ -gt 1mb} { '{0:N2}MB' -f ($_ / 1mb); break }
                    {$_ -gt 1kb} { '{0:N2}KB' -f ($_ / 1Kb); break }
                    default { '{0}B ' -f $_ }
                }
            )
        }
    }

    $result | Select-Object -ExpandProperty Size
}

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


Function Initialize-FileDownload {
   param(
        [Parameter(Mandatory=$false)]
        [Alias("Title")]
        [string]$Name,

        [Parameter(Mandatory=$true,Position=1)]
        [string]$Url,

        [Parameter(Mandatory=$true,Position=2)]
        [Alias("TargetDest")]
        [string]$TargetFile
    )
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name

        ## Check running account
        [Security.Principal.WindowsIdentity]$CurrentProcessToken = [Security.Principal.WindowsIdentity]::GetCurrent()
        [Security.Principal.SecurityIdentifier]$CurrentProcessSID = $CurrentProcessToken.User
        [boolean]$IsLocalSystemAccount = $CurrentProcessSID.IsWellKnown([Security.Principal.WellKnownSidType]'LocalSystemSid')
        [boolean]$IsLocalServiceAccount = $CurrentProcessSID.IsWellKnown([Security.Principal.WellKnownSidType]'LocalServiceSid')
        [boolean]$IsNetworkServiceAccount = $CurrentProcessSID.IsWellKnown([Security.Principal.WellKnownSidType]'NetworkServiceSid')
        [boolean]$IsServiceAccount = [boolean]($CurrentProcessToken.Groups -contains [Security.Principal.SecurityIdentifier]'S-1-5-6')
        [boolean]$IsProcessUserInteractive = [Environment]::UserInteractive
    }
    Process
    {
        $ChildURLPath = $($url.split('/') | Select-Object -Last 1)

        $uri = New-Object "System.Uri" "$url"
        $request = [System.Net.HttpWebRequest]::Create($uri)
        $request.set_Timeout(15000) #15 second timeout
        $response = $request.GetResponse()
        $totalLength = [System.Math]::Floor($response.get_ContentLength()/1024)
        $responseStream = $response.GetResponseStream()
        $targetStream = New-Object -TypeName System.IO.FileStream -ArgumentList $targetFile, Create

        $buffer = new-object byte[] 10KB
        $count = $responseStream.Read($buffer,0,$buffer.length)
        $downloadedBytes = $count

        If($Name){$Label = $Name}Else{$Label = $ChildURLPath}

        Write-LogEntry ("Initializing File Download from URL: {0}" -f $Url) -Source ${CmdletName} -Severity 1

        while ($count -gt 0)
        {
            $targetStream.Write($buffer, 0, $count)
            $count = $responseStream.Read($buffer,0,$buffer.length)
            $downloadedBytes = $downloadedBytes + $count

            # display progress
            #  Check if script is running with no user session or is not interactive
            If ( ($IsProcessUserInteractive -eq $false) -or $IsLocalSystemAccount -or $IsLocalServiceAccount -or $IsNetworkServiceAccount -or $IsServiceAccount) {
                # display nothing
                write-host "." -NoNewline
            }
            Else{
                Show-ProgressStatus -Message ("Downloading: {0} ($([System.Math]::Floor($downloadedBytes/1024))K of $($totalLength)K): " -f $Label) -Step ([System.Math]::Floor($downloadedBytes/1024)) -MaxStep $totalLength
            }
        }

        Start-Sleep 3

        $targetStream.Flush()
        $targetStream.Close()
        $targetStream.Dispose()
        $responseStream.Dispose()
   }
   End{
        #Write-Progress -activity "Finished downloading file '$($url.split('/') | Select-Object -Last 1)'"
        If($Name){$Label = $Name}Else{$Label = $ChildURLPath}
        Show-ProgressStatus -Message ("Finished downloading file: {0}" -f $Label) -Step $totalLength -MaxStep $totalLength

        #change meta in file from internet to allow to run on system
        If(Test-Path $TargetFile){Unblock-File $TargetFile -ErrorAction SilentlyContinue | Out-Null}
   }

}