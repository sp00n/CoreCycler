param(
    [switch]$ValidateOnly
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
}
catch {
    Write-Error 'Windows Forms is not available on this system. This editor requires a Windows desktop session.'
    exit 1
}

$rootPath = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($rootPath)) {
    $entryAssembly = [System.Reflection.Assembly]::GetEntryAssembly()
    if ($null -ne $entryAssembly -and -not [string]::IsNullOrWhiteSpace($entryAssembly.Location)) {
        $rootPath = Split-Path -Path $entryAssembly.Location -Parent
    }
}
if ([string]::IsNullOrWhiteSpace($rootPath)) {
    $rootPath = [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}
if ([string]::IsNullOrWhiteSpace($rootPath)) {
    $rootPath = (Get-Location).Path
}
$rootPath = [System.IO.Path]::GetFullPath($rootPath)

$configFile = Join-Path $rootPath 'config.ini'
$defaultConfigFile = Join-Path $rootPath 'configs/default.config.ini'

if (-not (Test-Path $configFile)) {
    if (Test-Path $defaultConfigFile) {
        Copy-Item $defaultConfigFile $configFile -Force
    }
    else {
        @(
            '# Config file for CoreCycler',
            '[General]',
            'stressTestProgram = PRIME95',
            'runtimePerCore = 6m'
        ) | Set-Content -Path $configFile -Encoding utf8
    }
}

function Read-IniFile {
    param([string]$Path)

    $result = [ordered]@{}
    $currentSection = $null

    if (-not (Test-Path $Path)) {
        return $result
    }

    foreach ($line in Get-Content -Path $Path) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        if ($trimmed.StartsWith('#') -or $trimmed.StartsWith(';')) { continue }

        if ($trimmed -match '^\[(.+)\]\s*$') {
            $sectionName = $matches[1].Trim()
            if (-not $result.Contains($sectionName)) {
                $result[$sectionName] = [ordered]@{}
            }
            $currentSection = $sectionName
            continue
        }

        if ($trimmed -match '^([^=]+?)\s*=(.*)$') {
            $name = $matches[1].Trim()
            $value = $matches[2].Trim()
            # Skip any key-value pairs that appear before the first section
            # This prevents creating invalid 'Global' sections
            if ($null -eq $currentSection) {
                continue
            }
            $result[$currentSection][$name] = $value
        }
    }

    return $result
}

function Write-IniFile {
    param(
        [string]$Path,
        [hashtable]$Sections
    )

    # Read the original file to preserve comments and structure
    $originalLines = @()
    if (Test-Path $Path) {
        $originalLines = [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)
    }

    $newLines = New-Object System.Collections.Generic.List[string]
    $currentSection = $null
    $sectionsToWrite = @{}

    # First, copy all original lines, updating values as needed
    foreach ($line in $originalLines) {
        # Check if this is a section header
        if ($line -match '^\[(.+)\]\s*$') {
            $sectionName = $matches[1].Trim()
            $currentSection = $sectionName
            $newLines.Add($line)
        }
        # Check if this is a key=value line
        elseif ($line -match '^([^=]+?)\s*=') {
            $keyName = $matches[1].Trim()
            
            # If we have an updated value for this key in this section, use it
            if ($null -ne $currentSection -and $Sections.Contains($currentSection) -and $Sections[$currentSection].Contains($keyName)) {
                $newValue = $Sections[$currentSection][$keyName]
                if ($null -eq $newValue) {
                    $newLines.Add("$keyName = ")
                } else {
                    $newLines.Add("$keyName = $newValue")
                }
                # Mark this section/key as written
                if (-not $sectionsToWrite.Contains($currentSection)) {
                    $sectionsToWrite[$currentSection] = @{}
                }
                $sectionsToWrite[$currentSection][$keyName] = $true
            }
            else {
                # Keep the original line as-is (preserves comments and formatting)
                $newLines.Add($line)
            }
        }
        else {
            # Comments and empty lines - preserve as-is
            $newLines.Add($line)
        }
    }

    # Add any new sections or keys that weren't in the original file
    foreach ($sectionName in $Sections.Keys) {
        # Check if this section was already processed from the original file
        if (-not $sectionsToWrite.Contains($sectionName)) {
            $newLines.Add('')
            $newLines.Add("[$sectionName]")
            $sectionValues = $Sections[$sectionName]
            foreach ($keyName in $sectionValues.Keys) {
                $value = $sectionValues[$keyName]
                if ($null -eq $value) {
                    $newLines.Add("$keyName = ")
                } else {
                    $newLines.Add("$keyName = $value")
                }
            }
        }
        else {
            # Add any new keys to an existing section
            $sectionValues = $Sections[$sectionName]
            foreach ($keyName in $sectionValues.Keys) {
                if (-not $sectionsToWrite[$sectionName].Contains($keyName)) {
                    $value = $sectionValues[$keyName]
                    if ($null -eq $value) {
                        $newLines.Add("$keyName = ")
                    } else {
                        $newLines.Add("$keyName = $value")
                    }
                }
            }
        }
    }

    # Use the same method as CoreCycler does to write the file
    [System.IO.File]::WriteAllLines($Path, $newLines.ToArray(), [System.Text.Encoding]::UTF8)
}

function Get-SettingValue {
    param(
        [hashtable]$Sections,
        [string]$Section,
        [string]$Key,
        [string]$DefaultValue = ''
    )

    if (-not $Sections.Contains($Section)) { return $DefaultValue }
    if (-not $Sections[$Section].Contains($Key)) { return $DefaultValue }
    return [string]$Sections[$Section][$Key]
}

function Set-SettingValue {
    param(
        [hashtable]$Sections,
        [string]$Section,
        [string]$Key,
        [string]$Value
    )

    if (-not $Sections.Contains($Section)) { $Sections[$Section] = [ordered]@{} }
    $Sections[$Section][$Key] = $Value
}

function Set-BoolControl {
    param([System.Windows.Forms.CheckBox]$Control, [string]$Value)
    $Control.Checked = ($Value -match '^(1|true|yes|on)$')
}

function Get-BoolValue {
    param([System.Windows.Forms.CheckBox]$Control)
    if ($Control.Checked) { return '1' }
    return '0'
}

function Add-SettingRow {
    param(
        [System.Windows.Forms.TableLayoutPanel]$Panel,
        [string]$LabelText,
        [System.Windows.Forms.Control]$Control,
        [int]$RowIndex
    )

    $label = [System.Windows.Forms.Label]::new()
    $label.Text = $LabelText
    $label.AutoSize = $true
    $label.Margin = [System.Windows.Forms.Padding]::new(0, 6, 8, 6)
    $label.Anchor = [System.Windows.Forms.AnchorStyles]::Left
    $label.ForeColor = [System.Drawing.Color]::FromArgb(50, 60, 80)

    $Panel.Controls.Add($label, 0, $RowIndex)
    $Panel.Controls.Add($Control, 1, $RowIndex)
}

function Set-ComboBoxValue {
    param(
        [System.Windows.Forms.ComboBox]$Control,
        [string]$Value,
        [string]$DefaultValue = ''
    )

    $resolvedValue = if ([string]::IsNullOrWhiteSpace($Value)) { $DefaultValue } else { $Value }
    if ($null -ne $resolvedValue -and $Control.Items.Contains($resolvedValue)) {
        $Control.SelectedItem = $resolvedValue
    }
    elseif ($Control.Items.Count -gt 0) {
        $Control.SelectedIndex = 0
    }
}

$sections = Read-IniFile -Path $configFile

if ($ValidateOnly) {
    Write-Host "Validated config file: $configFile"
    Write-Host "Loaded sections: $($sections.Keys -join ', ')"
    exit 0
}

$form = [System.Windows.Forms.Form]::new()
$form.Text = 'CoreCycler Config Editor'
$form.Size = [System.Drawing.Size]::new(1030, 900)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
$form.MaximizeBox = $true
$form.MinimizeBox = $true
$form.AutoScroll = $true
$form.MinimumSize = [System.Drawing.Size]::new(980, 780)

$iconPath = Join-Path $rootPath 'CoreCycler.ico'
if (Test-Path $iconPath) {
    try {
        $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath)
    }
    catch {
        # Ignore icon load failures and fall back to the default form icon
    }
}

$controls = [ordered]@{}

$form = [System.Windows.Forms.Form]::new()
$form.Text = 'CoreCycler Config Editor'
$form.Size = [System.Drawing.Size]::new(1180, 950)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
$form.MaximizeBox = $true
$form.MinimizeBox = $true
$form.AutoScroll = $true
$form.MinimumSize = [System.Drawing.Size]::new(1080, 780)
$form.Font = [System.Drawing.Font]::new('Segoe UI', 10)
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)

