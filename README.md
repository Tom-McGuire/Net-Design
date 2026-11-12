# Net Design - Network Topology & Protocol Sandbox

An interactive, offline-first **Layer 2 / Layer 3 Network Topology & Protocol Sandbox** desktop application built with Flutter for **Windows, macOS, and Linux**.

---

## 📖 Specifications & Design Principles

Before implementing features or modifying the application, consult the following foundational documentation:

- **Application Specification:** [SPECIFICATION.md](file:///home/tom-code/projects/flutter/net-design/SPECIFICATION.md)  
  *Detailed specification covering vendor-neutral local template libraries, data models, graph structures, deterministic 4-pass validation & simulation engine (STP, VLAN reachability, IGMP snooping, resource budgets), and UI canvas controls.*

- **Suite UI & Design Principles:** [UI_AND_DESIGN_PRINCIPLES.md](file:///home/tom-code/projects/flutter/net-design/UI_AND_DESIGN_PRINCIPLES.md)  
  *(Also located at `\home\tom-code\projects\flutter\UI_AND_DESIGN_PRINCIPLES.md`)*  
  *The reference specification for UI/UX ergonomics, dynamic dark/light `AppTheme` design tokens, cross-process theme synchronization via `SharedDeviceDatabase`, typography, and desktop screen architectures.*

---

## 🖥️ Target Desktop Platforms

- **Windows** (`windows/`): Configured with 1280x720 window defaults and Win32 application runner.
- **macOS** (`macos/`): Configured with macOS Runner target and Cocoa integration.
- **Linux** (`linux/`): Configured with GTK3/header bar support and 1280x720 window defaults.

---

## 🏗️ Architecture & Directory Layout

```
net-design/
├── SPECIFICATION.md                 # Primary application specification & engine checklist
├── UI_AND_DESIGN_PRINCIPLES.md      # Suite UI & Design Tokens guide
├── lib/
│   ├── main.dart                    # Desktop entrypoint & theme synchronizer
│   ├── data/
│   │   └── services/                # Storage services (templates library & project files)
│   ├── domain/
│   │   ├── engine/                  # Deterministic simulation solvers (STP, VLAN, IGMP, Budget)
│   │   └── models/                  # Switch & Endpoint templates, node instances, links
│   └── ui/
│       ├── features/
│       │   ├── canvas/              # Topology canvas, node cards, and link painters
│       │   ├── inspector/           # Port matrix inspector & issues triage drawer
│       │   └── library/             # Switch & endpoint template editors
│       ├── theme/
│       │   └── app_theme.dart       # Dynamic Dark/Light tokens from UI principles
│       └── widgets/                 # Reusable suite widgets & dialogs
├── linux/                           # Linux desktop runner
├── macos/                           # macOS desktop runner
├── windows/                         # Windows desktop runner
└── test/                            # Unit, widget, and simulation scenario tests
```

---

## 🚀 Development Quick Start

```bash
# Fetch dependencies
flutter pub get

# Run static analysis
flutter analyze

# Execute tests
flutter test

# Run the desktop app on current OS (e.g. Linux)
flutter run -d linux
```
