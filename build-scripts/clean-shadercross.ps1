$RootDir = (Get-Item "$PSScriptRoot\..").FullName

Write-Host "Cleaning SDL3 Shadercross"
Remove-Item -Recurse -Force -Path "$RootDir\external\SDL_shadercross\build" -ErrorAction SilentlyContinue

