﻿[CmdletBinding()]
Param(
    [string]$Script = "build.cake",
    [switch]$useMagic,
    [string]$Target,
    [string]$Configuration,
    [ValidateSet("Quiet", "Minimal", "Normal", "Verbose", "Diagnostic")]
    [string]$Verbosity,
    [switch]$ShowDescription,
    [Alias("WhatIf", "Noop")]
    [switch]$DryRun,
    [switch]$SkipToolPackageRestore,
    [Parameter(Position=0,Mandatory=$false,ValueFromRemainingArguments=$true)]
    [string[]]$ScriptArgs
)

# Attempt to set highest encryption available for SecurityProtocol.
# PowerShell will not set this by default (until maybe .NET 4.6.x). This
# will typically produce a message for PowerShell v2 (just an info
# message though)
try {
    # Set TLS 1.2 (3072), then TLS 1.1 (768), then TLS 1.0 (192), finally SSL 3.0 (48)
    # Use integers because the enumeration values for TLS 1.2 and TLS 1.1 won't
    # exist in .NET 4.0, even though they are addressable if .NET 4.5+ is
    # installed (.NET 4.5 is an in-place upgrade).
    # PowerShell Core already has support for TLS 1.2 so we can skip this if running in that.
    if (-not $IsCoreCLR) {
        [System.Net.ServicePointManager]::SecurityProtocol = 3072 -bor 768 -bor 192 -bor 48
    }
} catch {
    Write-Output 'Unable to set PowerShell to use TLS 1.2 and TLS 1.1 due to old .NET Framework installed. If you see underlying connection closed or trust errors, you may need to upgrade to .NET Framework 4.5+ and PowerShell v3'
}

[Reflection.Assembly]::LoadWithPartialName("System.Security") | Out-Null

function MD5HashFile([string] $filePath)
{
    if ([string]::IsNullOrEmpty($filePath) -or !(Test-Path $filePath -PathType Leaf))
    {
        return $null
    }

    [System.IO.Stream] $file = $null;
    [System.Security.Cryptography.MD5] $md5 = $null;
    try
    {
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $file = [System.IO.File]::OpenRead($filePath)
        return [System.BitConverter]::ToString($md5.ComputeHash($file))
    }
    finally
    {
        if ($null -ne $file)
        {
            $file.Dispose()
        }
    }
}

function GetProxyEnabledWebClient
{
    $wc = New-Object System.Net.WebClient
    $proxy = [System.Net.WebRequest]::GetSystemWebProxy()
    $proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
    $wc.Proxy = $proxy
    return $wc
}

if(!$PSScriptRoot){
    $PSScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}

$dotnet_exe = "dotnet"
$npm_exe = "npm"

if ((-not $IsCoreCLR) -or $IsWindows) {
    $dotnet_exe = "$dotnet_exe.exe"
}

$tool_path = Join-Path $PSScriptRoot "tools"
$dotnet_install_path = Join-Path $tool_path "dotnet"
$node_install_path = Join-Path $tool_path "node"
$VERSION = "v13.12.0"
$DISTRO = "win-x64"
if ($IsMacOS) {
    $DISTRO = "darwin-x64"
}
elseif ($IsLinux) {
    $DISTRO = "linux-x64"
}
$node_dist = "node-$VERSION-$DISTRO"
$node_dist_path = Join-Path $node_install_path $node_dist

$dotnet_exist = $false
$local_dotnet_exist = $false
$npm_exist = $false
$local_npm_exist = $false

# 如果本地安装则使用本地
if ((Test-Path $dotnet_install_path) -and (Test-Path (Join-Path $dotnet_install_path $dotnet_exe))) {
    Write-Host "发现本地安装的 .NET Core: $dotnet_install_path" -ForegroundColor "Green"
    $local_dotnet_exist = $true
    $env:Path="$dotnet_install_path;"+$env:Path
    $env:DOTNET_ROOT=$dotnet_install_path
}

if (Test-Path $node_install_path) {
    if(Test-Path $node_dist_path) 
    {
        $has_bin = if ((-not $IsCoreCLR) -or $IsWindows) {
            Test-Path (Join-Path $node_dist_path "npm.cmd")
        }
        else {
            Test-Path (Join-Path $node_dist_path "bin" "npm")
        }

        if ($has_bin) {
            Write-Host "发现本地安装的 Nodejs: $node_dist_path" -ForegroundColor "Green"
            $local_npm_exist = $true
            if ((-not $IsCoreCLR) -or $IsWindows) {
                $env:Path="$node_dist_path;"+$env:Path
            }
            else {
                $node_dist_path = Join-Path $node_dist_path "bin"
                $env:Path="$node_dist_path;"+$env:Path
            }
        }
    }
}

