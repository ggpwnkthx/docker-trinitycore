param (
    [string]$branch = "master",
    [string]$repo = "git://github.com/TrinityCore/TrinityCore.git"
)
if($branch -eq "master") {
    $version = "9.1.0"
} else {
    $version = $branch
}
$SQL_ROOT_PW = "trinity_root"

$SCRIPTROOT = "$PSScriptRoot/.."
$SOURCE_DIR = "source/$version"
$LOCAL_SOURCE_DIR = "$SCRIPTROOT\$SOURCE_DIR".Replace("/", "\")
$BUILD_DIR = "build/$version"
$LOCAL_BUILD_DIR = "$SCRIPTROOT\$BUILD_DIR".Replace("/", "\")
$CLIENT_DIR = "clients/$version"
$LOCAL_CLIENT_DIR = "$SCRIPTROOT\$CLIENT_DIR".Replace("/", "\")

# Build compiler container
echo "Building compiler environment image..."
cd $SCRIPTROOT
docker build -t trinitycore:windows -f .\docker\Dockerfile_windows .\docker\

# Create directories
if (-not (Test-Path -Path $LOCAL_SOURCE_DIR)) {
    New-Item -Path $SCRIPTROOT -Name "source" -ItemType Directory | Out-Null
    New-Item -Path $SCRIPTROOT/source -Name $version -ItemType Directory | Out-Null
}
if (-not (Test-Path -Path $LOCAL_BUILD_DIR)) {
    New-Item -Path $SCRIPTROOT -Name "build" -ItemType Directory | Out-Null
    New-Item -Path $SCRIPTROOT/build -Name $version -ItemType Directory | Out-Null
    New-Item -Path $SCRIPTROOT/build/$version -Name "bin" -ItemType Directory | Out-Null
    New-Item -Path $SCRIPTROOT/build/$version -Name "db" -ItemType Directory | Out-Null
    New-Item -Path $SCRIPTROOT/build/$version/db -Name "base" -ItemType Directory | Out-Null
}
if (-not (Test-Path -Path $LOCAL_CLIENT_DIR)) {
    New-Item -Path $SCRIPTROOT -Name "clients" -ItemType Directory | Out-Null
    New-Item -Path $SCRIPTROOT/clients -Name $version -ItemType Directory | Out-Null
}

# Download source code
docker run -it --rm `
    -v $LOCAL_SOURCE_DIR/:C:/TrinityCore/ `
    trinitycore:windows pwsh -c "
        git clone -b $branch $repo C:\TrinityCore;
        cd C:\trinitycore; 
        git pull;
    ".Replace("`r","")
if($version -eq "3.3.5") {
    # Download Eluna
    docker run -it --rm `
        -v $LOCAL_SOURCE_DIR/:C:/TrinityCore/ `
        trinitycore:windows pwsh -c "
            cd C:\TrinityCore;
            git pull --recurse-submodules https://github.com/ElunaLuaEngine/ElunaTrinityWotlk.git;
            git submodule init;
            git submodule update;
            git remote add ElunaTrinityWotlk https://github.com/ElunaLuaEngine/ElunaTrinityWotlk.git;
        ".Replace("`r","")
}

# Build
docker run -it --rm `
    -v $LOCAL_SOURCE_DIR/:C:/TrinityCore/ `
    -v $LOCAL_BUILD_DIR/:"C:/Program Files/TrinityCore/" `
    trinitycore:windows pwsh -c "
        & 'C:\Program Files\CMake\bin\cmake.exe' -G 'Visual Studio 16 2019' C:\TrinityCore\ -DCMAKE_INSTALL_PREFIX='C:\Program Files\TrinityCore' -DSCRIPTS=dynamic -DWITH_WARNINGS=1;
        & 'C:\Program Files\CMake\bin\cmake.exe' --build . --config Release;
        & 'C:\Program Files\CMake\bin\cmake.exe' --install . ;
    ".Replace("`r","")
