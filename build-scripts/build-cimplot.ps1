param(
    [string]$Target = "Debug",
    [string]$CMakeArgs = "",
    [string]$MakeArgs = "",
    [string]$MakeInstallArgs = ""
)

Write-Host "Building cimplot"
Write-Host "----------------------------------------------------------------------------------------------------`n"

$RootDir = (Get-Item "$PSScriptRoot\..").FullName

$SDir = $RootDir
$PDir = "$RootDir\external\cimplot"
$BDir = "$RootDir\external\cimplot-build\build"
$IDir = "$RootDir\external\build"

New-Item -ItemType Directory -Force -Path $BDir | Out-Null
New-Item -ItemType Directory -Force -Path $IDir | Out-Null

Set-Location $PDir
git submodule update --init --recursive

Set-Location $BDir

$cmakeConfigure = "cmake .. $CMakeArgs `
    -DCMAKE_INSTALL_PREFIX=`"$IDir`" `
    -DCMAKE_BUILD_TYPE=$Target `
    -DCMAKE_FIND_PACKAGE_REDIRECTS_DIR=`"$IDir\lib\cmake`" `
    -DIMGUI_USER_CONFIG=`"$RootDir\external\cimgui\cimconfig.h`" `
"

Invoke-Expression $cmakeConfigure
Invoke-Expression "cmake --build . -- $MakeArgs"
Invoke-Expression "cmake --install . $MakeInstallArgs"

Set-Location $SDir
Write-Host "`n"
