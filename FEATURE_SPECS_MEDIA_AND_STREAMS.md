# Feature Specifications: Physical Port Media & Multicast Stream Flow

**Status:** Locked-In Specification (Approved Scope via Review)  
**Target Project:** Network Design & Validation Sandbox (`net-design`)  
**Implementation Hold:** Specification finalized prior to implementation; no code changes are to be made until requested.

---

## Locked-In Design Decisions (Agreed Scope)

These five decisions were finalized during interactive scope review to maximize practical AV/lighting system-design value while preventing feature creep:

| # | Area | Locked-In Decision | Anti-Creep Boundary |
| :--- | :--- | :--- | :--- |
| 1 | **Switch Physical Ports** | Switches define fixed RJ45 (`100M`, `1G`, `2.5G`, `5G`, `10G`) + dedicated Fibre (`1G SFP`, `10G SFP+`) port counts in the Switch Template. PoE applies strictly to RJ45 copper ports. | No combo/shared port toggles and no per-instance port media overrides. |
| 2 | **Multi-Port Edge Devices** | Endpoints support `1..N` independent NIC ports (`EndpointPortConfig`), each `RJ45` or `SFP/Fibre`. Each `TrafficRequirement` selects which NIC port it binds to (defaulting to Port 1). | No internal 2-port daisy-chain switching or pass-through forwarding inside endpoints. |
| 3 | **Fibre Speed Step-Down** | Only like-for-like media connections are allowed (`RJ45 <-> RJ45` and `SFP/Fibre <-> SFP/Fibre`). Connecting a `1G SFP` port to a `10G SFP+` port is **allowed** (since both are Fibre), negotiates/steps down to `1G`, and raises a **Warning**: `"10G SFP+ connected to 1G SFP — verify transceiver compatibility / speed step-down"`. | Keep transceiver checks concise without full SFP wavelength/SMF/MMF/DOM optic catalogs. |
| 4 | **Multicast Stream & RX UX** | **sACN** uses Universe numbers/ranges (e.g., `1-8, 20`) and auto-calculates ANSI E1.31 `239.255.x.x` multicast IPs, stream count, and bandwidth (`0.25 Mbps/universe` default). **Other Multicast** (`Dante / AES67`, `NDI`, `Custom`) provides an **optional** Multicast IP/range field (e.g., `239.69.0.1-4`); if left empty, the flow stays aggregate bandwidth only. **RX UX** displays clickable quick-pick chips for TX streams advertised on that VLAN plus a text input for explicit Universe ranges or Multicast IPs (e.g., `"1-4"` out of `"1-16"`). | Do not force users to look up/enter multicast IPs just to budget normal Dante/NDI bandwidth. |
| 5 | **Canvas Stream Visualization** | A static **"Trace Stream"** dropdown in the Tier 3 Filter Bar renders per-link stream delivery state:<br>• **Green + Directional Arrows:** Active delivered path (`TX Sender -> Active IGMP Querier -> Subscribed RX Receiver(s)`) with stream count & Mbps on each link.<br>• **Amber (`FLOODED`):** Links receiving the stream because IGMP Snooping is disabled or no Active Querier exists on the VLAN.<br>• **Dimmed (`IGMP PRUNED`):** Links where IGMP Snooping blocked the stream because no downstream RX device subscribed to it. | Static visual overlay only—no animated moving dots/particles or packet-level replay timelines. |

---

# Specification 1: Physical Port Media Types & Multi-Port Endpoints

## 1.1 Scope & Goals

Enable real-world physical layer (Layer 1) accuracy for AV, lighting, and broadcast deployments by distinguishing copper RJ45 ports from SFP/SFP+ fibre ports on switches and allowing edge devices to expose multiple independent NIC ports (such as dual-NIC Dante primary/secondary hardware, lighting consoles with dedicated sACN + control NICs, or media servers with SFP+ capture cards + copper management ports).

### Explicitly Out of Scope (Spec 1)
- **No Combo / Dual-Personality Ports:** Switches will not toggle shared RJ45/SFP ports or dynamically swap port media on individual canvas instances. Port counts and media types come strictly from the Switch Template.
- **No Per-Instance Media Overrides:** Users change speed or VLAN settings on switch ports via the inspector, not copper-vs-fibre identity.
- **No Endpoint Daisy-Chaining / Pass-Through Switching:** An endpoint with 2 ports represents 2 separate network interfaces (e.g., Port 1 = Primary Copper, Port 2 = Secondary or 10G Fibre). Packets do not switch internally from Port 1 to Port 2 through an endpoint.
- **No Fibre Optic Type Matrix:** Do not model SMF vs MMF, BiDi, OS2/OM3/OM4, or dBm optical budgets; only copper vs SFP/Fibre media matching and `1G SFP <-> 10G SFP+` step-down warnings.

