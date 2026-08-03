param(
    [string]$Target = "Debug",
    [string]$CMakeArgs = "",
    [string]$MakeArgs = "",
    [string]$MakeInstallArgs = ""
)

$RootDir = (Get-Item "$PSScriptRoot\..").FullName

Set-Location $RootDir
git submodule update --init --recursive

Write-Host "`nBuilding target $Target"
Write-Host "cmake args:        `"$CMakeArgs`""
Write-Host "make args:         `"$MakeArgs`""
Write-Host "make install args: `"$MakeInstallArgs`"`n"

& "$RootDir\build-scripts\build-sdl.ps1" $Target $CMakeArgs $MakeArgs $MakeInstallArgs
& "$RootDir\build-scripts\build-sdl_image.ps1" $Target $CMakeArgs $MakeArgs $MakeInstallArgs
& "$RootDir\build-scripts\build-sdl_mixer.ps1" $Target $CMakeArgs $MakeArgs $MakeInstallArgs
& "$RootDir\build-scripts\build-sdl_ttf.ps1" $Target $CMakeArgs $MakeArgs $MakeInstallArgs
& "$RootDir\build-scripts\build-shadercross.ps1" $Target $CMakeArgs $MakeArgs $MakeInstallArgs
& "$RootDir\build-scripts\build-cimgui.ps1" $Target $CMakeArgs $MakeArgs $MakeInstallArgs
& "$RootDir\build-scripts\build-cimplot.ps1" $Target $CMakeArgs $MakeArgs $MakeInstallArgs
