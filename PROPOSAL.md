# B&G Marine Network Diagnostics Dashboard — Proposal

**Author:** Forge (OpenClaw Agent)
**Date:** 2026-06-23
**Updated:** 2026-06-24
**For:** Marcus Wunderlich
**Platform:** Windows 11 — Geekom A9 Mini PC
**Purpose:** Network diagnostics and monitoring (not a sailing instrument)

---

## 1. Executive Summary

This proposal outlines an open-source diagnostic dashboard for monitoring all data flowing through the boat's B&G instrumentation network. The system captures raw traffic from two distinct paths — the **NMEA 2000 CAN bus** (via Actisense NGT gateway) and the **B&G ethernet backbone** (via GoFree router) — and presents it through Grafana dashboards focused on network health, device status, message rates, and protocol-level visibility.

This is a **diagnostics and network monitoring tool**, not a sailing instrument. Its purpose is to answer: "What devices are on my network? What are they saying? How fast? Are any misbehaving?"

---

## 2. Existing Hardware Inventory

| Component | Connection | Role |
|-----------|-----------|------|
| B&G H5000 CPU | Ethernet + NMEA 2000 | Central processor, data routing, calculations |
| B&G Zeus 3S Chartplotter | Ethernet + NMEA 2000 | Navigation display, chart plotting |
| B&G GoFree Router | Ethernet (hub) | Network backbone, WiFi bridge |
| B&G H5000 Autopilot | NMEA 2000 | Heading control |
| 2x H5000 Pilot Controllers | NMEA 2000 | Autopilot user interface |
| 2x H5000 Graphic Displays | NMEA 2000 / Ethernet | Instrument displays |
| 3x HV Displays | NMEA 2000 | Large-format instrument displays |
| Depth sensor(s) | NMEA 2000 | Water depth |
| Wind sensor(s) | NMEA 2000 | Apparent/true wind speed and angle |
| Compass / 3D motion sensor | NMEA 2000 | Heading, pitch, roll, rate of turn |
| Actisense NGT Gateway | NMEA 2000 → Serial (COM3) | N2K-to-PC bridge, 115200 baud |
| Geekom A9 Mini PC | Ethernet + Serial | Dashboard host (Windows 11) |

### Network Topology

```
                          ┌─────────────────────┐
                          │   NMEA 2000 Bus      │
                          │  (CAN backbone)      │
                          └──┬──┬──┬──┬──┬──┬──┬─┘
                             │  │  │  │  │  │  │
                  ┌──────────┘  │  │  │  │  │  └──────────┐
                  │             │  │  │  │  │              │
              ┌───┴───┐   ┌────┴──┴──┴──┴──┴────┐    ┌────┴────┐
              │H5000  │   │ Sensors: Wind, Depth,│    │Actisense│
              │  CPU  │   │ Compass, 3D Motion,  │    │  NGT    │
              │       │   │ GPS, etc.            │    │         │
              └───┬───┘   └─────────────────────┘    └────┬────┘
                  │ Ethernet                         Serial│COM3
                  │                                   115200 baud
            ┌─────┴──────┐                                │
            │  GoFree    │                                │
            │  Router    │                                │
            └──┬──┬──┬───┘                                │
               │  │  │ Ethernet                           │
    ┌──────────┘  │  └──────────┐                         │
    │             │              │                         │
┌───┴───┐   ┌────┴────┐   ┌─────┴─────┐                  │
│Zeus 3S│   │Graphic  │   │ Geekom A9 │◄─────────────────┘
│       │   │Displays │   │ Win 11 PC │
└───────┘   └─────────┘   └───────────┘
```

---

## 3. Software Architecture

### Data Flow

