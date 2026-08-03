$RootDir = (Get-Item "$PSScriptRoot\..").FullName

Write-Host "Cleaning SDL3 TTF"
Remove-Item -Recurse -Force -Path "$RootDir\external\SDL_ttf\build" -ErrorAction SilentlyContinue

