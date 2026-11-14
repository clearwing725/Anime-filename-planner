$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms

function New-PropertyCondition($property, $value) {
    return [System.Windows.Automation.PropertyCondition]::new($property, $value)
}

$automation = [System.Windows.Automation.AutomationElement]
$scope = [System.Windows.Automation.TreeScope]
$process = New-PropertyCondition ($automation::ProcessIdProperty) ([int]$env:PLANNER_TEST_PID)
$name = New-PropertyCondition ($automation::NameProperty) 'Save As'
$condition = [System.Windows.Automation.AndCondition]::new($process, $name)
$deadline = [DateTime]::UtcNow.AddSeconds(10)
do {
    $dialog = $automation::RootElement.FindFirst($scope::Children, $condition)
    if ($dialog) { break }
    Start-Sleep -Milliseconds 200
} while ([DateTime]::UtcNow -lt $deadline)
if (!$dialog) { throw 'The app did not open its Windows Save As dialog.' }

$type = [System.Windows.Automation.ControlType]
$editCondition = [System.Windows.Automation.AndCondition]::new(
    (New-PropertyCondition ($automation::AutomationIdProperty) '1001'),
    (New-PropertyCondition ($automation::ControlTypeProperty) ($type::Edit)))
$buttonCondition = [System.Windows.Automation.AndCondition]::new(
    (New-PropertyCondition ($automation::AutomationIdProperty) '1'),
    (New-PropertyCondition ($automation::ControlTypeProperty) ($type::Button)))
$filename = $dialog.FindFirst($scope::Descendants, $editCondition)
$saveButton = $dialog.FindFirst($scope::Descendants, $buttonCondition)
if ($filename -and $saveButton) {
    $filename.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($env:PLANNER_TEST_EXPORT)
    $saveButton.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    return
}

# Some common dialogs expose a different accessibility tree. Use the default filename selection.
$foreground = New-Object -ComObject WScript.Shell
if (!$foreground.AppActivate('Save As')) { throw 'Could not focus the Save As dialog.' }
if ($dialog.Current.ProcessId -ne [int]$env:PLANNER_TEST_PID) { throw 'The Save As dialog belongs to another app.' }
[System.Windows.Forms.Clipboard]::SetText($env:PLANNER_TEST_EXPORT)
[System.Windows.Forms.SendKeys]::SendWait('^a^v{ENTER}')
