# Specification: Vendor-Neutral Network Topology & VLAN/STP Design Sandbox

## 1. Overview & Design Philosophy

Build an interactive, offline-first **Layer 2 / Layer 3 Network Topology & Protocol Sandbox** desktop application in Flutter. 

To remain future-proof and focused strictly on network engineering fundamentals rather than product marketing, this application avoids vendor-locked hardware catalogs. Instead, it provides a **Local User-Editable Template Library** based purely on physical port tier breakdowns (`100M`, `1G`, `2.5G`, `5G`, `10G`), PoE budgets, and abstract traffic profiles.

Users drag custom-defined switches and endpoints onto a visual canvas, configure port-level VLANs, trunks, STP priorities, and IGMP settings, and receive **real-time deterministic validation** of potential faults—such as STP loop hazards, arbitrary Root Bridge elections, VLAN trunk blackholes, link speed bottlenecks, and IGMP snooping timeouts—before deploying hardware on-site.

---

## 2. Local Template Library (Vendor-Neutral)

All switch and endpoint blueprints are stored locally (e.g., `templates_library.json` in the application support directory, with JSON import/export support) and seeded with generic starter templates that the user can edit, duplicate, delete, or expand at any time.

### 2.1 Switch Template Builder (`SwitchTemplate`)
When creating or editing a switch template in the library, the user defines:
* **Template Name:** Generic role label (e.g., *"Compact 8-Port PoE + 2x 1G SFP"*, *"24-Port 1G + 4x 10G Core"*).
* **Port Tier Breakdown:** Exact port counts per physical link capability:
  * `ports100M`: Integer (e.g., `0` or `8` for legacy nodes)
  * `ports1G`: Integer (e.g., `8`, `16`, `24`, `48`)
  * `ports2_5G`: Integer (e.g., `0`, `4`, `8`)
  * `ports5G`: Integer (e.g., `0`, `2`)
  * `ports10G`: Integer (e.g., `0`, `2`, `4`)
  * *Port Generation:* Automatically generates sequential logical interfaces (`Port 1` through `Port N`, ordered from lowest speed tier to highest uplink tier, with user-editable port labels).
* **PoE Capability:**
  * `poeBudgetWatts`: Integer (`0` for non-PoE, or e.g., `65`, `120`, `370`, `740`).
  * `poeCapablePortRange`: Optional start/end port indices (e.g., Ports 1–8 supply PoE, Ports 9–10 SFP uplinks do not).
* **Default Switch Capabilities:**
  * `supportsStp`: Boolean (distinguishes managed switches from unmanaged/dumb switches).
  * `supportsVlans`: Boolean.
  * `supportsIgmpSnooping`: Boolean.
  * `supportsIgmpQuerier`: Boolean.

### 2.2 Endpoint / Node Template Builder (`EndpointTemplate`)
When creating or editing an endpoint template (e.g., lighting console, sACN gateway, audio stagebox, media server, wireless AP), the user defines:
* **Template Name:** Generic device role (e.g., *"Lighting Console (Primary)"*, *"4-Port DMX/sACN Node"*, *"64-Ch Audio Stagebox"*, *"Video Media Server"*).
* **Node Category Icon:** `Console`, `Gateway/Node`, `Audio/DSP`, `Media Server`, `Control/PC`, `Generic Endpoint`.
* **Physical NIC Speed:** Enum (`100M`, `1G`, `2.5G`, `5G`, `10G`).
* **PoE Requirement (`poeDrawWatts`):** Double (e.g., `0W` mains-powered, `12.5W` Class 3 node, `25W` Class 4 touchscreen/AP).
* **Traffic Demand Profiles (`List<TrafficRequirement>`):** A device can generate or subscribe to one or more traffic flows:
  * `protocol`: Enum (`sACN / E1.31`, `Art-Net`, `ACN / E1.17`, `Dante / AES67`, `NDI / Video`, `Control / Unicast`, `Custom`).
  * `direction`: Enum (`TX / Publisher`, `RX / Subscriber`, `Bidirectional`).
  * `deliveryType`: Enum (`Multicast`, `Broadcast`, `Unicast`).
  * `estimatedBandwidthMbps`: Double (auto-calculated via helper—e.g., `0.25 Mbps` per sACN universe, `100 Mbps` per 64ch audio stream—or manually entered by the user).
  * `requiresIgmp`: Boolean (true for multicast subscribers).
  * `defaultVlanId`: Integer (e.g., `1`, `20`, `30`).

---

## 3. Data Models (Canvas Instances & Graph)

