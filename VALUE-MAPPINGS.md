# VALUE-MAPPINGS.md — Grafana Value Mapping Reference

B&G Network Diagnostics Dashboard — reference sheet for populating Grafana value mappings
after initial discovery. These tables are **templates**: fill in the actual source addresses
and IP addresses after your first run (see notes at bottom of each section).

---

## 1. NMEA 2000 PGN Numbers → Human-Readable Names

Enter these in Grafana: **Dashboard Settings → Value Mappings** for any panel that displays
the `pgn` tag (e.g. the Live PGN Table, Per-Device PGN tables).

Unknown PGNs not in this list should display as `Unknown (PGN XXXXXX)` — configure this
as the default/fallback mapping.

| PGN (decimal) | Human-Readable Name |
|---------------|---------------------|
| 059392 | ISO Acknowledgement |
| 059904 | ISO Request |
| 060928 | ISO Address Claim |
| 065240 | ISO Commanded Address |
| 065280 | B&G / Navico Proprietary (Manufacturer Proprietary) |
| 065341 | B&G Autopilot State (Manufacturer Proprietary) |
| 126208 | NMEA Request/Command/Acknowledge Group Function |
| 126992 | System Time |
| 126993 | Heartbeat |
| 126996 | Product Information |
| 126998 | Configuration Information |
| 127237 | Heading/Track Control |
| 127245 | Rudder Angle |
| 127250 | Vessel Heading |
| 127251 | Rate of Turn |
| 127257 | Attitude (Pitch, Roll, Yaw) |
| 127258 | Magnetic Variation |
| 127488 | Engine Parameters (Rapid Update) |
| 127489 | Engine Parameters (Dynamic) |
| 127505 | Fluid Level |
| 127508 | Battery Status |
| 128259 | Speed Through Water |
| 128267 | Water Depth |
| 128275 | Distance Log |
| 129025 | Position (Rapid Update) |
| 129026 | COG & SOG (Rapid Update) |
| 129029 | GNSS Position Data |
| 129033 | Time & Date |
| 129038 | AIS Class A Position Report |
| 129039 | AIS Class B Position Report |
| 129283 | Cross Track Error |
| 129284 | Navigation Data |
| 129285 | Navigation — Route/WP Information |
| 129539 | GNSS DOPs |
| 129540 | GNSS Sats in View |
| 129793 | AIS UTC and Date Report |
| 129794 | AIS Class A Static and Voyage Related Data |
| 129798 | AIS SAR Aircraft Position Report |
| 129809 | AIS Class B CS Static Data Report, Part A |
| 129810 | AIS Class B CS Static Data Report, Part B |
| 130306 | Wind Data |
| 130310 | Water Temperature / Outside Temperature |
| 130311 | Environmental Parameters |
| 130312 | Temperature (Detailed) |
| 130313 | Humidity |
| 130314 | Actual Pressure |

**B&G Proprietary PGN note:** PGNs 065280–065341 are B&G/Navico proprietary. canboatjs has
partial decoding for some of these; others will show raw hex. Update rates are still monitored
and diagnostically valuable — silence from a proprietary PGN can indicate a firmware issue
even without full decoding.

---

## 2. N2K Source Addresses → Device Names

Enter these in Grafana value mappings for the `source` tag after your first run.

**How to discover:** Run the dashboard for a few minutes and inspect the Live PGN Table —
source addresses appear as decimal integers (0–253). PGN 126996 (Product Information) will
reveal each device's manufacturer name, model, and serial number for confident identification.

> **Fill in after first run** — source addresses are assigned dynamically by the N2K address
> claim process (ISO 11783-5) and may change if devices are added/removed.

| N2K Source Address | Device Name | Notes |
|--------------------|-------------|-------|
| _(fill in)_ | B&G H5000 CPU | Central processor; outputs NMEA 0183 on TCP 10110 |
| _(fill in)_ | B&G Zeus 3S Chartplotter | MFD; GPS source |
| _(fill in)_ | B&G H5000 Autopilot | Heading control |
| _(fill in)_ | B&G H5000 Pilot Controller 1 | Autopilot UI handset |
| _(fill in)_ | B&G H5000 Pilot Controller 2 | Autopilot UI handset |
| _(fill in)_ | B&G H5000 Graphic Display 1 | Instrument display |
| _(fill in)_ | B&G H5000 Graphic Display 2 | Instrument display |
| _(fill in)_ | B&G HV Display 1 | Large-format display |
| _(fill in)_ | B&G HV Display 2 | Large-format display |
| _(fill in)_ | B&G HV Display 3 | Large-format display |
| _(fill in)_ | Airmar ST850 | Speed through water (paddlewheel) |
| _(fill in)_ | Depth Sensor | Water depth (transducer) |
| _(fill in)_ | Wind Sensor | Apparent wind speed and angle |
| _(fill in)_ | Compass / 3D Motion Sensor | Heading, pitch, roll, rate of turn |
| _(fill in)_ | Actisense NGT-1 | N2K-to-PC bridge (COM3); usually appears as a source for ISO frames |
| 255 | N2K Broadcast | Broadcast address — not a real device |

