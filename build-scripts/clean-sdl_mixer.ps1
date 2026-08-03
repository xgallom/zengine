$RootDir = (Get-Item "$PSScriptRoot\..").FullName

Write-Host "Cleaning SDL3 Mixer"
Remove-Item -Recurse -Force -Path "$RootDir\external\SDL_mixer\build" -ErrorAction SilentlyContinue

