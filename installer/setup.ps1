<#
.SYNOPSIS
    B&G Network Dashboard post-install setup script.
    Called by the Inno Setup installer after binaries are extracted.

.PARAMETER AppDir
    Path where config files were installed (e.g. C:\bg-network-dashboard).
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$AppDir,
    [switch]$InstallNSSM,
    [switch]$InstallWireshark
)

# Log file path (launch.cmd already wrote the startup marker)
$logFile = "C:\bg-dashboard-install.log"

$ErrorActionPreference = "Stop"

# Force TLS 1.2  -  required for downloads on some Windows builds
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Start-Transcript -Path $logFile -Append -Force
Write-Host "=== B&G Dashboard Setup Log: $(Get-Date) ===" -ForegroundColor Yellow
Write-Host "AppDir: $AppDir"
Write-Host "PowerShell version: $($PSVersionTable.PSVersion)"
Write-Host "Is Admin: $([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "=== $Message ===" -ForegroundColor Cyan
}

function Wait-ForService {
    param(
        [string]$ServiceName,
        [int]$TimeoutSeconds = 60
    )
    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq "Running") {
            Write-Host "  Service '$ServiceName' is running."
            return $true
        }
        Start-Sleep -Seconds 2
        $elapsed += 2
    }
    throw "Service '$ServiceName' did not start within $TimeoutSeconds seconds."
}

function Wait-ForUrl {
    param(
        [string]$Url,
        [int]$TimeoutSeconds = 120
    )
    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5
            if ($response.StatusCode -eq 200) {
                Write-Host "  $Url is responding."
                return $true
            }
        } catch {
            # Not ready yet
        }
        Start-Sleep -Seconds 3
        $elapsed += 3
    }
    throw "$Url did not respond within $TimeoutSeconds seconds."
}

function Invoke-GrafanaApi {
    param(
        [string]$Method,
        [string]$Path,
        [string]$Body = $null,
        [string]$User = "marcuswunderlich",
        [string]$Password = "sunfast3300",
        [int]$MaxRetries = 5
    )
    $url = "http://localhost:3001$Path"
    $pair = "${User}:${Password}"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
    $base64 = [System.Convert]::ToBase64String($bytes)
    $headers = @{
        "Authorization" = "Basic $base64"
        "Content-Type"  = "application/json"
    }

    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        try {
            $params = @{
                Uri             = $url
                Method          = $Method
                Headers         = $headers
                UseBasicParsing = $true
            }
            if ($Body) {
                $params["Body"] = $Body
            }
            $response = Invoke-RestMethod @params
            return $response
        } catch {
            $attempt++
            if ($attempt -ge $MaxRetries) {
                Write-Host "  WARNING: Grafana API call failed after $MaxRetries attempts: $Path" -ForegroundColor Yellow
                Write-Host "  Error: $_" -ForegroundColor Yellow
                return $null
            }
            $wait = [math]::Pow(2, $attempt)
            Write-Host "  Grafana API not ready, retrying in ${wait}s... (attempt $attempt/$MaxRetries)"
            Start-Sleep -Seconds $wait
        }
    }
}

# ============================================================
# Download helpers
# ============================================================
function Get-Download {
    param([string]$Url, [string]$Dest)
    Write-Host "  Downloading $(Split-Path $Url -Leaf)..."
    Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing
}