---

## 1.2 Domain Model Changes

### New Enum: `PortMediaType` (`lib/domain/models/enums.dart`)
```dart
enum PortMediaType {
  rj45('RJ45 Copper'),
  sfpFibre('SFP / Fibre');

  const PortMediaType(this.label);
  final String label;
}
```
Allowed link speeds by media type:
- `PortMediaType.rj45`: `100M`, `1G`, `2.5G`, `5G`, `10G` (preserving existing RJ45 speeds).
- `PortMediaType.sfpFibre`: `1G`, `10G` (`1G SFP` and `10G SFP+`).

### Switch Models (`lib/domain/models/switch_template.dart` & port config)
1. **`SwitchTemplate` additions:**
   - Dedicated fibre port counts alongside copper port definitions:
     - `sfpPorts1G` (`int`, default `0`)
     - `sfpPorts10G` (`int`, default `0`)
   - Total ports on a switch equals RJ45 ports (`rj45PortCount`) + `sfpPorts1G` + `sfpPorts10G`.
   - RJ45 ports occupy indices `1..rj45PortCount`; SFP/Fibre ports follow contiguously (or tagged explicitly as `SFP 1..M`) with fixed `mediaType: PortMediaType.sfpFibre`.
   - PoE budget & per-port PoE capability apply **strictly to `PortMediaType.rj45` ports**. SFP ports always have `poeEnabled = false` / no PoE sourcing.
2. **`SwitchPortConfig` additions:**
   - `final PortMediaType mediaType` (derived from template port slot; immutable per instance).
   - Helper constraints: available speed options filtered by `mediaType`; PoE toggle hidden/disabled when `mediaType == PortMediaType.sfpFibre`.

### Endpoint Models (`lib/domain/models/endpoint_template.dart`, endpoint node & `TrafficRequirement`)
1. **`EndpointPortConfig` (New Model):**
   - `int portNumber` (`1..N`)
   - `String label` (optional human label, e.g., `"Primary"`, `"Secondary"`, `"10G Fiber"`)
   - `PortMediaType mediaType` (`rj45` or `sfpFibre`)
   - `LinkSpeed speed` (constrained by `mediaType`: `100M..10G` for RJ45; `1G`/`10G` for SFP/Fibre)
   - `bool poeRequired` / PoE draw (only valid when `mediaType == PortMediaType.rj45`)
2. **`EndpointTemplate` & placed endpoint node:**
   - Stores `List<EndpointPortConfig> ports` (`>= 1` port).
   - **Backward-compatible migration:** Legacy templates/projects JSON without `ports` automatically synthesize a single Port 1 (`PortMediaType.rj45`) using the template/node's existing speed and PoE properties.
   - Multiple links can connect to the same endpoint node, provided each link attaches to a different unoccupied `EndpointPortConfig.portNumber`.
3. **`TrafficRequirement.boundPortNumber`:**
   - Nullable `int? boundPortNumber` (defaults to `1` when omitted or migrating legacy files).
   - Allows each TX or RX traffic requirement on a multi-port endpoint to declare which NIC port carries that flow (e.g., Control/Art-Net/Dante Primary on Port 1 RJ45, NDI/Media Stream on Port 2 `10G SFP+`).

### Link Edge Model (`lib/domain/models/network_link_edge.dart`)
- Track endpoint port index (`sourceEndpointPort` / `targetEndpointPort`, defaulting to `1`) in addition to switch port numbers so multi-NIC endpoints bind each cable cleanly to a specific NIC slot and faceplate pill.

---

## 1.3 Wiring Guard & Validation Rules

### Interactive Wiring (`SandboxViewModel.completeWiringToPort`)
- **Enforced Like-for-Like Media Rule:**
  - `RJ45 <-> RJ45`: Allowed.
  - `SFP/Fibre <-> SFP/Fibre`: Allowed (including `1G SFP <-> 10G SFP+`).
  - `RJ45 <-> SFP/Fibre`: **Blocked** during interactive wiring with clear feedback (`"Incompatible media: RJ45 copper cannot connect directly to an SFP/Fibre port"`).
- **Visual Guidance While Wiring:**
  - While dragging/selecting a destination port after choosing a source port, incompatible-media ports on target switches and multi-port endpoints are visually dimmed/badged as incompatible so valid targets stand out immediately.

