# Clear Yug POS Windows Cache
# This script removes the local Firestore data and cached Auth tokens to resolve "Permission Denied" errors.

$AppName = "yug_pos" # Update this if the AppData folder name is different
$Path = "$env:LOCALAPPDATA\$AppName"

if (Test-Path $Path) {
    Write-Host "Cleaning cache at $Path..." -ForegroundColor Yellow
    try {
        Remove-Item -Path "$Path\firestore" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$Path\shared_preferences.json" -Force -ErrorAction SilentlyContinue
        Write-Host "Successfully cleared local cache." -ForegroundColor Green
    } catch {
        Write-Host "Errors occurred while clearing some files. Please ensure the app is closed." -ForegroundColor Red
    }
} else {
    Write-Host "AppData path $Path not found. Please verify the application name." -ForegroundColor Cyan
}

Write-Host "Done. Please restart the Yug POS application." -ForegroundColor Green
