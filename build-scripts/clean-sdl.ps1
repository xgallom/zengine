$RootDir = (Get-Item "$PSScriptRoot\..").FullName

Write-Host "Cleaning SDL3"
Remove-Item -Recurse -Force -Path "$RootDir\external\SDL\build" -ErrorAction SilentlyContinue