### Static Diagnostics (`ResourceBudgetSolver`)
1. **Media Mismatch (`Critical`):** If a loaded or edited file connects `PortMediaType.rj45` to `PortMediaType.sfpFibre`, emit a **Critical** validation issue.
2. **SFP Speed Step-Down (`Warning`):** When two `PortMediaType.sfpFibre` ports are connected with `1G` on one end and `10G` on the other:
   - Link remains connected and active.
   - Negotiated effective link bandwidth steps down to **`1G`** (`1000 Mbps`).
   - Emit a **Warning**:  
     `"10G SFP+ connected to 1G SFP — verify transceiver compatibility / speed step-down"`
3. **PoE Over Fibre Guard (`Critical`):** If a PoE-requiring endpoint port is mapped or wired in legacy data onto an SFP/Fibre port (or non-PoE RJ45), flag appropriately and prevent PoE supply over SFP.
4. **Per-NIC Bandwidth Accounting:** Endpoint egress/ingress bandwidth validation evaluates traffic per `(endpointId, boundPortNumber)` against the link attached to that specific NIC port rather than summing unrelated NICs together.

---

## 1.4 UI & Canvas Updates (Spec 1)

- **Library Switch Template Editor:** Add numeric inputs for `1G SFP Ports` and `10G SFP+ Ports` alongside RJ45 ports; auto-assign copper PoE eligibility exclusively to RJ45 ports.
- **Library Endpoint Template Editor:** Allow adding/removing `1..N` NIC ports (`RJ45` or `SFP/Fibre`, speed, optional label, PoE toggle for RJ45).
- **Switch Node & Port Matrix (`port_vlan_matrix_editor.dart`, `switch_node_widget.dart`):**
  - Visually separate or style RJ45 copper bays vs SFP/Fibre cage icons (e.g., distinct SFP cage outline badge for `1G SFP` / `10G SFP+`).
  - Show negotiated speed (highlighting `1G step-down` badge on mixed `1G SFP <-> 10G SFP+` uplinks).
- **Endpoint Node Card (`endpoint_node_widget.dart`) & Inspector (`node_inspector_panel.dart`):**
  - Multi-port endpoints display clickable NIC port pills/connectors (`P1 RJ45`, `P2 10G SFP+`, etc.) for wiring and link status.
  - `_buildTrafficFlowCard` includes a `NIC Port` selector dropdown when an endpoint has `> 1` port (`Port 1`, `Port 2`, ...).

---

## 1.5 Spec 1 Verification Plan

- **Unit Tests:**
  - JSON serialization/deserialization and legacy single-port endpoint migration (`boundPortNumber == null` -> `1`, missing `ports` -> `[Port 1 RJ45]`).
  - Wiring guard tests: `RJ45 <-> SFP/Fibre` rejected; `1G SFP <-> 10G SFP+` accepted, effective capacity capped at `1G`, and exact warning emitted.
  - Per-NIC bandwidth checks on a 2-port endpoint (saturating Port 2 SFP+ without falsely failing Port 1 RJ45).
- **Widget & Analyzer Checks:**
  - `flutter analyze` zero issues.
  - Switch faceplate renders RJ45 and SFP port groups cleanly; Endpoint inspector lists multiple NICs and binds traffic flows per port.

---

# Specification 2: Multicast Stream & sACN Universe Data Flow Visualization

## 2.1 Scope & Goals

Allow lighting, audio, and video engineers to define **what** multicast streams a TX device transmits (e.g., sACN Universes `1-16`, Dante flows `239.69.0.1-4`) and **which** subsets an RX device subscribes to, then verify on the network canvas exactly how **IGMP Snooping**, **Active IGMP Querier placement**, **STP blocked links**, and **VLAN/Trunk segmentation** prune, deliver, or flood those streams across the topology.

### Explicitly Out of Scope (Spec 2)
- **No Animated Moving Dots / Packet Particles:** Stream tracing uses static color-coded lines, directional arrowheads, and count/Mbps badges.
- **No Full Time-Series / Packet Simulator:** No timers, IGMP join/leave packet animations, or jitter/latency buffering models.
- **No L3 Multicast Routing (PIM / mDNS Relay):** Streams are traced strictly within their configured Layer 2 VLAN broadcast domain.
- **Optional Non-sACN IPs:** Dante/AES67, NDI, and Custom multicast flows do **not** require multicast IP entry; omitting the IP keeps them as aggregate bandwidth flows without forcing busywork.