```
┌──────────────────────────────────────────────────────────────────┐
│                        Geekom A9 (Windows 11)                    │
│                                                                  │
│  ┌─────────────┐     ┌──────────────┐     ┌──────────────────┐  │
│  │  Actisense  │     │              │     │                  │  │
│  │  NGT on     │────►│  Signal K    │────►│    InfluxDB      │  │
│  │  COM3       │     │  Server      │     │  (time-series    │  │
│  │  (N2K data) │     │  (Node.js)   │     │   database)      │  │
│  └─────────────┘     │              │     └────────┬─────────┘  │
│                      │  Decodes all │              │             │
│  ┌─────────────┐     │  PGNs via    │              │             │
│  │  H5000 CPU  │     │  canboatjs   │              ▼             │
│  │  TCP/UDP    │────►│              │     ┌──────────────────┐  │
│  │  (0183 over │     │  Normalizes  │     │                  │  │
│  │  ethernet)  │     │  to Signal K │     │    Grafana       │  │
│  └─────────────┘     │  data model  │     │  (dashboards)    │  │
│                      └──────┬───────┘     │                  │  │
│                             │             │  localhost:3001   │  │
│                             │ REST/WS API │                  │  │
│                             └────────────►│                  │  │
│                                           └──────────────────┘  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Wireshark (raw ethernet packet analysis)                │   │
│  │  - NMEA 0183 dissector (kmpm/wireshark-nmea)             │   │
│  │  - NMEA 2000 dissector (fkie-cad/maritime-dissector)     │   │
│  └──────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

### Software Stack

| Software | Version | Role | Port |
|----------|---------|------|------|
| Node.js | LTS (20.x+) | Runtime for Signal K | — |
| Signal K Server | Latest | NMEA ingestion, PGN decoding, data normalization | 3000 |
| canboatjs | Bundled | Actisense NGT-1 serial protocol + PGN decoder | — |
| signalk-to-influxdb | Plugin | Writes all Signal K paths to InfluxDB | — |
| InfluxDB | 2.x | Time-series storage for all sensor data | 8086 |
| Grafana | Latest | Dashboard visualization | 3001 |
| Wireshark | Latest | Raw ethernet/protocol analysis | — |
| Actisense NMEA Reader | Latest | Direct PGN diagnostics (backup tool) | — |

---

## 4. Installation Guide

### 4.1 Install Node.js

1. Download Node.js LTS from https://nodejs.org
2. Run installer, accept defaults
3. Verify: open PowerShell, run `node --version`

### 4.2 Install Signal K Server

```powershell
npm install -g signalk-server
signalk-server-setup
```

During setup:
- Set vessel name and MMSI (if applicable)
- The server will start on `http://localhost:3000`

### 4.3 Configure Signal K — NMEA 2000 via Actisense NGT

In the Signal K admin UI (`http://localhost:3000`):

1. Go to **Server → Data Connections**
2. Click **Add**
3. Configure:
   - **Data Type:** NMEA 2000
   - **Provider:** Actisense NGT-1 (canboatjs)
   - **Serial Port:** COM3
   - **Baud Rate:** 115200
4. Click **Apply** and restart

### 4.4 Configure Signal K — NMEA 0183 over Ethernet (H5000 CPU)

1. Determine the H5000 CPU's IP address on the GoFree network (check the Zeus 3S network settings or router DHCP table)
2. In Signal K admin UI → **Server → Data Connections → Add**:
   - **Data Type:** NMEA 0183
   - **Provider:** TCP Client
   - **Host:** [H5000 CPU IP address]
   - **Port:** 10110 (standard NMEA 0183 over TCP port)
3. Apply and restart

### 4.5 Install InfluxDB

1. Download InfluxDB 2.x for Windows from https://influxdata.com
2. Extract and run `influxd.exe`
3. Open `http://localhost:8086`, complete initial setup
4. Create a bucket named `signalk`
5. Generate an API token for Signal K to write data

### 4.6 Install signalk-to-influxdb Plugin

In Signal K admin UI:
1. Go to **Appstore → Available**
2. Search for `signalk-to-influxdb2` (for InfluxDB 2.x)
3. Install, then go to **Server → Plugin Config → InfluxDB**
4. Configure:
   - **URL:** `http://localhost:8086`
   - **Token:** [your InfluxDB API token]
   - **Organization:** [your org name]
   - **Bucket:** `signalk`
   - **Enable:** checked
5. Submit and restart

### 4.7 Install Grafana

1. Download Grafana OSS for Windows from https://grafana.com
2. Run the installer
3. Grafana runs on `http://localhost:3000` by default — change to **port 3001** to avoid conflict with Signal K:
   - Edit `C:\Program Files\GrafanaLabs\grafana\conf\defaults.ini`
   - Set `http_port = 3001`
4. Restart Grafana service
5. Log in at `http://localhost:3001` (default: admin/admin)

### 4.8 Connect Grafana to InfluxDB

