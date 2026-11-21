param([Parameter(Mandatory)][string]$Executable)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms

$automation = [System.Windows.Automation.AutomationElement]
$scope = [System.Windows.Automation.TreeScope]
$types = [System.Windows.Automation.ControlType]
$invokePattern = [System.Windows.Automation.InvokePattern]::Pattern
$valuePattern = [System.Windows.Automation.ValuePattern]::Pattern

function New-PropertyCondition($property, $value) {
    [System.Windows.Automation.PropertyCondition]::new($property, $value)
}

function Wait-For([string]$description, [int]$seconds, [scriptblock]$query) {
    $deadline = [DateTime]::UtcNow.AddSeconds($seconds)
    do {
        try {
            $result = & $query
            if ($result) { return $result }
        } catch [System.Windows.Automation.ElementNotAvailableException] { }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Timed out waiting for $description."
}

function Find-NamedElement($window, [string]$name, $controlType) {
    $condition = [System.Windows.Automation.AndCondition]::new(
        (New-PropertyCondition ($automation::NameProperty) $name),
        (New-PropertyCondition ($automation::ControlTypeProperty) $controlType))
    $window.FindFirst($scope::Descendants, $condition)
}

$expected = 'InuYasha (2000) - S06E28-E29.mkv'
$profile = Join-Path ([System.IO.Path]::GetTempPath()) ('anime-planner-test-' + [guid]::NewGuid().ToString('N'))
[System.IO.Directory]::CreateDirectory($profile) | Out-Null
$destination = Join-Path $profile 'anime-filenames.txt'
$env:WEBVIEW2_USER_DATA_FOLDER = Join-Path $profile 'webview'
$env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = '--force-renderer-accessibility'
$clipboardSaved = $false
try {
    $previousClipboard = [System.Windows.Forms.Clipboard]::GetDataObject()
    $clipboardSaved = $true
    $app = Start-Process -FilePath $Executable -WorkingDirectory (Split-Path $Executable) -PassThru
    $window = Wait-For 'the main planner window' 20 {
        $app.Refresh()
        if ($app.HasExited) { throw "The planner exited with code $($app.ExitCode)." }
        if ($app.MainWindowHandle -ne [IntPtr]::Zero -and $app.MainWindowTitle -eq 'Anime Filename Planner') {
            $automation::FromHandle($app.MainWindowHandle)
        }
    }
    $copy = Wait-For 'the Copy list button' 18 {
        $button = Find-NamedElement $window 'Copy list' ($types::Button)
        if ($button -and $button.Current.IsEnabled) { $button }
    }
    Write-Output 'PASS: The Windows executable opens and loads the planner.'

    [System.Windows.Forms.Clipboard]::SetText('Waiting for Anime Filename Planner')
    $copy.GetCurrentPattern($invokePattern).Invoke()
    Wait-For 'the expected filename on the Windows clipboard' 8 {
        try { [System.Windows.Forms.Clipboard]::GetText() -ceq $expected }
        catch [System.Runtime.InteropServices.ExternalException] { $false }
    } | Out-Null
    Write-Output 'PASS: The native clipboard contains InuYasha (2000) - S06E28-E29.mkv.'

    $download = Find-NamedElement $window 'Download .txt' ($types::Button)
    if (!$download) { throw 'The Download .txt button is missing.' }
    $download.GetCurrentPattern($invokePattern).Invoke()
    $dialogCondition = New-PropertyCondition ($automation::NameProperty) 'Save As'
    $dialog = Wait-For 'the Windows Save As dialog' 10 {
        $window.FindFirst($scope::Descendants, $dialogCondition)
    }
    $editCondition = [System.Windows.Automation.AndCondition]::new(
        (New-PropertyCondition ($automation::AutomationIdProperty) '1001'),
        (New-PropertyCondition ($automation::ControlTypeProperty) ($types::Edit)))
    $edit = $dialog.FindFirst($scope::Descendants, $editCondition)
    $save = Find-NamedElement $dialog 'Save' ($types::Button)
    if ($edit -and $save) {
        $edit.GetCurrentPattern($valuePattern).SetValue($destination)
        $save.GetCurrentPattern($invokePattern).Invoke()
    } else {
        $foreground = New-Object -ComObject WScript.Shell
        if (!$foreground.AppActivate('Save As')) { throw 'Could not focus the Save As dialog.' }
        [System.Windows.Forms.Clipboard]::SetText($destination)
        [System.Windows.Forms.SendKeys]::SendWait('^a^v{ENTER}')
    }
    Wait-For 'the exported text file' 10 { Test-Path -LiteralPath $destination -PathType Leaf } | Out-Null
    if ([System.IO.File]::ReadAllText($destination) -cne $expected) { throw 'The exported filename was incorrect.' }
    Write-Output 'PASS: The native Windows Save dialog writes the expected text.'

    $range = Find-NamedElement $window 'Episode range' ($types::Edit)
    if (!$range) { throw 'The Episode range field is missing.' }
    $range.SetFocus()
    [System.Windows.Forms.Clipboard]::SetText('165-167')
    [System.Windows.Forms.SendKeys]::SendWait('^a^v')
    Wait-For 'two generated filenames' 10 {
        $window.FindFirst($scope::Descendants, (New-PropertyCondition ($automation::NameProperty) '2 files'))
    } | Out-Null

    $first = Join-Path $profile 'Source 1.mkv'
    $second = Join-Path $profile 'Source 2.mkv'
    $single = Join-Path $profile 'InuYasha (2000) - S06E27.mkv'
    $combined = Join-Path $profile $expected
    [System.IO.File]::WriteAllText($first, 'combined video contents')
    [System.IO.File]::WriteAllText($second, 'single video contents')
    $selection = '"{0}" "{1}"' -f $first, $second
    $rename = Find-NamedElement $window 'Rename files' ($types::Button)
    $rename.GetCurrentPattern($invokePattern).Invoke()
    $picker = Wait-For 'the file selection dialog' 10 {
        $window.FindFirst($scope::Descendants,
            (New-PropertyCondition ($automation::NameProperty) 'Select 2 files to rename'))
    }
    $openEdit = Find-NamedElement $picker 'File name:' ($types::Edit)
    $open = Find-NamedElement $picker 'Open' ($types::Button)
    if ($openEdit -and $open) {
        $openEdit.GetCurrentPattern($valuePattern).SetValue($selection)
        $open.GetCurrentPattern($invokePattern).Invoke()
    } else {
        $foreground = New-Object -ComObject WScript.Shell
        if (!$foreground.AppActivate('Select 2 files to rename')) { throw 'Could not focus the file picker.' }
        [System.Windows.Forms.Clipboard]::SetText($selection)
        [System.Windows.Forms.SendKeys]::SendWait('%n^a^v{ENTER}')
    }
    $down = Wait-For 'the enabled Move file down button' 10 {
        $button = Find-NamedElement $window 'Move file down' ($types::Button)
        if ($button -and $button.Current.IsEnabled) { $button }
    }
    if (!(Test-Path -LiteralPath $first) -or !(Test-Path -LiteralPath $second)) {
        throw 'Preview changed the original files.'
    }
    $down.GetCurrentPattern($invokePattern).Invoke()
    Wait-For 'the enabled Move file up button' 10 {
        $button = Find-NamedElement $window 'Move file up' ($types::Button)
        if ($button -and $button.Current.IsEnabled) { $button }
    } | Out-Null
    $apply = Find-NamedElement $window 'Apply renames' ($types::Button)
    $apply.GetCurrentPattern($invokePattern).Invoke()
    Wait-For 'both renamed media files' 10 {
        (Test-Path -LiteralPath $single -PathType Leaf) -and (Test-Path -LiteralPath $combined -PathType Leaf)
    } | Out-Null
    if ((Test-Path -LiteralPath $first) -or (Test-Path -LiteralPath $second) -or
        [System.IO.File]::ReadAllText($single) -cne 'single video contents' -or
        [System.IO.File]::ReadAllText($combined) -cne 'combined video contents') {
        throw 'The reordered files were not renamed to the intended episodes.'
    }
    Write-Output 'PASS: The Windows app applies the reordered episode assignments.'
} catch {
    if ($window) {
        $window.FindAll($scope::Subtree, [System.Windows.Automation.Condition]::TrueCondition) |
            ForEach-Object { $_.Current.Name } | Where-Object { $_ } | Select-Object -First 35
    }
    throw
} finally {
    if ($app -and !$app.HasExited) {
        $null = & taskkill.exe /PID $app.Id /T /F 2>$null
    }
    if ($clipboardSaved) {
        try {
            if ($previousClipboard) { [System.Windows.Forms.Clipboard]::SetDataObject($previousClipboard, $true) }
            else { [System.Windows.Forms.Clipboard]::Clear() }
        } catch [System.Runtime.InteropServices.ExternalException] { }
    }
    Remove-Item -LiteralPath $profile -Recurse -Force -ErrorAction SilentlyContinue
}
