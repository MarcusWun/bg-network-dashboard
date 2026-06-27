#Requires -RunAsAdministrator
<#
.SYNOPSIS
    B&G Network Dashboard post-install setup script.
    Called by the Inno Setup installer after binaries are extracted.

.PARAMETER AppDir
    Path where config files were installed (e.g. C:\bg-network-dashboard).
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$AppDir
)

$ErrorActionPreference = "Stop"

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
# Step 1: Wait for InfluxDB
# ============================================================
Write-Step "Step 1: Waiting for InfluxDB service"
try {
    # Start the service if it's not running
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

    # Parse token from tabular output — token is in the second column
    $tokenLine = ($tokenOutput | Select-String -Pattern "bg-dashboard-token").Line
    if (-not $tokenLine) {
        # Fallback: try to find a line that looks like a token row
        $tokenLine = $tokenOutput | Where-Object { $_ -match "bg-dashboard-token" } | Select-Object -First 1
    }
    # Split on whitespace — fields: ID, Description, Token, User, ...
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
# Step 7: Install Node.js if not present
# ============================================================
Write-Step "Step 7: Checking Node.js installation"
try {
    $nodeVersion = & node --version 2>&1
    Write-Host "  Node.js already installed: $nodeVersion"
} catch {
    Write-Host "  Node.js not found in PATH. It should have been installed by the Inno Setup installer."
    Write-Host "  If Node.js was just installed, PATH may not be updated in this session."
    # Refresh PATH
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
    try {
        $nodeVersion = & node --version 2>&1
        Write-Host "  Node.js found after PATH refresh: $nodeVersion"
    } catch {
        Write-Host "  ERROR: Node.js still not found. Please install manually." -ForegroundColor Red
        throw
    }
}

# ============================================================
# Step 8: Install Signal K Server
# ============================================================
Write-Step "Step 8: Installing Signal K Server"
try {
    $skVersion = & npm list -g signalk-server --depth=0 2>&1
    if ($LASTEXITCODE -eq 0 -and $skVersion -match "signalk-server") {
        Write-Host "  Signal K Server already installed."
    } else {
        Write-Host "  Installing signalk-server globally via npm..."
        & npm install -g signalk-server 2>&1 | Out-Null
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
    Write-Host "  settings.json already exists — skipping to avoid overwriting user config."
    Write-Host "  Injecting token into existing settings.json..."
    $skContent = Get-Content $skSettingsPath -Raw
    $skContent = $skContent -replace "INFLUXDB_TOKEN_PLACEHOLDER", $token
    Set-Content -Path $skSettingsPath -Value $skContent -NoNewline
} else {
    $settingsJson = @"
{
  "interfaces": {},
  "vessels": {
    "self": {
      "uuid": "urn:mrn:imo:mmsi:0"
    }
  },
  "ssl": false,
  "pipedProviders": [
    {
      "id": "NGT-1",
      "pipeElements": [
        {
          "type": "providers/serialport",
          "options": {
            "device": "COM3",
            "baudrate": 115200
          }
        },
        {
          "type": "providers/nmea2000",
          "options": {
            "type": "iKonvert"
          }
        }
      ]
    },
    {
      "id": "H5000-NMEA0183",
      "pipeElements": [
        {
          "type": "providers/tcp",
          "options": {
            "host": "192.168.1.233",
            "port": 10110
          }
        },
        {
          "type": "providers/nmea0183-provider"
        }
      ]
    }
  ],
  "plugins": {
    "signalk-to-influxdb2": {
      "active": true,
      "configuration": {
        "influxUrl": "http://localhost:8086",
        "organisation": "StratosRacing",
        "bucket": "signalk",
        "token": "$token"
      }
    }
  }
}
"@
    Set-Content -Path $skSettingsPath -Value $settingsJson
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
    Write-Host "  NSSM not found — Signal K will not be installed as a service."
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
            Write-Host "  Signal K service already exists — skipping."
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
    Write-Host "  Skipping — NSSM not available."
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
    $grafanaSvc = Get-Service -Name "Grafana" -ErrorAction SilentlyContinue
    if ($grafanaSvc -and $grafanaSvc.Status -ne "Running") {
        Start-Service Grafana
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
            Write-Host "  Password already changed (got 401 with default creds) — skipping."
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
        # Datasource may already exist — try to get its UID
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

$services = @("influxdb", "telegraf", "signalk", "Grafana")
foreach ($svc in $services) {
    try {
        $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if (-not $service) {
            Write-Host "  Service '$svc' not found — skipping."
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