1. In Grafana → **Configuration → Data Sources → Add data source**
2. Select **InfluxDB**
3. Configure:
   - **Query Language:** Flux
   - **URL:** `http://localhost:8086`
   - **Organization:** [your org]
   - **Token:** [your API token]
   - **Default Bucket:** `signalk`
4. Click **Save & Test**

### 4.9 Install Wireshark (Ethernet Analysis)

1. Download Wireshark from https://wireshark.org
2. Install with Npcap (packet capture driver for Windows)
3. Install maritime dissectors:
   - Clone `https://github.com/kmpm/wireshark-nmea` (NMEA 0183)
   - Clone `https://github.com/fkie-cad/maritime-dissector` (NMEA 2000)
   - Copy `.lua` files to Wireshark's plugin directory (`%APPDATA%\Wireshark\plugins`)
4. Restart Wireshark — capture on the ethernet interface connected to GoFree router

---

## 5. Grafana Dashboard Design

### Dashboard 1: "NMEA 2000 Network Monitor"

The primary diagnostic view — every PGN on the bus with source, rate, and decoded values.

#### Row 1: Network Health Summary

```
┌──────────────────┬──────────────────┬──────────────────┬─────────────┐
│                  │                  │                  │             │
│  TOTAL PGNs      │  ACTIVE SOURCES  │  MSG RATE        │  ERRORS     │
│                  │                  │                  │             │
│  Stat: 47        │  Stat: 12        │  Stat: 142 msg/s │  Stat: 0    │
│  (big number)    │  (big number)    │  (big number)    │  (red if >0)│
│                  │                  │                  │             │
│  Panel type:     │  Panel type:     │  Panel type:     │  Panel type:│
│  Stat            │  Stat            │  Stat            │  Stat       │
│                  │                  │                  │             │
│  Thresholds:     │  Thresholds:     │  Thresholds:     │  Thresholds:│
│  green >0        │  green >5        │  green >50       │  green =0   │
│  red =0          │  yellow 1-5      │  yellow 10-50    │  yellow 1-5 │
│                  │  red =0          │  red <10         │  red >5     │
└──────────────────┴──────────────────┴──────────────────┴─────────────┘
```

**InfluxDB query for TOTAL PGNs:**
```flux
from(bucket: "signalk")
  |> range(start: -30s)
  |> group(columns: ["_measurement"])
  |> count()
  |> group()
  |> count()
  |> rename(columns: {_value: "Unique PGNs"})
```

**InfluxDB query for MSG RATE:**
```flux
from(bucket: "signalk")
  |> range(start: -10s)
  |> group()
  |> count()
  |> map(fn: (r) => ({r with _value: float(v: r._value) / 10.0}))
  |> rename(columns: {_value: "msg/s"})
```

#### Row 2: Live PGN Table (the core diagnostic view)

```
┌──────────────────────────────────────────────────────────────────────┐
│  LIVE PGN TABLE                                          Filter: [__]│
│                                                                      │
│  PGN    │ Name                  │ Source       │ Rate  │ Last Value   │
│  ───────┼───────────────────────┼──────────────┼───────┼──────────────│
│  127250 │ Vessel Heading        │ H5000 CPU(3) │ 10 Hz │ 224.7°       │
│  128259 │ Speed, Water          │ H5000 CPU(3) │  2 Hz │ 7.23 kts     │
│  128267 │ Water Depth           │ Depth Snsr(7)│  2 Hz │ 12.4 m       │
│  129025 │ Position Rapid Update │ Zeus 3S  (4) │ 10 Hz │ 41.35°N ...  │
│  129026 │ COG/SOG Rapid Update  │ Zeus 3S  (4) │ 10 Hz │ 225° 7.1kts  │
│  130306 │ Wind Data             │ Wind Snsr(5) │  1 Hz │ 14.2kts 045° │
│  127245 │ Rudder                │ Autopilot(6) │  5 Hz │ -3.2°        │
│  127258 │ Magnetic Variation    │ Zeus 3S  (4) │ 0.1Hz │ -14.2°       │
│  126996 │ Product Information   │ Various      │ rare  │ (device info)│
│  065280 │ Manufacturer Propri.  │ H5000 CPU(3) │  1 Hz │ (B&G custom) │
│  ...    │ ...                   │ ...          │ ...   │ ...          │
│                                                                      │
│  Showing 47 PGNs from 12 sources                   [Export CSV]      │
└──────────────────────────────────────────────────────────────────────┘
```