try {
    Invoke-Expression "$dotnet_exe --version" | Out-Null
    $dotnet_exist = $true
    if (-not $local_dotnet_exist) {
        Write-Host "使用 Path 的 .NET Core" -ForegroundColor "Green"
    }
}
catch {
    
}

try {
    Invoke-Expression "$npm_exe -v" | Out-Null
    $npm_exist = $true
    if (-not $local_npm_exist) {
        Write-Host "使用 Path 的 NodeJs" -ForegroundColor "Green"
    }
}
catch {
    
}

if (-not $dotnet_exist) {
    Write-Host "未发现 .NET Core, 将进行安装" -ForegroundColor "Yellow"
    # 安装 dotnet
    $dotnet_install_url = "https://dot.net/v1/dotnet-install.ps1" # https://dot.net/v1/dotnet-install.sh
    $dotnet_install_file = Join-Path $tool_path "dotnet-install.ps1"
    if (-not (Test-Path -Path $tool_path)) {
        New-Item -Path $tool_path -ItemType Directory | Out-Null
    }
    if (-not (Test-Path -Path $dotnet_install_path)) {
        New-Item -Path $dotnet_install_path -ItemType Directory | Out-Null
    }
    Write-Host "正在下载 .NET Core 安装脚本"
    $wc = GetProxyEnabledWebClient
    $wc.DownloadFile($dotnet_install_url, $dotnet_install_file)
    # Invoke-WebRequest -Uri $dotnet_install_url -OutFile $dotnet_install_file

    Write-Host "正在安装 .NET Core"
    Invoke-Expression "$dotnet_install_file -Channel Current -Version Latest -InstallDir $dotnet_install_path -NoPath"
    
    if ($LASTEXITCODE -ne 0) {
        Throw "An error occurred while installing .NET Core."
    }

    $env:Path="$dotnet_install_path;"+$env:Path
    $env:DOTNET_ROOT=$dotnet_install_path
}

if (-not $npm_exist) {
    Write-Host "未发现 NodeJs, 将进行安装" -ForegroundColor "Yellow"
    # 安装 nodejs
    $node_ext = "zip"
    if ($IsMacOS) {
        $node_ext = "tar.xz"
    }
    elseif ($IsLinux) {
        $node_ext = "tar.xz"
    }

    $node_arc = "$node_dist.$node_ext"
    $node_downloaded_file = Join-Path $tool_path $node_arc

    $official_node_dist = "https://nodejs.org/dist/"
    $taobao_node_dist = "https://npm.taobao.org/mirrors/node/"
    $node_url = ""
    if ($useMagic) {
        $node_url = "$taobao_node_dist$VERSION/$node_arc";  
    } 
    else {
        $node_url = "$official_node_dist$VERSION/$node_arc";  
    }
    
    Write-Host "正在下载 $node_url"
    $wc = GetProxyEnabledWebClient
    $wc.DownloadFile($node_url, $node_downloaded_file)
    # Invoke-WebRequest -Uri $node_url -OutFile $node_downloaded_file

    Write-Host "正在解压 $node_arc"
    if ((-not $IsCoreCLR) -or $IsWindows) {
        Expand-Archive -LiteralPath $node_downloaded_file -DestinationPath $node_install_path
        $env:Path="$node_dist_path;"+$env:Path
    }
    else {
        Invoke-Expression "tar -xJvf $node_downloaded_file -C $node_install_path"
        if ($LASTEXITCODE -ne 0) {
            Throw "An error occurred while installing NodeJs"
        }
        $node_dist_path = Join-Path $node_dist_path "bin"
        $env:Path="$node_dist_path;"+$env:Path
    }
}

$cake_bin = "dotnet-cake"
if ((-not $IsCoreCLR) -or $IsWindows) {
    $cake_bin = "$cake_bin.exe"
}
$cake_exe = Join-Path $tool_path $cake_bin

Write-Host "正在安装Cake"
Invoke-Expression "$dotnet_exe tool install --tool-path $tool_path Cake.Tool" | Out-Null

$cakeArguments = @()
if ($Script) { $cakeArguments += "`"$Script`"" }
if ($Target) { $cakeArguments += "-target=`"$Target`"" }
if ($Configuration) { $cakeArguments += "-configuration=$Configuration" }
if ($Verbosity) { $cakeArguments += "-verbosity=$Verbosity" }
if ($ShowDescription) { $cakeArguments += "-showdescription" }
if ($DryRun) { $cakeArguments += "-dryrun" }
$cakeArguments += "-useMagic=$useMagic"
$cakeArguments += $ScriptArgs

# 运行Build
Write-Host "开始构建"
Invoke-Expression "$cake_exe $($cakeArguments -join " ")"
exit $LASTEXITCODE