```
lib/
├── data/
│   └── services/
│       ├── library_storage_service.dart      <-- Local JSON persistence + Import/Export
│       └── project_storage_service.dart      <-- Saves/loads canvas diagrams
├── domain/
│   ├── models/
│   │   ├── switch_template.dart
│   │   ├── endpoint_template.dart
│   │   ├── switch_node_instance.dart
│   │   ├── endpoint_node_instance.dart
│   │   ├── switch_port_config.dart
│   │   ├── network_link_edge.dart
│   │   └── validation_issue.dart
│   └── engine/
│       ├── topology_validator.dart           <-- Orchestrates all 4 rule passes
│       ├── stp_election_solver.dart          <-- Bridge ID election, cycle & split solver
│       ├── vlan_reachability_solver.dart     <-- Per-VLAN BFS path tracer
│       ├── igmp_domain_solver.dart           <-- Per-VLAN snooping/querier check
│       └── resource_budget_solver.dart       <-- Link bandwidth & PoE aggregation
└── ui/
    └── features/
        ├── library/
        │   ├── library_drawer.dart
        │   ├── edit_switch_template_dialog.dart
        │   └── edit_endpoint_template_dialog.dart
        ├── canvas/
        │   ├── design_canvas.dart
        │   ├── switch_node_widget.dart
        │   ├── endpoint_node_widget.dart
        │   └── link_edge_painter.dart
        └── inspector/
            ├── node_inspector_panel.dart
            ├── port_vlan_matrix_editor.dart
            └── issues_drawer_panel.dart
```

### 3.1 `SwitchNodeInstance` (Placed on Canvas)
* `id`: UUID
* `templateId`: Reference to `SwitchTemplate`
* `userLabel`: Custom instance name editable anytime on the canvas (e.g., *"FOH Rack Switch A"*, *"Truss 1 Switch"*)
* `macAddress`: String (6-byte hex, e.g., `02:00:00:4A:1F:09` — locally administered OUI by default)
* `managementIp`: Optional IPv4 string
* `stpMode`: Enum (`disabled`, `stp`, `rstp`)
* `stpPriority`: Integer (`0` to `61440` in increments of `4096`, default `32768`)
* `vlanConfigs`: Map of `vlanId -> SwitchVlanSettings`:
  * `vlanName`: String (e.g., `"Control"`, `"sACN"`, `"Dante"`)
  * `igmpSnoopingEnabled`: Boolean
  * `igmpQuerierEnabled`: Boolean
  * `igmpQuerierVersion`: Enum (`v2`, `v3`)
  * `dropUnregisteredMulticast`: Boolean
* `ports`: `List<SwitchPortConfig>` (generated from template port tier counts)

### 3.2 `SwitchPortConfig`
* `portNumber`: Integer (`1..N`)
* `maxSpeed`: Enum (`speed100M`, `speed1G`, `speed2_5G`, `speed5G`, `speed10G`)
* `poeCapable`: Boolean
* `poeEnabled`: Boolean
* `portMode`: Enum (`access`, `trunk`)
* `nativeVlan`: Integer (PVID, default `1`)
* `allowedVlans`: `Set<int>` (used when `portMode == trunk`)
* `lagGroupId`: Optional Integer (e.g., `1` for Port-Channel 1)

### 3.3 `EndpointNodeInstance` (Placed on Canvas)
* `id`: UUID
* `templateId`: Reference to `EndpointTemplate`
* `userLabel`: Custom instance name (e.g., *"Main Console"*, *"Stage Left Dimmer Node"*)
* `ipAddress`: Optional IPv4 string
* `activeTrafficFlows`: Cloned from `EndpointTemplate.trafficProfiles` (editable per instance)
* `poeDrawWatts`: Double (editable per instance)

### 3.4 `NetworkLinkEdge`
* `id`: UUID
* `sourceNodeId`: String
* `sourcePortNumber`: Integer
* `targetNodeId`: String
* `targetPortNumber`: Integer
* **Computed Simulation Outputs:**
  * `negotiatedSpeed`: `min(sourcePort.maxSpeed, targetPort.maxSpeed)`
  * `stpState`: Enum (`forwarding`, `blocking`, `loopUnprotected`, `notApplicable`)
  * `activeVlans`: `Set<int>` (intersection of VLANs permitted by both ends)
  * `estimatedLoadMbps`: Double

---

## 4. Deterministic Validation & Simulation Engine

Every time the user adds a node, connects a cable, toggles a setting, or clicks **"Randomise MAC Addresses"**, `TopologyValidator` runs the following four passes synchronously:

### 4.1 Pass 1: Spanning Tree Election & Ring Split Solver (`StpElectionSolver`)
1. **Unmanaged / STP-Disabled Loop Check (`Critical`):**
   * Detect cycles containing any switch where `supportsStp == false` or `stpMode == disabled`.
   * *Flag:* `"Unprotected Layer 2 Loop detected between [Switch A] and [Switch B] — broadcast/multicast storm hazard."`