**Panel type:** Table

**Implementation notes:**
- Grafana Table panel querying InfluxDB, or Signal K's REST API via the JSON API datasource plugin
- Signal K exposes source metadata at `/signalk/v1/api/sources` which maps source addresses to device names
- For PGN names, use canboat's PGN definition database (bundled with Signal K) or a Grafana value mapping

**InfluxDB query for PGN table:**
```flux
from(bucket: "signalk")
  |> range(start: -1m)
  |> group(columns: ["_measurement", "source"])
  |> reduce(
      fn: (r, accumulator) => ({
        count: accumulator.count + 1,
        last: r._value
      }),
      identity: {count: 0, last: 0.0}
    )
  |> map(fn: (r) => ({
      r with
      rate_hz: float(v: r.count) / 60.0
    }))
  |> group()
  |> sort(columns: ["_measurement"])
```

#### Row 3: Per-Source Device Panels

One collapsible panel per detected N2K device, using Grafana's **Repeat** feature (template variable = source address).

```
┌──────────────────────────────────────────────────────────────────────┐
│  DEVICE: H5000 CPU (Source Address: 3)                        [▼]    │
│  ─────────────────────────────────────                               │
│  Product: B&G H5000 CPU │ SW: v3.1.2 │ Manufacturer: Navico         │
│  Status: ● ACTIVE (last seen <1s ago)                                │
│                                                                      │
│  PGNs Transmitted:                                                   │
│  ┌─────────┬──────────────────────────┬───────┬─────────────────┐    │
│  │ PGN     │ Name                     │ Rate  │ Last Value      │    │
│  ├─────────┼──────────────────────────┼───────┼─────────────────┤    │
│  │ 127250  │ Vessel Heading           │ 10 Hz │ 224.7°          │    │
│  │ 128259  │ Speed, Water Referenced  │  2 Hz │ 7.23 kts        │    │
│  │ 127245  │ Rudder                   │  5 Hz │ -3.2°           │    │
│  │ 065280  │ Manufacturer Proprietary │  1 Hz │ (hex: 0A3F...)  │    │
│  └─────────┴──────────────────────────┴───────┴─────────────────┘    │
│                                                                      │
│  Total: 12 PGNs │ 22 msg/s │ Uptime: 3d 14h                        │
├──────────────────────────────────────────────────────────────────────┤
│  DEVICE: Zeus 3S Chartplotter (Source Address: 4)             [▼]    │
│  ──────────────────────────────────────────────                      │
│  Product: B&G Zeus 3S │ SW: v22.1 │ Manufacturer: Navico             │
│  Status: ● ACTIVE (last seen <1s ago)                                │
│                                                                      │
│  PGNs Transmitted:                                                   │
│  ┌─────────┬──────────────────────────┬───────┬─────────────────┐    │
│  │ 129025  │ Position, Rapid Update   │ 10 Hz │ 41.35°N 72.09°W │    │
│  │ 129026  │ COG & SOG, Rapid Update  │ 10 Hz │ 225° / 7.1 kts  │    │
│  │ 127258  │ Magnetic Variation       │ 0.1Hz │ -14.2°          │    │
│  │ 129029  │ GNSS Position Data       │  1 Hz │ (full fix data) │    │
│  └─────────┴──────────────────────────┴───────┴─────────────────┘    │
│                                                                      │
│  Total: 8 PGNs │ 25 msg/s │ Uptime: 3d 14h                         │
├──────────────────────────────────────────────────────────────────────┤
│  DEVICE: Wind Sensor (Source Address: 5)                      [▼]    │
│  ──────────────────────────────────────                              │
│  Product: B&G WS320 │ SW: v1.4.0 │ Manufacturer: Navico             │
│  Status: ● ACTIVE (last seen <1s ago)                                │
│                                                                      │
│  PGNs Transmitted:                                                   │
│  ┌─────────┬──────────────────────────┬───────┬─────────────────┐    │
│  │ 130306  │ Wind Data                │  1 Hz │ 14.2kts / 045°  │    │
│  │ 130311  │ Environmental Parameters │ 0.5Hz │ Air: 22.1°C     │    │
│  └─────────┴──────────────────────────┴───────┴─────────────────┘    │
│                                                                      │
│  Total: 2 PGNs │ 1.5 msg/s │ Uptime: 3d 14h                        │
├──────────────────────────────────────────────────────────────────────┤
│  DEVICE: Autopilot (Source Address: 6)                        [▼]    │
│  ─────────────────────────────────────                               │
│  ...                                                                 │
├──────────────────────────────────────────────────────────────────────┤
│  DEVICE: Depth Sensor (Source Address: 7)                     [▼]    │
│  ────────────────────────────────────────                            │
│  ...                                                                 │
├──────────────────────────────────────────────────────────────────────┤
│  DEVICE: Compass / 3D Motion (Source Address: 8)              [▼]    │
│  ───────────────────────────────────────────────                     │
│  ...                                                                 │
├──────────────────────────────────────────────────────────────────────┤
│  DEVICE: Graphic Display 1 (Source Address: 9)                [▼]    │
│  ...                                                                 │
│  DEVICE: Graphic Display 2 (Source Address: 10)               [▼]    │
│  ...                                                                 │
│  DEVICE: HV Display 1 (Source Address: 11)                    [▼]    │
│  ...                                                                 │
│  DEVICE: HV Display 2 (Source Address: 12)                    [▼]    │
│  ...                                                                 │
│  DEVICE: HV Display 3 (Source Address: 13)                    [▼]    │
│  ...                                                                 │
│  DEVICE: Pilot Controller 1 (Source Address: 14)              [▼]    │
│  ...                                                                 │
│  DEVICE: Pilot Controller 2 (Source Address: 15)              [▼]    │
│  ...                                                                 │
└──────────────────────────────────────────────────────────────────────┘
```

