<#
.SYNOPSIS
    GUI module for the Tiny11 Builder Ultimate Edition.

.DESCRIPTION
    Windows Forms module providing a two-stage wizard (mount mode + image index
    selection). Enhanced from the reforged fork with:
      - Smart drive detection (auto-find Windows setup)
      - Version tracking in the window title
      - Real-time build log window
      - App customization checkbox grid
      - Splash screen with version info

    This module is imported by tiny11gui.ps1 (the GUI entry point). The GUI
    collects user input then launches tiny11maker.ps1 or tiny11Coremaker.ps1
    with the appropriate parameters.
#>

#---------[ Module Manifest (auto-generated at import) ]---------#
$modulePath = $PSScriptRoot -replace '\\', '/'
$moduleName = "tiny11gui"
$moduleVersion = "26.09.2026"
$moduleAuthor = "Ultimate Fork"
$moduleDescription = "GUI wizard for the Tiny11 Builder Ultimate Edition."

if (Test-Path "$modulePath/$moduleName.psd1") {
    if ((Get-ExecutionPolicy) -ne 'Bypass') {
        try {
            Import-Module -Name "$modulePath/$moduleName.psd1" -Scope Global -Force -ErrorAction Stop
        } catch {
            # Fallback: register the module manifest inline
            New-ModuleManifest -Path "$modulePath/$moduleName.psd1" `
                -RootModule "$moduleName.psm1" `
                -ModuleVersion $moduleVersion `
                -Author $moduleAuthor `
                -Description $moduleDescription `
                -FunctionsToExport @() `
                -CmdletsToExport @() `
                -VariablesToExport @()
        }
    }
}

#---------[ Global Variables ]---------#
New-Variable -Name AppTitle -Value "Tiny11 Builder" -Scope Script -Option AllScope -Force
New-Variable -Name AppVersion -Value "Ultimate Edition v26.09.2026" -Scope Script -Option AllScope -Force

New-Variable -Name WINDOW_CLOSED -Value $false -Scope Script -Option AllScope -Force
New-Variable -Name MODE_SELECT -Value 0 -Scope Script -Option AllScope -Force
New-Variable -Name INDEX_SELECT -Value 0 -Scope Script -Option AllScope -Force
New-Variable -Name SCREEN_STAGE -Value 0 -Scope Script -Option AllScope -Force
New-Variable -Name TEXTBOX_ISO -Value $null -Scope Script -Option AllScope -Force
New-Variable -Name COMBOBOX_DRIVE -Value $null -Scope Script -Option AllScope -Force
New-Variable -Name BUTTON_BROWSE -Value $null -Scope Script -Option AllScope -Force
New-Variable -Name BUTTON_SEARCH -Value $null -Scope Script -Option AllScope -Force
New-Variable -Name COMBOBOX_INDEX -Value $null -Scope Script -Option AllScope -Force
New-Variable -Name LIST_DRIVES -Value $null -Scope Script -Option AllScope -Force
New-Variable -Name LIST_EDITIONS -Value $null -Scope Script -Option AllScope -Force

#---------[ Popup Helpers ]---------#

## Pop-up notification window
function Invoke-PopupInfo {
    param(
        [Parameter(Mandatory = $true)][string]$title,
        [Parameter(Mandatory = $true)][string]$message
    )
    $ButtonType = [System.Windows.Forms.MessageBoxButtons]::OK
    $MessageIcon = [System.Windows.Forms.MessageBoxIcon]::Information
    $null = [System.Windows.Forms.MessageBox]::Show($message, $title, $ButtonType, $MessageIcon)
}

## Pop-up error window
function Invoke-PopupError {
    param(
        [Parameter(Mandatory = $true)][string]$title,
        [Parameter(Mandatory = $true)][string]$message
    )
    $ButtonType = [System.Windows.Forms.MessageBoxButtons]::OK
    $MessageIcon = [System.Windows.Forms.MessageBoxIcon]::Error
    $null = [System.Windows.Forms.MessageBox]::Show($message, $title, $ButtonType, $MessageIcon)
}

## Pop-up yes/no choice window
function Invoke-PopupYesOrNo {
    param(
        [Parameter(Mandatory = $true)][string]$title,
        [Parameter(Mandatory = $true)][string]$message
    )
    $ButtonType = [System.Windows.Forms.MessageBoxButtons]::YesNo
    $MessageIcon = [System.Windows.Forms.MessageBoxIcon]::Question
    $Result = [System.Windows.Forms.MessageBox]::Show($message, $title, $ButtonType, $MessageIcon)
    return ($Result -eq [System.Windows.Forms.DialogResult]::Yes)
}

## Dialog window to select a ISO file
function Open-IsoFile {
    $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{
        Title          = "Select Windows 11 ISO file"
        InitialDirectory = [Environment]::GetFolderPath('Desktop')
        Filter         = 'ISO image (*.iso)|*.iso|All files (*.*)|*.*'
    }
    $null = $FileBrowser.ShowDialog()
    return $FileBrowser.FileName
}

#---------[ Data Lists ]---------#

## Sets a list of available system file drives
function Set-DrivesList {
    param([Parameter(Mandatory = $true)][string[]]$list)
    $LIST_DRIVES = $list
}

## Sets a list of available Windows 11 editions
function Set-EditionsList {
    param([Parameter(Mandatory = $true)][string[]]$list)
    $LIST_EDITIONS = $list
}

## Auto-Detects which drive has a Windows setup image
function Invoke-AutoDetect {
    param([Parameter(Mandatory = $true)][string[]]$drivesList)
    foreach ($drive in $drivesList) {
        if ((Test-Path "$($drive)sources\install.esd") -or (Test-Path "$($drive)sources\install.wim")) {
            Invoke-PopupInfo -title "Drive found" -message "Windows setup image found at drive $drive"
            return $drive
        }
    }
    Invoke-PopupError -title "Not found" -message "Unable to find a mounted Windows setup image!"
    return $drivesList[0]
}

#---------[ Event Loop & State ]---------#

## Update the events of the window and keep it from closing
function Update-EventLoop {
    param([Parameter(Mandatory = $true)][int]$stage)
    while (-not $WINDOW_CLOSED -and $SCREEN_STAGE -eq $stage) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 33
    }
}

function Get-ScreenStage { return $SCREEN_STAGE }
function Get-ModeSelect { return $MODE_SELECT }
function Get-IsoPath { return $TEXTBOX_ISO.Text }
function Get-SelectedDrive { return $COMBOBOX_DRIVE.SelectedItem.ToString() }
function Get-SelectedImageIndex { return $INDEX_SELECT }

#---------[ Validation ]---------#

## Checks whether the user can proceed to the next step
function Validate-NextStep {
    if ($MODE_SELECT -eq 0) {
        Invoke-PopupError -title "No mode selected" -message "Please, select a mounting mode first!"
        return
    }
    if ($MODE_SELECT -eq 1) {
        $isoExists = Test-Path (Get-IsoPath)
        if (-not $isoExists) {
            Invoke-PopupError -title "Not found" -message "ISO file not found!"
            return
        }
    }
    if ($MODE_SELECT -eq 2) {
        $hasESD = Test-Path "$(Get-SelectedDrive)sources\install.esd"
        $hasWIM = Test-Path "$(Get-SelectedDrive)sources\install.wim"
        if ((-not $hasESD) -and (-not $hasWIM)) {
            Invoke-PopupError -title "Setup not found" -message "$(Get-SelectedDrive) doesn't contain setup files!"
            return
        }
    }
    $SCREEN_STAGE = 1
}

## Checks whether the user can create the Tiny11 ISO
function Validate-CreateTiny11 {
    if (($LIST_EDITIONS -eq $null) -or ($LIST_EDITIONS.Count -eq 0) -or ($LIST_EDITIONS[0] -eq "No image index found")) {
        Invoke-PopupError -title "No index found" -message "Unable to find a valid image index!"
        $WINDOW_CLOSED = $true
        return
    }
    $INDEX_SELECT = $($COMBOBOX_INDEX.SelectedIndex + 1)
    $SCREEN_STAGE = 2
}

#---------[ Main Window ]---------#

## Creates the main application window
function Invoke-MainForm {
    param(
        [Parameter(Mandatory = $true)][string]$title,
        [Parameter(Mandatory = $true)][string]$version,
        [Parameter(Mandatory = $true)][string]$icoPath,
        [Parameter(Mandatory = $true)][string]$splashPath
    )

    $AppIconObj = $null
    $AppSplashObj = $null
    try { $AppIconObj = New-Object System.Drawing.Icon($icoPath) } catch { }
    try { $AppSplashObj = [System.Drawing.Image]::FromFile($splashPath) } catch { }

    [System.Windows.Forms.Application]::EnableVisualStyles()
    $FormWindow = New-Object System.Windows.Forms.Form
    $FormWindow.Text = "$title - $version"
    if ($AppIconObj) { $FormWindow.Icon = $AppIconObj }
    $FormWindow.Width = 800
    $FormWindow.Height = 600
    $FormWindow.BackColor = "White"
    $FormWindow.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
    $FormWindow.MaximizeBox = $false
    $FormWindow.MinimizeBox = $false
    $FormWindow.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen

    $SplashPictureBox = New-Object System.Windows.Forms.PictureBox
    if ($AppSplashObj) {
        $SplashPictureBox.Image = $AppSplashObj
    } else {
        # Fallback: solid color with text
        $SplashPictureBox.BackColor = [System.Drawing.Color]::SteelBlue
        $SplashPictureBox.BackColor = [System.Drawing.Color]::FromArgb(0, 122, 204)
    }
    $SplashPictureBox.Width = 800
    $SplashPictureBox.Height = 300
    $SplashPictureBox.Left = 0
    $SplashPictureBox.Top = 0
    $SplashPictureBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    if (-not $AppSplashObj) { $SplashPictureBox.BorderStyle = [System.Windows.Forms.BorderStyle]::Fixed3D }
    $FormWindow.Controls.Add($SplashPictureBox)

    $FormWindow.Add_FormClosed({ $WINDOW_CLOSED = $true })

    return $FormWindow
}

#---------[ Stage 1: Mount Mode ]---------#

## UI for mount mode (ISO file or mounted drive)
function Invoke-MountMode {
    $MyFontFamily = New-Object System.Drawing.FontFamily "Segoe UI"

    $MountPanel = New-Object System.Windows.Forms.Panel
    $MountPanel.Location = New-Object System.Drawing.Point 0, 0
    $MountPanel.Size = New-Object System.Drawing.Size 800, 600
    $MountPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::None

    $LabelMountMode = New-Object System.Windows.Forms.Label
    $LabelMountMode.Text = "Select how to provide the Windows 11 image:"
    $LabelMountMode.Font = New-Object System.Drawing.Font($MyFontFamily, 16.0, [System.Drawing.FontStyle]::Bold)
    $LabelMountMode.Location = New-Object System.Drawing.Point 0, 270
    $LabelMountMode.Size = New-Object System.Drawing.Size 800, 50
    $LabelMountMode.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter

    $RadioButtonIso = New-Object System.Windows.Forms.RadioButton
    $RadioButtonDrive = New-Object System.Windows.Forms.RadioButton

    $ModeGroupBox = New-Object System.Windows.Forms.GroupBox
    $ModeGroupBox.Controls.Add($RadioButtonIso)
    $ModeGroupBox.Controls.Add($RadioButtonDrive)
    $ModeGroupBox.Location = New-Object System.Drawing.Point 0, 285
    $ModeGroupBox.Size = New-Object System.Drawing.Size 800, 300

    $RadioButtonIso.Location = New-Object System.Drawing.Point 250, 10
    $RadioButtonIso.Size = New-Object System.Drawing.Size 280, 100
    $RadioButtonIso.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $RadioButtonIso.Font = New-Object System.Drawing.Font($MyFontFamily, 13.0, [System.Drawing.FontStyle]::Regular)
    $RadioButtonIso.Text = "Mount a ISO file:"
    $RadioButtonIso.Add_Click({
        $MODE_SELECT = 1
        $TEXTBOX_ISO.Enabled = $true
        $COMBOBOX_DRIVE.Enabled = $false
        $BUTTON_BROWSE.Enabled = $true
        $BUTTON_SEARCH.Enabled = $false
    })
    $RadioButtonIso.Add_MouseEnter({ $this.Cursor = [System.Windows.Forms.Cursors]::Hand })
    $RadioButtonIso.Add_MouseLeave({ $this.Cursor = [System.Windows.Forms.Cursors]::Arrow })

    $TEXTBOX_ISO = New-Object System.Windows.Forms.TextBox
    $TEXTBOX_ISO.Multiline = $false
    $TEXTBOX_ISO.AcceptsTab = $false
    $TEXTBOX_ISO.Location = New-Object System.Drawing.Point 280, 70
    $TEXTBOX_ISO.Size = New-Object System.Drawing.Size 400, 45
    $TEXTBOX_ISO.BorderStyle = [System.Windows.Forms.FormBorderStyle]::Fixed3D
    $TEXTBOX_ISO.ForeColor = [System.Drawing.Color]::Black
    $TEXTBOX_ISO.BackColor = [System.Drawing.Color]::WhiteSmoke
    $TEXTBOX_ISO.Font = New-Object System.Drawing.Font($MyFontFamily, 12.0, [System.Drawing.FontStyle]::Regular)
    $TEXTBOX_ISO.Enabled = $false
    $RadioButtonIso.Controls.Add($TEXTBOX_ISO)

    $LabelPathToIso = New-Object System.Windows.Forms.Label
    $LabelPathToIso.Text = "Full path:"
    $LabelPathToIso.Font = New-Object System.Drawing.Font($MyFontFamily, 12.0, [System.Drawing.FontStyle]::Regular)
    $LabelPathToIso.Location = New-Object System.Drawing.Point 180, 75
    $LabelPathToIso.Size = New-Object System.Drawing.Size 90, 20
    $LabelPathToIso.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight

    $BUTTON_BROWSE = New-Object System.Windows.Forms.Button
    $BUTTON_BROWSE.Location = New-Object System.Drawing.Point 700, 70
    $BUTTON_BROWSE.Size = New-Object System.Drawing.Size 80, 35
    $BUTTON_BROWSE.ForeColor = [System.Drawing.Color]::Black
    $BUTTON_BROWSE.BackColor = [System.Drawing.Color]::FromArgb(0, 122, 204)
    $BUTTON_BROWSE.ForeColor = [System.Drawing.Color]::White
    $BUTTON_BROWSE.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $BUTTON_BROWSE.Font = New-Object System.Drawing.Font($MyFontFamily, 12.0, [System.Drawing.FontStyle]::Regular)
    $BUTTON_BROWSE.Text = "Browse"
    $BUTTON_BROWSE.Add_MouseEnter({ $this.Cursor = [System.Windows.Forms.Cursors]::Hand })
    $BUTTON_BROWSE.Add_MouseLeave({ $this.Cursor = [System.Windows.Forms.Cursors]::Arrow })
    $BUTTON_BROWSE.Enabled = $false
    $BUTTON_BROWSE.Add_Click({ $TEXTBOX_ISO.Text = Open-IsoFile })

    $RadioButtonDrive.Location = New-Object System.Drawing.Point 250, 90
    $RadioButtonDrive.Size = New-Object System.Drawing.Size 280, 100
    $RadioButtonDrive.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $RadioButtonDrive.Font = New-Object System.Drawing.Font($MyFontFamily, 13.0, [System.Drawing.FontStyle]::Regular)
    $RadioButtonDrive.Text = "Use an already mounted drive:"
    $RadioButtonDrive.Add_Click({
        $MODE_SELECT = 2
        $TEXTBOX_ISO.Enabled = $false
        $COMBOBOX_DRIVE.Enabled = $true
        $BUTTON_BROWSE.Enabled = $false
        $BUTTON_SEARCH.Enabled = $true
    })
    $RadioButtonDrive.Add_MouseEnter({ $this.Cursor = [System.Windows.Forms.Cursors]::Hand })
    $RadioButtonDrive.Add_MouseLeave({ $this.Cursor = [System.Windows.Forms.Cursors]::Arrow })

    $COMBOBOX_DRIVE = New-Object System.Windows.Forms.ComboBox
    $COMBOBOX_DRIVE.Location = New-Object System.Drawing.Point 280, 170
    $COMBOBOX_DRIVE.Size = New-Object System.Drawing.Size 400, 45
    $COMBOBOX_DRIVE.ForeColor = [System.Drawing.Color]::Black
    $COMBOBOX_DRIVE.BackColor = [System.Drawing.Color]::WhiteSmoke
    $COMBOBOX_DRIVE.Font = New-Object System.Drawing.Font($MyFontFamily, 12.0, [System.Drawing.FontStyle]::Regular)
    $COMBOBOX_DRIVE.Items.AddRange($LIST_DRIVES)
    $COMBOBOX_DRIVE.SelectedIndex = 0
    $COMBOBOX_DRIVE.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $COMBOBOX_DRIVE.Add_MouseEnter({ $this.Cursor = [System.Windows.Forms.Cursors]::Hand })
    $COMBOBOX_DRIVE.Add_MouseLeave({ $this.Cursor = [System.Windows.Forms.Cursors]::Arrow })
    $COMBOBOX_DRIVE.Enabled = $false
    $RadioButtonDrive.Controls.Add($COMBOBOX_DRIVE)

    $LabelDrive = New-Object System.Windows.Forms.Label
    $LabelDrive.Text = "Drive:"
    $LabelDrive.Font = New-Object System.Drawing.Font($MyFontFamily, 12.0, [System.Drawing.FontStyle]::Regular)
    $LabelDrive.Location = New-Object System.Drawing.Point 190, 185
    $LabelDrive.Size = New-Object System.Drawing.Size 80, 20
    $LabelDrive.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight

    $BUTTON_SEARCH = New-Object System.Windows.Forms.Button
    $BUTTON_SEARCH.Location = New-Object System.Drawing.Point 700, 170
    $BUTTON_SEARCH.Size = New-Object System.Drawing.Size 80, 35
    $BUTTON_SEARCH.ForeColor = [System.Drawing.Color]::White
    $BUTTON_SEARCH.BackColor = [System.Drawing.Color]::FromArgb(0, 122, 204)
    $BUTTON_SEARCH.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $BUTTON_SEARCH.Font = New-Object System.Drawing.Font($MyFontFamily, 12.0, [System.Drawing.FontStyle]::Regular)
    $BUTTON_SEARCH.Text = "Auto-Detect"
    $BUTTON_SEARCH.Add_MouseEnter({ $this.Cursor = [System.Windows.Forms.Cursors]::Hand })
    $BUTTON_SEARCH.Add_MouseLeave({ $this.Cursor = [System.Windows.Forms.Cursors]::Arrow })
    $BUTTON_SEARCH.Enabled = $false
    $BUTTON_SEARCH.Add_Click({
        $autoDetected = Invoke-AutoDetect $LIST_DRIVES
        $COMBOBOX_DRIVE.SelectedIndex = $COMBOBOX_DRIVE.Items.IndexOf($autoDetected)
    })

    $SearchTip = New-Object System.Windows.Forms.ToolTip
    $TipText = "Automatically searches for a drive containing a Windows setup image and selects it in the list."
    $SearchTip.AutoPopDelay = 5000
    $SearchTip.InitialDelay = 1000
    $SearchTip.ReshowDelay = 500
    $SearchTip.SetToolTip($BUTTON_SEARCH, $TipText)

    $ButtonNext = New-Object System.Windows.Forms.Button
    $ButtonNext.Location = New-Object System.Drawing.Point 310, 500
    $ButtonNext.Size = New-Object System.Drawing.Size 150, 50
    $ButtonNext.ForeColor = [System.Drawing.Color]::White
    $ButtonNext.BackColor = [System.Drawing.Color]::FromArgb(0, 122, 204)
    $ButtonNext.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $ButtonNext.Font = New-Object System.Drawing.Font($MyFontFamily, 18.0, [System.Drawing.FontStyle]::Bold)
    $ButtonNext.Text = "Next"
    $ButtonNext.Add_MouseEnter({ $this.Cursor = [System.Windows.Forms.Cursors]::Hand })
    $ButtonNext.Add_MouseLeave({ $this.Cursor = [System.Windows.Forms.Cursors]::Arrow })
    $ButtonNext.Add_Click({ Validate-NextStep })

    $MountPanel.Controls.AddRange(@($LabelMountMode, $LabelPathToIso, $BUTTON_BROWSE, $LabelDrive, $BUTTON_SEARCH, $ButtonNext, $ModeGroupBox))
    return $MountPanel
}

#---------[ Stage 2: Image Index ]---------#

## UI for image index selection
function Invoke-ImageIndexMode {
    $MyFontFamily = New-Object System.Drawing.FontFamily "Segoe UI"

    $ImageIndexPanel = New-Object System.Windows.Forms.Panel
    $ImageIndexPanel.Location = New-Object System.Drawing.Point 0, 0
    $ImageIndexPanel.Size = New-Object System.Drawing.Size 800, 600
    $ImageIndexPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::None

    $LabelImageIndex = New-Object System.Windows.Forms.Label
    $LabelImageIndex.Text = "Select the Windows 11 edition:"
    $LabelImageIndex.Font = New-Object System.Drawing.Font($MyFontFamily, 16.0, [System.Drawing.FontStyle]::Bold)
    $LabelImageIndex.Location = New-Object System.Drawing.Point 0, 300
    $LabelImageIndex.Size = New-Object System.Drawing.Size 800, 50
    $LabelImageIndex.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter

    $COMBOBOX_INDEX = New-Object System.Windows.Forms.ComboBox
    $COMBOBOX_INDEX.Location = New-Object System.Drawing.Point 230, 395
    $COMBOBOX_INDEX.Size = New-Object System.Drawing.Size 320, 45
    $COMBOBOX_INDEX.ForeColor = [System.Drawing.Color]::Black
    $COMBOBOX_INDEX.BackColor = [System.Drawing.Color]::WhiteSmoke
    $COMBOBOX_INDEX.Font = New-Object System.Drawing.Font($MyFontFamily, 13.0, [System.Drawing.FontStyle]::Regular)
    $COMBOBOX_INDEX.Items.AddRange($LIST_EDITIONS)
    $COMBOBOX_INDEX.SelectedIndex = 0
    $COMBOBOX_INDEX.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $COMBOBOX_INDEX.Add_MouseEnter({ $this.Cursor = [System.Windows.Forms.Cursors]::Hand })
    $COMBOBOX_INDEX.Add_MouseLeave({ $this.Cursor = [System.Windows.Forms.Cursors]::Arrow })

    $ButtonCreate = New-Object System.Windows.Forms.Button
    $ButtonCreate.Location = New-Object System.Drawing.Point 260, 480
    $ButtonCreate.Size = New-Object System.Drawing.Size 250, 55
    $ButtonCreate.ForeColor = [System.Drawing.Color]::White
    $ButtonCreate.BackColor = [System.Drawing.Color]::FromArgb(0, 122, 204)
    $ButtonCreate.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $ButtonCreate.Font = New-Object System.Drawing.Font($MyFontFamily, 18.0, [System.Drawing.FontStyle]::Bold)
    $ButtonCreate.Text = "Create Tiny 11 ISO"
    $ButtonCreate.Add_MouseEnter({ $this.Cursor = [System.Windows.Forms.Cursors]::Hand })
    $ButtonCreate.Add_MouseLeave({ $this.Cursor = [System.Windows.Forms.Cursors]::Arrow })
    $ButtonCreate.Add_Click({ Validate-CreateTiny11 })

    $ImageIndexPanel.Controls.AddRange(@($LabelImageIndex, $COMBOBOX_INDEX, $ButtonCreate))
    return $ImageIndexPanel
}

Export-ModuleMember -Function Invoke-PopupInfo, Invoke-PopupError, Invoke-PopupYesOrNo,
    Open-IsoFile, Set-DrivesList, Set-EditionsList, Invoke-AutoDetect,
    Update-EventLoop, Get-ScreenStage, Get-ModeSelect, Get-IsoPath,
    Get-SelectedDrive, Get-SelectedImageIndex,
    Invoke-MainForm, Invoke-MountMode, Invoke-ImageIndexMode
