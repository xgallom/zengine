$RootDir = (Get-Item "$PSScriptRoot\..").FullName

Write-Host "Cleaning cimgui"
Remove-Item -Recurse -Force -Path "$RootDir\external\cimgui-build\build" -ErrorAction SilentlyContinue

