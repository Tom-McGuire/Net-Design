# Project Review & Improvement Report: Net Design (`net_design`)

**Date:** 2026-11-19  
**Reviewed Version:** `0.5.7-beta+1`  
**Target SDK:** Dart `^3.13.0` / Flutter Desktop (Linux, macOS, Windows)  
**Baseline Status:** `flutter analyze` passes with 0 issues; all 34 tests in `flutter test` pass.

---

## Executive Summary

**Net Design** is a well-structured, deterministic Layer 2 / Layer 3 network topology and protocol sandbox. Its 4-pass validation engine (`StpElectionSolver`, `VlanReachabilitySolver`, `IgmpDomainSolver`, `MulticastFlowTracer`, `ResourceBudgetSolver`), physical media validation (`RJ45` vs `SFP/Fibre`), and multi-NIC endpoint model are clean, fast, and covered by solid unit, widget, and fuzz tests.

However, a deep audit of the codebase identified:
- **7 High-Severity** issues (domain solver edge-case bugs, macOS App Sandbox entitlements blocking file I/O and shared SQLite theme sync, and unguarded file-picker exceptions).
- **13 Medium-Severity** issues (spec deviations in RX quick-pick chips and VLAN highlighting, duplicate theme synchronization mechanisms, `ChangeNotifier` rebuild/validation storms during node dragging and text editing, and two oversized files exceeding 1,400–1,850 lines).
- **16 Unused Code / Dead Dependency / Asset items** (unused packages in `pubspec.yaml`, unreferenced assets, dead model fields/methods, and half-wired features).

Each finding below includes exact file paths, line numbers, root cause analysis, and concrete instructions so another coding agent can implement the fixes directly.

---

## Part 1: Bugs & Functional Issues (High & Medium Priority)