**Implementation:**
- Grafana template variable: `$source` populated from InfluxDB tag values
- Repeat panel: one Table + Stat row per `$source` value
- Device product info from Signal K's `/signalk/v1/api/sources` endpoint (PGN 126996 Product Information)
- Status indicator: green if messages received in last 5s, yellow if 5-30s, red if >30s

#### Row 4: Message Rate Timeline

```
┌──────────────────────────────────────────────────────────────────────┐
│  MESSAGE RATE BY SOURCE (last 15 min)                    Refresh: 5s │
│                                                                      │
│  msg/s                                                               │
│  50│  ████ H5000 CPU                                                 │
│  40│  ████████████████████████████████████████████████               │
│  30│  ░░░░ Zeus 3S                                                   │
│  20│  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░                │
│  10│  ▓▓▓▓ Wind / Depth / Compass / Others                           │
│   0│  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓                │
│    └─────────────────────────────────────────────────                │
│     -15m              -10m              -5m       now                 │
│                                                                      │
│  KEY DIAGNOSTIC VALUE:                                               │
│  - Sudden drops in a source's rate = device offline or sensor failure│
│  - Spikes may indicate address claim storms or firmware issues       │
│  - Flat zero for a source that was active = connection lost          │
└──────────────────────────────────────────────────────────────────────┘
```

**Panel type:** Time Series (stacked area)

**InfluxDB query:**
```flux
from(bucket: "signalk")
  |> range(start: -15m)
  |> group(columns: ["source"])
  |> aggregateWindow(every: 5s, fn: count)
  |> map(fn: (r) => ({r with _value: float(v: r._value) / 5.0}))  // normalize to msg/s
```

#### Row 5: Bus Load Indicator

```
┌──────────────────────────────────────────────────────────────────────┐
│  N2K BUS LOAD                                                        │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────┐      │
│  │ ████████████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │      │
│  │ 35%                                                        │      │
│  └────────────────────────────────────────────────────────────┘      │
│                                                                      │
│  Thresholds: Green <50% │ Yellow 50-70% │ Red >70%                   │
│                                                                      │
│  NMEA 2000 CAN bus max: ~250 kbps → ~1600 fast-packet frames/sec    │
│  Current: ~560 frames/sec (35%)                                      │
│                                                                      │
│  NOTE: If bus load exceeds 70%, consider increasing NGT baud to      │
│  230400 via Actisense NMEA Reader                                    │
└──────────────────────────────────────────────────────────────────────┘
```

**Panel type:** Bar Gauge (horizontal) with thresholds

**InfluxDB query:**
```flux
from(bucket: "signalk")
  |> range(start: -10s)
  |> group()
  |> count()
  |> map(fn: (r) => ({r with _value: (float(v: r._value) / 10.0) / 1600.0 * 100.0}))
  |> rename(columns: {_value: "Bus Load %"})
```

