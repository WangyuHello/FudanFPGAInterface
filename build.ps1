[cmdletbinding()]
param(
   [switch]$useMagic
)

$dotnet_exe = "dotnet"
$npm_exe = "npm"

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

# ������ذ�װ��ʹ�ñ���
if (Test-Path $dotnet_install_path) {
    Write-Host "���ֱ��ذ�װ�� .NET Core: $dotnet_install_path"
    $local_dotnet_exist = $true
    $env:Path="$dotnet_install_path;"+$env:Path
    $env:DOTNET_ROOT=$dotnet_install_path
}

if (Test-Path $node_install_path) {
    if(Test-Path $node_dist_path) 
    {
        Write-Host "���ֱ��ذ�װ�� Nodejs: $node_dist_path"
        $local_npm_exist = $true
        if ($IsWindows) {
            $env:Path="$node_dist_path;"+$env:Path
        }
        else {
            $node_dist_path = Join-Path $node_dist_path "bin"
            $env:Path="$node_dist_path;"+$env:Path
        }
    }
}

try {
    $_ = Start-Process -FilePath $dotnet_exe -ArgumentList "--version" -NoNewWindow -PassThru -Wait
    $dotnet_exist = $true
    if (-not $local_dotnet_exist) {
        Write-Host "ʹ�� Path �� .NET Core"
    }
}
catch {}

try {
    $_ = Start-Process -FilePath $npm_exe -ArgumentList "-v" -NoNewWindow -PassThru -Wait
    $npm_exist = $true
    if (-not $local_npm_exist) {
        Write-Host "ʹ�� Path �� NodeJs"
    }
}
catch {}

if (-not $dotnet_exist) {
    Write-Host "δ���� .NET Core, �����а�װ"
    # ��װ dotnet
    $dotnet_install_url = "https://dot.net/v1/dotnet-install.ps1" # https://dot.net/v1/dotnet-install.sh
    $dotnet_install_file = Join-Path $tool_path "dotnet-install.ps1"
    if (-not (Test-Path -Path $tool_path)) {
        New-Item -Path $tool_path -ItemType Directory
    }
    if (-not (Test-Path -Path $dotnet_install_path)) {
        New-Item -Path $dotnet_install_path -ItemType Directory
    }
    Write-Host "�������� .NET Core ��װ�ű�"
    Invoke-WebRequest -Uri $dotnet_install_url -OutFile $dotnet_install_file

    Write-Host "���ڰ�װ .NET Core"
    Start-Process -FilePath "powershell" -ArgumentList $dotnet_install_file, "-Channel", "Current", "-Version", "Latest", "-InstallDir", $dotnet_install_path, "-NoPath" -NoNewWindow -Wait

    $env:Path="$dotnet_install_path;"+$env:Path
    $env:DOTNET_ROOT=$dotnet_install_path
}

if (-not $npm_exist) {
    Write-Host "δ���� NodeJs, �����а�װ"
    # ��װ nodejs
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
    $tuna_node_dist = "https://mirrors.tuna.tsinghua.edu.cn/nodejs-release/"
    $node_url = ""
    if ($useMagic) {
        $node_url = "$tuna_node_dist$VERSION/$node_arc";  
    } 
    else {
        $node_url = "$official_node_dist$VERSION/$node_arc";  
    }
    
    Write-Host "�������� $node_url"
    Invoke-WebRequest -Uri $node_url -OutFile $node_downloaded_file

    Write-Host "���ڽ�ѹ $node_arc"
    if ($IsWindows) {
        Expand-Archive -LiteralPath $node_downloaded_file -DestinationPath $node_install_path
        $env:Path="$node_dist_path;"+$env:Path
    }
    else {
        Start-Process -FilePath "tar" -ArgumentList "-xJvf", $node_downloaded_file, "-C", $node_install_path -NoNewWindow -Wait
        $node_dist_path = Join-Path $node_dist_path "bin"
        $env:Path="$node_dist_path;"+$env:Path
    }
}

$cake_file = Join-Path $tool_path "dotnet-cake"
if (Test-Path $cake_file) {
    Write-Host "���ֱ��ذ�װ�� Cake: $cake_file"
}
else {
    # ��װCake
    Start-Process "dotnet" -ArgumentList "tool", "install", "--tool-path", $tool_path, "Cake.Tool" -NoNewWindow -Wait
}

# ����Build
Start-Process $cake_file -ArgumentList "-useMagic=$useMagic" -NoNewWindow -Wait