$iconPath = Join-Path $rootPath 'CoreCycler.ico'
if (Test-Path $iconPath) {
    try {
        $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath)
    }
    catch {
    }
}

$mainLayout = [System.Windows.Forms.TableLayoutPanel]::new()
$mainLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
$mainLayout.ColumnCount = 1
$mainLayout.RowCount = 3
$mainLayout.Padding = [System.Windows.Forms.Padding]::new(16)
$mainLayout.AutoScroll = $true
$mainLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize)) | Out-Null
$mainLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Percent, 100)) | Out-Null
$mainLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize)) | Out-Null
$form.Controls.Add($mainLayout)

$headerPanel = [System.Windows.Forms.Panel]::new()
$headerPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$headerPanel.Height = 90
$headerPanel.Padding = [System.Windows.Forms.Padding]::new(18, 14, 18, 14)
$headerPanel.BackColor = [System.Drawing.Color]::FromArgb(34, 62, 110)
$mainLayout.Controls.Add($headerPanel, 0, 0)

$headerTitle = [System.Windows.Forms.Label]::new()
$headerTitle.Text = 'CoreCycler Configuration'
$headerTitle.AutoSize = $true
$headerTitle.ForeColor = [System.Drawing.Color]::White
$headerTitle.Font = [System.Drawing.Font]::new('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$headerTitle.Location = [System.Drawing.Point]::new(0, 0)
$headerPanel.Controls.Add($headerTitle)

$headerSubtitle = [System.Windows.Forms.Label]::new()
$headerSubtitle.Text = 'Organize settings by task, then save them back to config.ini.'
$headerSubtitle.AutoSize = $true
$headerSubtitle.ForeColor = [System.Drawing.Color]::FromArgb(226, 234, 246)
$headerSubtitle.Font = [System.Drawing.Font]::new('Segoe UI', 10)
$headerSubtitle.Location = [System.Drawing.Point]::new(0, 34)
$headerPanel.Controls.Add($headerSubtitle)

$tabControl = [System.Windows.Forms.TabControl]::new()
$tabControl.Dock = [System.Windows.Forms.DockStyle]::Fill
$tabControl.Padding = [System.Drawing.Point]::new(8, 6)
$tabControl.Font = [System.Drawing.Font]::new('Segoe UI', 10)
$mainLayout.Controls.Add($tabControl, 0, 1)

$generalPage = [System.Windows.Forms.TabPage]::new(); $generalPage.Text = 'General'
$generalPage.Padding = [System.Windows.Forms.Padding]::new(12)
$tabControl.TabPages.Add($generalPage)

$generalPanel = [System.Windows.Forms.Panel]::new(); $generalPanel.Dock = [System.Windows.Forms.DockStyle]::Fill; $generalPanel.AutoScroll = $true
$generalPage.Controls.Add($generalPanel)

$generalLayout = [System.Windows.Forms.TableLayoutPanel]::new(); $generalLayout.Dock = [System.Windows.Forms.DockStyle]::Fill; $generalLayout.AutoSize = $true; $generalLayout.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; $generalLayout.ColumnCount = 1; $generalLayout.Padding = [System.Windows.Forms.Padding]::new(0, 0, 0, 6)
$generalPanel.Controls.Add($generalLayout)

$generalGroup = [System.Windows.Forms.GroupBox]::new(); $generalGroup.Text = 'Core behavior'; $generalGroup.AutoSize = $true; $generalGroup.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; $generalGroup.Margin = [System.Windows.Forms.Padding]::new(0, 0, 0, 12); $generalGroup.Padding = [System.Windows.Forms.Padding]::new(10)
$generalLayout.Controls.Add($generalGroup)
$generalInner = [System.Windows.Forms.TableLayoutPanel]::new(); $generalInner.AutoSize = $true; $generalInner.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; $generalInner.ColumnCount = 2; $generalInner.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::AutoSize)) | Out-Null; $generalInner.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100)) | Out-Null
$generalGroup.Controls.Add($generalInner)

$controls.useConfigFile = [System.Windows.Forms.TextBox]::new(); $controls.useConfigFile.Width = 440; $controls.useConfigFile.Text = (Get-SettingValue -Sections $sections -Section 'General' -Key 'useConfigFile' -DefaultValue '')
Add-SettingRow -Panel $generalInner -LabelText 'Use config file' -Control $controls.useConfigFile -RowIndex 0
$controls.stressTestProgram = [System.Windows.Forms.ComboBox]::new(); $controls.stressTestProgram.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList; $controls.stressTestProgram.Items.AddRange(([string[]]@('PRIME95','AIDA64','YCRUNCHER','YCRUNCHER_OLD','LINPACK'))); $controls.stressTestProgram.Width = 180
Set-ComboBoxValue -Control $controls.stressTestProgram -Value (Get-SettingValue -Sections $sections -Section 'General' -Key 'stressTestProgram' -DefaultValue 'PRIME95') -DefaultValue 'PRIME95'
Add-SettingRow -Panel $generalInner -LabelText 'Stress test program' -Control $controls.stressTestProgram -RowIndex 1
$controls.runtimePerCore = [System.Windows.Forms.TextBox]::new(); $controls.runtimePerCore.Width = 180; $controls.runtimePerCore.Text = (Get-SettingValue -Sections $sections -Section 'General' -Key 'runtimePerCore' -DefaultValue '6m')
Add-SettingRow -Panel $generalInner -LabelText 'Runtime per core' -Control $controls.runtimePerCore -RowIndex 2
$controls.suspendPeriodically = [System.Windows.Forms.CheckBox]::new(); $controls.suspendPeriodically.Text = ''; Set-BoolControl -Control $controls.suspendPeriodically -Value (Get-SettingValue -Sections $sections -Section 'General' -Key 'suspendPeriodically' -DefaultValue '1')
Add-SettingRow -Panel $generalInner -LabelText 'Suspend periodically' -Control $controls.suspendPeriodically -RowIndex 3
$controls.coreTestOrder = [System.Windows.Forms.ComboBox]::new(); $controls.coreTestOrder.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList; $controls.coreTestOrder.Items.AddRange(([string[]]@('Default','Alternate','CorePairs','Random','Sequential'))); $controls.coreTestOrder.Width = 180
Set-ComboBoxValue -Control $controls.coreTestOrder -Value (Get-SettingValue -Sections $sections -Section 'General' -Key 'coreTestOrder' -DefaultValue 'Default') -DefaultValue 'Default'
Add-SettingRow -Panel $generalInner -LabelText 'Core test order' -Control $controls.coreTestOrder -RowIndex 4
$controls.numberOfThreads = [System.Windows.Forms.ComboBox]::new(); $controls.numberOfThreads.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList; $controls.numberOfThreads.Items.AddRange(([string[]]@('1','2'))); $controls.numberOfThreads.Width = 80
Set-ComboBoxValue -Control $controls.numberOfThreads -Value (Get-SettingValue -Sections $sections -Section 'General' -Key 'numberOfThreads' -DefaultValue '1') -DefaultValue '1'
Add-SettingRow -Panel $generalInner -LabelText 'Threads' -Control $controls.numberOfThreads -RowIndex 5
$controls.assignBothVirtualCores = [System.Windows.Forms.CheckBox]::new(); $controls.assignBothVirtualCores.Text = ''; Set-BoolControl -Control $controls.assignBothVirtualCores -Value (Get-SettingValue -Sections $sections -Section 'General' -Key 'assignBothVirtualCoresForSingleThread' -DefaultValue '0')
Add-SettingRow -Panel $generalInner -LabelText 'Assign both virtual cores' -Control $controls.assignBothVirtualCores -RowIndex 6
$controls.maxIterations = [System.Windows.Forms.TextBox]::new(); $controls.maxIterations.Width = 120; $controls.maxIterations.Text = (Get-SettingValue -Sections $sections -Section 'General' -Key 'maxIterations' -DefaultValue '10000')
Add-SettingRow -Panel $generalInner -LabelText 'Max iterations' -Control $controls.maxIterations -RowIndex 7
$controls.coresToIgnore = [System.Windows.Forms.TextBox]::new(); $controls.coresToIgnore.Width = 220; $controls.coresToIgnore.Text = (Get-SettingValue -Sections $sections -Section 'General' -Key 'coresToIgnore' -DefaultValue '')
Add-SettingRow -Panel $generalInner -LabelText 'Cores to ignore' -Control $controls.coresToIgnore -RowIndex 8
$controls.restartTestProgramForEachCore = [System.Windows.Forms.CheckBox]::new(); $controls.restartTestProgramForEachCore.Text = ''; Set-BoolControl -Control $controls.restartTestProgramForEachCore -Value (Get-SettingValue -Sections $sections -Section 'General' -Key 'restartTestProgramForEachCore' -DefaultValue '0')
Add-SettingRow -Panel $generalInner -LabelText 'Restart for each core' -Control $controls.restartTestProgramForEachCore -RowIndex 9
$controls.delayBetweenCores = [System.Windows.Forms.TextBox]::new(); $controls.delayBetweenCores.Width = 120; $controls.delayBetweenCores.Text = (Get-SettingValue -Sections $sections -Section 'General' -Key 'delayBetweenCores' -DefaultValue '15')
Add-SettingRow -Panel $generalInner -LabelText 'Delay between cores' -Control $controls.delayBetweenCores -RowIndex 10

