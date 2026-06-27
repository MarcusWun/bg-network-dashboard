# B&G Network Dashboard — Windows Service Reference

Quick reference for managing all four services on the Geekom A9.

---

## Service Overview

| Service Name | Display Name | Managed By | Port |
|---|---|---|---|
| `influxdb` | InfluxDB | Windows Service (MSI) | 8086 |
| `Grafana` | Grafana | Windows Service (MSI) | 3001 |
| `signalk` | signalk | NSSM | 3000 |
| `telegraf` | telegraf | Telegraf CLI | — |

---

## Startup Order

Services should start in this order:

1. **InfluxDB** — must be running first (database backend)
2. **Signal K + Telegraf** — can start simultaneously (both write to InfluxDB)
3. **Grafana** — start last (reads from InfluxDB)

> All services are set to auto-start with Windows. InfluxDB and Grafana start automatically via their MSI installers. Signal K is set to `SERVICE_DELAYED_AUTO_START` via NSSM, which naturally gives InfluxDB time to initialize first.

---

## InfluxDB

**Service name:** `influxdb`
**Log file:** `%ProgramData%\InfluxData\influxdb\influxd.log`

### PowerShell / sc.exe
```powershell
# Start / Stop / Restart / Status
Start-Service influxdb
Stop-Service influxdb
Restart-Service influxdb
Get-Service influxdb

# sc.exe equivalents
sc.exe start influxdb
sc.exe stop influxdb
sc.exe query influxdb
```

### Services GUI
Win+R → `services.msc` → find **InfluxDB** → right-click → Start / Stop / Restart.

---

## Grafana

**Service name:** `Grafana`
**Log file:** `C:\Program Files\GrafanaLabs\grafana\data\log\grafana.log`

### PowerShell / sc.exe
```powershell
Start-Service Grafana
Stop-Service Grafana
Restart-Service Grafana
Get-Service Grafana

sc.exe start Grafana
sc.exe stop Grafana
sc.exe query Grafana
```

### Services GUI
Win+R → `services.msc` → find **Grafana** → right-click → Start / Stop / Restart.

---

## Signal K (NSSM)

**Service name:** `signalk`
**Log file:** `%APPDATA%\signalk-server\signalk.log`

### PowerShell / sc.exe
```powershell
Start-Service signalk
Stop-Service signalk
Restart-Service signalk
Get-Service signalk

sc.exe start signalk
sc.exe stop signalk
sc.exe query signalk
```

### NSSM commands
```powershell
nssm start signalk
nssm stop signalk
nssm restart signalk
nssm status signalk

# Edit service configuration
nssm edit signalk
```

### Services GUI
Win+R → `services.msc` → find **signalk** → right-click → Start / Stop / Restart.

---

## Telegraf

**Service name:** `telegraf`
**Log file:** `C:\telegraf\telegraf.log`

### PowerShell / sc.exe
```powershell
Start-Service telegraf
Stop-Service telegraf
Restart-Service telegraf
Get-Service telegraf

sc.exe start telegraf
sc.exe stop telegraf
sc.exe query telegraf
```

### Services GUI
Win+R → `services.msc` → find **telegraf** → right-click → Start / Stop / Restart.

---

## Restart All Services (Correct Order)

```powershell
# Stop all (reverse order)
Stop-Service Grafana -Force
Stop-Service telegraf -Force
Stop-Service signalk -Force
Stop-Service influxdb -Force

# Start all (correct order)
Start-Service influxdb
Start-Sleep -Seconds 10
Start-Service signalk
Start-Service telegraf
Start-Service Grafana
```

---

## Check If Data Is Flowing

### 1. Signal K Admin UI
Open **http://localhost:3000** → **Data Browser**. You should see live NMEA data paths updating.

### 2. InfluxDB CLI query
```powershell
influx query '
  from(bucket: "signalk")
    |> range(start: -5m)
    |> limit(n: 5)
' --org StratosRacing
```

If data is flowing, this returns recent records.

### 3. Grafana datasource test
Open **http://localhost:3001** → **Connections** → **Data sources** → select **InfluxDB** → **Save & Test**.

Should show: "datasource is working. X buckets found".

---

## Tailing Logs on Windows

### PowerShell (Get-Content -Wait)
```powershell
# Tail InfluxDB log
Get-Content "$env:ProgramData\InfluxData\influxdb\influxd.log" -Wait -Tail 50

# Tail Grafana log
Get-Content "C:\Program Files\GrafanaLabs\grafana\data\log\grafana.log" -Wait -Tail 50

# Tail Signal K log
Get-Content "$env:APPDATA\signalk-server\signalk.log" -Wait -Tail 50

# Tail Telegraf log
Get-Content "C:\telegraf\telegraf.log" -Wait -Tail 50
```

Press **Ctrl+C** to stop tailing.

---

## Troubleshooting

| Symptom | Check |
|---|---|
| No data in Grafana | Is Signal K receiving data? Check http://localhost:3000 |
| Signal K not receiving NMEA 2000 | Is NGT-1 on COM3? Check Device Manager → Ports |
| Signal K not receiving NMEA 0183 | Is H5000 reachable? `Test-NetConnection 192.168.1.233 -Port 10110` |
| InfluxDB not starting | Check log: `%ProgramData%\InfluxData\influxdb\influxd.log` |
| Telegraf errors | Check log: `C:\telegraf\telegraf.log` — likely token issue |
| Grafana can't reach InfluxDB | Verify InfluxDB is running, check datasource token |