---

### Dashboard 2: "Ethernet Traffic Monitor"

Visibility into the B&G ethernet backbone between GoFree router, Zeus 3S, H5000 CPU, and Graphic Displays.

#### Row 1: Ethernet Summary

```
┌──────────────────┬──────────────────┬──────────────────┬─────────────┐
│                  │                  │                  │             │
│  TOTAL BANDWIDTH │  ACTIVE HOSTS    │  NMEA 0183/TCP   │  UPTIME     │
│                  │                  │                  │             │
│  Stat: 2.4 Mbps  │  Stat: 5         │  Stat:           │  Stat:      │
│                  │                  │  142 sentences/s │  3d 14h     │
│  Panel: Stat     │  Panel: Stat     │  Panel: Stat     │  Panel: Stat│
│                  │                  │                  │             │
└──────────────────┴──────────────────┴──────────────────┴─────────────┘
```

**Data source:** Telegraf agent with `net` and `netstat` input plugins writing to the same InfluxDB instance, or use Grafana's JSON API datasource to poll Signal K's TCP connection stats.

#### Row 2: Host Table

```
┌──────────────────────────────────────────────────────────────────────┐
│  ETHERNET HOSTS ON B&G NETWORK                                       │
│                                                                      │
│  IP Address    │ Hostname / Device  │ MAC Address     │ Traffic      │
│  ──────────────┼────────────────────┼─────────────────┼──────────────│
│  192.168.0.1   │ GoFree Router      │ 00:0E:B6:xx:xx  │ 1.2 Mbps     │
│  192.168.0.10  │ H5000 CPU          │ 00:0E:B6:xx:xx  │ 0.8 Mbps     │
│  192.168.0.11  │ Zeus 3S            │ 00:0E:B6:xx:xx  │ 0.3 Mbps     │
│  192.168.0.20  │ Graphic Display 1  │ 00:0E:B6:xx:xx  │ 0.05 Mbps    │
│  192.168.0.21  │ Graphic Display 2  │ 00:0E:B6:xx:xx  │ 0.05 Mbps    │
│  192.168.0.100 │ Geekom A9 (this PC)│ XX:XX:XX:xx:xx  │ 0.01 Mbps    │
│                                                                      │
│  Panel type: Table                                                   │
│  Note: IP addresses are examples — actual IPs depend on GoFree       │
│  router DHCP configuration. Map MAC → device name manually or via    │
│  Grafana value mappings after initial discovery.                     │
└──────────────────────────────────────────────────────────────────────┘
```

**Implementation options:**
- **Option A:** Telegraf `inputs.net` + `inputs.netstat` plugins → InfluxDB → Grafana Table
- **Option B:** Periodic `tshark` captures exported to CSV → InfluxDB (heavier but more detailed)
- **Option C:** Lightweight Python script using `scapy` to do ARP scanning + traffic counting, writing to InfluxDB

#### Row 3: NMEA 0183 Sentence Monitor (via H5000 TCP stream)

```
┌──────────────────────────────────────────────────────────────────────┐
│  NMEA 0183 SENTENCES (from H5000 TCP port 10110)                     │
│                                                                      │
│  Sentence │ Description              │ Rate   │ Last Value           │
│  ─────────┼──────────────────────────┼────────┼──────────────────────│
│  $IIMWV   │ Wind Speed & Angle       │ 1 Hz   │ 045.0,R,14.2,N,A    │
│  $IIVHW   │ Water Speed & Heading    │ 1 Hz   │ 225.0,T,224.7,M,7.2 │
│  $IIDBT   │ Depth Below Transducer   │ 1 Hz   │ 40.7,f,12.4,M,6.8   │
│  $IIHDM   │ Heading Magnetic         │ 2 Hz   │ 224.7,M              │
│  $IIRSA   │ Rudder Sensor Angle      │ 2 Hz   │ -3.2,A,,             │
│  $GPGGA   │ GPS Fix Data             │ 1 Hz   │ 41.3512,N,072.09,W   │
│  $GPRMC   │ Recommended Minimum      │ 1 Hz   │ A,4121.07,N,...      │
│  $IIHTD   │ Heading True & Deviation │ 1 Hz   │ 225.0,T              │
│  $IIXDR   │ Transducer Measurements  │ 1 Hz   │ A,-5.2,D,PITCH,...   │
│  ...      │ ...                      │ ...    │ ...                  │
│                                                                      │
│  Panel type: Table                                                   │
│  Data source: Signal K logs 0183 sentences with timestamps;          │
│  alternatively, direct TCP listener logging to InfluxDB              │
│                                                                      │
│  DIAGNOSTIC VALUE:                                                   │
│  - Compare N2K PGNs vs 0183 sentences to verify H5000 is            │
│    converting correctly                                              │
│  - Missing sentences indicate H5000 0183 output misconfiguration    │
│  - Checksum errors indicate wiring or interference issues            │
└──────────────────────────────────────────────────────────────────────┘
```

