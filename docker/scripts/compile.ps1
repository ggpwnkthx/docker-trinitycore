param (
    [string]$Branch = "master",
    [string]$GitHubRepo = "TrinityCore/TrinityCore"
)

$Repo = Invoke-RestMethod -Method GET -Uri https://api.github.com/repos/$GitHubRepo
$Branches = Invoke-RestMethod -Method GET -Uri https://api.github.com/repos/$GitHubRepo/branches
$versions = [regex]::match($Repo.description, "[(].*[)]").Value
$versions.Substring(1, $versions.Length -2).Split(",") | Foreach-Object {
    $v = $_.Split("=")
    $Branches | Where-Object -Property "name" -EQ $v[0].Trim() | Add-Member -MemberType NoteProperty -Name "version" -Value $v[1].Trim()
}
$version = ($Branches | Where-Object -Property "name" -EQ $Branch).Version

# Create directories
@(
    "$PSScriptRoot/../../source/$version"
    "$PSScriptRoot/../../builds/$version/db/base"
    "$PSScriptRoot/../../clients/$version"
) | Foreach-Object {
    if (-not (Test-Path -Path $_)) {
        New-Item -Path $_ -ItemType Directory | Out-Null
    }
}

$DIR_Root = $PWD
$DIR_Source = Resolve-Path -Path "$PSScriptRoot/../../source/$version"
$DIR_Build = Resolve-Path -Path "$PSScriptRoot/../../builds/$version"
$DIR_Client = Resolve-Path -Path "$PSScriptRoot/../../clients/$version"

git clone -b $Branch $Repo.git_url $DIR_Source.Path
cd $DIR_Source.Path
git reset --hard
git pull

if ($Branch -eq "3.3.5") {
    git pull --recurse-submodules https://github.com/ElunaLuaEngine/ElunaTrinityWotlk.git;
    git submodule init;
    git submodule update;
    git remote add ElunaTrinityWotlk https://github.com/ElunaLuaEngine/ElunaTrinityWotlk.git;
}

cd $DIR_Root

Switch ([environment]::OSVersion.Platform) {
    "Win32NT" {
        cmake @("-G","Visual Studio 16 2019","-S",$DIR_Source.Path,"-B",$DIR_Build.Path,"-DSCRIPTS=dynamic")
        cmake @("--build",$DIR_Build.Path,"--config","Release")
    }
}