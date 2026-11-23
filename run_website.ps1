# Starts the Naggiar website on this computer and opens it in the browser.
Set-Location -Path $PSScriptRoot

$python = $null
foreach ($cmd in @("py", "python")) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) { $python = $cmd; break }
}
if (-not $python) {
    Write-Host "Python is not installed. Get it from https://www.python.org/downloads/" -ForegroundColor Red
    Write-Host "During setup, tick 'Add python.exe to PATH', then run this again."
    Read-Host "Press Enter to close"
    exit 1
}

Write-Host "Installing Flask (first time only)..." -ForegroundColor Cyan
& $python -m pip install --quiet flask

Write-Host "Starting the website at http://127.0.0.1:5000  (close this window to stop it)" -ForegroundColor Green
Start-Job { Start-Sleep 3; Start-Process "http://127.0.0.1:5000" } | Out-Null
& $python app.py
