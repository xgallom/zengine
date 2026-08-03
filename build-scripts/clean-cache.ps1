$RootDir = (Get-Item "$PSScriptRoot\..").FullName

Write-Host "`nCleaning cache"
& "$RootDir\build-scripts\clean-sdl.ps1"
& "$RootDir\build-scripts\clean-shadercross.ps1"
& "$RootDir\build-scripts\clean-sdl_image.ps1"
& "$RootDir\build-scripts\clean-sdl_mixer.ps1"
& "$RootDir\build-scripts\clean-sdl_ttf.ps1"
& "$RootDir\build-scripts\clean-cimgui.ps1"
& "$RootDir\build-scripts\clean-cimplot.ps1"