2. **Root Bridge Election (`Info` / `Warning`):**
   * Compare all STP-enabled switches by `Bridge ID = (stpPriority << 48) | macAddressInt`.
   * The lowest Bridge ID becomes the **Root Bridge** (`isRootBridge = true`).
   * *Warning if default:* If the winning Root Bridge still has `stpPriority == 32768`, emit: `"Root Bridge elected arbitrarily by MAC address on [Switch Label] (default priority 32768). Set explicit priority 4096 on your core switch."`
3. **Shortest-Path Tree & Blocking Port (`Info`):**
   * Compute path costs from the Root Bridge using IEEE 802.1D/802.1w link costs (`10G = 2`, `5G = 3`, `2.5G = 4`, `1G = 4`, `100M = 19`).
   * Any redundant link not selected in the shortest-path spanning tree is marked `stpState = blocking` at the higher-cost / higher-Bridge-ID end.
4. **Ring Hop Depth (`Warning`):**
   * If maximum hop depth from Root Bridge exceeds `6` hops, warn about RSTP convergence latency and TCN multicast flushes.

### 4.2 Pass 2: Port VLAN & End-to-End Reachability Tracer (`VlanReachabilitySolver`)
1. **Link-Level Symmetry Checks:**
   * **Access-to-Trunk Mismatch (`Critical`):** One end of an inter-switch link is `portMode == access` while the other end is `portMode == trunk`.
   * **Native VLAN Mismatch (`Critical`):** Both ends are `trunk`, but `portA.nativeVlan != portB.nativeVlan`.
   * **Asymmetric Allowed VLANs (`Warning`):** `portA.allowedVlans` contains VLANs missing from `portB.allowedVlans` (e.g., `"VLAN 20 is allowed out of [Switch A: Port 9] but blocked on [Switch B: Port 9]"`).
2. **Endpoint-to-Endpoint Path Trace:**
   * For every `EndpointNodeInstance`, determine its ingress VLAN from the switch port it is plugged into (`port.nativeVlan`).
   * Run a **VLAN-Filtered BFS** across all `stpState == forwarding` links where `vlanId` is permitted on *both* ingress and egress ports of every hop.
   * **Isolated Endpoint / Blackhole (`Critical`):** If two endpoints share the same protocol/VLAN (e.g., an sACN Publisher on VLAN 20 and an sACN Subscriber on VLAN 20) but cannot reach each other because a trunk link drops VLAN 20 or is set to `Access VLAN 1`, highlight the exact blocking port and flag: `"[Endpoint B] on VLAN 20 cannot reach [Endpoint A] — VLAN 20 is not carried across [Switch A Port 9 -> Switch B Port 9]."`

### 4.3 Pass 3: Per-VLAN IGMP Snooping & Active Querier Solver (`IgmpDomainSolver`)
Evaluate each active VLAN independently across its connected forwarding subgraph:
1. **Snooping Active Without a Querier (`Critical`):**
   * If any switch in the VLAN's reachable subgraph has `igmpSnoopingEnabled == true`, verify that at least one reachable switch in that **same VLAN** has `igmpQuerierEnabled == true`.
   * *Flag:* `"VLAN [X] has IGMP Snooping enabled on [Switch A], but no reachable IGMP Querier on VLAN [X]. Multicast streams will time out and drop after ~260 seconds."`
2. **Querier / Root Bridge Split (`Warning`):**
   * If the active IGMP Querier (lowest management IP among enabled queriers on that VLAN) is on a different switch than the STP Root Bridge, warn that multicast traffic will hair-pin across trunk links.
3. **IGMP Version Conflict (`Warning`):**
   * Flag if switches in the same VLAN mix `IGMPv2` and `IGMPv3` querier settings.
4. **Flooded Multicast / Broadcast into 100M Port (`Warning`):**
   * If `igmpSnoopingEnabled == false` (or traffic is `Broadcast` like Art-Net) and aggregate multicast/broadcast exceeds `70 Mbps` on a switch with `100M` access ports, warn of port saturation on `100M` nodes.

### 4.4 Pass 4: Bandwidth & PoE Budget Aggregation (`ResourceBudgetSolver`)
1. **Link Utilization (`Warning` / `Critical`):**
   * Trace active traffic flows along the `stpState == forwarding` tree and sum `estimatedBandwidthMbps` per link.
   * Flag `Warning` if load $> 75\%$ of `negotiatedSpeed`, and `Critical` if load $> 95\%$.
   * Flag `Info` if a `10G` port is connected to a `1G` or `100M` port (`negotiatedSpeed` stepped down).
