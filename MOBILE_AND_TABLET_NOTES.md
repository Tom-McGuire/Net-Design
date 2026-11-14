# Net Design — Mobile, Tablet & Chromebook Readiness Notes

> **Status:** Exploratory Assessment (Pending Feedback)  
> **Target Form Factors:** iPad (iPadOS), Android Tablets, Chromebooks (ChromeOS via Android APK or Crostini Linux)

---

## 1. Executive Summary

Porting **Net Design** to tablets and Chromebooks is **low-to-moderate effort**. The deterministic validation engine (`StpElectionSolver`, `VlanReachabilitySolver`, `IgmpDomainSolver`, `ResourceBudgetSolver`), state layer (`Provider` / `SandboxViewModel`), storage (`sqlite3`, `path_provider`), and canvas pan/zoom (`InteractiveViewer`) are pure Dart or already cross-platform.

Landscape tablets (1024px+ wide) and Chromebooks can use the existing 5-tier workspace almost immediately, while **portrait tablets and split-screen modes** need responsive panel collapsing and minor touch ergonomics refinements.

---

## 2. What Already Works Out of the Box

| Subsystem | Current Implementation | Tablet / Mobile Compatibility |
|---|---|---|
| **Simulation & Solvers** | Pure Dart (`lib/domain/engine/*`) | 100% portable; zero native FFI or desktop platform channels |
| **State Management** | `provider` (`ChangeNotifier`) | 100% portable across Android & iOS |
| **Theme Service** | `SuiteThemeService` (`lib/data/services/suite_theme_service.dart`) | Wraps desktop `SharedDeviceDatabase.getDefaultDatabasePath()` in `try/catch`; safely falls back to local Light/Dark toggling when no desktop DB exists |
| **Canvas Pan / Zoom** | `InteractiveViewer` in `DesignCanvas` | Native multi-touch pinch-to-zoom and pan support |
| **Node Dragging** | `SwitchNodeWidget` & `EndpointNodeWidget` | Already allows `PointerDeviceKind.touch` and `PointerDeviceKind.stylus` (Apple Pencil / USI stylus ready) |
| **File Save** | `FilePicker.saveFile(..., bytes: bytes)` | Already passes `bytes`, which is mandatory on Android & iOS scoped storage |

---

## 3. Required Work Breakdown

### 3.1 Add `android/` and `ios/` Platform Runners
Currently only `linux/`, `macos/`, and `windows/` exist in the repository:
1. Run `flutter create --platforms=android,ios .` from the project root (preserving existing `lib/`, `test/`, and `pubspec.yaml`).
2. Generate adaptive/rounded mobile app icons from `assets/app_icon.png` (e.g., `mipmap-*` resources for Android and `AppIcon.appiconset` iOS idioms).
3. Configure Android `minSdk` compatibility if needed for `sqlite3` / `file_picker` and iOS `UISupportedInterfaceOrientations` (prioritizing landscape & all orientations for iPad).

### 3.2 Responsive Layout Breakpoints (< 850px Width)
In `lib/ui/features/sandbox_screen.dart`, the desktop layout currently renders a fixed horizontal `Row`:
- `DesignCanvas` (`Expanded`)
- `NodeInspectorPanel` (`width: 356` in `lib/ui/features/inspector/node_inspector_panel.dart`)
- `IssuesDrawerPanel` (`height: 230` in `lib/ui/features/inspector/issues_drawer_panel.dart`)
- `LibraryDrawer` dialog (`width: 780` in `lib/ui/features/library/library_drawer.dart`)

To support portrait tablets, split-screen multitasking, and smaller Android tablets:
- Wrap `SandboxScreen` in `SafeArea` (handling iPadOS status bar / home indicator and Android camera cutouts).
- Add a `LayoutBuilder` breakpoint (e.g., `< 850px` width):
  - Hide the persistent right-side `NodeInspectorPanel` on narrow screens and present it inside a slide-over `endDrawer` or modal bottom sheet automatically opened when a switch, endpoint, or link is tapped.
  - Constrain `LibraryDrawer` width with `min(780, mediaWidth * 0.94)` instead of a hardcoded `780px`.
  - Allow `IssuesDrawerPanel` height to scale proportionally (`min(230, mediaHeight * 0.32)`) so the canvas stays visible on shorter portrait/split-screen viewports.
- Add a compact overflow/scrollable menu or responsive collapse on `TopControlBar` if needed for `< 700px` split-screen widths.

### 3.3 Touch Ergonomics & Mobile File Picker Quirks
1. **Tap Targets & Hit Testing:**
   - Increase link tap tolerance in `DesignCanvas._hitTestLink` from `18.0px` to `26.0–28.0px` for finger accuracy (stylus input remains crisp either way).
   - Add slightly more tap padding (`>= 32x32` effective hit area) around card header edit/wire icons and mini faceplate port chips (`_MiniPortChip` is currently `21x19` visual size; keeping visual density while expanding hit slop or zooming comfortably helps finger wiring).
2. **`.netdesign` Custom Extension Picking on iOS / Android:**
   - Native mobile document pickers (`UIDocumentPickerViewController` / Android SAF) frequently grey out unknown custom extensions when `FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['netdesign', 'json'])` is called.
   - **Fix:** On `Platform.isAndroid || Platform.isIOS`, call `FilePicker.pickFiles(type: FileType.any)` (or `withData: true`) and validate the `.netdesign` / `.json` extension and JSON structure in Dart.

---

## 4. Platform-Specific Deployment Notes

| Platform | Runtime Path | Build / Distribution Requirements |
|---|---|---|
| **Chromebook (ChromeOS)** | **Easiest:** Run Android APK directly via ChromeOS Android subsystem, **or** run the existing Linux build inside Crostini | Android `.apk` needs minimal permissions; Linux build works today on x64 Chromebooks with Linux dev environment enabled |
| **Android Tablet** | Native Android runner (`android/`) | Standard Android SDK/NDK build (`.apk` / `.aab`); can be added directly to `.github/workflows/release.yml` using `ubuntu-latest` + debug/upload keystore |
| **iPad (iPadOS)** | Native iOS runner (`ios/`) | Code changes are identical to Android, **but** building/installing to physical iPads requires **macOS + Xcode** (or `macos-latest` CI runner) plus an **Apple Developer** certificate & provisioning profile |

---

## 5. Open Questions Before Implementation
1. Should phones (< 600px) also be targeted cleanly, or is **tablets + Chromebooks (≥ 700px)** the primary UX target?
2. Should GitHub Actions `.github/workflows/release.yml` publish signed/unsigned `.apk` artifacts alongside Windows/macOS/Linux desktop builds?
3. Would pinch/pan locking (toggleable "Lock Canvas" button) be helpful when dragging many small switches on a touchscreen?