$generalNotifications = [System.Windows.Forms.GroupBox]::new(); $generalNotifications.Text = 'Error handling & notifications'; $generalNotifications.AutoSize = $true; $generalNotifications.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; $generalNotifications.Padding = [System.Windows.Forms.Padding]::new(10); $generalNotifications.Margin = [System.Windows.Forms.Padding]::new(0, 0, 0, 12)
$generalLayout.Controls.Add($generalNotifications)
$generalNotifyInner = [System.Windows.Forms.TableLayoutPanel]::new(); $generalNotifyInner.AutoSize = $true; $generalNotifyInner.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; $generalNotifyInner.ColumnCount = 2; $generalNotifyInner.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::AutoSize)) | Out-Null; $generalNotifyInner.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100)) | Out-Null
$generalNotifications.Controls.Add($generalNotifyInner)
$controls.skipCoreOnError = [System.Windows.Forms.CheckBox]::new(); $controls.skipCoreOnError.Text = ''; Set-BoolControl -Control $controls.skipCoreOnError -Value (Get-SettingValue -Sections $sections -Section 'General' -Key 'skipCoreOnError' -DefaultValue '1')
Add-SettingRow -Panel $generalNotifyInner -LabelText 'Skip core on error' -Control $controls.skipCoreOnError -RowIndex 0
$controls.stopOnError = [System.Windows.Forms.CheckBox]::new(); $controls.stopOnError.Text = ''; Set-BoolControl -Control $controls.stopOnError -Value (Get-SettingValue -Sections $sections -Section 'General' -Key 'stopOnError' -DefaultValue '0')
Add-SettingRow -Panel $generalNotifyInner -LabelText 'Stop on error' -Control $controls.stopOnError -RowIndex 1
$controls.beepOnError = [System.Windows.Forms.CheckBox]::new(); $controls.beepOnError.Text = ''; Set-BoolControl -Control $controls.beepOnError -Value (Get-SettingValue -Sections $sections -Section 'General' -Key 'beepOnError' -DefaultValue '1')
Add-SettingRow -Panel $generalNotifyInner -LabelText 'Beep on error' -Control $controls.beepOnError -RowIndex 2
$controls.flashOnError = [System.Windows.Forms.CheckBox]::new(); $controls.flashOnError.Text = ''; Set-BoolControl -Control $controls.flashOnError -Value (Get-SettingValue -Sections $sections -Section 'General' -Key 'flashOnError' -DefaultValue '1')
Add-SettingRow -Panel $generalNotifyInner -LabelText 'Flash on error' -Control $controls.flashOnError -RowIndex 3
$controls.lookForWheaErrors = [System.Windows.Forms.CheckBox]::new(); $controls.lookForWheaErrors.Text = ''; Set-BoolControl -Control $controls.lookForWheaErrors -Value (Get-SettingValue -Sections $sections -Section 'General' -Key 'lookForWheaErrors' -DefaultValue '1')
Add-SettingRow -Panel $generalNotifyInner -LabelText 'Check WHEA errors' -Control $controls.lookForWheaErrors -RowIndex 4
$controls.treatWheaWarningAsError = [System.Windows.Forms.CheckBox]::new(); $controls.treatWheaWarningAsError.Text = ''; Set-BoolControl -Control $controls.treatWheaWarningAsError -Value (Get-SettingValue -Sections $sections -Section 'General' -Key 'treatWheaWarningAsError' -DefaultValue '1')
Add-SettingRow -Panel $generalNotifyInner -LabelText 'Treat WHEA warning as error' -Control $controls.treatWheaWarningAsError -RowIndex 5

$stressPage = [System.Windows.Forms.TabPage]::new(); $stressPage.Text = 'Stress Programs'
$stressPage.Padding = [System.Windows.Forms.Padding]::new(12)
$tabControl.TabPages.Add($stressPage)

$stressPanel = [System.Windows.Forms.Panel]::new(); $stressPanel.Dock = [System.Windows.Forms.DockStyle]::Fill; $stressPanel.AutoScroll = $true
$stressPage.Controls.Add($stressPanel)

$stressLayout = [System.Windows.Forms.TableLayoutPanel]::new(); $stressLayout.Dock = [System.Windows.Forms.DockStyle]::Fill; $stressLayout.AutoSize = $true; $stressLayout.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; $stressLayout.ColumnCount = 1; $stressLayout.Padding = [System.Windows.Forms.Padding]::new(0, 0, 0, 6)
$stressPanel.Controls.Add($stressLayout)

$primeGroup = [System.Windows.Forms.GroupBox]::new(); $primeGroup.Text = 'Prime95'; $primeGroup.AutoSize = $true; $primeGroup.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; $primeGroup.Padding = [System.Windows.Forms.Padding]::new(10); $primeGroup.Margin = [System.Windows.Forms.Padding]::new(0, 0, 0, 12)
$stressLayout.Controls.Add($primeGroup)
$primeInner = [System.Windows.Forms.TableLayoutPanel]::new(); $primeInner.AutoSize = $true; $primeInner.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; $primeInner.ColumnCount = 2; $primeInner.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::AutoSize)) | Out-Null; $primeInner.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100)) | Out-Null
$primeGroup.Controls.Add($primeInner)
$controls.prime95Mode = [System.Windows.Forms.ComboBox]::new(); $controls.prime95Mode.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList; $controls.prime95Mode.Items.AddRange(([string[]]@('SSE','AVX','AVX2','AVX512','CUSTOM'))); $controls.prime95Mode.Width = 140
Set-ComboBoxValue -Control $controls.prime95Mode -Value (Get-SettingValue -Sections $sections -Section 'Prime95' -Key 'mode' -DefaultValue 'SSE') -DefaultValue 'SSE'
Add-SettingRow -Panel $primeInner -LabelText 'Mode' -Control $controls.prime95Mode -RowIndex 0
$controls.prime95FftSize = [System.Windows.Forms.ComboBox]::new(); $controls.prime95FftSize.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList; $controls.prime95FftSize.Items.AddRange(([string[]]@('Smallest','Small','Large','Huge','All','Moderate','Heavy','HeavyShort'))); $controls.prime95FftSize.Width = 140
Set-ComboBoxValue -Control $controls.prime95FftSize -Value (Get-SettingValue -Sections $sections -Section 'Prime95' -Key 'FFTSize' -DefaultValue 'Huge') -DefaultValue 'Huge'
Add-SettingRow -Panel $primeInner -LabelText 'FFT preset' -Control $controls.prime95FftSize -RowIndex 1