2. **PoE Budget & Port Capability (`Critical`):**
   * If an endpoint with `poeDrawWatts > 0` is plugged into a port with `poeCapable == false` or `poeEnabled == false`, flag: `"[Endpoint] requires [X]W PoE, but [Switch: Port Y] does not supply PoE."`
   * Sum `poeDrawWatts` of all powered endpoints per switch; flag `Warning` if total $> 80\%$ of `poeBudgetWatts` and `Critical` if total $> 100\%$.

---

## 5. Key UI Features & Interactive Controls

### 5.1 Top Simulation Toolbar
* **Randomise Switch MACs Button (`🎲 Randomise MACs`):**
  * Regenerates randomized locally-administered MAC addresses for every switch on the canvas and immediately re-runs `TopologyValidator`.
  * Visually demonstrates how an unconfigured ring (`Priority 32768`) shifts its **Root Bridge** and **Blocking (`BLK`) Link** unpredictably when hardware is swapped or rebooted.
* **VLAN Path Highlighter (`Highlight VLAN: [ All | VLAN 1 | VLAN 20 | VLAN 30 ... ]`):**
  * Dims unrelated links and illuminates every port and cable carrying the selected VLAN in high-contrast green, while pulsing red on the exact trunk port where the VLAN stops.
* **Library Manager Button (`📚 Device Library`):**
  * Opens the local template editor to create/edit custom Switch Templates (specifying `100M` / `1G` / `2.5G` / `5G` / `10G` port counts and PoE budget) and Endpoint Templates (specifying traffic profiles and PoE draw).

### 5.2 Interactive Canvas & Node Cards
* **Switch Card:**
  * Displays the user-editable label (e.g., *"Dimmer Room Switch"*), summary port pills (e.g., `8x 1G • 2x 10G`), current MAC address, STP Priority, **`STP ROOT`** crown badge (when elected), **`IGMP QUERIER`** badge, and a live **PoE Load Bar** (`48W / 120W`).
* **Endpoint Card:**
  * Displays user-editable label, NIC speed badge (`100M` / `1G` / `10G`), traffic flow pills (e.g., `sACN TX: 16 Univ (4 Mbps)`), and PoE draw (`12W`).
* **Link Lines:**
  * Solid green/blue for `Forwarding` with directional arrows pointing away from the Root Bridge.
  * Dashed red with a **`BLK (STP)`** pill on the exact port where Spanning Tree cuts a loop.
  * Amber warning badge on speed step-downs (`10G -> 1G`) or VLAN mismatches.

### 5.3 Live Issues Drawer
* Persistent collapsible bottom or side panel grouping detected faults by **`Critical`**, **`Warning`**, and **`Info`**.
* Clicking any issue centers the canvas on the offending switch, port, or link and opens its settings in the **Inspector Panel** so the user can test a fix immediately.

---

## 6. Implementation Checklist for Agent

1. **Core Domain & Presets:**
   * Create `SwitchTemplate`, `EndpointTemplate`, `SwitchPortConfig`, `SwitchNodeInstance`, `EndpointNodeInstance`, `NetworkLinkEdge`, and `ValidationIssue` models with full JSON serialization (`save/load` `.netdesign` project files and `templates_library.json`).
   * Seed default generic device templates in `device_templates.dart`.

2. **Deterministic Simulation Services:**
   * Implement `StpElectionSolver` (8-byte Bridge ID comparator, Dijkstra shortest-path cost tree, cycle detection, and blocking port assignment).
   * Implement `VlanReachabilitySolver` (per-VLAN port filtering + active-tree BFS to detect isolated VLAN islands and access-port mismatches).
   * Implement `IgmpDomainSolver` (per-VLAN snooping/querier verification and Root/Querier alignment checks).
   * Implement `ResourceBudgetSolver` (link bandwidth accumulation and switch PoE draw validation).

3. **Interactive Canvas & Port Inspector UI:**
   * Build `DesignTopologyCanvas` supporting node drag-and-drop, port-to-port cable wiring, live `STP ROOT` / `IGMP QUERIER` / `BLK` badges, and `Highlight VLAN` path coloring.
   * Build `SwitchInspectorDrawer` with the clickable switch faceplate port matrix and per-VLAN IGMP toggles.
   * Add the **`🎲 Randomise MACs`** button to `SandboxTopToolbar` and the categorized `ValidationIssuesPanel`.

4. **Unit & Scenario Tests:**
   * Test STP Root tie-breaking when randomizing MAC addresses at equal priorities (`32768`) vs. explicit priority (`4096`).
   * Test VLAN reachability when a middle trunk port omits `VLAN 20` or when an STP blocking port forces traffic around the alternate side of a ring.
   * Test per-VLAN IGMP Snooping failure detection when the Querier is isolated by a VLAN pruning mistake.
