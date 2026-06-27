# B&G Network Dashboard — Installation Guide

Full step-by-step installation of the diagnostics stack on the Geekom A9 mini PC (Windows 11).

**Stack:** Signal K → InfluxDB 2.x → Grafana + Telegraf

**Network:**
| Device | IP | Notes |
|---|---|---|
| Geekom A9 | 192.168.1.253 | Adapter: Ethernet |
| GoFree Router | 192.168.1.1 | |
| H5000 CPU | 192.168.1.233 | NMEA 0183 TCP on port 10110 |
| Zeus 3S | 192.168.1.219 | |

**Ports:**
| Service | Port |
|---|---|
| Signal K | 3000 |
| Grafana | 3001 |
| InfluxDB | 8086 |

---

## 1. Install Node.js 20 LTS

Option A — winget (recommended):
```powershell
winget install OpenJS.NodeJS.LTS
```

Option B — download the MSI from https://nodejs.org/en/download and run it.

Verify:
```powershell
node --version   # v20.x.x
npm --version
```

Close and reopen any terminal windows after installation so PATH updates take effect.

---

## 2. Install & Configure Signal K Server

### 2a. Install Signal K

```powershell
npm install -g signalk-server
```

Verify:
```powershell
signalk-server --version
```

### 2b. Create Signal K configuration

```powershell
signalk-server-setup
```

Accept defaults. This creates a config directory at `%APPDATA%\signalk-server`.

### 2c. Start Signal K (temporary, for configuration)

```powershell
signalk-server
```

Leave this terminal open. Open the Signal K Admin UI at **http://localhost:3000**.

### 2d. Configure data connections

In the Signal K Admin UI → **Server** → **Data Connections**, add two connections:

**Connection 1 — NMEA 2000 (Actisense NGT-1):**
| Field | Value |
|---|---|
| Data Type | NMEA 2000 |
| Provider | Actisense NGT-1 (canboatjs) |
| Serial Port | COM3 |
| Baud Rate | 115200 |
| Data Bits / Stop Bits / Parity | 8 / 1 / None |

> **Note:** NGT-1 BST initialization is handled automatically by Signal K/canboatjs. No manual startup command is needed.

**Connection 2 — NMEA 0183 (H5000 TCP):**
| Field | Value |
|---|---|
| Data Type | NMEA 0183 |
| Provider | TCP Client |
| Host | 192.168.1.233 |
| Port | 10110 |

Click **Submit** for each connection, then **Restart** Signal K from the Admin UI.

---

## 3. Install InfluxDB 2.x

Download the Windows installer from https://www.influxdata.com/downloads/ (InfluxDB 2.x, Windows).

Run the installer — it automatically registers InfluxDB as a Windows service named `influxdb`.

### 3a. Initial setup

Open **http://localhost:8086** in a browser.

Complete the initial setup:

| Field | Value |
|---|---|
| Username | marcuswunderlich |
| Password | sunfast3300 |
| Organization | StratosRacing |
| Bucket | signalk |
| Retention | 7 days |

### 3b. Create the downsampled bucket

Open a terminal and run:
```powershell
influx bucket create `
  --name signalk_1m `
  --retention 2160h `
  --org StratosRacing
```

This creates a 90-day retention bucket for 1-minute downsampled data.

### 3c. Generate an all-access API token

```powershell
influx auth create `
  --all-access `
  --org StratosRacing `
  --description "bg-dashboard-token"
```

**Copy the token value from the output — you will need it for Telegraf and Signal K configuration.**

### 3d. Create the downsample task

```powershell
influx task create `
  --file C:\bg-network-dashboard\downsample_signalk.flux `
  --org StratosRacing
```

---

## 4. Install & Configure Signal K InfluxDB Plugin

### 4a. Install the plugin

Open the Signal K Admin UI at **http://localhost:3000** → **Appstore** → search for **signalk-to-influxdb2** → **Install**.

Restart Signal K when prompted.

### 4b. Configure the plugin

Go to **Server** → **Plugin Config** → **Signal K to InfluxDB 2**:

| Field | Value |
|---|---|
| InfluxDB URL | http://localhost:8086 |
| Organization | StratosRacing |
| Bucket | signalk |
| Token | *(paste the API token from step 3c)* |

Enable the plugin and click **Submit**.

---

## 5. Install & Configure Grafana

Download the Windows MSI installer from https://grafana.com/grafana/download (OSS edition).

Run the installer — it automatically registers Grafana as a Windows service.

### 5a. Change Grafana port to 3001

Edit `C:\Program Files\GrafanaLabs\grafana\conf\defaults.ini`:

```ini
http_port = 3001
http_addr = 0.0.0.0
```

Restart the Grafana service:
```powershell
Restart-Service Grafana
```

### 5b. Initial login

