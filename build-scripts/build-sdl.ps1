param(
    [string]$Target = "Debug",
    [string]$CMakeArgs = "",
    [string]$MakeArgs = "",
    [string]$MakeInstallArgs = ""
)

Write-Host "Building SDL3"
Write-Host "----------------------------------------------------------------------------------------------------`n"

$RootDir = (Get-Item "$PSScriptRoot\..").FullName

$SDir = $RootDir
$PDir = "$RootDir\external\SDL"
$BDir = "$PDir\build"
$IDir = "$RootDir\external\build"

New-Item -ItemType Directory -Force -Path $BDir | Out-Null
New-Item -ItemType Directory -Force -Path $IDir | Out-Null

Set-Location $PDir
git submodule update --init --recursive

Set-Location $BDir

$cmakeConfigure = "cmake .. $CMakeArgs `
    -DCMAKE_INSTALL_PREFIX=`"$IDir`" `
    -DCMAKE_BUILD_TYPE=$Target `
	-DCMAKE_POSITION_INDEPENDENT_CODE=ON `
    -DCMAKE_OSX_ARCHITECTURES=`"x86_64;arm64`" `
    -DSDL_VULKAN=ON -DSDL_RENDER_VULKAN=ON `
	-DSDL_TEST_LIBRARY=OFF

Invoke-Expression $cmakeConfigure
Invoke-Expression "cmake --build . -- $MakeArgs"
Invoke-Expression "cmake --install . $MakeInstallArgs"

Set-Location $SDir
Write-Host "`n"