function Install-Msi {
    param([string]$MsiPath, [string]$Description)
    Write-Host "  Installing $Description..."
    $proc = Start-Process msiexec.exe -ArgumentList "/i `"$MsiPath`" /qn /norestart" -Wait -PassThru
    if ($proc.ExitCode -notin @(0, 3010)) {
        throw "$Description installer exited with code $($proc.ExitCode)"
    }
    Write-Host "  $Description installed."
}

$TmpDir = $env:TEMP

try {

# ============================================================
# Phase 0: Download and install dependencies
# ============================================================

Write-Step "Phase 0: Installing Node.js 20 LTS"
try {
    $nodeVersion = & node --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Node.js already installed: $nodeVersion"
    } else {
        throw "not found"
    }
} catch {
    $nodeMsi = Join-Path $TmpDir "node-v20.19.0-x64.msi"
    Get-Download "https://nodejs.org/dist/v20.19.0/node-v20.19.0-x64.msi" $nodeMsi
    Install-Msi $nodeMsi "Node.js 20 LTS"
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

Write-Step "Phase 0: Installing InfluxDB 2.x"
$influxDir = "C:\Program Files\InfluxData\influxdb"
$influxDataDir = "C:\ProgramData\InfluxDB"
try {
    # Download and extract server (influxd.exe) if not present
    if (-not (Test-Path "$influxDir\influxd.exe")) {
        $influxZip = Join-Path $TmpDir "influxdb2-windows.zip"
        Get-Download "https://dl.influxdata.com/influxdb/releases/influxdb2-2.7.6-windows.zip" $influxZip
        New-Item -ItemType Directory -Path $influxDir -Force | Out-Null
        Expand-Archive -Path $influxZip -DestinationPath $influxDir -Force
        Get-ChildItem "$influxDir\influxdb2-*" -Directory | ForEach-Object {
            Get-ChildItem $_.FullName | Move-Item -Destination $influxDir -Force
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        }
        Write-Host "  InfluxDB server extracted to $influxDir."
    } else {
        Write-Host "  InfluxDB server already present."
    }

    # Download CLI (influx.exe) separately - shipped independently from server in 2.7+
    if (-not (Test-Path "$influxDir\influx.exe")) {
        $influxCliZip = Join-Path $TmpDir "influxdb2-client-windows.zip"
        Get-Download "https://dl.influxdata.com/influxdb/releases/influxdb2-client-2.7.5-windows-amd64.zip" $influxCliZip
        $influxCliTmp = Join-Path $TmpDir "influxdb2-client-extracted"
        Expand-Archive -Path $influxCliZip -DestinationPath $influxCliTmp -Force
        Get-ChildItem $influxCliTmp -Recurse -Filter "influx.exe" | Select-Object -First 1 | Move-Item -Destination $influxDir -Force
        Remove-Item $influxCliTmp -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  InfluxDB CLI extracted to $influxDir."
    } else {
        Write-Host "  InfluxDB CLI already present."
    }

    # Add to machine PATH if not there, and always refresh current session PATH
    $mp = [System.Environment]::GetEnvironmentVariable("Path","Machine")
    if ($mp -notlike "*InfluxData\influxdb*") {
        [System.Environment]::SetEnvironmentVariable("Path","$mp;$influxDir","Machine")
    }
    # Always refresh session PATH so influx.exe is callable in this run
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

    New-Item -ItemType Directory -Path $influxDataDir -Force | Out-Null
    # Service registration happens after NSSM is installed (influxd is not service-aware)
} catch {
    Write-Host "  ERROR installing InfluxDB: $_" -ForegroundColor Red
    throw
}

Write-Step "Phase 0: Installing Grafana"
try {
    if (Get-Service Grafana -ErrorAction SilentlyContinue) {
        Write-Host "  Grafana service already present."
    } else {
        $grafanaMsi = Join-Path $TmpDir "grafana-11.6.0.msi"
        Get-Download "https://dl.grafana.com/oss/release/grafana-11.6.0.windows-amd64.msi" $grafanaMsi
        Install-Msi $grafanaMsi "Grafana"
        # Write custom.ini to override port  -  always takes precedence over defaults.ini
        $grafanaCustomIni = "C:\Program Files\GrafanaLabs\grafana\conf\custom.ini"
        "[server]`nhttp_port = 3001`nhttp_addr = 0.0.0.0" | Set-Content $grafanaCustomIni
        Write-Host "  Grafana custom.ini written (port 3001, bind 0.0.0.0)."
        # Detect service name  -  Grafana installer uses different names across versions
        $grafanaSvcName = @("GrafanaLabs.Grafana","Grafana") | Where-Object { Get-Service $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
        if ($grafanaSvcName) { Start-Service $grafanaSvcName -ErrorAction SilentlyContinue }
        Write-Host "  Grafana installed on port 3001."
    }
} catch {
    Write-Host "  ERROR installing Grafana: $_" -ForegroundColor Red
    throw
}

Write-Step "Phase 0: Installing Telegraf"
try {
    if (Get-Service telegraf -ErrorAction SilentlyContinue) {
        Write-Host "  Telegraf service already present."
    } else {
        $telegrafZip = Join-Path $TmpDir "telegraf-windows.zip"
        Get-Download "https://dl.influxdata.com/telegraf/releases/telegraf-1.33.0_windows_amd64.zip" $telegrafZip
        $telegrafDir = "C:\telegraf"
        New-Item -ItemType Directory -Path $telegrafDir -Force | Out-Null
        Expand-Archive -Path $telegrafZip -DestinationPath $telegrafDir -Force
        # Move contents out of versioned subfolder
        Get-ChildItem "$telegrafDir\telegraf-*" -Directory | ForEach-Object {
            Get-ChildItem $_.FullName | Move-Item -Destination $telegrafDir -Force
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        }
        Write-Host "  Telegraf extracted to $telegrafDir."
    }
} catch {
    Write-Host "  ERROR installing Telegraf: $_" -ForegroundColor Red
    throw
}

if ($InstallNSSM) {
    Write-Step "Phase 0: Installing NSSM"
    try {
        $nssmExe = "C:\nssm\nssm.exe"
        if (Test-Path $nssmExe) {
            Write-Host "  NSSM already installed."
        } else {
            $nssmZip = Join-Path $TmpDir "nssm-2.24.zip"
            $nssmDir = "C:\nssm"
            $nssmDownloaded = $false
            # Try nssm.cc first, fall back to Chocolatey
            try {
                Get-Download "https://nssm.cc/release/nssm-2.24.zip" $nssmZip
                $nssmDownloaded = $true
            } catch {
                Write-Host "  nssm.cc unavailable, trying Chocolatey..."
                try {
                    & choco install nssm -y --no-progress 2>&1 | Out-Null
                    $chocoNssm = "C:\ProgramData\chocolatey\bin\nssm.exe"
                    if (Test-Path $chocoNssm) {
                        New-Item -ItemType Directory -Path $nssmDir -Force | Out-Null
                        Copy-Item $chocoNssm "$nssmDir\nssm.exe" -Force
                        Write-Host "  NSSM installed via Chocolatey."
                    }
                } catch {
                    Write-Host "  WARNING: Could not install NSSM via Chocolatey either: $_" -ForegroundColor Yellow
                }
            }
            if ($nssmDownloaded) {
                New-Item -ItemType Directory -Path $nssmDir -Force | Out-Null
                Expand-Archive -Path $nssmZip -DestinationPath $nssmDir -Force
                # Move win64 binary to C:\nssm\
                Get-ChildItem "$nssmDir\nssm-*\win64\nssm.exe" | Move-Item -Destination $nssmDir -Force
                Get-ChildItem "$nssmDir\nssm-*" -Directory | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "  NSSM installed to $nssmDir."
            }
            $mp = [System.Environment]::GetEnvironmentVariable("Path","Machine")
            if ($mp -notlike "*C:\nssm*") {
                [System.Environment]::SetEnvironmentVariable("Path","$mp;C:\nssm","Machine")
                $env:Path = "$env:Path;C:\nssm"
            }
        }
    } catch {
        Write-Host "  WARNING: NSSM install failed: $_" -ForegroundColor Yellow
    }
}

if ($InstallWireshark) {
    Write-Step "Phase 0: Installing Wireshark"
    try {
        $wsExe = Join-Path $TmpDir "Wireshark-latest-x64.exe"
        Get-Download "https://2.na.dl.wireshark.org/win64/Wireshark-latest-x64.exe" $wsExe
        $proc = Start-Process $wsExe -ArgumentList "/S" -Wait -PassThru
        Write-Host "  Wireshark installed (exit code $($proc.ExitCode))."
    } catch {
        Write-Host "  WARNING: Wireshark install failed: $_" -ForegroundColor Yellow
    }
}

# ============================================================
# Phase 0: Register InfluxDB as NSSM service
# (must run after NSSM is installed; influxd.exe is not service-aware)
# ============================================================
Write-Step "Phase 0: Registering InfluxDB service via NSSM"
try {
    $nssmExe = "C:\nssm\nssm.exe"
    $existingSvc = Get-Service influxdb -ErrorAction SilentlyContinue
    if ($existingSvc) {
        Stop-Service influxdb -Force -ErrorAction SilentlyContinue
        & sc.exe delete influxdb | Out-Null
        Start-Sleep -Seconds 3
        Write-Host "  Removed previous InfluxDB service registration."
    }
    if (Test-Path $nssmExe) {
        & $nssmExe install influxdb "$influxDir\influxd.exe" | Out-Null
        & $nssmExe set influxdb AppParameters "--bolt-path $influxDataDir\influxd.bolt --engine-path $influxDataDir\engine --sqlite-path $influxDataDir\influxd.sqlite" | Out-Null
        & $nssmExe set influxdb DisplayName "InfluxDB" | Out-Null
        & $nssmExe set influxdb Start SERVICE_DELAYED_AUTO_START | Out-Null
        & $nssmExe set influxdb AppStdout "$influxDataDir\influxd.log" | Out-Null
        & $nssmExe set influxdb AppStderr "$influxDataDir\influxd.log" | Out-Null
        Write-Host "  InfluxDB service registered via NSSM (data: $influxDataDir)."
    } else {
        Write-Host "  WARNING: NSSM not found - InfluxDB will not start automatically." -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ERROR registering InfluxDB service: $_" -ForegroundColor Red
    throw
}

# ============================================================
# Step 1: Wait for InfluxDB
# ============================================================
Write-Step "Step 1: Waiting for InfluxDB service"
try {
    $influxSvc = Get-Service -Name "influxdb" -ErrorAction SilentlyContinue
    if ($influxSvc -and $influxSvc.Status -ne "Running") {
        Start-Service influxdb
    }
    Wait-ForService -ServiceName "influxdb" -TimeoutSeconds 60
} catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    throw
}

# ============================================================
# Step 2: Run InfluxDB initial setup
# ============================================================
Write-Step "Step 2: Running InfluxDB initial setup"
try {
    $setupResult = & influx setup `
        --username marcuswunderlich `
        --password sunfast3300 `
        --org StratosRacing `
        --bucket signalk `
        --retention 168h `
        --force 2>&1
    Write-Host "  InfluxDB setup complete."
    Write-Host "  $setupResult"
} catch {
    Write-Host "  WARNING: InfluxDB setup may have already been run: $_" -ForegroundColor Yellow
}

# ============================================================
# Step 3: Create signalk_1m bucket
# ============================================================
Write-Step "Step 3: Creating signalk_1m bucket (90-day retention)"
try {
    & influx bucket create `
        --name signalk_1m `
        --retention 2160h `
        --org StratosRacing 2>&1 | Out-Null
    Write-Host "  Bucket signalk_1m created."
} catch {
    Write-Host "  WARNING: Bucket may already exist: $_" -ForegroundColor Yellow
}

