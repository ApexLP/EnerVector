# FieldSight

A computer vision field app for iPhone and iPad, built for electrical contractors, data center construction, commercial energy audits and solar site surveys. Native SwiftUI, iOS 18+. Everything runs on-device.

## What it does

| Workflow | How it works |
|---|---|
| **Nameplate capture** | VisionKit document scanner (or camera / photo library) → Vision OCR → parser extracts manufacturer, model, serial, voltage, amperage, phase, kVA, HVAC tonnage (incl. from BTU/h), refrigerant, year and equipment tag. Technician reviews and corrects before saving. |
| **Arc flash label check** | OCR looks for NFPA 70E label text (ARC FLASH, incident energy cal/cm², PPE category, boundaries). Equipment that NEC 110.16 expects to carry a label (panelboards, switchboards, MCCs, disconnects, UPS/PDU, etc.) is flagged when none is found — always after the tech confirms. |
| **Panel schedules** | Photograph the directory card; two-column (odd/even) schedules are parsed into circuit #, description, breaker size and poles. Editable. |
| **As-built room scans** | RoomPlan (LiDAR) captures walls, doors, windows and objects → dimensioned 2D floor plan, floor area and ceiling height. USDZ 3D model is kept for sharing. Non-LiDAR devices fall back to entered dimensions. |
| **Conduit & cable tray progress** | Planned vs. installed footage per segment, overall progress ring, behind/complete status. Installed length can be measured with an ARKit polyline (snaps to the LiDAR mesh when available). |
| **Roof & solar survey** | Trace the roof outline and obstructions in AR (true 3D surface area, so pitched roofs aren't under-counted) or enter areas → usable area, module count, kW and annual kWh. |
| **Load estimate** | HVAC tonnage × kW/ton plus lighting/plug W/sq ft over building area (sum of room scans, or entered). |
| **Reports** | On-device PDF (US Letter): cover stats, compliance flags, equipment and HVAC tables, panel schedules, floor plans, run progress, roof plan, load estimate, photo log, disclaimer. **Email** via the native Mail composer with PDF + CSV attached (falls back to the share sheet when Mail isn't set up). Share to Files, AirDrop, etc. CSV equipment export from Captures too. |

iPad gets a sidebar (`TabView` `.sidebarAdaptable`); iPhone gets a tab bar.

## Running it

```bash
open FieldSight.xcodeproj
```

Pick an iPhone/iPad and run. Set your signing team under *Signing & Capabilities* before running on a device.

- **Simulator:** no camera, LiDAR or ARKit — the app shows manual-entry fallbacks and you can import photos from the library for OCR. Sample sites load on first launch (Settings → Remove sample data).
- **Device:** LiDAR room scans need an iPhone Pro / iPad Pro. Document scanning and OCR work on any supported iPhone/iPad.

> The project lives inside an iCloud-synced `Documents` folder. If a command-line `xcodebuild` fails at CodeSign with "resource fork, Finder information, or similar detritus not allowed", build with a `-derivedDataPath` outside `Documents` (Xcode's default `~/Library/Developer/Xcode/DerivedData` is fine).

## Layout

```
FieldSight/
  App/        App entry, tab/sidebar root, navigation destinations
  Models/     SwiftData models, geometry, units, sample data
  Vision/     OCR (Vision), nameplate / arc flash / panel schedule parsers
  Capture/    Document scanner & camera, RoomPlan capture, ARKit measure tool
  Views/      Dashboard, sites, captures, equipment, room scans, runs, roof, reports, settings
  Report/     PDF report builder + CSV, plan renderer, Mail composer, PDF preview
```

## Notes & next steps

- OCR requests are pinned to `en-US` and Cyrillic/Greek look-alike letters are normalized — Vision's auto language detection otherwise returns "МСА" for "MCA" on all-caps plates.
- Parsers are heuristic; the review screen is the source of truth. Worth collecting real nameplate photos to tune against.
- Ideas: iCloud/CloudKit sync across a crew, drawing (PDF) import with conduit runs overlaid on the plan, DXF export of as-builts, satellite imagery for roofs, per-company report branding/logo.
