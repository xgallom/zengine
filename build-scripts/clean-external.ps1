$RootDir = (Get-Item "$PSScriptRoot\..").FullName

& "$RootDir\build-scripts\clean-cache.ps1"

Write-Host "`nCleaning external"
Remove-Item -Recurse -Force -Path "$RootDir\external\build" -ErrorAction SilentlyContinue