$yCruncherGroup = [System.Windows.Forms.GroupBox]::new(); $yCruncherGroup.Text = 'y-cruncher'; $yCruncherGroup.AutoSize = $true; $yCruncherGroup.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; $yCruncherGroup.Padding = [System.Windows.Forms.Padding]::new(10); $yCruncherGroup.Margin = [System.Windows.Forms.Padding]::new(0, 0, 0, 12)
$stressLayout.Controls.Add($yCruncherGroup)
$yCruncherInner = [System.Windows.Forms.TableLayoutPanel]::new(); $yCruncherInner.AutoSize = $true; $yCruncherInner.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; $yCruncherInner.ColumnCount = 2; $yCruncherInner.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::AutoSize)) | Out-Null; $yCruncherInner.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100)) | Out-Null
$yCruncherGroup.Controls.Add($yCruncherInner)
$controls.yCruncherMode = [System.Windows.Forms.ComboBox]::new(); $controls.yCruncherMode.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList; $controls.yCruncherMode.Items.AddRange(([string[]]@('00-x86','04-P4P','05-A64 ~ Kasumi','08-NHM ~ Ushio','11-SNB ~ Hina','12-BD2 ~ Miyu','13-HSW ~ Airi','14-BDW ~ Kurumi','17-SKX ~ Kotori','17-ZN1 ~ Yukina','18-CNL ~ Shinoa','19-ZN2 ~ Kagari','22-ZN4 ~ Kizuna','24-ZN5 ~ Komari'))); $controls.yCruncherMode.Width = 140
Set-ComboBoxValue -Control $controls.yCruncherMode -Value (Get-SettingValue -Sections $sections -Section 'yCruncher' -Key 'mode' -DefaultValue '00-x86') -DefaultValue '00-x86'
Add-SettingRow -Panel $yCruncherInner -LabelText 'Mode' -Control $controls.yCruncherMode -RowIndex 0
$controls.yCruncherTests = [System.Windows.Forms.TextBox]::new(); $controls.yCruncherTests.Width = 420; $controls.yCruncherTests.Text = (Get-SettingValue -Sections $sections -Section 'yCruncher' -Key 'tests' -DefaultValue 'BKT, BBP, SFTv4, SNT, SVT, FFTv4, N63, VT3')
Add-SettingRow -Panel $yCruncherInner -LabelText 'Tests' -Control $controls.yCruncherTests -RowIndex 1
$controls.yCruncherTestDuration = [System.Windows.Forms.TextBox]::new(); $controls.yCruncherTestDuration.Width = 140; $controls.yCruncherTestDuration.Text = (Get-SettingValue -Sections $sections -Section 'yCruncher' -Key 'testDuration' -DefaultValue '60')
Add-SettingRow -Panel $yCruncherInner -LabelText 'Test duration' -Control $controls.yCruncherTestDuration -RowIndex 2
$controls.yCruncherMemory = [System.Windows.Forms.TextBox]::new(); $controls.yCruncherMemory.Width = 220; $controls.yCruncherMemory.Text = (Get-SettingValue -Sections $sections -Section 'yCruncher' -Key 'memory' -DefaultValue 'Default')
Add-SettingRow -Panel $yCruncherInner -LabelText 'Memory' -Control $controls.yCruncherMemory -RowIndex 3
$controls.enableYCruncherLoggingWrapper = [System.Windows.Forms.CheckBox]::new(); $controls.enableYCruncherLoggingWrapper.Text = ''; Set-BoolControl -Control $controls.enableYCruncherLoggingWrapper -Value (Get-SettingValue -Sections $sections -Section 'yCruncher' -Key 'enableYCruncherLoggingWrapper' -DefaultValue '1')
Add-SettingRow -Panel $yCruncherInner -LabelText 'Enable logging wrapper' -Control $controls.enableYCruncherLoggingWrapper -RowIndex 4

$aida64Group = [System.Windows.Forms.GroupBox]::new(); $aida64Group.Text = 'Aida64'; $aida64Group.AutoSize = $true; $aida64Group.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; $aida64Group.Padding = [System.Windows.Forms.Padding]::new(10); $aida64Group.Margin = [System.Windows.Forms.Padding]::new(0, 0, 0, 12)
$stressLayout.Controls.Add($aida64Group)
$aida64Inner = [System.Windows.Forms.TableLayoutPanel]::new(); $aida64Inner.AutoSize = $true; $aida64Inner.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; $aida64Inner.ColumnCount = 2; $aida64Inner.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::AutoSize)) | Out-Null; $aida64Inner.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100)) | Out-Null
$aida64Group.Controls.Add($aida64Inner)
$controls.aida64Mode = [System.Windows.Forms.ComboBox]::new(); $controls.aida64Mode.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList; $controls.aida64Mode.Items.AddRange(([string[]]@('CACHE','FPU','MEMORY','CUSTOM'))); $controls.aida64Mode.Width = 140
Set-ComboBoxValue -Control $controls.aida64Mode -Value (Get-SettingValue -Sections $sections -Section 'Aida64' -Key 'mode' -DefaultValue 'CACHE') -DefaultValue 'CACHE'
Add-SettingRow -Panel $aida64Inner -LabelText 'Mode' -Control $controls.aida64Mode -RowIndex 0
$controls.aida64UseAvx = [System.Windows.Forms.CheckBox]::new(); $controls.aida64UseAvx.Text = ''; Set-BoolControl -Control $controls.aida64UseAvx -Value (Get-SettingValue -Sections $sections -Section 'Aida64' -Key 'useAVX' -DefaultValue '0')
Add-SettingRow -Panel $aida64Inner -LabelText 'Use AVX' -Control $controls.aida64UseAvx -RowIndex 1
$controls.aida64MaxMemory = [System.Windows.Forms.TextBox]::new(); $controls.aida64MaxMemory.Width = 140; $controls.aida64MaxMemory.Text = (Get-SettingValue -Sections $sections -Section 'Aida64' -Key 'maxMemory' -DefaultValue '90')
Add-SettingRow -Panel $aida64Inner -LabelText 'Max memory (%)' -Control $controls.aida64MaxMemory -RowIndex 2

$linpackGroup = [System.Windows.Forms.GroupBox]::new(); $linpackGroup.Text = 'Linpack'; $linpackGroup.AutoSize = $true; $linpackGroup.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; $linpackGroup.Padding = [System.Windows.Forms.Padding]::new(10)
$stressLayout.Controls.Add($linpackGroup)
$linpackInner = [System.Windows.Forms.TableLayoutPanel]::new(); $linpackInner.AutoSize = $true; $linpackInner.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; $linpackInner.ColumnCount = 2; $linpackInner.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::AutoSize)) | Out-Null; $linpackInner.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100)) | Out-Null
$linpackGroup.Controls.Add($linpackInner)
$controls.linpackVersion = [System.Windows.Forms.ComboBox]::new(); $controls.linpackVersion.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList; $controls.linpackVersion.Items.AddRange(([string[]]@('2018','2019','2021','2024'))); $controls.linpackVersion.Width = 120
Set-ComboBoxValue -Control $controls.linpackVersion -Value (Get-SettingValue -Sections $sections -Section 'Linpack' -Key 'version' -DefaultValue '2018') -DefaultValue '2018'
Add-SettingRow -Panel $linpackInner -LabelText 'Version' -Control $controls.linpackVersion -RowIndex 0
$controls.linpackMode = [System.Windows.Forms.ComboBox]::new(); $controls.linpackMode.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList; $controls.linpackMode.Items.AddRange(([string[]]@('LOW','MEDIUM','HIGH'))); $controls.linpackMode.Width = 140
Set-ComboBoxValue -Control $controls.linpackMode -Value (Get-SettingValue -Sections $sections -Section 'Linpack' -Key 'mode' -DefaultValue 'MEDIUM') -DefaultValue 'MEDIUM'
Add-SettingRow -Panel $linpackInner -LabelText 'Mode' -Control $controls.linpackMode -RowIndex 1
$controls.linpackMemory = [System.Windows.Forms.TextBox]::new(); $controls.linpackMemory.Width = 140; $controls.linpackMemory.Text = (Get-SettingValue -Sections $sections -Section 'Linpack' -Key 'memory' -DefaultValue '2GB')
Add-SettingRow -Panel $linpackInner -LabelText 'Memory' -Control $controls.linpackMemory -RowIndex 2

$automationPage = [System.Windows.Forms.TabPage]::new(); $automationPage.Text = 'Automation & Recovery'
$automationPage.Padding = [System.Windows.Forms.Padding]::new(12)
$tabControl.TabPages.Add($automationPage)

$automationPanel = [System.Windows.Forms.Panel]::new(); $automationPanel.Dock = [System.Windows.Forms.DockStyle]::Fill; $automationPanel.AutoScroll = $true
$automationPage.Controls.Add($automationPanel)

$automationLayout = [System.Windows.Forms.TableLayoutPanel]::new(); $automationLayout.Dock = [System.Windows.Forms.DockStyle]::Fill; $automationLayout.AutoSize = $true; $automationLayout.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; $automationLayout.ColumnCount = 1; $automationLayout.Padding = [System.Windows.Forms.Padding]::new(0, 0, 0, 6)
$automationPanel.Controls.Add($automationLayout)