Open **http://localhost:3001** — log in with `admin` / `admin`, then change password to `sunfast3300` when prompted.

### 5c. Install JSON API plugin

```powershell
grafana cli plugins install marcusolsson-json-datasource
Restart-Service Grafana
```

Or install via Grafana UI: **Administration** → **Plugins** → search "JSON API" → **Install**.

### 5d. Add InfluxDB datasource

Go to **Connections** → **Data sources** → **Add data source** → **InfluxDB**:

| Field | Value |
|---|---|
| Query Language | Flux |
| URL | http://localhost:8086 |
| Organization | StratosRacing |
| Token | *(paste the API token from step 3c)* |
| Default Bucket | signalk |

Click **Save & Test** — should show "datasource is working".

### 5e. Add JSON API datasource (Signal K)

Go to **Connections** → **Data sources** → **Add data source** → **JSON API**:

| Field | Value |
|---|---|
| URL | http://localhost:3000/signalk/v1/api/ |

Click **Save & Test**.

### 5f. Import dashboards

Go to **Dashboards** → **Import** for each dashboard:

1. Upload `dashboard-n2k-network-monitor.json` — when prompted, select the **InfluxDB** datasource for "DS_INFLUXDB" and **JSON API** datasource for "DS_SIGNALK". Click **Import**.
2. Upload `dashboard-ethernet-monitor.json` — same datasource mapping. Click **Import**.

---

## 6. Install & Configure Telegraf

Download the Telegraf Windows zip from https://www.influxdata.com/downloads/ (Telegraf, Windows).

Extract to `C:\telegraf\`.

### 6a. Configure Telegraf

Edit the `telegraf.toml` file in your install directory (`C:\bg-network-dashboard\telegraf.toml`):

Replace `YOUR_INFLUXDB_API_TOKEN_HERE` with the API token from step 3c.

Copy the configured file to the Telegraf directory:
```powershell
Copy-Item C:\bg-network-dashboard\telegraf.toml C:\telegraf\telegraf.toml
```

### 6b. Install Telegraf as a Windows service

```powershell
C:\telegraf\telegraf.exe --service install --config C:\telegraf\telegraf.toml
C:\telegraf\telegraf.exe --service start
```

---

## 7. Install Signal K as a Windows Service (NSSM)

Download NSSM from https://nssm.cc/download — extract to `C:\nssm\` and add `C:\nssm\win64` to your PATH.

Stop the Signal K terminal you started in step 2c (Ctrl+C).

### 7a. Install the service

```powershell
nssm install signalk node.exe
nssm set signalk AppDirectory "%APPDATA%\signalk-server"
nssm set signalk AppParameters "%APPDATA%\npm\node_modules\signalk-server\bin\signalk-server --config %APPDATA%\signalk-server"
nssm set signalk Start SERVICE_DELAYED_AUTO_START
nssm set signalk AppStdout "%APPDATA%\signalk-server\signalk.log"
nssm set signalk AppStderr "%APPDATA%\signalk-server\signalk.log"
nssm start signalk
```

---

## 8. Install Wireshark (Optional)

Download Wireshark + Npcap from https://www.wireshark.org/download.html.

Run the installer, ensuring the **Npcap** component is selected.

Optionally install maritime Lua dissectors for deep NMEA packet inspection.

---

## 9. Post-Install Verification

### 9a. Check all services are running

Open **Services** (Win+R → `services.msc`) and verify these four services show **Running**:

| Service | Display Name |
|---|---|
| influxdb | InfluxDB |
| Grafana | Grafana |
| signalk | signalk (NSSM) |
| telegraf | telegraf |

Or via PowerShell:
```powershell
Get-Service influxdb, Grafana, signalk, telegraf | Format-Table Name, Status
```

### 9b. Check Signal K data flow

Open **http://localhost:3000** → **Data Browser**. You should see NMEA 2000 and NMEA 0183 data paths appearing.

### 9c. Check Grafana dashboards

Open **http://localhost:3001** → **Dashboards**. Both dashboards should load and show data panels.

### 9d. Verify from other devices on the network

From the Zeus 3S or a tablet connected to the GoFree network, open:
- **http://192.168.1.253:3001** — Grafana dashboards

Signal K Admin UI remains local-only on port 3000 (no 0.0.0.0 binding).

---

## 10. After First Run (Boat Powered Up)

Once the boat is powered up and NMEA 2000 devices are transmitting:

1. Open the **N2K Network Monitor** dashboard in Grafana.
2. Note the source addresses that appear for each device.
3. Use **VALUE-MAPPINGS.md** to fill in Grafana value mappings — mapping source addresses to device names (e.g., `25 → H5000 CPU`, `35 → Zeus 3S`).

To add value mappings in Grafana: edit the relevant panel → **Field** tab → **Value mappings** → add entries.
