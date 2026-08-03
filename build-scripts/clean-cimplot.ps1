$RootDir = (Get-Item "$PSScriptRoot\..").FullName

Write-Host "Cleaning cimplot"
Remove-Item -Recurse -Force -Path "$RootDir\external\cimplot-build\build" -ErrorAction SilentlyContinue