---

## 2.2 Domain Model & Stream Addressing

### `TrafficRequirement` Additions
Extend endpoint traffic flows with optional stream metadata:
- **`String? sacnUniverseSpec`** (used when protocol is sACN / multicast lighting):
  - Accepts single numbers, comma-separated lists, and inclusive ranges, e.g., `"1-8, 20"`.
- **`String? multicastGroupSpec`** (optional, used for `Dante / AES67`, `NDI`, `Custom` multicast flows):
  - Accepts single IPv4 multicast addresses, comma-separated entries, or last-octet ranges, e.g., `"239.69.0.1-4, 239.69.0.10"`.
  - When `null` / empty on non-sACN flows, the flow continues to contribute aggregate Mbps load to VLAN/link bandwidth budgets as today, and simply does not emit per-group IGMP trace targets.
- **Flow Direction Semantics:**
  - `TX` (Sender / Publisher): Advertises the resolved set of multicast streams on the flow's bound NIC VLAN.
  - `RX` (Receiver / Subscriber): Declares the subset of streams that endpoint listens to / sends IGMP Joins for on that VLAN.

### New Helper: `MulticastStreamResolver`
Pure domain utility responsible for parsing, expanding, and deduplicating stream specs:
1. **sACN Universe -> ANSI E1.31 Multicast IP Mapping:**
   - Valid sACN Universe range: `1..63999` (reject `<= 0` or `> 63999` with inline validation error).
   - Formula:
     - `highByte = (universe >> 8) & 0xFF`
     - `lowByte = universe & 0xFF`
     - Multicast IP = `'239.255.$highByte.$lowByte'` (e.g., Universe `1` -> `239.255.0.1`, Universe `256` -> `239.255.1.0`).
   - **Auto-Calculated Stream Count & Bandwidth:**
     - `streamCount = expandedUniverses.length`
     - Default sACN bandwidth calculation: `streamCount * 0.25 Mbps` (44 Hz full DMX frame + protocol overhead), auto-populating TX/RX flow Mbps while remaining inspectable/overridable if needed.
2. **Multicast IP / Range Parser:**
   - Parses specs such as `239.69.0.1-4` -> `['239.69.0.1', '239.69.0.2', '239.69.0.3', '239.69.0.4']`.
   - Validates multicast IPv4 range (`224.0.0.0` – `239.255.255.255`, warning/error on invalid IP syntax or reverse ranges).

---

## 2.3 RX Subscription UX (Inspector)

In `_buildTrafficFlowCard` when editing an `RX` multicast flow on an endpoint:
1. **Advertised TX Stream Quick-Pick Chips:**
   - Inspect all `TX` multicast flows currently defined across the project on the **same VLAN**.
   - Render compact, clickable filter/choice chips (e.g., `U 1-8`, `U 20`, `239.69.0.1-4`) above the input field.
   - Tapping a chip toggles adding/removing those universes or multicast IPs in the RX flow's subscription spec.
2. **Explicit Text Box (Subset / Custom Range Input):**
   - Paired text input (`Universe Range` for sACN, `Multicast IP / Range` for other protocols) where users can type exact subsets such as `"1-4"` even when a TX sender advertises `"1-16"`.
   - Displays live resolved count (e.g., `4 universes • 1.00 Mbps` or `4 streams`).

---

## 2.4 `MulticastFlowTracer` Engine & Diagnostics

A pure Dart solver operating alongside `VlanReachabilitySolver` and `ResourceBudgetSolver`:

### Inputs
- Selected trace target from the Tier 3 Filter Bar (either `"All Streams in VLAN"` or a specific sACN Universe / Multicast Group IP, or specific TX stream).
- Active Layer 2 forwarding graph for the target VLAN:
  - Uses active **STP forwarding** links only (STP blocking links carry no stream traffic).
  - Enforces VLAN membership on access ports and **valid trunk configuration (`NetworkLinkEdge.isValidTrunk`)** with matching allowed VLANs on trunks.
- Per-switch IGMP state on the stream's VLAN (Snooping enabled/disabled, Querier enabled/active querier reachability).

### Per-Link State Classification
For every link edge reachable within the stream's L2 VLAN tree:
1. **Delivered (Active Multicast Path):**
   - When IGMP Snooping is active and a valid **Active IGMP Querier** is reachable on that VLAN:
     - Path from `TX Sender -> Active IGMP Querier` (switches always forward multicast toward the active querier router port) AND path from `TX Sender / Tree -> Subscribed RX Receiver(s)`.
   - Reports exact **matching stream count** and **aggregate stream Mbps** traversing that link in the direction away from TX.
