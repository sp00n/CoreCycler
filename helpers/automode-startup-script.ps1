<#
.AUTHOR
    sp00n
.LINK
    https://github.com/sp00n/corecycler
.LICENSE
    Creative Commons "CC BY-NC-SA"
    https://creativecommons.org/licenses/by-nc-sa/4.0/
    https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode
.DESCRIPTION
    This is the script that is being called by the Scheduled Task for Automatic Testing
    and tries to resume the testing process
#>
Set-StrictMode -Version 3.0
$Error.Clear()



$logBuffer         = [System.Collections.ArrayList]::new()
$canUseLogFile     = $false
$logFileCoreCycler = $null

$taskName          = 'CoreCycler AutoMode Startup Task'
$taskPath          = '\CoreCycler\'

# This file is in \helpers, our main script is one level above
$scriptRoot        = Split-Path -Path $PSScriptRoot -Parent
$autoModeFile      = $scriptRoot + '\.automode'
$autoModeFileBak   = $scriptRoot + '\.automode-bak'
$maxTimeLimit      = 12 * 60 * 60



<#
.DESCRIPTION
    Write a message to the screen and to the log file
.PARAMETER text
    [String] The text to output
.PARAMETER NoNewline
    [Switch] (optional) If set, will not end the line after the text
.OUTPUTS
    [Void]
#>
function Write-Text {
    param(
        [Parameter(Mandatory=$true)] $text,
        [Parameter(Mandatory=$false)] [Switch] $NoNewline
    )

    $paramsLog = @{
        'string'    = $text
        'NoNewline' = $NoNewline.IsPresent
    }

    $paramsText = @{
        'Object'    = $paramsLog['string']
        'NoNewline' = $paramsLog['NoNewline']
    }

    Write-Host @paramsText
    Write-LogEntry @paramsLog
}



<#
.DESCRIPTION
    Write a string to the log file
.PARAMETER string
    [String] The string to log
.PARAMETER NoNewline
    [Switch] (optional) If set, will no end the line after the text
.OUTPUTS
    [Void]
#>
function Write-LogEntry {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyString()] [String] $string,
        [Parameter(Mandatory=$false)] [Switch] $NoNewline
    )

    # If we cannot use the logfile (yet), store the messages in a buffer
    if (!$canUseLogFile) {
        [Void] $Script:logBuffer.Add($string)
        return
    }

    # The second parameter defines if to append ($true) or overwrite ($false)
    $stream = [System.IO.StreamWriter]::new($logFileCoreCycler, $true, ([System.Text.Utf8Encoding]::new()))

    if ($NoNewline.IsPresent) {
        $stream.Write($string)
    }
    else {
        $stream.WriteLine($string)
    }

    $stream.Close()
}



<#
.DESCRIPTION
    Remove the existing startup script