$automaticModeGroup = [System.Windows.Forms.GroupBox]::new(); $automaticModeGroup.Text = 'Automatic test mode'; $automaticModeGroup.AutoSize = $true; $automaticModeGroup.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; $automaticModeGroup.Padding = [System.Windows.Forms.Padding]::new(10); $automaticModeGroup.Margin = [System.Windows.Forms.Padding]::new(0, 0, 0, 12)
$automationLayout.Controls.Add($automaticModeGroup)
$automaticModeInner = [System.Windows.Forms.TableLayoutPanel]::new(); $automaticModeInner.AutoSize = $true; $automaticModeInner.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; $automaticModeInner.ColumnCount = 2; $automaticModeInner.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::AutoSize)) | Out-Null; $automaticModeInner.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100)) | Out-Null
$automaticModeGroup.Controls.Add($automaticModeInner)
$controls.enableAutomaticAdjustment = [System.Windows.Forms.CheckBox]::new(); $controls.enableAutomaticAdjustment.Text = ''; Set-BoolControl -Control $controls.enableAutomaticAdjustment -Value (Get-SettingValue -Sections $sections -Section 'AutomaticTestMode' -Key 'enableAutomaticAdjustment' -DefaultValue '0')
Add-SettingRow -Panel $automaticModeInner -LabelText 'Enable automatic adjustment' -Control $controls.enableAutomaticAdjustment -RowIndex 0
$controls.startValues = [System.Windows.Forms.TextBox]::new(); $controls.startValues.Width = 220; $controls.startValues.Text = (Get-SettingValue -Sections $sections -Section 'AutomaticTestMode' -Key 'startValues' -DefaultValue 'CurrentValues')
Add-SettingRow -Panel $automaticModeInner -LabelText 'Start values' -Control $controls.startValues -RowIndex 1
$controls.maxValue = [System.Windows.Forms.TextBox]::new(); $controls.maxValue.Width = 120; $controls.maxValue.Text = (Get-SettingValue -Sections $sections -Section 'AutomaticTestMode' -Key 'maxValue' -DefaultValue '0')
Add-SettingRow -Panel $automaticModeInner -LabelText 'Max value' -Control $controls.maxValue -RowIndex 2
$controls.incrementBy = [System.Windows.Forms.TextBox]::new(); $controls.incrementBy.Width = 160; $controls.incrementBy.Text = (Get-SettingValue -Sections $sections -Section 'AutomaticTestMode' -Key 'incrementBy' -DefaultValue 'Default')
Add-SettingRow -Panel $automaticModeInner -LabelText 'Increment by' -Control $controls.incrementBy -RowIndex 3
$controls.setVoltageOnlyForTestedCore = [System.Windows.Forms.CheckBox]::new(); $controls.setVoltageOnlyForTestedCore.Text = ''; Set-BoolControl -Control $controls.setVoltageOnlyForTestedCore -Value (Get-SettingValue -Sections $sections -Section 'AutomaticTestMode' -Key 'setVoltageOnlyForTestedCore' -DefaultValue '0')
Add-SettingRow -Panel $automaticModeInner -LabelText 'Set voltage only for tested core' -Control $controls.setVoltageOnlyForTestedCore -RowIndex 4
$controls.repeatCoreOnError = [System.Windows.Forms.CheckBox]::new(); $controls.repeatCoreOnError.Text = ''; Set-BoolControl -Control $controls.repeatCoreOnError -Value (Get-SettingValue -Sections $sections -Section 'AutomaticTestMode' -Key 'repeatCoreOnError' -DefaultValue '1')
Add-SettingRow -Panel $automaticModeInner -LabelText 'Repeat core on error' -Control $controls.repeatCoreOnError -RowIndex 5
$controls.enableResumeAfterUnexpectedExit = [System.Windows.Forms.CheckBox]::new(); $controls.enableResumeAfterUnexpectedExit.Text = ''; Set-BoolControl -Control $controls.enableResumeAfterUnexpectedExit -Value (Get-SettingValue -Sections $sections -Section 'AutomaticTestMode' -Key 'enableResumeAfterUnexpectedExit' -DefaultValue '0')
Add-SettingRow -Panel $automaticModeInner -LabelText 'Resume after unexpected exit' -Control $controls.enableResumeAfterUnexpectedExit -RowIndex 6
$controls.waitBeforeAutomaticResume = [System.Windows.Forms.TextBox]::new(); $controls.waitBeforeAutomaticResume.Width = 140; $controls.waitBeforeAutomaticResume.Text = (Get-SettingValue -Sections $sections -Section 'AutomaticTestMode' -Key 'waitBeforeAutomaticResume' -DefaultValue '120')
Add-SettingRow -Panel $automaticModeInner -LabelText 'Wait before resume (s)' -Control $controls.waitBeforeAutomaticResume -RowIndex 7
$controls.createSystemRestorePoint = [System.Windows.Forms.CheckBox]::new(); $controls.createSystemRestorePoint.Text = ''; Set-BoolControl -Control $controls.createSystemRestorePoint -Value (Get-SettingValue -Sections $sections -Section 'AutomaticTestMode' -Key 'createSystemRestorePoint' -DefaultValue '1')
Add-SettingRow -Panel $automaticModeInner -LabelText 'Create restore point' -Control $controls.createSystemRestorePoint -RowIndex 8
$controls.askForSystemRestorePointCreation = [System.Windows.Forms.CheckBox]::new(); $controls.askForSystemRestorePointCreation.Text = ''; Set-BoolControl -Control $controls.askForSystemRestorePointCreation -Value (Get-SettingValue -Sections $sections -Section 'AutomaticTestMode' -Key 'askForSystemRestorePointCreation' -DefaultValue '1')
Add-SettingRow -Panel $automaticModeInner -LabelText 'Ask before restore point' -Control $controls.askForSystemRestorePointCreation -RowIndex 9

$updateGroup = [System.Windows.Forms.GroupBox]::new(); $updateGroup.Text = 'Updates'; $updateGroup.AutoSize = $true; $updateGroup.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; $updateGroup.Padding = [System.Windows.Forms.Padding]::new(10)
$automationLayout.Controls.Add($updateGroup)
$updateInner = [System.Windows.Forms.TableLayoutPanel]::new(); $updateInner.AutoSize = $true; $updateInner.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; $updateInner.ColumnCount = 2; $updateInner.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::AutoSize)) | Out-Null; $updateInner.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100)) | Out-Null
$updateGroup.Controls.Add($updateInner)
$controls.enableUpdateCheck = [System.Windows.Forms.CheckBox]::new(); $controls.enableUpdateCheck.Text = ''; Set-BoolControl -Control $controls.enableUpdateCheck -Value (Get-SettingValue -Sections $sections -Section 'Update' -Key 'enableUpdateCheck' -DefaultValue '1')
Add-SettingRow -Panel $updateInner -LabelText 'Enable update check' -Control $controls.enableUpdateCheck -RowIndex 0
$controls.updateCheckFrequency = [System.Windows.Forms.TextBox]::new(); $controls.updateCheckFrequency.Width = 120; $controls.updateCheckFrequency.Text = (Get-SettingValue -Sections $sections -Section 'Update' -Key 'updateCheckFrequency' -DefaultValue '24')
Add-SettingRow -Panel $updateInner -LabelText 'Check frequency (h)' -Control $controls.updateCheckFrequency -RowIndex 1

$loggingPage = [System.Windows.Forms.TabPage]::new(); $loggingPage.Text = 'Logging & Debugging'
$loggingPage.Padding = [System.Windows.Forms.Padding]::new(12)
$tabControl.TabPages.Add($loggingPage)

$loggingPanel = [System.Windows.Forms.Panel]::new(); $loggingPanel.Dock = [System.Windows.Forms.DockStyle]::Fill; $loggingPanel.AutoScroll = $true
$loggingPage.Controls.Add($loggingPanel)

$loggingLayout = [System.Windows.Forms.TableLayoutPanel]::new(); $loggingLayout.Dock = [System.Windows.Forms.DockStyle]::Fill; $loggingLayout.AutoSize = $true; $loggingLayout.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; $loggingLayout.ColumnCount = 1; $loggingLayout.Padding = [System.Windows.Forms.Padding]::new(0, 0, 0, 6)
$loggingPanel.Controls.Add($loggingLayout)

