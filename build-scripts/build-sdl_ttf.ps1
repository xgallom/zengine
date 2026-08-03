param(
    [string]$Target = "Debug",
    [string]$CMakeArgs = "",
    [string]$MakeArgs = "",
    [string]$MakeInstallArgs = ""
)

Write-Host "Building SDL3 TTF"
Write-Host "----------------------------------------------------------------------------------------------------`n"

$RootDir = (Get-Item "$PSScriptRoot\..").FullName

$SDir = $RootDir
$PDir = "$RootDir\external\SDL_ttf"
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
	-DCMAKE_FIND_PACKAGE_REDIRECTS_DIR=`"$IDIR\lib\cmake`" `
	-DCMAKE_POSITION_INDEPENDENT_CODE=ON `
	-DSDLTTF_VENDORED=ON `
	-DSDLTTF_HARFBUZZ=ON `
	-DSDLTTF_FREETYPE=ON `
	-DBUILD_SHARED_LIBS=ON `
	-DSDLTTF_BUILD_SHARED_LIBS=ON `
	-DSDLTTF_INSTALL=ON `
"

Invoke-Expression $cmakeConfigure
Invoke-Expression "cmake --build . -- $MakeArgs"
Invoke-Expression "cmake --install . $MakeInstallArgs"

Set-Location $SDir
Write-Host "`n"