#>
function Remove-StartupTask {
    Write-Text('Removing the startup task "' + $taskPath + '\' + $taskName + '"')
    Write-Text('')
    Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false -ErrorAction SilentlyContinue
}



<#
.DESCRIPTION
    Exit the script
#>
function Exit-Script {
    Write-Text('')
    Write-Text('The startup script has finished')
    Write-Text('Press any key to close the window...')
    Write-Text('')
    Write-Text('')
    Write-Text('')

    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit
}



<#
.DESCRIPTION
    Wait for a specific time, or contiue with a key press
.PARAMETER timeout
    [Int] How long to wait
.SOURCE
    https://gist.github.com/asheroto/7be9d7c945a09d82bca86df75e9a9d7a
#>
function Wait-ForKeyOrTimeout {
    param (
        [Int] $timeout = 120
    )

    for ($i = $timeout; $i -ge 0; $i--) {
        $message = "`r" + ($i.ToString() + ' seconds... (Press any key to immediately continue)').PadRight(54, ' ')

        # Only log the first entry
        if ($i -eq $timeout) {
            Write-Text($message) -NoNewline
        }
        else {
            Write-Host($message) -NoNewline
        }
        
        
        if ([System.Console]::KeyAvailable) {
            [void][System.Console]::ReadKey($true)
            Write-Text("`r" + ('Key pressed, continuing...')).PadRight(54, ' ')
            return
        }

        Start-Sleep -Seconds 1
    }
    
    Write-Text("`r" + ('0 seconds... (Press any key to immediately continue)').PadRight(54, ' ')) -NoNewline
}



<#
.DESCRIPTION
    This is a custom exception, just to get out of the try {} block without throwing an actual error
#>
class EndTryBlockException: System.Exception {
    EndTryBlockException([string] $x) :
        base('Try-Block Exit Exception. Message: ' + $x) {}
}



<#
.DESCRIPTION
    Another custom exception that does show an error message, but no extended information
#>
class AutoModeResumeFailedException: System.Exception {
    AutoModeResumeFailedException([string] $x) :
        base('Auto Mode resume failed.' + [Environment]::NewLine + $x) {}
}



# The main functionality
try {
    $startDate = Get-Date
    $formatDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $curTimeStamp = Get-Date -UFormat %s -Millisecond 0

    # Limit the maximum time between when the test was started and when the resume script was started
    $limitTimestamp = $curTimeStamp - $maxTimeLimit


    Write-Text('')
    Write-Text('┌────────────────────────────────────────────┐')
    Write-Text('│    CoreCycler Auto Mode Recovery Script    │')
    Write-Text('└────────────────────────────────────────────┘')
    Write-Text('')
    Write-Text($formatDate)
    Write-Text('Recovering from an unexpected exit (crash/reboot)')
    Write-Text('')


    # We need to be admin to use the Auto Test Mode
    $weAreAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (!$weAreAdmin) {
        throw [AutoModeResumeFailedException] 'We don''t have admininstrator privileges, aborting!'
    }



    if (!(Test-Path -LiteralPath $autoModeFile -PathType Leaf) -and !(Test-Path -LiteralPath $autoModeFileBak -PathType Leaf)) {
        Write-Text('The .automode file does not exist!')
        Write-Text('The file is needed to be able to continue the testing process, aborting.')
        Write-Text('(Looking for: ' + $autoModeFile + ')')
        Write-Text('')

        Remove-StartupTask

        throw [EndTryBlockException] 'The .automode file does not exist, aborting!'
    }



    # Try to get the info from the .automode file
    # There are two generations of the file, so if the current one is broken or missing, we can fall back to the previous one
    $autoModeInfoFromJson = $null
    $lastErrorMessage     = 'Could not parse the .automode file!'

    foreach ($thisFilePath in @($autoModeFile, $autoModeFileBak)) {
        if (!(Test-Path -LiteralPath $thisFilePath -PathType Leaf)) {
            continue
        }

        Write-Text('Parsing the .automode file:')
        Write-Text($thisFilePath)
        Write-Text('')

        # Everything that can fail for this generation of the file needs to happen inside this try block,
        # otherwise we would never get to the backup generation
        # This includes reading the file itself (e.g. a sharing violation) and all of the casts of the stored values
        try {
            $autoModeFileContentString = [System.IO.File]::ReadAllText($thisFilePath).Trim()

            $parsedJson = ConvertFrom-Json $autoModeFileContentString

            # We have some required properties
            @('fileTimestamp', 'lastCoreTested', 'logFileCoreCycler', 'logFileStressTest', 'voltageValues') | ForEach-Object {
                if (!($parsedJson -and ($parsedJson | Get-Member $_))) {
                    throw ('The .automode file is missing the entry "' + $_ + '"!')
                }
            }

            # There also needs to be a valid core that was being tested, otherwise we cannot resume anything
            # CoreCycler would treat an invalid core number as a regular new run and start all over again
            if ([Int] $parsedJson.lastCoreTested -lt 0) {
                throw ('The .automode file doesn''t contain a valid tested core ("' + $parsedJson.lastCoreTested + '")!')
            }

            $fileTimestamp     = [UInt64] $parsedJson.fileTimestamp
            $lastCoreTested    = [Int] $parsedJson.lastCoreTested
            $logFileCoreCycler = [String] $parsedJson.logFileCoreCycler
            $logFileStressTest = [String] $parsedJson.logFileStressTest
            $voltageValues     = [Array] $parsedJson.voltageValues
            $waitBeforeResume  = $(if ($parsedJson | Get-Member 'waitBeforeResume') { [Int] $parsedJson.waitBeforeResume } else { 0 })     # Optional

            # Optional entries of the newer file format
            $schemaVersion     = $(if ($parsedJson | Get-Member 'schemaVersion') { [Int] $parsedJson.schemaVersion } else { 1 })
            $storedIteration   = $(if ($parsedJson | Get-Member 'iteration') { [Int] $parsedJson.iteration } else { 0 })
            $remainingCores    = $(if ($parsedJson | Get-Member 'remainingCoreOrder') { @([Array] $parsedJson.remainingCoreOrder) } else { @() })

            $autoModeInfoFromJson = $parsedJson
            break
        }
        catch {
            $lastErrorMessage = $_.Exception.Message
            Write-Text('Could not use this file: ' + $lastErrorMessage)
            Write-Text('')
        }
    }

    if (!$autoModeInfoFromJson) {
        throw [AutoModeResumeFailedException] ('Possible file corruption detected, could not parse the .automode file!' + [Environment]::NewLine + 'Reason: ' + $lastErrorMessage)
    }


    Write-Text('Timestamp:           ' + $fileTimestamp)
    Write-Text('Tested Core:         ' + $lastCoreTested)
    Write-Text('Logfile CoreCycler:  ' + $logFileCoreCycler)
    Write-Text('Logfile Stress Test: ' + $logFileStressTest)
    Write-Text('Voltage Settings:    ' + $voltageValues)
    Write-Text('Wait before resume:  ' + $waitBeforeResume)
    Write-Text('File version:        ' + $schemaVersion)

    if ($schemaVersion -ge 2) {
        Write-Text('Iteration:           ' + $storedIteration)
        Write-Text('Remaining cores:     ' + $(if ($remainingCores.Count -gt 0) { $remainingCores -Join ', ' } else { '(none)' }))
    }

    Write-Text('')


    # Try to use the log file
    if (!(Test-Path -LiteralPath $logFileCoreCycler -PathType Leaf)) {
        Write-Text('The CoreCycler log file doesn''t exist, generating')
        Write-Text('')
        $null = New-Item $logFileCoreCycler -ItemType File -Force
    }


    # The log file exists now, dump all the previous messages to it
    $canUseLogFile = $true

    if ($logBuffer.Count -gt 0) {
        forEach ($logEntry in $logBuffer) {
            Write-LogEntry $logEntry
        }

        $logBuffer = $null
    }


    if ($fileTimestamp -lt $limitTimestamp) {
        $actualTimeDiff = $curTimeStamp - $fileTimestamp
        throw [AutoModeResumeFailedException] ('The resume timestamp is too long ago (too much time has passed: ' + [Math]::Round($actualTimeDiff / 60 / 60, 1) + ' hours, max: ' + [Math]::Round($maxTimeLimit / 60 / 60, 1) + ' hours)')
    }


    # Wait for some time to prevent triggering a "failed" boot
    if (-not [String]::IsNullOrWhiteSpace($waitBeforeResume) -and [Int]$waitBeforeResume -gt 0) {
        Write-Text('Waiting for ' + $waitBeforeResume + ' seconds before resuming the test, to avoid a "failed" boot')

        Wait-ForKeyOrTimeout $waitBeforeResume
        
        Write-Text('')
        Write-Text('')
    }

    Write-Text('Re-starting CoreCycler...')
    Write-Text('')


    # Start the script now
    Write-Text('Command:')
    Write-Text('Start-Process -PassThru -FilePath "' + $env:ComSpec + '" -WorkingDirectory "' + $env:SystemDrive + '" -ArgumentList @(''/C'', "' + $scriptRoot + '\Run CoreCycler.bat", ' + $lastCoreTested + ')')

    # We need to set the working directory if the current path contains wildcard characters
    $process = Start-Process -PassThru -FilePath "$env:ComSpec" -WorkingDirectory "$env:SystemDrive" -ArgumentList @('/C', ('"' + $scriptRoot + '\Run CoreCycler.bat"'), $lastCoreTested)
}

# Don't throw an error
catch [EndTryBlockException] {
}

catch [AutoModeResumeFailedException] {
    Write-Text('')
    Write-Text('ERROR:')
    Write-Text($_.Exception.Message)
}

catch {
    Write-Text('')
    Write-Text('ERROR:')
    Write-Text($_ | Format-List -Force | Out-String)
    Write-Text($_.InvocationInfo | Format-List -Force | Out-String)
}

finally {
    Exit-Script
}
