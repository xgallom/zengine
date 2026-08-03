$RootDir = (Get-Item "$PSScriptRoot\..").FullName

Write-Host "Cleaning SDL3 Image"
Remove-Item -Recurse -Force -Path "$RootDir\external\SDL_image\build" -ErrorAction SilentlyContinue

