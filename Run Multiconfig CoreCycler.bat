@echo off
SETLOCAL EnableDelayedExpansion


REM -----------------------------------------------------------------------------------------------------
REM With this batch file you can run CoreCycler with multiple different configs in a row,
REM without having to manually edit/replace the config.ini file.
REM
REM Instead if you use this batch file, it looks for config files in the format "multiconfig-x.ini",
REM so e.g. "multiconfig-1.ini", "multiconfig-2.ini" etc, and  will then sequentially run these
REM configs by copying it to the config.ini and starting a CoreCycler run.
REM
REM The batch file will continue to the next config file as long as the current config run ends normally.
REM
REM It will stop under the following circumstances:
REM - it encounters a script error, e.g. something has gone terribly wrong
REM - it terminates with a fatal error
REM - all of the cores have thrown an error during the current config run
REM - the "stopOnError" setting has been enabled in the current config
REM
REM There are a few caveats with this right now:
REM - it will create a new logfile for each config
REM - if you use the Automatic Test Mode, it will not continue with multi config, instead it will just
REM   contine with the currently active config and then stop if it completes
REM -----------------------------------------------------------------------------------------------------


echo [32mษออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออป[0m
echo [32mบ[0m With this batch file you can run CoreCycler with multiple different configs  [32mบ[0m
echo [32mบ[0m in a row, without having to manually edit/replace the config.ini file.       [32mบ[0m
echo [32mบ[0m                                                                              [32mบ[0m
echo [32mบ[0m Instead if you use this batch file, it looks for config files in the format  [32mบ[0m
echo [32mบ[0m [93m"multiconfig-x.ini"[0m, so e.g. [36mmulticonfig-1.ini[0m, [36mmulticonfig-2.ini[0m, etc, and  [32mบ[0m
echo [32mบ[0m will then sequentially run these configs by copying it to the config.ini and [32mบ[0m
echo [32mบ[0m starting a CoreCycler run.                                                   [32mบ[0m
echo [32mบ[0m                                                                              [32mบ[0m
echo [32mบ[0m The batch file will continue to the next config file as long as the current  [32mบ[0m
echo [32mบ[0m config run ends normally.                                                    [32mบ[0m
echo [32mบ[0m                                                                              [32mบ[0m
echo [32mบ[0m It will stop under the following circumstances:                              [32mบ[0m
echo [32mบ[0m - it encounters a script error, e.g. something has gone terribly wrong       [32mบ[0m
echo [32mบ[0m - it terminates with a fatal error                                           [32mบ[0m
echo [32mบ[0m - all of the cores have thrown an error during the current config run        [32mบ[0m
echo [32mบ[0m - the "stopOnError" setting has been enabled in the current config           [32mบ[0m
echo [32mฬออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออน[0m
echo [32mบ[91m There are a few caveats with this right now:                                 [32mบ[0m
echo [32mบ[91m - it will create a new logfile for each config                               [32mบ[0m
echo [32mบ[91m - if you use the Automatic Test Mode, it will not continue with the multi    [32mบ[0m
echo [32mบ[91m   config, instead it will just contine with the currently active config and  [32mบ[0m
echo [32mบ[91m   then stop if it completes                                                  [32mบ[0m
echo [32mศออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออผ[0m
echo.
echo.

echo Starting a multiconfig run of CoreCycler...


REM Prepare the variable for the last config file
SET "LASTCONFIG="
FOR /F %%G IN ('dir /b multiconfig-*.ini') DO SET "LASTCONFIG=%%G"

IF [!LASTCONFIG!] EQU [] (
    echo [91mError^^^! No multiconfig files found, aborting^^^![0m
    pause
    exit 1
)


REM Loop through the config files
FOR /R %%G IN (multiconfig-*.ini) DO (
    SET "CURRENTCONFIG=%%~nxG"

    echo.
    echo [36mออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออ[0m
    echo [36m[!TIME!] Starting run with [93m!CURRENTCONFIG![0m
    echo [36mออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออ[0m
    copy /Y "!CURRENTCONFIG!" config.ini >nul

    IF !ERRORLEVEL! NEQ 0 (
        echo [91mERROR^^^! Could not use "!CURRENTCONFIG!"[0m
        pause
        exit 2
    )

    echo.

    REM Doesn't really work with the Automatic Test Mode yet
    REM start "CoreCycler" cmd.exe /k powershell.exe -ExecutionPolicy Bypass -File "%~dp0script-corecycler.ps1" %PARAMS%

    REM Extra command for the last iteration, to keep the window open
    IF !LASTCONFIG! EQU !CURRENTCONFIG! (
        echo This is the last config
        cmd.exe /k powershell.exe -ExecutionPolicy Bypass -File "%~dp0script-corecycler.ps1"
    ) ELSE (
        powershell.exe -ExecutionPolicy Bypass -File "%~dp0script-corecycler.ps1"
    )


    IF !ERRORLEVEL! NEQ 0 (
        echo [91mError level: !ERRORLEVEL![0m
        echo [91m[!TIME!] ERROR^^^! CoreCycler run did not complete successfully^^^![0m
        pause
        exit !ERRORLEVEL!
    )

    echo.
)

pause