$loggingGroup = [System.Windows.Forms.GroupBox]::new(); $loggingGroup.Text = 'Logging'; $loggingGroup.AutoSize = $true; $loggingGroup.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; $loggingGroup.Padding = [System.Windows.Forms.Padding]::new(10); $loggingGroup.Margin = [System.Windows.Forms.Padding]::new(0, 0, 0, 12)
$loggingLayout.Controls.Add($loggingGroup)
$loggingInner = [System.Windows.Forms.TableLayoutPanel]::new(); $loggingInner.AutoSize = $true; $loggingInner.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; $loggingInner.ColumnCount = 2; $loggingInner.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::AutoSize)) | Out-Null; $loggingInner.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100)) | Out-Null
$loggingGroup.Controls.Add($loggingInner)
$controls.loggingName = [System.Windows.Forms.TextBox]::new(); $controls.loggingName.Width = 260; $controls.loggingName.Text = (Get-SettingValue -Sections $sections -Section 'Logging' -Key 'name' -DefaultValue 'CoreCycler')
Add-SettingRow -Panel $loggingInner -LabelText 'Log name' -Control $controls.loggingName -RowIndex 0
$controls.logLevel = [System.Windows.Forms.TextBox]::new(); $controls.logLevel.Width = 100; $controls.logLevel.Text = (Get-SettingValue -Sections $sections -Section 'Logging' -Key 'logLevel' -DefaultValue '2')
Add-SettingRow -Panel $loggingInner -LabelText 'Log level' -Control $controls.logLevel -RowIndex 1
$controls.useWindowsEventLog = [System.Windows.Forms.CheckBox]::new(); $controls.useWindowsEventLog.Text = ''; Set-BoolControl -Control $controls.useWindowsEventLog -Value (Get-SettingValue -Sections $sections -Section 'Logging' -Key 'useWindowsEventLog' -DefaultValue '1')
Add-SettingRow -Panel $loggingInner -LabelText 'Use Windows event log' -Control $controls.useWindowsEventLog -RowIndex 2
$controls.flushDiskWriteCache = [System.Windows.Forms.CheckBox]::new(); $controls.flushDiskWriteCache.Text = ''; Set-BoolControl -Control $controls.flushDiskWriteCache -Value (Get-SettingValue -Sections $sections -Section 'Logging' -Key 'flushDiskWriteCache' -DefaultValue '0')
Add-SettingRow -Panel $loggingInner -LabelText 'Flush disk write cache' -Control $controls.flushDiskWriteCache -RowIndex 3

$debugGroup = [System.Windows.Forms.GroupBox]::new(); $debugGroup.Text = 'Debugging'; $debugGroup.AutoSize = $true; $debugGroup.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; $debugGroup.Padding = [System.Windows.Forms.Padding]::new(10)
$loggingLayout.Controls.Add($debugGroup)
$debugInner = [System.Windows.Forms.TableLayoutPanel]::new(); $debugInner.AutoSize = $true; $debugInner.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; $debugInner.ColumnCount = 2; $debugInner.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::AutoSize)) | Out-Null; $debugInner.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100)) | Out-Null
$debugGroup.Controls.Add($debugInner)
$controls.disableCpuUtilizationCheck = [System.Windows.Forms.CheckBox]::new(); $controls.disableCpuUtilizationCheck.Text = ''; Set-BoolControl -Control $controls.disableCpuUtilizationCheck -Value (Get-SettingValue -Sections $sections -Section 'Debug' -Key 'disableCpuUtilizationCheck' -DefaultValue '0')
Add-SettingRow -Panel $debugInner -LabelText 'Disable CPU utilization check' -Control $controls.disableCpuUtilizationCheck -RowIndex 0
$controls.useWindowsPerformanceCountersForCpuUtilization = [System.Windows.Forms.CheckBox]::new(); $controls.useWindowsPerformanceCountersForCpuUtilization.Text = ''; Set-BoolControl -Control $controls.useWindowsPerformanceCountersForCpuUtilization -Value (Get-SettingValue -Sections $sections -Section 'Debug' -Key 'useWindowsPerformanceCountersForCpuUtilization' -DefaultValue '0')
Add-SettingRow -Panel $debugInner -LabelText 'Use performance counters' -Control $controls.useWindowsPerformanceCountersForCpuUtilization -RowIndex 1
$controls.enableCpuFrequencyCheck = [System.Windows.Forms.CheckBox]::new(); $controls.enableCpuFrequencyCheck.Text = ''; Set-BoolControl -Control $controls.enableCpuFrequencyCheck -Value (Get-SettingValue -Sections $sections -Section 'Debug' -Key 'enableCpuFrequencyCheck' -DefaultValue '0')
Add-SettingRow -Panel $debugInner -LabelText 'Enable CPU frequency check' -Control $controls.enableCpuFrequencyCheck -RowIndex 2
$controls.tickInterval = [System.Windows.Forms.TextBox]::new(); $controls.tickInterval.Width = 100; $controls.tickInterval.Text = (Get-SettingValue -Sections $sections -Section 'Debug' -Key 'tickInterval' -DefaultValue '10')
Add-SettingRow -Panel $debugInner -LabelText 'Tick interval' -Control $controls.tickInterval -RowIndex 3
$controls.delayFirstErrorCheck = [System.Windows.Forms.TextBox]::new(); $controls.delayFirstErrorCheck.Width = 100; $controls.delayFirstErrorCheck.Text = (Get-SettingValue -Sections $sections -Section 'Debug' -Key 'delayFirstErrorCheck' -DefaultValue '0')
Add-SettingRow -Panel $debugInner -LabelText 'Delay first error check' -Control $controls.delayFirstErrorCheck -RowIndex 4
$controls.stressTestProgramPriority = [System.Windows.Forms.ComboBox]::new(); $controls.stressTestProgramPriority.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList; $controls.stressTestProgramPriority.Items.AddRange(([string[]]@('Idle','BelowNormal','Normal','AboveNormal','High','Realtime'))); $controls.stressTestProgramPriority.Width = 160
Set-ComboBoxValue -Control $controls.stressTestProgramPriority -Value (Get-SettingValue -Sections $sections -Section 'Debug' -Key 'stressTestProgramPriority' -DefaultValue 'Normal') -DefaultValue 'Normal'
Add-SettingRow -Panel $debugInner -LabelText 'Process priority' -Control $controls.stressTestProgramPriority -RowIndex 5
$controls.stressTestProgramWindowToForeground = [System.Windows.Forms.CheckBox]::new(); $controls.stressTestProgramWindowToForeground.Text = ''; Set-BoolControl -Control $controls.stressTestProgramWindowToForeground -Value (Get-SettingValue -Sections $sections -Section 'Debug' -Key 'stressTestProgramWindowToForeground' -DefaultValue '0')
Add-SettingRow -Panel $debugInner -LabelText 'Bring stress window to foreground' -Control $controls.stressTestProgramWindowToForeground -RowIndex 6
$controls.suspensionTime = [System.Windows.Forms.TextBox]::new(); $controls.suspensionTime.Width = 120; $controls.suspensionTime.Text = (Get-SettingValue -Sections $sections -Section 'Debug' -Key 'suspensionTime' -DefaultValue '1000')
Add-SettingRow -Panel $debugInner -LabelText 'Suspension time' -Control $controls.suspensionTime -RowIndex 7
$controls.modeToUseForSuspension = [System.Windows.Forms.ComboBox]::new(); $controls.modeToUseForSuspension.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList; $controls.modeToUseForSuspension.Items.AddRange(([string[]]@('Threads','Processes'))); $controls.modeToUseForSuspension.Width = 140
Set-ComboBoxValue -Control $controls.modeToUseForSuspension -Value (Get-SettingValue -Sections $sections -Section 'Debug' -Key 'modeToUseForSuspension' -DefaultValue 'Threads') -DefaultValue 'Threads'
Add-SettingRow -Panel $debugInner -LabelText 'Suspension mode' -Control $controls.modeToUseForSuspension -RowIndex 8

$advancedPage = [System.Windows.Forms.TabPage]::new(); $advancedPage.Text = 'Prime95 Custom'
$advancedPage.Padding = [System.Windows.Forms.Padding]::new(12)
$tabControl.TabPages.Add($advancedPage)

$advancedPanel = [System.Windows.Forms.Panel]::new(); $advancedPanel.Dock = [System.Windows.Forms.DockStyle]::Fill; $advancedPanel.AutoScroll = $true
$advancedPage.Controls.Add($advancedPanel)

$advancedLayout = [System.Windows.Forms.TableLayoutPanel]::new(); $advancedLayout.Dock = [System.Windows.Forms.DockStyle]::Fill; $advancedLayout.AutoSize = $true; $advancedLayout.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; $advancedLayout.ColumnCount = 1; $advancedLayout.Padding = [System.Windows.Forms.Padding]::new(0, 0, 0, 6)
$advancedPanel.Controls.Add($advancedLayout)