#### Row 4: Ethernet Bandwidth Timeline

```
┌──────────────────────────────────────────────────────────────────────┐
│  BANDWIDTH BY HOST (last 60 min)                         Refresh: 10s│
│                                                                      │
│  Mbps                                                                │
│  3.0│                                                                │
│  2.5│  ████ GoFree Router                                            │
│  2.0│  ████████████████████████████████████████████                  │
│  1.5│  ░░░░ H5000 CPU                                                │
│  1.0│  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░                  │
│  0.5│  ▓▓▓▓ Zeus 3S + Displays                                      │
│  0.0│  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓                  │
│    └──────────────────────────────────────────────                   │
│     -60m             -40m            -20m       now                   │
│                                                                      │
│  Panel type: Time Series (stacked area)                              │
│                                                                      │
│  DIAGNOSTIC VALUE:                                                   │
│  - Sudden bandwidth spikes = firmware updates, chart downloads       │
│  - Flat zero for a host = ethernet cable disconnected or device off  │
│  - Unusual patterns may indicate broadcast storms                    │
└──────────────────────────────────────────────────────────────────────┘
```

#### Row 5: Connection Status Map

```
┌──────────────────────────────────────────────────────────────────────┐
│  ETHERNET CONNECTION STATUS                                          │
│                                                                      │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐         │
│  │  GoFree      │     │  H5000 CPU   │     │  Zeus 3S     │         │
│  │  Router      │─────│              │─────│              │         │
│  │  ● ONLINE    │     │  ● ONLINE    │     │  ● ONLINE    │         │
│  │  1.2 Mbps    │     │  0.8 Mbps    │     │  0.3 Mbps    │         │
│  └──────┬───────┘     └──────────────┘     └──────────────┘         │
│         │                                                            │
│    ┌────┴────┬──────────┐                                            │
│    │         │          │                                            │
│  ┌─┴────┐ ┌─┴────┐ ┌───┴────┐                                      │
│  │GFX 1 │ │GFX 2 │ │Geekom  │                                      │
│  │● ON  │ │● ON  │ │● ON    │                                      │
│  └──────┘ └──────┘ └────────┘                                       │
│                                                                      │
│  Panel type: Node Graph or Status Map plugin                         │
│  Green = responding to ping/ARP │ Red = not seen >30s               │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 6. Grafana Alert Rules

Focused on network health diagnostics:

| Alert | Condition | Severity | Action |
|-------|-----------|----------|--------|
| N2K Device Offline | Source message rate = 0 for 30s | Critical | Red indicator on device panel, notification |
| N2K Bus Overload | Total msg rate > 70% of 1600 frames/s | Warning | Yellow bar gauge, notification |
| Ethernet Host Down | No ARP/traffic from known host for 60s | Critical | Red status on connection map |
| NMEA 0183 Checksum Errors | Error count > 0 in 1 min window | Warning | Counter on 0183 sentence table |
| Signal K Server Down | No new data written to InfluxDB for 30s | Critical | Grafana datasource health alert |
| High Bus Latency | PGN delivery delay > 500ms | Warning | Stat panel indicator |

---

## 7. Key Signal K Data Paths Reference

Signal K paths that map to the B&G sensors (useful for building queries):

| Signal K Path | PGN | Source Device | Unit |
|---------------|-----|--------------|------|
| `environment.wind.speedApparent` | 130306 | Wind sensor | m/s |
| `environment.wind.angleApparent` | 130306 | Wind sensor | rad |
| `environment.wind.speedTrue` | 130306 | H5000 (calc) | m/s |
| `environment.wind.angleTrueGround` | 130306 | H5000 (calc) | rad |
| `environment.wind.directionTrue` | 130306 | H5000 (calc) | rad |
| `environment.depth.belowTransducer` | 128267 | Depth sensor | m |
| `navigation.headingMagnetic` | 127250 | Compass | rad |
| `navigation.headingTrue` | 127250 | H5000 (calc) | rad |
| `navigation.courseOverGroundTrue` | 129026 | GPS / Zeus 3S | rad |
| `navigation.speedOverGround` | 129026 | GPS / Zeus 3S | m/s |
| `navigation.speedThroughWater` | 128259 | Paddlewheel | m/s |
| `navigation.position` | 129025 | GPS / Zeus 3S | lat/lon |
| `navigation.rateOfTurn` | 127251 | 3D sensor | rad/s |
| `navigation.attitude` | 127257 | 3D sensor | rad |
| `steering.rudderAngle` | 127245 | Rudder sensor | rad |
| `steering.autopilot.state` | 65341* | H5000 autopilot | enum |
| `steering.autopilot.target.headingTrue` | 65341* | H5000 autopilot | rad |

*Autopilot PGNs are often manufacturer-proprietary (PGN 065280/065341).

---

## 8. Additional Diagnostic Queries

### Query: Devices Not Seen Recently (offline detection)
```flux
import "date"

