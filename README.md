# Net Design — Network Topology & Protocol Sandbox

An interactive, offline-first **Layer 2 / Layer 3 Network Topology & Protocol Sandbox** desktop application for **Windows, macOS, and Linux**, built for designing, simulating, and troubleshooting live-production and AV networks (**sACN**, **Art-Net**, **Dante / AES67**, **NDI**, and control networks) before deploying hardware on site.

> **User Manual:** View or download the full illustrated guide in [USER_MANUAL.pdf](USER_MANUAL.pdf) (also accessible from the `?` button in the app's top bar).

---

## ✨ What Net Design Does

### Interactive Design Canvas
- **Visual Topology Workspace:** Place managed/unmanaged switches and endpoints on a pannable, zoomable canvas (`45%`–`200%`). New devices automatically appear in the center of whichever part of the canvas you are currently viewing.
- **Fast Editing:** Right-click any switch, endpoint, or empty canvas area to **Copy**, **Paste**, or **Delete**, with full keyboard shortcuts (`Ctrl+C`, `Ctrl+V`, `Delete`, and 30-step `Ctrl+Z` / `Ctrl+Y` Undo/Redo).
- **Dark & Light Mode:** Defaults to low-glare Dark Mode for control rooms and FOH desks, with one-click Light Mode switching and live theme sync across the Network Suite.

### Spanning Tree (STP / RSTP) Simulation
- **Root Bridge Election:** Simulates IEEE 802.1D / 802.1w Bridge ID election using STP Priority and editable **Bridge MAC** addresses. Use **Randomise MACs** to test tie-breaking when switch priorities are equal.
- **Redundant Ring Blocking & Loop Detection:** Automatically places redundant links into `BLK (STP)` state, flags excessive hop depth (`> 6` hops), and highlights **Unprotected Layer 2 Loops** (`LOOP!`) when unmanaged or STP-disabled switches close a cycle.

### VLAN Segmentation & Trunk Validation
- **Switch Faceplate Matrix:** Click any port on a switch to configure **Access** or **Trunk** mode, Native VLAN, Allowed VLANs, port speed, and PoE state.
- **Visual Filters:** Filter the canvas by **All**, **Trunks** (highlights only symmetrically configured trunks), or any custom VLAN (displayed with its label, e.g. `Lighting (5)`).
- **Fault Highlighting & Auto-Fix:** Pruned trunk links highlight in red with `VLAN X PRUNED` badges, and the Link Inspector includes a one-click **Fix Trunk VLAN Symmetry** action.

### Physical Port Media, Multi-NIC Endpoints & Resource Budgets
- **RJ45 Copper vs. SFP / Fibre:** Define copper ports (`100M`, `1G`, `2.5G`, `10G`) and fibre slots (`1G SFP`, `10G SFP+`). Cross-wiring copper to fibre is flagged as `MEDIA MISMATCH`, while speed mismatches show `1G SFP STEP-DOWN` or `100M STEP-DOWN`.
- **Multi-NIC Endpoints:** Configure up to 8 network interfaces per endpoint (mixing RJ45 and SFP/Fibre) and bind TX/RX traffic flows to specific NICs.
- **PoE & Bandwidth Budgets:** Aggregates PoE draw against each switch's PoE watt budget (copper ports only) and estimates link bandwidth utilization across forwarding paths.

### IGMP Snooping, Querier & Multicast Stream Tracing
- **IGMP Domain Analysis:** Configure per-VLAN **IGMP Snooping**, **IGMP Querier**, **IGMPv2 / IGMPv3**, and **Drop Unknown Multicast**. Detects snooping-without-querier faults, IGMP version conflicts, Querier/STP-Root splits, and 100M flood risks.
- **Multicast & sACN Flow Tracing:** Map sACN universe ranges (e.g. `1-16` &rarr; `239.255.x.x`) or custom multicast IP groups (e.g. Dante/AES67 `239.69.0.1-2`), with quick-pick RX subscription chips and duplicate TX / orphan RX diagnostics.
- **Trace Stream View:** Select a whole VLAN (`All VLAN 20 Streams`), a TX/RX bundle, or an individual universe/group in the **Trace Stream** dropdown to visualize `DELIVERED` (green), `FLOODED` (amber), and `IGMP PRUNED` (dashed muted) paths across the network.

### Device Library, Scenarios & Exports
- **Customizable Device Library:** Create, edit, import, and export Switch and Endpoint templates (JSON), with opt-in **Update Plan** syncing so template edits never overwrite placed devices without your consent.
- **Built-In Scenarios:** Load reference and fault-finding demos (`Healthy Reference Ring`, `Arbitrary Root & VLAN Blackhole`, `Unmanaged Loop & 100M Flood`) to explore common live-event failure modes.
- **Diagnostics & Exports:** Click any issue in the bottom **Issues Drawer** to center the canvas on the offending device or cable, inspect the **CLI Config Preview**, save/open `.netdesign` project files, or copy a Markdown validation report.

---

## ⌨️ Keyboard Shortcuts

| Action | Windows / Linux | macOS |
| :--- | :--- | :--- |
| **Copy selected device** | `Ctrl+C` | `Cmd+C` |
| **Paste device** | `Ctrl+V` | `Cmd+V` |
| **Delete selected device or link** | `Delete` / `Backspace` | `Delete` |
| **Undo** | `Ctrl+Z` | `Cmd+Z` |
| **Redo** | `Ctrl+Y` or `Ctrl+Shift+Z` | `Cmd+Shift+Z` |

---

## ⚠️ Engineering Advisory

Net Design models logical Layer 2 / Layer 3 behaviour (STP, VLANs, IGMP, link speeds, multicast paths, and PoE budgets) to help catch configuration errors early. Real-world installations can involve vendor-specific firmware quirks, optical transceiver compatibility, and physical cabling factors that may require on-site verification and adjustment.

---

## 📖 Documentation

- **User Manual (PDF):** [USER_MANUAL.pdf](USER_MANUAL.pdf)
- **Application Specification:** [SPECIFICATION.md](SPECIFICATION.md)
- **Physical Media & Multicast Stream Spec:** [FEATURE_SPECS_MEDIA_AND_STREAMS.md](FEATURE_SPECS_MEDIA_AND_STREAMS.md)
- **Suite UI & Design Principles:** [UI_AND_DESIGN_PRINCIPLES.md](UI_AND_DESIGN_PRINCIPLES.md)

---

## 🖥️ Supported Desktop Platforms

Prebuilt binaries for **Windows**, **macOS**, and **Linux** are built via GitHub Actions on each release tag:

- **Windows** (`windows/`): Win32 desktop runner (`1280x720` default window).
- **macOS** (`macos/`): Cocoa desktop runner with user-selected file & network client entitlements.
- **Linux** (`linux/`): GTK3 desktop runner (`1280x720` default window).

---

## 🏗️ Architecture & Directory Layout

```text
net-design/
├── USER_MANUAL.pdf                  # Illustrated desktop user manual
├── SPECIFICATION.md                 # Primary application specification & engine checklist
├── FEATURE_SPECS_MEDIA_AND_STREAMS.md
├── UI_AND_DESIGN_PRINCIPLES.md      # Suite UI & dynamic Dark/Light token guide
├── lib/
│   ├── main.dart                    # Desktop entrypoint & suite theme synchronizer
│   ├── data/
│   │   └── services/                # Project storage, template library & theme services
│   ├── domain/
│   │   ├── engine/                  # Deterministic solvers (STP, VLAN, IGMP, Streams, Budget, CLI)
│   │   └── models/                  # Switch & Endpoint templates, instances, links, issues
│   └── ui/
│       ├── features/
│       │   ├── canvas/              # Interactive topology canvas, node cards & link painters
│       │   ├── inspector/           # Switch/Endpoint/Link inspectors, VLAN matrix & issues drawer
│       │   └── library/             # Switch & Endpoint template library dialogs
│       ├── theme/
│       │   └── app_theme.dart       # Dynamic Dark/Light theme tokens
│       └── widgets/                 # Top control bar, advisory & rename dialogs
├── linux/                           # Linux desktop runner
├── macos/                           # macOS desktop runner
├── windows/                         # Windows desktop runner
└── test/                            # Solver unit tests, widget tests & fuzz tests
```

---

## 🚀 Development Quick Start

```bash
# Fetch dependencies
flutter pub get

# Run static analysis
flutter analyze

# Execute all tests
flutter test

# Run the desktop app on your OS (linux, macos, or windows)
flutter run -d linux
```