$primeCustomGroup = [System.Windows.Forms.GroupBox]::new(); $primeCustomGroup.Text = 'Prime95 custom tuning'; $primeCustomGroup.AutoSize = $true; $primeCustomGroup.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; $primeCustomGroup.Padding = [System.Windows.Forms.Padding]::new(10)
$advancedLayout.Controls.Add($primeCustomGroup)
$primeCustomInner = [System.Windows.Forms.TableLayoutPanel]::new(); $primeCustomInner.AutoSize = $true; $primeCustomInner.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; $primeCustomInner.ColumnCount = 2; $primeCustomInner.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::AutoSize)) | Out-Null; $primeCustomInner.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100)) | Out-Null
$primeCustomGroup.Controls.Add($primeCustomInner)
$controls.cpuSupportsAvx = [System.Windows.Forms.CheckBox]::new(); $controls.cpuSupportsAvx.Text = ''; Set-BoolControl -Control $controls.cpuSupportsAvx -Value (Get-SettingValue -Sections $sections -Section 'Prime95Custom' -Key 'CpuSupportsAVX' -DefaultValue '0')
Add-SettingRow -Panel $primeCustomInner -LabelText 'CPU supports AVX' -Control $controls.cpuSupportsAvx -RowIndex 0
$controls.cpuSupportsAvx2 = [System.Windows.Forms.CheckBox]::new(); $controls.cpuSupportsAvx2.Text = ''; Set-BoolControl -Control $controls.cpuSupportsAvx2 -Value (Get-SettingValue -Sections $sections -Section 'Prime95Custom' -Key 'CpuSupportsAVX2' -DefaultValue '0')
Add-SettingRow -Panel $primeCustomInner -LabelText 'CPU supports AVX2' -Control $controls.cpuSupportsAvx2 -RowIndex 1
$controls.cpuSupportsFma3 = [System.Windows.Forms.CheckBox]::new(); $controls.cpuSupportsFma3.Text = ''; Set-BoolControl -Control $controls.cpuSupportsFma3 -Value (Get-SettingValue -Sections $sections -Section 'Prime95Custom' -Key 'CpuSupportsFMA3' -DefaultValue '0')
Add-SettingRow -Panel $primeCustomInner -LabelText 'CPU supports FMA3' -Control $controls.cpuSupportsFma3 -RowIndex 2
$controls.cpuSupportsAvx512 = [System.Windows.Forms.CheckBox]::new(); $controls.cpuSupportsAvx512.Text = ''; Set-BoolControl -Control $controls.cpuSupportsAvx512 -Value (Get-SettingValue -Sections $sections -Section 'Prime95Custom' -Key 'CpuSupportsAVX512' -DefaultValue '0')
Add-SettingRow -Panel $primeCustomInner -LabelText 'CPU supports AVX512' -Control $controls.cpuSupportsAvx512 -RowIndex 3
$controls.minTortureFft = [System.Windows.Forms.TextBox]::new(); $controls.minTortureFft.Width = 100; $controls.minTortureFft.Text = (Get-SettingValue -Sections $sections -Section 'Prime95Custom' -Key 'MinTortureFFT' -DefaultValue '4')
Add-SettingRow -Panel $primeCustomInner -LabelText 'Min torture FFT' -Control $controls.minTortureFft -RowIndex 4
$controls.maxTortureFft = [System.Windows.Forms.TextBox]::new(); $controls.maxTortureFft.Width = 100; $controls.maxTortureFft.Text = (Get-SettingValue -Sections $sections -Section 'Prime95Custom' -Key 'MaxTortureFFT' -DefaultValue '8192')
Add-SettingRow -Panel $primeCustomInner -LabelText 'Max torture FFT' -Control $controls.maxTortureFft -RowIndex 5
$controls.tortureMem = [System.Windows.Forms.TextBox]::new(); $controls.tortureMem.Width = 100; $controls.tortureMem.Text = (Get-SettingValue -Sections $sections -Section 'Prime95Custom' -Key 'TortureMem' -DefaultValue '0')
Add-SettingRow -Panel $primeCustomInner -LabelText 'Torture memory' -Control $controls.tortureMem -RowIndex 6
$controls.tortureTime = [System.Windows.Forms.TextBox]::new(); $controls.tortureTime.Width = 100; $controls.tortureTime.Text = (Get-SettingValue -Sections $sections -Section 'Prime95Custom' -Key 'TortureTime' -DefaultValue '1')
Add-SettingRow -Panel $primeCustomInner -LabelText 'Torture time' -Control $controls.tortureTime -RowIndex 7

$buttonPanel = [System.Windows.Forms.FlowLayoutPanel]::new()
$buttonPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$buttonPanel.AutoSize = $true
$buttonPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
$buttonPanel.Margin = [System.Windows.Forms.Padding]::new(0, 12, 0, 0)
$mainLayout.Controls.Add($buttonPanel, 0, 2)

$closeButton = [System.Windows.Forms.Button]::new(); $closeButton.Text = 'Close'; $closeButton.Width = 90; $closeButton.Add_Click({ $form.Close() })
$buttonPanel.Controls.Add($closeButton)