---

## 3. Ethernet IP Addresses → Device Names

Enter these in Grafana value mappings for the `host` field in the Ethernet Host Table panel.

**How to discover:** Run `arp -a` from the Geekom A9 after connecting to the GoFree network,
or check the GoFree router's admin page for DHCP leases. The Telegraf ARP scan will also
populate InfluxDB with discovered hosts after the first collection cycle (every 30s).

> **Fill in after first run** — IPs may be DHCP-assigned and can change.
> Consider setting static DHCP leases in the GoFree router to keep these stable.

| IP Address | Device Name | Notes |
|------------|-------------|-------|
| _(fill in)_ | B&G GoFree Router | Default gateway; admin UI on port 80 |
| _(fill in)_ | B&G H5000 CPU | NMEA 0183 TCP output on port 10110 |
| _(fill in)_ | B&G Zeus 3S Chartplotter | MFD |
| _(fill in)_ | B&G H5000 Graphic Display 1 | Ethernet-connected instrument display |
| _(fill in)_ | B&G H5000 Graphic Display 2 | Ethernet-connected instrument display |
| 127.0.0.1 | Geekom A9 (localhost) | Dashboard host — not a B&G device |

---

## 4. NMEA 0183 Sentence Types → Descriptions

Enter these in Grafana value mappings for the NMEA 0183 Sentence Monitor panel (`sentence` tag).

The H5000 CPU outputs NMEA 0183 sentences on TCP port 10110. Signal K tags each decoded
sentence with its talker ID + sentence type (e.g. `II-MWV`, `GP-GGA`). Map the sentence
type portion here; Grafana will match on the suffix.

| Sentence Type | Description |
|---------------|-------------|
| GGA | Global Positioning System Fix Data (position, altitude, fix quality) |
| GLL | Geographic Position — Latitude/Longitude |
| GSA | GPS DOP and Active Satellites |
| GSV | Satellites in View |
| HDG | Heading with Deviation and Variation |
| HDT | Heading True |
| MWV | Wind Speed and Angle (apparent or true) |
| RMC | Recommended Minimum Specific GNSS Data (position, COG, SOG) |
| VHW | Water Speed and Heading |
| VTG | Track Made Good and Ground Speed |
| VWR | Relative Wind Speed and Angle (apparent) |
| DBT | Depth Below Transducer |
| DPT | Depth of Water (below transducer + offset) |
| MTW | Mean Temperature of Water |
| MWD | Wind Direction and Speed (true) |
| RSA | Rudder Sensor Angle |
| ROT | Rate of Turn |
| XDR | Transducer Measurement (generic — pitch, roll, temperature, etc.) |
| VDR | Set and Drift (current direction and speed) |
| VDM | AIS VHF Data-Link Message (Class A/B position, static data) |
| VDO | AIS VHF Data-Link Own-Vessel Report |
| APB | Autopilot Sentence B (heading to steer, XTE) |
| BOD | Bearing — Origin to Destination Waypoint |
| BWC | Bearing and Distance to Waypoint (Great Circle) |
| RTE | Routes |
| WPL | Waypoint Location |
| XTE | Cross-Track Error (measured) |
| ZDA | Time and Date |

---

## 5. Notes on Mapping Workflow

1. **Run first.** Start the full stack (Signal K, InfluxDB, Telegraf, Grafana) and let it
   collect data for at least 5 minutes before populating mappings.

2. **Check the Live PGN Table** in Dashboard 1. Every PGN on your bus will appear here.
   Cross-reference unknown source addresses against PGN 126996 rows to identify devices.

3. **Check the Ethernet Host Table** in Dashboard 2. All ARP-visible hosts will appear.
   Compare against the GoFree router's DHCP lease list to confirm device identity.

4. **Enter mappings in Grafana** via:
   - Panel Edit → Value Mappings (for individual panels), or
   - Dashboard Settings → Templating (for template variable label mappings)

5. **Consider static DHCP leases.** Ask your GoFree router to always assign the same IP
   to each device's MAC address. This prevents IP changes across power cycles and keeps
   your Telegraf ping list and Grafana IP mappings stable.

6. **Re-check after network changes.** Adding a new N2K device triggers an address claim
   storm — source addresses for existing devices may change. Re-verify the source address
   table after any hardware addition or removal.