# ============================================================
# Step 4: Generate all-access API token
# ============================================================
Write-Step "Step 4: Generating all-access API token"
try {
    $tokenOutput = & influx auth create `
        --all-access `
        --org StratosRacing `
        --description "bg-dashboard-token" 2>&1

    # Parse token from tabular output  -  token is in the second column
    $tokenLine = ($tokenOutput | Select-String -Pattern "bg-dashboard-token").Line
    if (-not $tokenLine) {
        # Fallback: try to find a line that looks like a token row
        $tokenLine = $tokenOutput | Where-Object { $_ -match "bg-dashboard-token" } | Select-Object -First 1
    }
    # Split on whitespace  -  fields: ID, Description, Token, User, ...
    $fields = ($tokenLine -split "\s{2,}").Trim()
    # Token is typically the longest field that looks like a base64/hex string
    $token = $fields | Where-Object { $_.Length -gt 40 -and $_ -notmatch "\s" } | Select-Object -First 1

    if (-not $token) {
        # Last resort: grab any string that looks like an InfluxDB token
        $token = [regex]::Match(($tokenOutput -join " "), "[A-Za-z0-9_\-=]{40,}").Value
    }

    if (-not $token) {
        throw "Could not parse API token from influx auth output."
    }

    Write-Host "  API token generated successfully."
    Write-Host "  Token: $($token.Substring(0, 10))..." -ForegroundColor DarkGray
} catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    throw
}

# ============================================================
# Step 5: Create downsample task
# ============================================================
Write-Step "Step 5: Creating InfluxDB downsample task"
try {
    $fluxFile = Join-Path $AppDir "downsample_signalk.flux"
    & influx task create `
        --file $fluxFile `
        --org StratosRacing 2>&1 | Out-Null
    Write-Host "  Downsample task created."
} catch {
    Write-Host "  WARNING: Task may already exist: $_" -ForegroundColor Yellow
}

# ============================================================
# Step 6: Inject token into telegraf.toml
# ============================================================
Write-Step "Step 6: Injecting API token into telegraf.toml"
try {
    $telegrafPath = Join-Path $AppDir "telegraf.toml"
    $content = Get-Content $telegrafPath -Raw
    $content = $content -replace "YOUR_INFLUXDB_API_TOKEN_HERE", $token
    Set-Content -Path $telegrafPath -Value $content -NoNewline
    Write-Host "  Token injected into telegraf.toml."

    # Also copy to C:\telegraf if it exists
    $telegrafServiceDir = "C:\telegraf"
    if (Test-Path $telegrafServiceDir) {
        Copy-Item $telegrafPath (Join-Path $telegrafServiceDir "telegraf.toml") -Force
        Write-Host "  Copied configured telegraf.toml to $telegrafServiceDir."
    }
} catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    throw
}

# ============================================================
# Step 7: Verify Node.js (installed in Phase 0)
# ============================================================
Write-Step "Step 7: Verifying Node.js"
try {
    # Refresh PATH in case Node.js was just installed
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    $nodeVersion = & node --version 2>&1
    Write-Host "  Node.js: $nodeVersion"
} catch {
    Write-Host "  ERROR: Node.js not found. Phase 0 install may have failed." -ForegroundColor Red
    throw
}

# ============================================================
# Step 8: Install Signal K Server
# ============================================================
Write-Step "Step 8: Installing Signal K Server"
try {
    # npm.ps1 on Windows writes deprecation warnings to stderr which PS5 treats as
    # errors under Stop preference -- temporarily relax for npm calls
    $prevPref = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $skVersion = & npm list -g signalk-server --depth=0 2>&1
    $skListExit = $LASTEXITCODE
    $ErrorActionPreference = $prevPref

    if ($skListExit -eq 0 -and ($skVersion | Out-String) -match "signalk-server") {
        Write-Host "  Signal K Server already installed."
    } else {
        Write-Host "  Installing signalk-server globally via npm..."
        $prevPref = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        & npm install -g signalk-server 2>&1 | Where-Object { $_ -match "error" -and $_ -notmatch "warn" } | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
        $npmExit = $LASTEXITCODE
        $ErrorActionPreference = $prevPref
        if ($npmExit -ne 0) { throw "npm install signalk-server failed (exit code $npmExit)" }
        Write-Host "  Signal K Server installed."
    }
} catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    throw
}

# ============================================================
# Step 9: Detect Signal K config directory
# ============================================================
Write-Step "Step 9: Setting up Signal K configuration"
$skConfigDir = Join-Path $env:APPDATA "signalk-server"

if (-not (Test-Path $skConfigDir)) {
    New-Item -ItemType Directory -Path $skConfigDir -Force | Out-Null
    Write-Host "  Created Signal K config directory: $skConfigDir"
} else {
    Write-Host "  Signal K config directory exists: $skConfigDir"
}

# ============================================================
# Step 10: Write Signal K settings.json
# ============================================================
Write-Step "Step 10: Writing Signal K settings.json"
$skSettingsPath = Join-Path $skConfigDir "settings.json"
if (Test-Path $skSettingsPath) {
    Write-Host "  settings.json already exists  -  skipping to avoid overwriting user config."
    Write-Host "  Injecting token into existing settings.json..."
    $skContent = Get-Content $skSettingsPath -Raw
    $skContent = $skContent -replace "INFLUXDB_TOKEN_PLACEHOLDER", $token
    Set-Content -Path $skSettingsPath -Value $skContent -NoNewline
} else {
    $settingsObj = [ordered]@{
        interfaces = [ordered]@{}
        vessels = [ordered]@{ self = [ordered]@{ uuid = "urn:mrn:imo:mmsi:0" } }
        ssl = $false
        pipedProviders = @(
            [ordered]@{
                id = "NGT-1"
                pipeElements = @(
                    [ordered]@{
                        type = "providers/actisense-serial"
                        options = [ordered]@{ device = "COM3"; baudrate = 115200 }
                    }
                )
            },
            [ordered]@{
                id = "H5000-NMEA0183"
                pipeElements = @(
                    [ordered]@{
                        type = "providers/tcp"
                        options = [ordered]@{ host = "192.168.1.233"; port = 10110 }
                    },
                    [ordered]@{ type = "providers/nmea0183-provider" }
                )
            }
        )
        plugins = [ordered]@{
            "signalk-to-influxdb2" = [ordered]@{
                active = $true
                configuration = [ordered]@{
                    influxUrl = "http://localhost:8086"
                    organisation = "StratosRacing"
                    bucket = "signalk"
                    token = $token
                }
            }
        }
    }
    $settingsJson = $settingsObj | ConvertTo-Json -Depth 10
    Set-Content -Path $skSettingsPath -Value $settingsJson -Encoding UTF8
    Write-Host "  Signal K settings.json created with data connections and InfluxDB plugin config."
}

# ============================================================
# Step 11: Install NSSM (if downloaded)
# ============================================================
Write-Step "Step 11: Setting up NSSM"
$nssmPath = "C:\nssm\nssm.exe"
if (Test-Path $nssmPath) {
    Write-Host "  NSSM found at $nssmPath."
    # Add to PATH if not already there
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($machinePath -notlike "*C:\nssm*") {
        [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;C:\nssm", "Machine")
        $env:Path = "$env:Path;C:\nssm"
        Write-Host "  Added C:\nssm to system PATH."
    }
} else {
    Write-Host "  NSSM not found  -  Signal K will not be installed as a service."
    Write-Host "  You can install NSSM later from https://nssm.cc and follow INSTALL.md step 7."
}

# ============================================================
# Step 12: Install Signal K as NSSM service
# ============================================================
Write-Step "Step 12: Installing Signal K as Windows service via NSSM"
if (Test-Path $nssmPath) {
    try {
        $existingSvc = Get-Service -Name "signalk" -ErrorAction SilentlyContinue
        if ($existingSvc) {
            Write-Host "  Signal K service already exists  -  skipping."
        } else {
            # Find node.exe path
            $nodePath = (Get-Command node -ErrorAction Stop).Source
            $npmGlobalDir = Join-Path $env:APPDATA "npm\node_modules\signalk-server\bin\signalk-server"

            & $nssmPath install signalk $nodePath
            & $nssmPath set signalk AppDirectory $skConfigDir
            & $nssmPath set signalk AppParameters "$npmGlobalDir --config $skConfigDir"
            & $nssmPath set signalk Start SERVICE_DELAYED_AUTO_START
            & $nssmPath set signalk AppStdout (Join-Path $skConfigDir "signalk.log")
            & $nssmPath set signalk AppStderr (Join-Path $skConfigDir "signalk.log")
            Write-Host "  Signal K service installed via NSSM."
        }
    } catch {
        Write-Host "  WARNING: Could not install Signal K service: $_" -ForegroundColor Yellow
    }
} else {
    Write-Host "  NSSM not found - installing Signal K service via sc.exe instead."
    try {
        $existingSvc = Get-Service -Name "signalk" -ErrorAction SilentlyContinue
        if ($existingSvc) {
            Write-Host "  Signal K service already exists  -  skipping."
        } else {
            $nodePath = (Get-Command node -ErrorAction Stop).Source
            $signalkScript = "$env:APPDATA\npm\node_modules\signalk-server\bin\signalk-server"
            if (Test-Path $signalkScript) {
                $svcBin = "`"$nodePath`" `"$signalkScript`" --config `"$skConfigDir`""
                & sc.exe create signalk binPath= $svcBin start= delayed-auto DisplayName= "Signal K Server" | Out-Null
                Write-Host "  Signal K service registered via sc.exe."
            } else {
                Write-Host "  WARNING: signalk-server not found at $signalkScript" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "  WARNING: Could not install Signal K service: $_" -ForegroundColor Yellow
    }
}

# ============================================================
# Step 13: Install Telegraf as service
# ============================================================
Write-Step "Step 13: Installing Telegraf as Windows service"
try {
    $existingTelegraf = Get-Service -Name "telegraf" -ErrorAction SilentlyContinue
    if ($existingTelegraf) {
        Write-Host "  Telegraf service already exists."
    } else {
        $telegrafExe = "C:\telegraf\telegraf.exe"
        if (Test-Path $telegrafExe) {
            $telegrafConf = Join-Path $AppDir "telegraf.toml"
            & $telegrafExe --service install --config $telegrafConf 2>&1 | Out-Null
            Write-Host "  Telegraf service installed."
        } else {
            Write-Host "  WARNING: telegraf.exe not found at $telegrafExe" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "  WARNING: Could not install Telegraf service: $_" -ForegroundColor Yellow
}

# ============================================================
# Step 14: Wait for Grafana
# ============================================================
Write-Step "Step 14: Waiting for Grafana service"
try {
    $grafanaSvcName = @("GrafanaLabs.Grafana","Grafana") | Where-Object { Get-Service $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
    if ($grafanaSvcName) {
        $grafanaSvc = Get-Service $grafanaSvcName
        if ($grafanaSvc.Status -ne "Running") { Start-Service $grafanaSvcName }
    }
    Wait-ForUrl -Url "http://localhost:3001/api/health" -TimeoutSeconds 120
} catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    throw
}

# ============================================================
# Step 15: Set Grafana admin password
# ============================================================
Write-Step "Step 15: Setting Grafana admin password"
try {
    $passwordBody = @{
        oldPassword = "admin"
        newPassword = "sunfast3300"
    } | ConvertTo-Json

    # Use default admin/admin credentials for the initial password change
    $pair = "admin:admin"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
    $base64 = [System.Convert]::ToBase64String($bytes)
    $headers = @{
        "Authorization" = "Basic $base64"
        "Content-Type"  = "application/json"
    }

    try {
        Invoke-RestMethod -Uri "http://localhost:3001/api/user/password" `
            -Method Put -Headers $headers -Body $passwordBody -UseBasicParsing | Out-Null
        Write-Host "  Grafana admin password changed."
    } catch {
        if ($_.Exception.Response.StatusCode -eq 401) {
            Write-Host "  Password already changed (got 401 with default creds)  -  skipping."
        } else {
            Write-Host "  WARNING: Could not change password: $_" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "  WARNING: Grafana password change failed: $_" -ForegroundColor Yellow
}

# ============================================================
# Step 16: Add InfluxDB datasource to Grafana
# ============================================================
Write-Step "Step 16: Adding InfluxDB datasource to Grafana"
try {
    $influxDsBody = @{
        name      = "InfluxDB"
        type      = "influxdb"
        access    = "proxy"
        url       = "http://localhost:8086"
        isDefault = $true
        jsonData  = @{
            version        = "Flux"
            organization   = "StratosRacing"
            defaultBucket  = "signalk"
        }
        secureJsonData = @{
            token = $token
        }
    } | ConvertTo-Json -Depth 5

    $influxDs = Invoke-GrafanaApi -Method "POST" -Path "/api/datasources" -Body $influxDsBody
    if ($influxDs) {
        $influxDsUid = $influxDs.datasource.uid
        Write-Host "  InfluxDB datasource added (UID: $influxDsUid)."
    } else {
        # Datasource may already exist  -  try to get its UID
        $existing = Invoke-GrafanaApi -Method "GET" -Path "/api/datasources/name/InfluxDB"
        if ($existing) {
            $influxDsUid = $existing.uid
            Write-Host "  InfluxDB datasource already exists (UID: $influxDsUid)."
        }
    }
} catch {
    Write-Host "  WARNING: Could not add InfluxDB datasource: $_" -ForegroundColor Yellow
}

# ============================================================
# Step 17: Add JSON API datasource for Signal K
# ============================================================
Write-Step "Step 17: Adding JSON API datasource for Signal K"
try {
    $signalkDsBody = @{
        name   = "SignalK"
        type   = "marcusolsson-json-datasource"
        access = "proxy"
        url    = "http://localhost:3000/signalk/v1/api/"
    } | ConvertTo-Json -Depth 5

    $signalkDs = Invoke-GrafanaApi -Method "POST" -Path "/api/datasources" -Body $signalkDsBody
    if ($signalkDs) {
        $signalkDsUid = $signalkDs.datasource.uid
        Write-Host "  SignalK JSON API datasource added (UID: $signalkDsUid)."
    } else {
        $existing = Invoke-GrafanaApi -Method "GET" -Path "/api/datasources/name/SignalK"
        if ($existing) {
            $signalkDsUid = $existing.uid
            Write-Host "  SignalK datasource already exists (UID: $signalkDsUid)."
        }
    }
} catch {
    Write-Host "  WARNING: Could not add SignalK datasource: $_" -ForegroundColor Yellow
}

# ============================================================
# Step 18: Import N2K Network Monitor dashboard
# ============================================================
Write-Step "Step 18: Importing N2K Network Monitor dashboard"
try {
    $dashboardFile = Join-Path $AppDir "dashboard-n2k-network-monitor.json"
    $dashboardJson = Get-Content $dashboardFile -Raw | ConvertFrom-Json

    $importBody = @{
        dashboard = $dashboardJson
        overwrite = $true
        inputs    = @(
            @{
                name     = "DS_INFLUXDB"
                type     = "datasource"
                pluginId = "influxdb"
                value    = $influxDsUid
            },
            @{
                name     = "DS_SIGNALK"
                type     = "datasource"
                pluginId = "marcusolsson-json-datasource"
                value    = $signalkDsUid
            }
        )
    } | ConvertTo-Json -Depth 20 -Compress

    $result = Invoke-GrafanaApi -Method "POST" -Path "/api/dashboards/import" -Body $importBody
    if ($result) {
        Write-Host "  N2K Network Monitor dashboard imported."
    }
} catch {
    Write-Host "  WARNING: Could not import N2K dashboard: $_" -ForegroundColor Yellow
}

# ============================================================
# Step 19: Import Ethernet Monitor dashboard
# ============================================================
Write-Step "Step 19: Importing Ethernet Monitor dashboard"
try {
    $dashboardFile = Join-Path $AppDir "dashboard-ethernet-monitor.json"
    $dashboardJson = Get-Content $dashboardFile -Raw | ConvertFrom-Json

    $importBody = @{
        dashboard = $dashboardJson
        overwrite = $true
        inputs    = @(
            @{
                name     = "DS_INFLUXDB"
                type     = "datasource"
                pluginId = "influxdb"
                value    = $influxDsUid
            },
            @{
                name     = "DS_SIGNALK"
                type     = "datasource"
                pluginId = "marcusolsson-json-datasource"
                value    = $signalkDsUid
            }
        )
    } | ConvertTo-Json -Depth 20 -Compress

    $result = Invoke-GrafanaApi -Method "POST" -Path "/api/dashboards/import" -Body $importBody
    if ($result) {
        Write-Host "  Ethernet Monitor dashboard imported."
    }
} catch {
    Write-Host "  WARNING: Could not import Ethernet dashboard: $_" -ForegroundColor Yellow
}

# ============================================================
# Step 20: Start all services
# ============================================================
Write-Step "Step 20: Starting all services"

$grafanaSvcNameFinal = @("GrafanaLabs.Grafana","Grafana") | Where-Object { Get-Service $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
$services = @("influxdb", "telegraf", "signalk", $grafanaSvcNameFinal) | Where-Object { $_ }
foreach ($svc in $services) {
    try {
        $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if (-not $service) {
            Write-Host "  Service '$svc' not found  -  skipping."
            continue
        }
        if ($service.Status -eq "Running") {
            Write-Host "  Service '$svc' already running."
        } else {
            Start-Service $svc
            Write-Host "  Service '$svc' started."
        }
    } catch {
        Write-Host "  WARNING: Could not start '$svc': $_" -ForegroundColor Yellow
    }
}

# ============================================================
# Step 21: Print summary
# ============================================================
Write-Step "Setup Complete"
Write-Host ""
Write-Host "Service Status:" -ForegroundColor Green
foreach ($svc in $services) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service) {
        $color = if ($service.Status -eq "Running") { "Green" } else { "Red" }
        Write-Host "  $($svc.PadRight(12)) $($service.Status)" -ForegroundColor $color
    } else {
        Write-Host "  $($svc.PadRight(12)) NOT INSTALLED" -ForegroundColor Red
    }
}
Write-Host ""
Write-Host "URLs:" -ForegroundColor Green
Write-Host "  Grafana:    http://localhost:3001"
Write-Host "  Signal K:   http://localhost:3000"
Write-Host "  InfluxDB:   http://localhost:8086"
Write-Host ""
Write-Host "Grafana is also accessible from other devices on the GoFree network:"
Write-Host "  http://192.168.1.253:3001"
Write-Host ""
Write-Host "Login: marcuswunderlich / sunfast3300" -ForegroundColor Green
Write-Host ""
Write-Host "Next step: Power up the boat, then use VALUE-MAPPINGS.md to configure" -ForegroundColor Yellow
Write-Host "           Grafana value mappings for NMEA 2000 device source addresses." -ForegroundColor Yellow

} catch {
    Write-Host ""
    Write-Host "FATAL: $($_.ToString())" -ForegroundColor Red
    Write-Host "$($_.ScriptStackTrace)" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

Stop-Transcript