$launchButton = [System.Windows.Forms.Button]::new(); $launchButton.Text = 'Launch CoreCycler'; $launchButton.Width = 140; $launchButton.Add_Click({
    try {
        $launchScript = Join-Path $rootPath 'script-corecycler.ps1'
        Start-Process -FilePath 'cmd.exe' -ArgumentList @('/k', 'powershell.exe -ExecutionPolicy Bypass -File', "`"$launchScript`"") -WorkingDirectory $rootPath | Out-Null
        [System.Windows.Forms.MessageBox]::Show('CoreCycler has been launched.', 'CoreCycler', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Unable to launch CoreCycler: $($_.Exception.Message)", 'CoreCycler', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})
$buttonPanel.Controls.Add($launchButton)

$saveButton = [System.Windows.Forms.Button]::new(); $saveButton.Text = 'Save'; $saveButton.Width = 90; $saveButton.Add_Click({
    try {
        $maxIterationsValue = 0
        if (-not [int]::TryParse($controls.maxIterations.Text, [ref]$maxIterationsValue)) {
            [System.Windows.Forms.MessageBox]::Show('Max iterations must be a whole number.', 'Validation error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }

        $delayValue = 0
        if (-not [int]::TryParse($controls.delayBetweenCores.Text, [ref]$delayValue)) {
            [System.Windows.Forms.MessageBox]::Show('Delay between cores must be a whole number.', 'Validation error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }

        Set-SettingValue -Sections $sections -Section 'General' -Key 'useConfigFile' -Value $controls.useConfigFile.Text.Trim()
        Set-SettingValue -Sections $sections -Section 'General' -Key 'stressTestProgram' -Value $controls.stressTestProgram.SelectedItem.ToString()
        Set-SettingValue -Sections $sections -Section 'General' -Key 'runtimePerCore' -Value $controls.runtimePerCore.Text.Trim()
        Set-SettingValue -Sections $sections -Section 'General' -Key 'suspendPeriodically' -Value (Get-BoolValue -Control $controls.suspendPeriodically)
        Set-SettingValue -Sections $sections -Section 'General' -Key 'coreTestOrder' -Value $controls.coreTestOrder.SelectedItem.ToString()
        Set-SettingValue -Sections $sections -Section 'General' -Key 'skipCoreOnError' -Value (Get-BoolValue -Control $controls.skipCoreOnError)
        Set-SettingValue -Sections $sections -Section 'General' -Key 'stopOnError' -Value (Get-BoolValue -Control $controls.stopOnError)
        Set-SettingValue -Sections $sections -Section 'General' -Key 'numberOfThreads' -Value $controls.numberOfThreads.SelectedItem.ToString()
        Set-SettingValue -Sections $sections -Section 'General' -Key 'assignBothVirtualCoresForSingleThread' -Value (Get-BoolValue -Control $controls.assignBothVirtualCores)
        Set-SettingValue -Sections $sections -Section 'General' -Key 'maxIterations' -Value $maxIterationsValue.ToString()
        Set-SettingValue -Sections $sections -Section 'General' -Key 'coresToIgnore' -Value $controls.coresToIgnore.Text.Trim()
        Set-SettingValue -Sections $sections -Section 'General' -Key 'restartTestProgramForEachCore' -Value (Get-BoolValue -Control $controls.restartTestProgramForEachCore)
        Set-SettingValue -Sections $sections -Section 'General' -Key 'delayBetweenCores' -Value $delayValue.ToString()
        Set-SettingValue -Sections $sections -Section 'General' -Key 'beepOnError' -Value (Get-BoolValue -Control $controls.beepOnError)
        Set-SettingValue -Sections $sections -Section 'General' -Key 'flashOnError' -Value (Get-BoolValue -Control $controls.flashOnError)
        Set-SettingValue -Sections $sections -Section 'General' -Key 'lookForWheaErrors' -Value (Get-BoolValue -Control $controls.lookForWheaErrors)
        Set-SettingValue -Sections $sections -Section 'General' -Key 'treatWheaWarningAsError' -Value (Get-BoolValue -Control $controls.treatWheaWarningAsError)

        Set-SettingValue -Sections $sections -Section 'Prime95' -Key 'mode' -Value $controls.prime95Mode.SelectedItem.ToString()
        Set-SettingValue -Sections $sections -Section 'Prime95' -Key 'FFTSize' -Value $controls.prime95FftSize.SelectedItem.ToString()
        Set-SettingValue -Sections $sections -Section 'yCruncher' -Key 'mode' -Value $controls.yCruncherMode.SelectedItem.ToString()
        Set-SettingValue -Sections $sections -Section 'yCruncher' -Key 'tests' -Value $controls.yCruncherTests.Text.Trim()
        Set-SettingValue -Sections $sections -Section 'yCruncher' -Key 'testDuration' -Value $controls.yCruncherTestDuration.Text.Trim()
        Set-SettingValue -Sections $sections -Section 'yCruncher' -Key 'memory' -Value $controls.yCruncherMemory.Text.Trim()
        Set-SettingValue -Sections $sections -Section 'yCruncher' -Key 'enableYCruncherLoggingWrapper' -Value (Get-BoolValue -Control $controls.enableYCruncherLoggingWrapper)
        Set-SettingValue -Sections $sections -Section 'Aida64' -Key 'mode' -Value $controls.aida64Mode.SelectedItem.ToString()
        Set-SettingValue -Sections $sections -Section 'Aida64' -Key 'useAVX' -Value (Get-BoolValue -Control $controls.aida64UseAvx)
        Set-SettingValue -Sections $sections -Section 'Aida64' -Key 'maxMemory' -Value $controls.aida64MaxMemory.Text.Trim()
        Set-SettingValue -Sections $sections -Section 'Linpack' -Key 'version' -Value $controls.linpackVersion.SelectedItem.ToString()
        Set-SettingValue -Sections $sections -Section 'Linpack' -Key 'mode' -Value $controls.linpackMode.SelectedItem.ToString()
        Set-SettingValue -Sections $sections -Section 'Linpack' -Key 'memory' -Value $controls.linpackMemory.Text.Trim()

        Set-SettingValue -Sections $sections -Section 'AutomaticTestMode' -Key 'enableAutomaticAdjustment' -Value (Get-BoolValue -Control $controls.enableAutomaticAdjustment)
        Set-SettingValue -Sections $sections -Section 'AutomaticTestMode' -Key 'startValues' -Value $controls.startValues.Text.Trim()
        Set-SettingValue -Sections $sections -Section 'AutomaticTestMode' -Key 'maxValue' -Value $controls.maxValue.Text.Trim()
        Set-SettingValue -Sections $sections -Section 'AutomaticTestMode' -Key 'incrementBy' -Value $controls.incrementBy.Text.Trim()
        Set-SettingValue -Sections $sections -Section 'AutomaticTestMode' -Key 'setVoltageOnlyForTestedCore' -Value (Get-BoolValue -Control $controls.setVoltageOnlyForTestedCore)
        Set-SettingValue -Sections $sections -Section 'AutomaticTestMode' -Key 'repeatCoreOnError' -Value (Get-BoolValue -Control $controls.repeatCoreOnError)
        Set-SettingValue -Sections $sections -Section 'AutomaticTestMode' -Key 'enableResumeAfterUnexpectedExit' -Value (Get-BoolValue -Control $controls.enableResumeAfterUnexpectedExit)
        Set-SettingValue -Sections $sections -Section 'AutomaticTestMode' -Key 'waitBeforeAutomaticResume' -Value $controls.waitBeforeAutomaticResume.Text.Trim()
        Set-SettingValue -Sections $sections -Section 'AutomaticTestMode' -Key 'createSystemRestorePoint' -Value (Get-BoolValue -Control $controls.createSystemRestorePoint)
        Set-SettingValue -Sections $sections -Section 'AutomaticTestMode' -Key 'askForSystemRestorePointCreation' -Value (Get-BoolValue -Control $controls.askForSystemRestorePointCreation)

        Set-SettingValue -Sections $sections -Section 'Update' -Key 'enableUpdateCheck' -Value (Get-BoolValue -Control $controls.enableUpdateCheck)
        Set-SettingValue -Sections $sections -Section 'Update' -Key 'updateCheckFrequency' -Value $controls.updateCheckFrequency.Text.Trim()

        Set-SettingValue -Sections $sections -Section 'Logging' -Key 'name' -Value $controls.loggingName.Text.Trim()
        Set-SettingValue -Sections $sections -Section 'Logging' -Key 'logLevel' -Value $controls.logLevel.Text.Trim()
        Set-SettingValue -Sections $sections -Section 'Logging' -Key 'useWindowsEventLog' -Value (Get-BoolValue -Control $controls.useWindowsEventLog)
        Set-SettingValue -Sections $sections -Section 'Logging' -Key 'flushDiskWriteCache' -Value (Get-BoolValue -Control $controls.flushDiskWriteCache)

        Set-SettingValue -Sections $sections -Section 'Debug' -Key 'disableCpuUtilizationCheck' -Value (Get-BoolValue -Control $controls.disableCpuUtilizationCheck)
        Set-SettingValue -Sections $sections -Section 'Debug' -Key 'useWindowsPerformanceCountersForCpuUtilization' -Value (Get-BoolValue -Control $controls.useWindowsPerformanceCountersForCpuUtilization)
        Set-SettingValue -Sections $sections -Section 'Debug' -Key 'enableCpuFrequencyCheck' -Value (Get-BoolValue -Control $controls.enableCpuFrequencyCheck)
        Set-SettingValue -Sections $sections -Section 'Debug' -Key 'tickInterval' -Value $controls.tickInterval.Text.Trim()
        Set-SettingValue -Sections $sections -Section 'Debug' -Key 'delayFirstErrorCheck' -Value $controls.delayFirstErrorCheck.Text.Trim()
        Set-SettingValue -Sections $sections -Section 'Debug' -Key 'stressTestProgramPriority' -Value $controls.stressTestProgramPriority.SelectedItem.ToString()
        Set-SettingValue -Sections $sections -Section 'Debug' -Key 'stressTestProgramWindowToForeground' -Value (Get-BoolValue -Control $controls.stressTestProgramWindowToForeground)
        Set-SettingValue -Sections $sections -Section 'Debug' -Key 'suspensionTime' -Value $controls.suspensionTime.Text.Trim()
        Set-SettingValue -Sections $sections -Section 'Debug' -Key 'modeToUseForSuspension' -Value $controls.modeToUseForSuspension.SelectedItem.ToString()

        Set-SettingValue -Sections $sections -Section 'Prime95Custom' -Key 'CpuSupportsAVX' -Value (Get-BoolValue -Control $controls.cpuSupportsAvx)
        Set-SettingValue -Sections $sections -Section 'Prime95Custom' -Key 'CpuSupportsAVX2' -Value (Get-BoolValue -Control $controls.cpuSupportsAvx2)
        Set-SettingValue -Sections $sections -Section 'Prime95Custom' -Key 'CpuSupportsFMA3' -Value (Get-BoolValue -Control $controls.cpuSupportsFma3)
        Set-SettingValue -Sections $sections -Section 'Prime95Custom' -Key 'CpuSupportsAVX512' -Value (Get-BoolValue -Control $controls.cpuSupportsAvx512)
        Set-SettingValue -Sections $sections -Section 'Prime95Custom' -Key 'MinTortureFFT' -Value $controls.minTortureFft.Text.Trim()
        Set-SettingValue -Sections $sections -Section 'Prime95Custom' -Key 'MaxTortureFFT' -Value $controls.maxTortureFft.Text.Trim()
        Set-SettingValue -Sections $sections -Section 'Prime95Custom' -Key 'TortureMem' -Value $controls.tortureMem.Text.Trim()
        Set-SettingValue -Sections $sections -Section 'Prime95Custom' -Key 'TortureTime' -Value $controls.tortureTime.Text.Trim()

        Write-IniFile -Path $configFile -Sections $sections
        [System.Windows.Forms.MessageBox]::Show("Settings were saved to $configFile", 'CoreCycler', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Unable to save settings: $($_.Exception.Message)", 'CoreCycler', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})
$buttonPanel.Controls.Add($saveButton)

$form.ShowDialog() | Out-Null