### 1.1 [HIGH] Unprotected L2 Loop Deduplication Masks Additional Faulty Links Between the Same Switch Pair
- **File:** [lib/domain/engine/stp_election_solver.dart](file:///home/tom-code/projects/flutter/net-design/lib/domain/engine/stp_election_solver.dart#L23-L65)
- **Category:** Bug / Solver Correctness
- **Problem:**
  In `StpElectionSolver.solve`, `reportedLoopComponents` deduplicates `ValidationIssue` entries using `pairKey = ([swA.id, swB.id]..sort()).join(':')` (line 45).
  1. When two parallel links connect `swStage` and `swDumb` (as in `DeviceTemplates.unmanagedLoopAndBroadcastDemo()`, lines 742–756), both links are marked `LinkStpState.loopUnprotected`, so `validation.unprotectedLoopCount` is `2`, **but only 1 `ValidationIssue` is emitted** (`stp-unprotected-loop-lnk-loop-1`). Clicking the issue only highlights the first cable; the second cable has no issue entry.
  2. When a single switch has a **self-loop** (`swA.id == swB.id`) with two separate self-loop cables, the second self-loop is silently omitted from `issues`.
- **Instructions for Agent:**
  - Either emit one `ValidationIssue` per redundant link in the cycle (remove `reportedLoopComponents` or key it by `link.id`), or include all offending link IDs / port numbers in the issue message so every cable contributing to the loop is reported consistently with `unprotectedLoopCount`.

---

### 1.2 [HIGH] Parallel Equal-Cost Links Between STP Switches Are Not Tie-Broken by Receiver Port ID (IEEE 802.1D / 802.1w)
- **File:** [lib/domain/engine/stp_election_solver.dart](file:///home/tom-code/projects/flutter/net-design/lib/domain/engine/stp_election_solver.dart#L178-L246)
- **Category:** Bug / Protocol Accuracy
- **Problem:**
  1. During Dijkstra relaxation (lines 179–192), when two parallel links exist between the same upstream switch `u` and downstream switch `v` (`bridgeCmp == 0`) and their sender port numbers happen to be equal or when tie-breaking on the receiver side is needed, only `upstreamPort < prevPort` is checked; the **receiver port number** (`link.portForNode(vId)`) is never used as the final IEEE 802.1D tie-breaker (`Root Path Cost -> Sender Bridge ID -> Sender Port ID -> Receiver Port ID`).
  2. More importantly, for non-tree **blocking** links (lines 227–246), when `link` is a parallel redundant cable between `swA` (Root, cost 0) and `swB` (non-Root, cost 4), `costCmp < 0` sets `blockAtB = true` and `link.blockedAtPortNumber = link.targetPortNumber`. That works for a 2-switch parallel link, **but** if `swA` and `swB` have **equal `rootPathCost`** AND **equal `compareBridgeId`** (or when two parallel links connect two switches and the user inspects which port blocks), the port-level tie-breaker is missing.
- **Instructions for Agent:**
  - In `StpElectionSolver.solve` (lines 185–191), add `parentDownstreamPort[vId]` tie-breaking when `upstreamPort == prevPort` (`downstreamPort < prevDownstreamPort`).
  - Add a unit test in `test/stp_election_solver_test.dart` covering two switches connected by two parallel 1G links (`P1<->P1` and `P2<->P2`), asserting that `P1<->P1` forwards and `P2<->P2` blocks at the non-root switch's Port 2.

---

### 1.3 [HIGH] Unmanaged Switch Connected Downstream of an STP Switch Has `hopDepthFromRoot = 0`, Reversing Forwarding Arrow Direction
- **File:** [lib/domain/engine/stp_election_solver.dart](file:///home/tom-code/projects/flutter/net-design/lib/domain/engine/stp_election_solver.dart#L287-L296)
- **Category:** Bug / Visual Simulation State
- **Problem:**
  Unmanaged switches (`!sw.isStpActive`) are excluded from the STP component Dijkstra pass, so their `hopDepthFromRoot` remains `0` (from `resetSimulationState()`).
  In lines 287–296:
  ```dart
  if (!swA.isStpActive || !swB.isStpActive) {
    link.stpState = LinkStpState.forwarding;
    link.directionFromRootSourceToTarget =
        swA.hopDepthFromRoot <= swB.hopDepthFromRoot;
  }
  ```
  If `swA` is an STP switch at `hopDepthFromRoot == 1` (or `2`) and `swB` is a downstream unmanaged switch (`hopDepthFromRoot == 0`), `swA.hopDepthFromRoot <= swB.hopDepthFromRoot` evaluates to `1 <= 0` (`false`)! As a result, `directionFromRootSourceToTarget` points **backward from the unmanaged edge switch toward the STP network**.
- **Instructions for Agent:**
  - In `StpElectionSolver.solve` (lines 287–296), if one switch is STP-active and the other is not (`swA.isStpActive != swB.isStpActive`), orient `directionFromRootSourceToTarget = swA.isStpActive` (away from the managed STP tree toward the unmanaged extension) and set the unmanaged switch's `hopDepthFromRoot = managedSw.hopDepthFromRoot + 1` via BFS over non-loop unmanaged extension links.

---

### 1.4 [HIGH] Multicast Flow Tracer Marks Intermediate Snooping-Disabled Switch Ports as `IGMP PRUNED` When Downstream of TX
- **File:** [lib/domain/engine/multicast_flow_tracer.dart](file:///home/tom-code/projects/flutter/net-design/lib/domain/engine/multicast_flow_tracer.dart#L598-L693)
- **Category:** Bug / Solver Correctness
- **Problem:**
  In `MulticastFlowTracer.applyTrace`:
  1. Line 600 checks `if (!txSwitchSnooping || activeQuerierSwId == null)` to decide whether to flood the whole VLAN component.
  2. When `txSwitchSnooping` is `true` and an `activeQuerierSwId` exists, lines 663–690 only walk the BFS path from each `targetSwId` (the Active Querier and subscribed RX switches) back to `txSw.id`.
  3. Inside that loop (lines 673–688), if an intermediate switch `swNode` on the delivered path has `!isSnoopingActive(swNode)`, it only floods to **endpoint access links attached directly to `swNode`** (`attachments.values` where `att.sw.id == swNode.id`). It does **not** flood out of `swNode`'s other forwarding inter-switch trunk links! Worse, because `candidatePrunedLinks.addAll(compLinks)` was executed at line 632, any inter-switch trunk link branching off an intermediate snooping-disabled switch is falsely labeled **`IGMP PRUNED`** instead of **`FLOODED`**, and `swNode == txSw` is skipped because the `while (cursor != null && cursor != txSw.id)` loop terminates before checking `txSw`.
  4. Similarly, in `ResourceBudgetSolver.solve` (line 158), `isFloodedMulticast` only checks `!snoopingOnTxSwitch` on the TX switch itself, ignoring snooping-disabled switches further along the multicast path.
- **Instructions for Agent:**
  - In `MulticastFlowTracer.applyTrace`, when any switch that receives the multicast stream has `!isSnoopingActive(swNode)`, propagate flooding recursively across all VLAN-forwarding inter-switch and endpoint links reachable from `swNode` without passing through a snooping-enabled switch (or flood all local ports + downstream trunks of `swNode`).

---

### 1.5 [HIGH] Endpoint Port Lookup Silently Falls Back to Port 1 When an Invalid Port Number Is Referenced
- **Files:**
  - [lib/domain/models/endpoint_node_instance.dart](file:///home/tom-code/projects/flutter/net-design/lib/domain/models/endpoint_node_instance.dart#L55-L61)
  - [lib/domain/models/endpoint_template.dart](file:///home/tom-code/projects/flutter/net-design/lib/domain/models/endpoint_template.dart#L272-L278)
  - [lib/domain/engine/multicast_flow_tracer.dart](file:///home/tom-code/projects/flutter/net-design/lib/domain/engine/multicast_flow_tracer.dart#L57-L79)
- **Category:** Bug / Data Integrity
- **Problem:**
  Unlike `SwitchNodeInstance.portByNumber(int)` which returns `SwitchPortConfig?` (`null` when a port does not exist), `EndpointNodeInstance.portByNumber(int)` returns `list.first` (Port 1) whenever `portNumber` is not found!
  - In `TopologyValidator._portOrNicSpeed` and `_portOrNicMedia` (lines 179–199), if a loaded `.netdesign` file has a link referencing a non-existent endpoint port (e.g. `sourcePortNumber: 99`), it silently pretends it is connected to Port 1 (inheriting Port 1's media type and speed).
  - In `MulticastFlowTracer.buildEndpointAttachments` (lines 57–79), `result['${epA.id}:${link.sourcePortNumber}']` registers an attachment for non-existent endpoint port `99` even if `epA` only has 1 port.
- **Instructions for Agent:**
  - Add a nullable `EndpointPortConfig? tryPortByNumber(int portNumber)` (or make `portByNumber` return `EndpointPortConfig?`) on `EndpointNodeInstance` and `EndpointTemplate`.
  - In `MulticastFlowTracer.buildEndpointAttachments`, verify that the endpoint actually has a port with `epPortNum` before adding it to `result`.

---

### 1.6 [HIGH] macOS App Sandbox Entitlements Block Project Save/Load, `url_launcher`, and Shared SQLite Database Access
- **Files:**
  - [macos/Runner/Release.entitlements](file:///home/tom-code/projects/flutter/net-design/macos/Runner/Release.entitlements#L1-L8)
  - [macos/Runner/DebugProfile.entitlements](file:///home/tom-code/projects/flutter/net-design/macos/Runner/DebugProfile.entitlements#L1-L12)
- **Category:** Platform Configuration / Bug
- **Problem:**
  `macos/Runner/Release.entitlements` has `<key>com.apple.security.app-sandbox</key><true/>` with **no other entitlements**:
  1. Missing `com.apple.security.files.user-selected.read-write`: `file_picker` open/save dialogs (`Open Project`, `Save Project`, `Import` template library) will fail with sandbox permission errors on macOS release builds.
  2. Missing `com.apple.security.network.client`: `url_launcher` opening the User Manual (`https://github.com/Tom-McGuire/Net-Design/blob/main/USER_MANUAL.pdf`) or any network operations in debug/release will be blocked if network client access is required.
  3. Cross-app SQLite access (`SharedDeviceDatabase` / `SuiteThemeService` accessing `~/.local/share/network_suite/shared_devices.db` or `~/Library/Application Support/...` outside the app's own sandbox container) is blocked by `app-sandbox = true` unless an App Group or temporary exception entitlement is configured, or `app-sandbox` is disabled for non-Mac-App-Store direct GitHub releases (note that `.github/workflows/release.yml` distributes direct `.zip` archives outside the Mac App Store).
- **Instructions for Agent:**
  - Update `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements` to add `com.apple.security.files.user-selected.read-write` and `com.apple.security.network.client` (or set `com.apple.security.app-sandbox` to `false` if distributed as a direct multi-tool desktop suite sharing a host SQLite database with `Net-App-Launcher`).

---

### 1.7 [HIGH] Unhandled Exceptions in UI When Opening or Importing Corrupted `.netdesign` / Library JSON Files
- **Files:**
  - [lib/ui/widgets/top_control_bar.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/widgets/top_control_bar.dart#L454-L483)
  - [lib/ui/features/library/library_drawer.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/library/library_drawer.dart#L78-L90)
- **Category:** Robustness / Error Handling
- **Problem:**
  1. In `TopControlBar._handleFileAction` (`case 'open'`, lines 454–464) and (`case 'save'`, lines 465–483), `await vm.loadProjectFromFile(path)` and `await vm.saveProjectToFile(...)` are called **without a `try / catch`**. If a user picks a malformed JSON file or a read-only path, `ProjectStorageService.deserializeProject` throws a `FormatException` or `FileSystemException` that goes completely unhandled into the Flutter error zone with no `SnackBar` or status banner feedback.
  2. In `LibraryDrawer.build` (lines 78–90), `await File(path).readAsString()` and `await vm.importLibraryJson(raw)` are likewise unguarded; importing an invalid JSON file throws an uncaught `FormatException`.
  3. Additionally, on `case 'save'` (lines 469–477), `FilePicker.saveFile(..., bytes: bytes)` already writes `bytes` to disk on several platforms, and then line 477 immediately writes the file a **second time** via `await vm.saveProjectToFile(outputUri.toFilePath())`.
- **Instructions for Agent:**
  - Wrap `open`, `save`, and `importLibraryJson` in `try / catch (e)` blocks and display a descriptive error `SnackBar` (or `vm` status message) when parsing or file I/O fails.

---

### 1.8 [MEDIUM] RX Quick-Pick Chips Overwrite Existing Subscription Instead of Toggling / Merging (Spec Deviation)
- **Files:**
  - [lib/ui/features/inspector/node_inspector_panel.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/inspector/node_inspector_panel.dart#L1535-L1543) and [lines 1806-1843](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/inspector/node_inspector_panel.dart#L1806-L1843)
  - [FEATURE_SPECS_MEDIA_AND_STREAMS.md](file:///home/tom-code/projects/flutter/net-design/FEATURE_SPECS_MEDIA_AND_STREAMS.md#L178-L183)
- **Category:** Spec Deviation / UX Bug
- **Problem:**
  1. Section 2.3 of `FEATURE_SPECS_MEDIA_AND_STREAMS.md` specifies: *"Tapping a chip toggles adding/removing those universes or multicast IPs in the RX flow's subscription spec."* Currently, tapping an `ActionChip` in `_TrafficFlowInspectorCard` (lines 1821–1840) **completely overwrites** `sacnUniverseSpec` / `multicastGroupSpec` with that single chip's spec, making it impossible to click two TX chips to subscribe to two transmitters.
  2. Line 1536 only shows `rxQuickPicks` when `flow.direction == TrafficDirection.rxSubscriber`, excluding `TrafficDirection.bidirectional` flows (even though `direction.isSubscriber` is true for bidirectional flows).
- **Instructions for Agent:**
  - Change line 1536 to use `flow.direction.isSubscriber`.
  - When a quick-pick chip is tapped, parse the current RX universes/IPs and the chip's universes/IPs using `MulticastStreamResolver`; if all of the chip's items are already present, remove them (toggle off), otherwise union them (toggle on) and format back via `MulticastStreamResolver.formatUniverseRanges`.

---

### 1.9 [MEDIUM] Highlight VLAN Mode Does Not Highlight the Exact Trunk Port Where a VLAN Is Pruned in Red (Spec Deviation)
- **Files:**
  - [lib/ui/features/canvas/link_edge_painter.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/canvas/link_edge_painter.dart#L213-L253) and [lines 411-449](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/canvas/link_edge_painter.dart#L411-L449)
  - [lib/ui/features/canvas/switch_node_widget.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/canvas/switch_node_widget.dart#L541-L575)
  - [SPECIFICATION.md](file:///home/tom-code/projects/flutter/net-design/SPECIFICATION.md#L197-L198)
- **Category:** Bug / Spec Deviation (Dead Branch in Painter)
- **Problem:**
  Look closely at `LinkEdgePainter.paint` and `_drawLinkPill`:
  1. At line 217, `LinkEdgePainter` computes:
     ```dart
     final isVlanPruned = highlightedVlanId != null &&
         link.prunedVlans.contains(highlightedVlanId);
     ```
  2. At line 446 inside `_drawLinkPill`, there is explicit code for `isVlanPruned`:
     ```dart
     } else if (isVlanPruned) {
       label = 'VLAN $highlightedVlanId PRUNED';
       textColor = AppTheme.error;
     ```
  3. **However, that branch is dead code and can NEVER execute!** Why? Because when `highlightedVlanId != null`, `isFilterActive` is `true`. When `link.prunedVlans.contains(highlightedVlanId)`, `isVlanHighlighted` (line 213) is `false`, which makes `matchesActiveFilter` (line 220) `false`! Then:
     - In `paint` (line 250), the link is drawn dimmed gray (`AppTheme.textMuted.withValues(alpha: 0.22)`).
     - In `_drawLinkPill` (line 411):
       ```dart
       if (isFilterActive && !matchesActiveFilter) {
         return; // Returns early BEFORE reaching `else if (isVlanPruned)`!
       }
       ```
  4. Thus, the `'VLAN $highlightedVlanId PRUNED'` pill at line 446 is unreachable dead code, and pruned trunk links disappear into faint gray instead of highlighting the pruning fault in red as specified in `SPECIFICATION.md` Section 5.1 (*"illuminates every port and cable carrying the selected VLAN in high-contrast green, while pulsing red on the exact trunk port where the VLAN stops"*).
- **Instructions for Agent:**
  - In `LinkEdgePainter.paint` (line 244), when `highlightedVlanId != null && isVlanPruned`, style the link with `AppTheme.error` and `dashed = true`.
  - In `_drawLinkPill` (line 411), change the early return to `if (isFilterActive && !matchesActiveFilter && !isVlanPruned) return;` so the `'VLAN $highlightedVlanId PRUNED'` error badge is actually rendered on the canvas.

---

### 1.10 [MEDIUM] Endpoint Card VLAN Highlight Filter Checks `flow.defaultVlanId` Instead of Effective Port VLAN
- **File:** [lib/ui/features/canvas/endpoint_node_widget.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/canvas/endpoint_node_widget.dart#L55-L59)
- **Category:** Bug / Visual Inconsistency
- **Problem:**
  In `EndpointNodeWidget.build`:
  ```dart
  final matchesHighlightedVlan = !isTrunkFilter &&
      (highlightedVlan == null ||
          endpointNode.activeTrafficFlows
              .any((f) => f.defaultVlanId == highlightedVlan));
  ```
  If an endpoint has no traffic flows configured yet (e.g. a generic endpoint wired to an Access VLAN 20 switch port) or its traffic flow's effective VLAN comes from the attached switch access port, `EndpointNodeWidget` only checks `f.defaultVlanId == highlightedVlan` and dims the endpoint even when its wired switch port and cable are highlighted green for that VLAN.
- **Instructions for Agent:**
  - Check whether any flow on `endpointNode` has `defaultVlanId == highlightedVlan` **OR** any connected link on `endpointNode` has `link.activeVlans.contains(highlightedVlan)`.

---

### 1.11 [MEDIUM] Editing an Endpoint NIC Label Cannot Clear the Label Back to Empty/Null
- **Files:**
  - [lib/ui/features/inspector/node_inspector_panel.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/inspector/node_inspector_panel.dart#L907-L911)
  - [lib/ui/features/library/edit_endpoint_template_dialog.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/library/edit_endpoint_template_dialog.dart#L326-L328)
- **Category:** Bug
- **Problem:**
  In `node_inspector_panel.dart` line 909:
  ```dart
  next[index] = port.copyWith(label: val.trim());
  ```
  Wait — `EndpointPortConfig.copyWith` has a `clearLabel` flag, and `toJson()` omits `'label'` when empty, while `displayName` checks `trimmed.isNotEmpty`. That works in memory, **except** at line 900:
  ```dart
  TextFormField(
    key: ValueKey('ep-nic-lbl-${ep.id}-${port.portNumber}'),
    initialValue: port.label ?? '',
  ```
  When the user clicks the `"Update from Library Template"` sync button (`Icons.sync` at line 598), `ep.id` and `port.portNumber` do **not** change, so `TextFormField` keeps its stale internal controller value instead of reflecting the template's updated NIC label! The same bug occurs on `TextFormField` for PoE watts (line 985) and in `EditEndpointTemplateDialog` (lines 319, 392, 569) when ports or flows are re-ordered or updated.
- **Instructions for Agent:**
  - Include the synced value or a generation counter in the `ValueKey`, or use managed `TextEditingController` instances (like `_TrafficFlowInspectorCard` does).

---

### 1.12 [MEDIUM] `addSwitchFromTemplate` Enables IGMP Snooping by Default on Non-Default VLANs While `DeviceTemplates._makeSwitch` and `SwitchVlanSettings` Default It to `false`
- **Files:**
  - [lib/ui/features/sandbox_view_model.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/sandbox_view_model.dart#L613-L620)
  - [lib/ui/features/sandbox_view_model.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/sandbox_view_model.dart#L927-L933)
  - [lib/ui/features/sandbox_view_model.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/sandbox_view_model.dart#L964-L968)
- **Category:** Inconsistent State Mutation
- **Problem:**
  - When a user defines a new VLAN via `+ VLAN` (`addKnownVlan`, line 967) or adds a switch from a template (`addSwitchFromTemplate`, line 618), `igmpSnoopingEnabled` is automatically set to `true` (`sw.supportsIgmpSnooping`).
  - However, when a user assigns a new VLAN ID via `updatePort` (line 929), `SwitchVlanSettings` is created with the constructor default `igmpSnoopingEnabled: false`!
  - Furthermore, because `addKnownVlan` auto-enables `igmpSnoopingEnabled: true` on all switches without enabling an IGMP Querier on any switch, clicking `+ VLAN` in the toolbar **immediately triggers a Critical validation error** (`"IGMP Snooping Without Active Querier"`) on every switch in the project before the user has even assigned the VLAN to any port!
- **Instructions for Agent:**
  - Make `SwitchVlanSettings` creation consistent across `addKnownVlan`, `updatePort`, and `addSwitchFromTemplate`, or in `IgmpDomainSolver.solve` (lines 49–56) only include switches in `participatingSwitches` for `vlanId` when at least one port on the switch actually permits `vlanId` (rather than every switch that merely has a passive `vlanConfigs[vlanId]` entry from `knownVlans`).

---

## Part 2: Architecture, Performance & Maintainability Improvements

### 2.1 [MEDIUM] Every Node Drag Frame Rebuilds the Entire Application Tree (`TopControlBar`, `NodeInspectorPanel`, `IssuesDrawerPanel`, and All Node Cards)
- **Files:**
  - [lib/ui/features/sandbox_screen.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/sandbox_screen.dart#L89)
  - [lib/ui/features/canvas/design_canvas.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/canvas/design_canvas.dart#L106)
  - [lib/ui/features/sandbox_view_model.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/sandbox_view_model.dart#L686-L706)
- **Category:** Performance / State Management
- **Problem:**
  `SandboxScreen`, `TopControlBar`, `DesignCanvas`, `SwitchNodeWidget`, `EndpointNodeWidget`, `NodeInspectorPanel`, and `IssuesDrawerPanel` all call `context.watch<SandboxViewModel>()`.
  When dragging a node on the canvas (`onPanUpdate` -> `vm.moveNode`), `notifyListeners()` fires at 60–120 Hz. Every single drag frame:
  1. Rebuilds `SandboxScreen`, `TopControlBar` (which re-runs `availableVlanIds` and `MulticastFlowTracer.buildTraceTargets(_project)`), `NodeInspectorPanel` (1,850 lines), and `IssuesDrawerPanel` (which re-filters all issues and regenerates the CLI config preview string).
  2. Rebuilds **every** `SwitchNodeWidget` and `EndpointNodeWidget` on the canvas, even though only one node moved and no network topology or validation result changed.
- **Instructions for Agent:**
  - Use `context.select<SandboxViewModel, ...>` in `TopControlBar`, `NodeInspectorPanel`, and `IssuesDrawerPanel` so they do not rebuild on mere `(dx, dy)` position changes.
  - Cache `availableStreamTraceTargets` and `availableVlanIds` inside `SandboxViewModel._revalidate()` instead of recomputing them inside getters on every widget `build()`.

---

### 2.2 [MEDIUM] `DesignCanvas.build` Mutates ViewModel State and Recomputes All Link Bezier Geometries synchronously inside `build()`
- **File:** [lib/ui/features/canvas/design_canvas.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/canvas/design_canvas.dart#L105-L125)
- **Category:** Performance / Flutter Best Practices
- **Problem:**
  1. Inside `LayoutBuilder.builder` (lines 115–116), `_viewportSize = constraints.biggest; _syncViewportCenter(vm);` is called directly during `build()`, which inverts a `Matrix4` and mutates `vm` on every layout pass.
  2. `LinkEdgePainter.shouldRepaint` (line 511) checks `oldDelegate.geometries != geometries`. Because `computeLinkGeometries(...)` returns a new `List<LinkGeometry>` instance on every `DesignCanvas.build` call, `oldDelegate.geometries != geometries` is **always `true`**, causing `LinkEdgePainter` to repaint on every `SandboxViewModel` notification (even when typing in the issues search box or collapsing the bottom drawer).
- **Instructions for Agent:**
  - Only call `_syncViewportCenter(vm)` when `constraints.biggest != _viewportSize` or inside `_onTransformChanged`.
  - Implement value equality (`operator ==` and `hashCode`) on `LinkGeometry` or compare list contents in `LinkEdgePainter.shouldRepaint`.

---

### 2.3 [MEDIUM] Oversized God-Files (`node_inspector_panel.dart` at 1,850 Lines & `sandbox_view_model.dart` at 1,450 Lines)
- **Files:**
  - [lib/ui/features/inspector/node_inspector_panel.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/inspector/node_inspector_panel.dart) (1,850 lines)
  - [lib/ui/features/sandbox_view_model.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/sandbox_view_model.dart) (1,450 lines)
  - [lib/ui/widgets/top_control_bar.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/widgets/top_control_bar.dart) (934 lines)
- **Category:** Maintainability / Architecture
- **Problem:**
  `node_inspector_panel.dart` packs four distinct inspectors plus a dialog and stateful traffic flow card into a single 1,850-line file. Similarly, `sandbox_view_model.dart` mixes selection state, canvas wiring state, project CRUD, template library CRUD, stream quick-pick queries, and CLI config string generation in a single 1,450-line class.
- **Instructions for Agent:**
  - Split `lib/ui/features/inspector/node_inspector_panel.dart` into focused widgets under `lib/ui/features/inspector/`:
    - `switch_inspector_view.dart` (Switch identity, STP, and Per-VLAN IGMP cards)
    - `endpoint_inspector_view.dart` (Endpoint identity and Multi-NIC port cards)
    - `traffic_flow_inspector_card.dart` (`_TrafficFlowInspectorCard` + Add Traffic Flow dialog)
    - `link_inspector_view.dart` (`_buildLinkInspector` and `_buildTopologySummary`)
  - Extract `generateCliConfigPreview` from `SandboxViewModel` (lines 1404–1449) into a dedicated pure domain/service class `lib/domain/engine/cli_config_generator.dart`.

---

### 2.4 [MEDIUM] Duplicate SQLite Connections & Polling Between `SharedDeviceDatabase` and `SuiteThemeService`
- **Files:**
  - [lib/main.dart](file:///home/tom-code/projects/flutter/net-design/lib/main.dart#L16-L24)
  - [lib/data/services/suite_theme_service.dart](file:///home/tom-code/projects/flutter/net-design/lib/data/services/suite_theme_service.dart#L29-L90)
  - [UI_AND_DESIGN_PRINCIPLES.md](file:///home/tom-code/projects/flutter/net-design/UI_AND_DESIGN_PRINCIPLES.md#L130-L177)
- **Category:** Architecture / Resource Duplication
- **Problem:**
  `main.dart` initializes `SharedDeviceDatabase.instance.init()` (from `network_suite_shared`), which already opens `shared_devices.db`. Immediately afterward, `SuiteThemeService` opens a **second independent SQLite `Database` connection** to the exact same `shared_devices.db` file and runs its own 1-second `Timer.periodic` executing `PRAGMA data_version;` every second.
  Furthermore, in `NetDesignAppState.dispose()` (lines 80–82):
  ```dart
  if (widget.themeService == null) {
    _themeService.dispose();
  }
  ```
  Because `main()` always passes `NetDesignApp(themeService: themeService)` (`widget.themeService != null`), `_themeService.dispose()` is **never called** when `NetDesignApp` is disposed (only if `didRequestAppExit` fires).
- **Instructions for Agent:**
  - Dispose `_themeService` unconditionally in `_NetDesignAppState.dispose()` (or guard `SuiteThemeService.dispose()` with an `_isDisposed` boolean so calling it from both `didRequestAppExit` and `dispose` is idempotent).

---

### 2.5 [MEDIUM] Missing Undo / Redo Stack for Canvas & Inspector Mutations
- **File:** [lib/ui/features/sandbox_view_model.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/sandbox_view_model.dart)
- **Category:** UX / Feature Improvement
- **Problem:**
  In a desktop design sandbox where users wire ports, delete switches, randomize MACs, or click "Update Plan" from a template, accidental deletions (`Delete` / `Backspace` key) or MAC randomizations cannot be undone with `Ctrl+Z` / `Ctrl+Y`. Because `TopologyProject.toJson()` / `fromJson()` (or `copyWith` deep-cloning) already serializes the entire project state deterministically in under 1 ms, adding a bounded snapshot undo/redo stack (e.g., 30 states) is straightforward.
- **Instructions for Agent:**
  - Add a bounded `_undoStack` / `_redoStack` of serialized or deep-copied `TopologyProject` snapshots in `SandboxViewModel` recorded before mutating actions (`addSwitchFromTemplate`, `addEndpointFromTemplate`, `removeNode`, `removeLink`, `connectPorts`, `randomiseSwitchMacs`, `autoFixLinkVlanSymmetry`, `applySwitchTemplateToPlan`, `applyEndpointTemplateToPlan`), and bind `Ctrl+Z` / `Ctrl+Y` (`Cmd+Z` / `Cmd+Shift+Z`) in `SandboxScreen._handleKeyEvent`.

---

### 2.6 [MEDIUM] Duplicated Graph BFS & Shortest-Path Helpers Across 3 Engine Solvers
- **Files:**
  - [lib/domain/engine/vlan_reachability_solver.dart](file:///home/tom-code/projects/flutter/net-design/lib/domain/engine/vlan_reachability_solver.dart#L348-L370) (`_isReachableOnVlan`)
  - [lib/domain/engine/multicast_flow_tracer.dart](file:///home/tom-code/projects/flutter/net-design/lib/domain/engine/multicast_flow_tracer.dart#L718-L772) (`_isVlanReachable`, `_buildBfsTree`)
  - [lib/domain/engine/resource_budget_solver.dart](file:///home/tom-code/projects/flutter/net-design/lib/domain/engine/resource_budget_solver.dart#L355-L411) (`_collectReachableVlanLinks`, `_collectShortestPathUnion`)
  - [lib/domain/engine/topology_validator.dart](file:///home/tom-code/projects/flutter/net-design/lib/domain/engine/topology_validator.dart#L169-L201) vs [lib/domain/engine/resource_budget_solver.dart](file:///home/tom-code/projects/flutter/net-design/lib/domain/engine/resource_budget_solver.dart#L35-L46) (`_portOrNicSpeed`, `_portOrNicMedia`)
- **Category:** Code Duplication / Performance
- **Problem:**
  - `_isReachableOnVlan` in `VlanReachabilitySolver` and `_isVlanReachable` in `MulticastFlowTracer` are byte-for-byte identical.
  - `_buildBfsTree` in `MulticastFlowTracer`, `_findBlockingVlanHop` in `VlanReachabilitySolver`, and `_collectShortestPathUnion` in `ResourceBudgetSolver` all implement the exact same BFS parent-pointer traversal over `List<NetworkLinkEdge>`, and all use `queue.removeAt(0)` (`O(V)` list shift) while scanning all links linearly (`O(V * E)`).
  - `MulticastFlowTracer.buildEndpointAttachments` is called **3 separate times** during a single `TopologyValidator.validate()` call (once in `VlanReachabilitySolver`, once in `IgmpDomainSolver`, once in `MulticastFlowTracer.validateStreams`, and a 4th time in `ResourceBudgetSolver`).
- **Instructions for Agent:**
  - Compute `epAttachments` and `forwardingInterSwitchLinks` once in `TopologyValidator.validate()` and pass them into the 4 solvers, or extract a shared `TopologyGraphUtils` helper in `lib/domain/engine/`.

---

### 2.7 [MEDIUM] Duplicate Traffic Flow Editor Logic Between `NodeInspectorPanel` and `EditEndpointTemplateDialog`
- **Files:**
  - [lib/ui/features/inspector/node_inspector_panel.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/inspector/node_inspector_panel.dart#L1015-L1252) and [lines 1447-1850](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/inspector/node_inspector_panel.dart#L1447-L1850)
  - [lib/ui/features/library/edit_endpoint_template_dialog.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/library/edit_endpoint_template_dialog.dart#L283-L654)
- **Category:** Code Duplication
- **Problem:**
  Both files independently implement NIC port row editors (`_buildEndpointNicCard` vs `_buildPortEditorRow`) and traffic flow editors (`_TrafficFlowInspectorCard` vs `_buildFlowEditorRow`) with nearly identical dropdowns, sACN universe auto-bandwidth math, and multicast validation. However, `EditEndpointTemplateDialog._buildFlowEditorRow` allows changing `Protocol` and `DeliveryType` on an existing flow, whereas `_TrafficFlowInspectorCard` in `NodeInspectorPanel` does **not** allow changing `Protocol` or `DeliveryType` once a flow is added (the user has to delete the flow and recreate it).
- **Instructions for Agent:**
  - Extract a shared `TrafficFlowEditorCard` widget used by both `NodeInspectorPanel` and `EditEndpointTemplateDialog`, and allow editing `Protocol` on placed endpoint flows as well.

---

### 2.8 [LOW] Hardcoded Non-Token Colors in `DesignCanvas` and `CanvasGridPainter`
- **Files:**
  - [lib/ui/features/canvas/design_canvas.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/canvas/design_canvas.dart#L126-L128)
  - [lib/ui/features/canvas/link_edge_painter.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/canvas/link_edge_painter.dart#L524)
- **Category:** Theme Consistency (`UI_AND_DESIGN_PRINCIPLES.md` Section 2)
- **Problem:**
  `UI_AND_DESIGN_PRINCIPLES.md` states: *"Never hardcode static colors... Use `AppTheme.<token>` dynamic getters"*.
  - `design_canvas.dart` lines 126–128 hardcode `const Color(0xFF0B0C0E)` and `const Color(0xFFDDE1E7)` for `backdropColor`.
  - `link_edge_painter.dart` line 524 hardcodes `const Color(0xFF252A32)` and `const Color(0xFFDADEE5)` for minor grid lines.
- **Instructions for Agent:**
  - Move `canvasBackdrop` and `canvasGridMinor` token getters into `AppTheme` (`lib/ui/theme/app_theme.dart`) and reference `AppTheme.canvasBackdrop` / `AppTheme.canvasGridMinor`.

---

### 2.9 [LOW] Default `com.example` Application / Bundle IDs and Placeholders Across Linux, macOS, and Windows Runners
- **Files:**
  - [linux/CMakeLists.txt](file:///home/tom-code/projects/flutter/net-design/linux/CMakeLists.txt#L10) (`set(APPLICATION_ID "com.example.net_design")`)
  - [macos/Runner/Configs/AppInfo.xcconfig](file:///home/tom-code/projects/flutter/net-design/macos/Runner/Configs/AppInfo.xcconfig#L11-L14) (`PRODUCT_BUNDLE_IDENTIFIER = com.example.netDesign`, `Copyright © 2026 com.example`)
  - [windows/runner/Runner.rc](file:///home/tom-code/projects/flutter/net-design/windows/runner/Runner.rc#L92-L99) (`CompanyName: "com.example"`, `ProductName: "net_design"`)
- **Category:** Platform Configuration
- **Problem:**
  All three desktop runners still use the template `com.example` bundle/company identifier.
- **Instructions for Agent:**
  - Replace `com.example` with the project's canonical reverse-domain identifier (e.g. `com.tommcguire.net_design` or `io.networksuite.net_design`) across `linux/CMakeLists.txt`, `macos/Runner/Configs/AppInfo.xcconfig`, and `windows/runner/Runner.rc`.

---

### 2.10 [LOW] Unpinned Git Dependency (`ref: main`) and Minimal Linter Rules
- **Files:**
  - [pubspec.yaml](file:///home/tom-code/projects/flutter/net-design/pubspec.yaml#L14-L17)
  - [analysis_options.yaml](file:///home/tom-code/projects/flutter/net-design/analysis_options.yaml#L22-L26)
- **Category:** Build Reproducibility & Static Analysis
- **Problem:**
  1. `network_suite_shared` in `pubspec.yaml` points to `ref: main` rather than an immutable tag or commit SHA. Breaking changes pushed to `network-suite-shared` `main` can break CI builds unexpectedly.
  2. `analysis_options.yaml` has an empty `rules:` block. Furthermore, lines 12–17 exclude `windows/**`, `macos/**`, and `linux/**`, which is fine, but enabling stricter Dart 3 lints (`prefer_single_quotes`, `unawaited_futures`, `avoid_dynamic_calls`, `prefer_final_locals`, `use_super_parameters`) would catch bugs like the `dynamic selectedSwitch` parameter in `IssuesDrawerPanel._buildCliPreview` ([lib/ui/features/inspector/issues_drawer_panel.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/inspector/issues_drawer_panel.dart#L309)).
- **Instructions for Agent:**
  - Change `dynamic selectedSwitch` in `IssuesDrawerPanel._buildCliPreview` (line 309) to `SwitchNodeInstance? selectedSwitch`.
  - Enable `prefer_single_quotes`, `unawaited_futures`, `avoid_dynamic_calls`, and `prefer_final_locals` in `analysis_options.yaml`.

---

## Part 3: Unused Code, Dead Dependencies & Unfinished Fields

Every item below was verified via full-repository search across `lib/` and `test/`.

### 3.1 Unused Dependencies in `pubspec.yaml`
- **File:** [pubspec.yaml](file:///home/tom-code/projects/flutter/net-design/pubspec.yaml#L19-L26)
  1. **`cupertino_icons: ^1.0.8`** (line 19): Never imported anywhere in `lib/` or `test/`.
  2. **`intl: ^0.20.2`** (line 24): Never imported anywhere in `lib/` or `test/`.
  - **Action:** Remove `cupertino_icons` and `intl` from `pubspec.yaml` and run `flutter pub get`.

### 3.2 Unused Asset Declared in `pubspec.yaml` and Tracked in Git
- **File:** [pubspec.yaml](file:///home/tom-code/projects/flutter/net-design/pubspec.yaml#L35-L38)
  - **`assets/app_icon.jpg`** (line 38): Never referenced anywhere in `lib/`, `test/`, or native runners (only `assets/app_icon.png` is used in `top_control_bar.dart:61`).
  - **Action:** Remove `- assets/app_icon.jpg` from `pubspec.yaml` and delete `assets/app_icon.jpg`.

### 3.3 Unused Model Methods & Getters
1. **`ValidationIssue.toJson()`** — [lib/domain/models/validation_issue.dart](file:///home/tom-code/projects/flutter/net-design/lib/domain/models/validation_issue.dart#L29-L42)
   - Never called anywhere in `lib/` or `test/`. (`ProjectStorageService` formats issues as Markdown, not JSON).
2. **`LinkStpState.fromJson` / `toJson`, `IssueSeverity.fromJson` / `toJson`, `IssueCategory.fromJson` / `toJson`** — [lib/domain/models/enums.dart](file:///home/tom-code/projects/flutter/net-design/lib/domain/models/enums.dart#L272-L328)
   - Never called anywhere in `lib/` or `test/` (except `IssueSeverity.toJson` and `IssueCategory.toJson` inside the unused `ValidationIssue.toJson`).
3. **`EndpointNodeInstance.totalTrafficMbps`** — [lib/domain/models/endpoint_node_instance.dart](file:///home/tom-code/projects/flutter/net-design/lib/domain/models/endpoint_node_instance.dart#L68-L71)
   - Defined as a getter on `EndpointNodeInstance`, never read anywhere in `lib/` or `test/`.
4. **`ResolvedMulticastStream.traceKey` and `ResolvedMulticastStream.shortLabel`** — [lib/domain/engine/multicast_stream_resolver.dart](file:///home/tom-code/projects/flutter/net-design/lib/domain/engine/multicast_stream_resolver.dart#L20-L23)
   - Never read anywhere in `lib/` or `test/` (`displayLabel` is used instead).

### 3.4 Half-Wired / Unused Domain Fields (Present in Models & JSON, Ignored by UI & Solvers)
These fields exist in the domain models and JSON serialization (and were mentioned in `SPECIFICATION.md`), but have **no UI controls** and **no solver logic** reading them:

1. **`SwitchVlanSettings.dropUnregisteredMulticast`** — [lib/domain/models/switch_node_instance.dart](file:///home/tom-code/projects/flutter/net-design/lib/domain/models/switch_node_instance.dart#L14-L64)
   - Serialized/deserialized in JSON, but never read by `IgmpDomainSolver`, `MulticastFlowTracer`, `ResourceBudgetSolver`, or displayed in `NodeInspectorPanel`.
   - **Action:** Either wire a toggle in `NodeInspectorPanel._buildVlanIgmpCard` and use it in `MulticastFlowTracer` (when `igmpSnoopingEnabled && !dropUnregisteredMulticast`, flood unregistered multicast), or remove the dead field.
2. **`SwitchPortConfig.lagGroupId` (`clearLagGroupId`)** — [lib/domain/models/switch_port_config.dart](file:///home/tom-code/projects/flutter/net-design/lib/domain/models/switch_port_config.dart#L15-L146)
   - Serialized/deserialized and preserved during `applySwitchTemplateToPlan`, but never used by `StpElectionSolver` (parallel links in a LAG should not block each other in STP and should aggregate bandwidth in `ResourceBudgetSolver`) and has no UI in `PortVlanMatrixEditor`.
   - **Action:** Either implement LAG (Port-Channel) support in `StpElectionSolver` / `ResourceBudgetSolver` + `PortVlanMatrixEditor`, or remove `lagGroupId` until LAG is in scope.
3. **`SwitchTemplate.isBuiltIn` & `EndpointTemplate.isBuiltIn`** — [lib/domain/models/switch_template.dart](file:///home/tom-code/projects/flutter/net-design/lib/domain/models/switch_template.dart#L24-L43), [lib/domain/models/endpoint_template.dart](file:///home/tom-code/projects/flutter/net-design/lib/domain/models/endpoint_template.dart#L248-L258)
   - Set to `true` on seeded templates in `DeviceTemplates`, serialized to JSON, and preserved on edit, but **never read anywhere in the UI** (e.g. built-in templates are not badged as `BUILT-IN` in `LibraryDrawer` nor protected from deletion).
   - **Action:** Render a `BUILT-IN` badge in `LibraryDrawer` (or remove the unused field).
4. **`TrafficRequirement.requiresIgmp`** — [lib/domain/models/endpoint_template.dart](file:///home/tom-code/projects/flutter/net-design/lib/domain/models/endpoint_template.dart#L100-L234)
   - Stored and serialized on every `TrafficRequirement`, but never read by `IgmpDomainSolver`, `MulticastFlowTracer`, or `ResourceBudgetSolver` (all solvers check `flow.deliveryType == DeliveryType.multicast` instead).
   - **Action:** Either check `flow.requiresIgmp` in `IgmpDomainSolver` or derive it as `bool get requiresIgmp => deliveryType == DeliveryType.multicast;`.
5. **`EndpointNodeInstance.macAddress` (`clearMacAddress`)** — [lib/domain/models/endpoint_node_instance.dart](file:///home/tom-code/projects/flutter/net-design/lib/domain/models/endpoint_node_instance.dart#L12-L36)
   - Passed to `RenameDeviceDialog` (in `endpoint_node_widget.dart:362`), but never populated when creating endpoints (`addEndpointFromTemplate` leaves `macAddress: null`) and has no text field in `NodeInspectorPanel._buildEndpointInspector`.
   - **Action:** Auto-generate a local MAC (or add an optional MAC field in `_buildEndpointInspector`) so `RenameDeviceDialog` can sync endpoint names to `SharedDeviceDatabase` just like switches.

---

## Part 4: Test Coverage Gaps

While solver unit tests and core widget tests are strong, the following areas have **zero automated test coverage**:

1. **Inspector Dialogs & Template Editors:**
   - `EditSwitchTemplateDialog` ([lib/ui/features/library/edit_switch_template_dialog.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/library/edit_switch_template_dialog.dart))
   - `EditEndpointTemplateDialog` ([lib/ui/features/library/edit_endpoint_template_dialog.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/library/edit_endpoint_template_dialog.dart))
   - `LibraryDrawer` modal interactions ([lib/ui/features/library/library_drawer.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/library/library_drawer.dart))
   - `RenameDeviceDialog` ([lib/ui/widgets/rename_device_dialog.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/widgets/rename_device_dialog.dart))
2. **Inspector Panel Interactive Flows:**
   - `PortVlanMatrixEditor` ([lib/ui/features/inspector/port_vlan_matrix_editor.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/inspector/port_vlan_matrix_editor.dart)) — changing port mode Access <-> Trunk, toggling allowed VLAN chips, toggling PoE.
   - `NodeInspectorPanel` link inspector (`Fix Trunk VLAN Symmetry` button -> `autoFixLinkVlanSymmetry`) and `_addEndpointFlow` dialog.
   - `IssuesDrawerPanel` ([lib/ui/features/inspector/issues_drawer_panel.dart](file:///home/tom-code/projects/flutter/net-design/lib/ui/features/inspector/issues_drawer_panel.dart)) — filtering issues by category chip, searching issues by text, clicking an issue to trigger `focusOnIssue`, and switching to the `CLI CONFIG PREVIEW` tab.
3. **Solver Edge Cases:**
   - Parallel links between two STP switches (port tie-breaking).
   - Unmanaged switch downstream of an STP switch (`hopDepthFromRoot` & arrow direction).
   - Intermediate switch with IGMP Snooping disabled on a multi-hop path between TX and RX.

---

## Part 5: Recommended Implementation Roadmap for Agents

To implement these improvements safely with zero regressions, hand off tasks in the following order:

1. **Phase 1 — Domain Engine & Model Fixes (Pure Dart + Unit Tests):**
   - Fix `StpElectionSolver` parallel link port tie-breaking, unmanaged downstream hop depth / arrow direction, and per-link unprotected loop reporting (Items **1.1**, **1.2**, **1.3**).
   - Fix `MulticastFlowTracer` intermediate snooping-disabled switch flooding (Item **1.4**).
   - Fix `EndpointNodeInstance.portByNumber` fallback masking invalid port numbers (Item **1.5**).
   - Fix `addKnownVlan` / `IgmpDomainSolver` false-positive critical issue on unused VLANs (Item **1.12**).
   - Deduplicate BFS helpers and `buildEndpointAttachments` calls across solvers (Item **2.6**).
2. **Phase 2 — Dead Code & Dependency Cleanup:**
   - Remove unused `cupertino_icons` and `intl` packages and `assets/app_icon.jpg` (Items **3.1**, **3.2**).
   - Clean up or wire unused model methods and fields (Items **3.3**, **3.4**).
   - Enable stricter lints in `analysis_options.yaml` and fix `dynamic selectedSwitch` (Item **2.10**).
3. **Phase 3 — UI Bug Fixes & Spec Alignment:**
   - Fix `LinkEdgePainter` dead `isVlanPruned` branch so pruned VLAN trunks highlight in red with `'VLAN X PRUNED'` badges (Item **1.9**).
   - Fix RX Quick-Pick chips to toggle/merge universes and support bidirectional flows (Item **1.8**).
   - Fix `EndpointNodeWidget` VLAN highlight check and `TextFormField` keys on template sync (Items **1.10**, **1.11**).
   - Add `try / catch` error handling around project open/save and library JSON import (Item **1.7**).
4. **Phase 4 — Refactoring, Performance & Platform Config:**
   - Split `node_inspector_panel.dart` (1,850 lines) and extract `CliConfigGenerator` from `sandbox_view_model.dart` (Item **2.3**).
   - Optimize `DesignCanvas` / `LinkEdgePainter.shouldRepaint` and narrow `Provider` rebuild scopes during node dragging (Items **2.1**, **2.2**).
   - Fix `SuiteThemeService` disposal and macOS entitlements / platform bundle IDs (Items **1.6**, **2.4**, **2.9**).
   - Add Undo/Redo support (`Ctrl+Z` / `Ctrl+Y`) and expand widget test coverage for inspector & library dialogs (Items **2.5**, **Part 4**).
