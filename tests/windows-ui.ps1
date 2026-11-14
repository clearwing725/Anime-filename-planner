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

    $original = Join-Path $profile 'InuYasha 166-167.mkv'
    $renamed = Join-Path $profile $expected
    [System.IO.File]::WriteAllText($original, 'sample video contents')
    $rename = Find-NamedElement $window 'Rename files' ($types::Button)
    $rename.GetCurrentPattern($invokePattern).Invoke()
    $picker = Wait-For 'the file selection dialog' 10 {
        $window.FindFirst($scope::Descendants,
            (New-PropertyCondition ($automation::NameProperty) 'Select 1 file to rename'))
    }
    $picker.FindFirst($scope::Descendants, $editCondition).GetCurrentPattern($valuePattern).SetValue($original)
    (Find-NamedElement $picker 'Open' ($types::Button)).GetCurrentPattern($invokePattern).Invoke()
    $apply = Wait-For 'the rename preview' 10 { Find-NamedElement $window 'Apply renames' ($types::Button) }
    if (!(Test-Path -LiteralPath $original -PathType Leaf)) { throw 'Preview changed the original file.' }
    $apply.GetCurrentPattern($invokePattern).Invoke()
    Wait-For 'the renamed media file' 10 { Test-Path -LiteralPath $renamed -PathType Leaf } | Out-Null
    if ((Test-Path -LiteralPath $original) -or [System.IO.File]::ReadAllText($renamed) -cne 'sample video contents') {
        throw 'The original file was not renamed in place with its contents intact.'
    }
    Write-Output 'PASS: The Windows app renames a selected media file in place after preview.'
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