lastSeen = from(bucket: "signalk")
  |> range(start: -5m)
  |> group(columns: ["source"])
  |> last()
  |> map(fn: (r) => ({
      r with
      seconds_ago: int(v: date.sub(d: r._time, from: now())) / -1000000000
    }))

lastSeen
  |> filter(fn: (r) => r.seconds_ago > 30)
  |> rename(columns: {source: "Offline Device"})
```

### Query: PGN Rate Anomaly Detection
```flux
// Compare current minute's rate to 15-minute average
current = from(bucket: "signalk")
  |> range(start: -1m)
  |> group(columns: ["_measurement", "source"])
  |> count()

baseline = from(bucket: "signalk")
  |> range(start: -15m)
  |> group(columns: ["_measurement", "source"])
  |> count()
  |> map(fn: (r) => ({r with _value: r._value / 15}))

// Significant deviation from baseline indicates a problem
```

### Query: Message Rate Heatmap (PGN x Time)
```flux
from(bucket: "signalk")
  |> range(start: -1h)
  |> group(columns: ["_measurement"])
  |> aggregateWindow(every: 1m, fn: count)
  |> pivot(rowKey: ["_time"], columnKey: ["_measurement"], valueColumn: "_value")
```

---

## 9. Notes and Considerations

### Performance
- The Geekom A9 (AMD Ryzen 9) has more than enough power for this entire stack
- InfluxDB retention: consider a 7-day retention policy for raw high-frequency data, with a 90-day downsampled bucket (1-minute aggregates) for trend analysis
- Grafana auto-refresh: set dashboards to 5-second refresh for monitoring; 1-second if actively debugging

### Unit Conversion
- Signal K stores everything in SI units (m/s, radians, meters, Kelvin)
- For diagnostics, raw SI values are fine — but you can convert in Grafana queries if preferred
- Wind: multiply m/s by 1.94384 for knots
- Angles: multiply radians by 57.2958 for degrees (or use Grafana's unit setting)

### Security
- All services run locally on the Geekom A9 — no internet exposure needed
- If accessing dashboards from other devices on the GoFree network (tablet, phone), ensure Grafana binds to `0.0.0.0` instead of `localhost`

### B&G Proprietary PGNs
- The H5000 system uses proprietary PGN 065280 for B&G-specific data (calibration values, performance calculations, custom data fields)
- canboat has partial decoding for some Navico/B&G proprietary PGNs, but not all
- These will appear in the PGN table as "Manufacturer Proprietary" — the raw hex data is still captured and stored
- This is valuable diagnostic information: you can observe update rates and detect when proprietary messages stop flowing even without full decoding

### Wireshark Integration
- Wireshark runs independently of the Grafana stack — use it for deep packet inspection when the dashboards flag an issue
- Consider running `tshark` (Wireshark CLI) as a background service with rolling pcap captures for post-incident analysis
- The `fkie-cad/maritime-dissector` plugin decodes NMEA 2000 PGNs within ethernet frames, showing source/destination addresses, priority, and data fields