2. **Flooded (`FLOODED`):**
   - Links carrying the multicast stream purely because **IGMP Snooping is disabled** on an upstream switch in that VLAN or **no Active IGMP Querier** exists on the VLAN (causing unknown/un-tracked multicast flooding across all forwarding VLAN links).
3. **IGMP Pruned (`IGMP PRUNED`):**
   - Links belonging to the active L2 VLAN forwarding tree where IGMP Snooping **successfully blocked** the traced stream because neither the Active Querier nor any subscribed RX device exists downstream of that branch.

### Stream Integrity Issues (Reported in Issues Panel)
- **Duplicate TX Stream Collision (`Warning` / `Critical`):** Two different TX endpoints (or ports) on the same VLAN advertise overlapping sACN Universe(s) or identical Multicast Group IP (e.g., two consoles both outputting Universe `5` on VLAN 20 without coordination).
- **Orphan RX Subscription (`Info` / `Warning`):** An RX endpoint subscribes to a sACN Universe or Multicast IP on a VLAN where no reachable TX source advertises that stream.
- **Missing Querier Flooding (`Warning` / cross-reference):** Traced stream enters `FLOODED` state on VLAN links due to missing Active IGMP Querier or disabled IGMP Snooping.

---

## 2.5 Canvas & Filter Bar UI (Spec 2)

### Tier 3 Filter Bar (`top_control_bar.dart`)
- Add a static **"Trace Stream"** dropdown alongside the existing VLAN / `Trunks` filter pills:
  - `Off` (default normal canvas view)
  - Grouped selectable items populated dynamically from TX & RX streams defined in the topology (e.g., `sACN U1-8`, `U1 (239.255.0.1)`, `239.69.0.1`, etc.).
- Selecting a stream keeps the view **static and crisp** (no animated particles).

### Canvas Link Styling (`link_edge_painter.dart`) When Stream Trace Is Active
- **Delivered Links (`Green` + Directional Arrows):**
  - Highlighted solid green stroke with directional arrowheads pointing downstream from TX toward Querier / subscribed RX devices.
  - Link pill displays stream count & Mbps (e.g., `4 streams • 1.0 Mbps` or `U1-4 • 1.0 Mbps`).
- **Flooded Links (`Amber` + `FLOODED` badge):**
  - Highlighted amber stroke indicating unintended multicast flooding due to snooping/querier misconfiguration.
  - Link pill includes `FLOODED` tag plus Mbps impact.
- **Pruned Links (`Dimmed` + `IGMP PRUNED` label):**
  - Low-opacity muted stroke on VLAN forwarding links cleanly pruned by IGMP Snooping, labeled `IGMP PRUNED` (either on hover or subtle pill so engineers see IGMP snooping working).
- Unrelated VLANs / links outside the stream's L2 VLAN are dimmed into the background so the traced flow stands out immediately.

---

## 2.6 Spec 2 Verification Plan

- **Unit Tests (`MulticastStreamResolver`):**
  - Universe parsing (`"1-8, 20"`, invalid `0` / `64000`, overlapping deduplication), ANSI E1.31 IP math (`1 -> 239.255.0.1`, `256 -> 239.255.1.0`, `63999 -> 239.255.249.255`), and `0.25 Mbps/universe` calculation.
  - IP range parsing (`"239.69.0.1-4"` -> 4 groups) and empty-optional behavior.
- **Unit Tests (`MulticastFlowTracer`):**
  - **Delivered + Pruned topology:** TX -> Switch A (Active Querier) -> Switch B (Snooping ON, RX subscribed to U1-4) vs Switch C (Snooping ON, no RX subscribed) -> Switch B link is `Delivered` (Green), Switch C link is `IGMP PRUNED` (Dimmed).
  - **Querier forwarding path:** TX on Switch B, Active Querier on Switch A, RX on Switch B -> trunk `B -> A` still receives stream (`Delivered`) because snooping switches forward multicast toward the Active Querier.
  - **Flooded topology:** Snooping disabled OR no Active Querier on VLAN -> VLAN links transition to `FLOODED` (Amber).
  - **STP Blocked / Invalid Trunk:** Blocked STP link or mismatched trunk VLAN never carries the stream.
  - **Duplicate TX & Orphan RX:** Properly flagged in diagnostics.
- **UI & Regression Checks:**
  - `flutter analyze` zero issues and all existing + new `flutter test` suites passing.
