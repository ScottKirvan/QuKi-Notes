# ArUco Tracking Plugin — Concept Summary & Technical Spec

**Created:** 2026-07-24  
**Context:** Exploratory conversation about building an ArUco marker tracking system for Meta Quest 3, with an eye toward a general-purpose, licensable Unreal Engine plugin.

---

## 1. Background & Use Case

The immediate use case is a **hands-on training simulator** built in Unreal Engine for Meta Quest 3. The simulator teaches users how to operate a specific piece of physical equipment. ArUco markers are affixed to the physical training device; the Quest 3's passthrough cameras detect and track those markers in real time, allowing virtual overlays and interactions to be anchored to the physical object's position and orientation.

### Why ArUco (vs. Meta Spatial Anchors)
- The training device **moves** and may have **sub-component tracking** needs (e.g., detecting whether a specific knob, switch, or panel is being interacted with)
- Spatial Anchors are better suited to fixed, room-scale placement — ArUco is the right tool for dynamic physical object tracking

---

## 2. Business Model

The plugin is to be developed as **independently owned, licensable IP** — not work-for-hire. Key points:

- The plugin layer is owned by the developer; clients license it
- The training simulator client owns all content built on top of the plugin
- This must be established explicitly in the client contract **before** development begins
- Potential licensing models: per-seat source license, per-project royalty, dual license (exclusive window then broad release), or Unreal Fab marketplace

### Market Opportunity
- Quest 3 training simulators
- Mobile AR games (iOS/Android) — board games, tabletop RPGs, educational apps
- Location-based entertainment (escape rooms, arcades)
- PC webcam use cases (virtual production, streaming overlays)

There is currently no mature, well-documented ArUco plugin on the Unreal Fab marketplace — this is a real gap.

---

## 3. Platform Strategy

The plugin is designed to be **platform-agnostic at the API level**, with platform-specific camera provider implementations swapped beneath a common interface.

### Platforms to Support
| Platform | Camera Provider | Priority |
|---|---|---|
| Meta Quest 3 | XrPassthroughCameraFB (Meta XR SDK) | P0 — implement now |
| Android (mobile) | Android Camera2 API | P1 — stub now, implement later |
| iOS | AVFoundation | P1 — stub now, implement later |
| PC (Windows/Mac) | Webcam / OpenCV VideoCapture | P2 |

**Strategy:** Design the full provider abstraction from day one. Implement Quest 3 only for the initial client. Stub remaining platforms. Estimated extra cost: ~30% more upfront engineering, saves a full rewrite later.

---

## 4. Architecture

```
┌─────────────────────────────────────────┐
│  Blueprint API (platform-agnostic)      │
│  StartTracking / StopTracking           │
│  OnMarkerDetected(ID, Transform)        │
│  OnMarkerLost(ID)                       │
├─────────────────────────────────────────┤
│  ArUco Detection Core (platform-agnostic│
│  OpenCV aruco::detectMarkers()          │
│  Pose estimation + coordinate mapping   │
│  Pose filtering (one-euro / Kalman)     │
├─────────────────────────────────────────┤
│  Camera Provider Interface              │
│  ICameraProvider                        │
│  + OnFrameAvailable(RawFrame)           │
├──────────┬──────────┬───────────────────┤
│ Quest3   │ Android  │ iOS  │ PC Webcam  │
│ Provider │ Provider │ Prov │ Provider   │
└──────────┴──────────┴──────┴────────────┘
```

### Plugin Directory Structure
```
ArucoTracker/
├── Source/
│   ├── ArucoTracker/               ← C++ core module
│   │   ├── Detection/              ← OpenCV wrapper, pose math
│   │   ├── Providers/              ← ICameraProvider + implementations
│   │   │   ├── Quest3CameraProvider
│   │   │   ├── AndroidCameraProvider   (stub)
│   │   │   ├── IOSCameraProvider       (stub)
│   │   │   └── WebcamProvider          (stub)
│   │   └── Filtering/              ← pose smoothing
│   └── ArucoTrackerBlueprintLib/   ← Blueprint-exposed wrapper nodes
├── ThirdParty/
│   └── OpenCV/
│       ├── ARM64/                  ← Quest 3 + Android libs
│       ├── x64/                    ← PC libs
│       └── include/
├── Content/                        ← optional demo assets / test scenes
└── ArucoTracker.uplugin
```

---

## 5. Key Technical Details

### Camera Access on Quest 3
- Requires Meta XR SDK **v65+** (start with latest, currently v74/v75 range)
- Uses `XrPassthroughCameraFB` OpenXR extension
- Requires Android manifest permissions: `USE_SCENE` + experimental camera permissions
- Raw YUV frames fed into OpenCV detection pipeline

### ArUco Detection
- `cv::aruco::detectMarkers()` → marker IDs + corner points per frame
- `cv::aruco::estimatePoseSingleMarkers()` → `rvec`/`tvec` in camera space
- For higher accuracy needs: use **ChArUco boards** or **ArUco marker boards** instead of single markers (significantly reduces pose noise)

### Coordinate Space Pipeline
```
OpenCV camera space (right-handed, Y-down)
  → Quest head space
  → Unreal world space (left-handed, Z-up)
```
Camera-to-head offset: fixed transform, calibrated once using Meta's published Quest 3 camera intrinsics.

### Pose Filtering
- Raw single-marker pose is noisy — filter with **one-euro filter** or **Kalman filter**
- Configurable per use case (training sim vs. fast-moving game object)

### Latency
- Passthrough camera → detection → render: typically 2–4 frames
- Acceptable for training simulator use cases; not suitable for sub-millisecond haptics

---

## 6. Blueprint API Surface (proposed)

```
// Lifecycle
StartTracking(MarkerDictionary, MarkerSizeMeters, CameraProvider)
StopTracking()

// Events (delegates)
OnMarkerDetected(MarkerId: int, WorldTransform: FTransform)
OnMarkerLost(MarkerId: int)
OnTrackingError(ErrorMessage: FString)

// Configuration
SetPoseFilterStrength(float)        // 0.0 = raw, 1.0 = maximum smoothing
SetDetectionFrequency(int FPS)      // throttle detection for perf budget
EnableDebugVisualization(bool)      // draw marker axes in viewport

// Utilities
GetLastKnownTransform(MarkerId) → FTransform
IsMarkerCurrentlyTracked(MarkerId) → bool
```

---

## 7. Physical Marker Guidelines

- **Minimum size:** ~5 cm for reliable arm's-length detection; larger = more stable pose
- **Surface:** flat, matte — Quest 3 passthrough cameras struggle with shiny/reflective materials
- **Placement:** design so markers remain **visible during normal equipment operation** — occlusion by hands breaks tracking
- **Multi-marker boards:** use ChArUco or ArUco boards instead of single markers when sub-millimeter accuracy is required

---

## 8. Implementation Phases

| Phase | Deliverable | Notes |
|---|---|---|
| **0 — Toolchain** | Meta XR SDK + Unreal + Quest 3 deploy pipeline working | Confirm raw passthrough camera frame access |
| **1 — Core** | C++ plugin wrapping OpenCV ArUco on Quest 3 camera frames | Validate pose accuracy before building content |
| **2 — API** | Clean Blueprint API, `ICameraProvider` abstraction, Quest 3 provider | Stubs for other platforms |
| **3 — Polish** | Pose filtering, debug visualization, performance profiling | One-euro or Kalman filter |
| **4 — Generalization** | Android + iOS camera providers | Enables mobile AR market |
| **5 — Distribution** | Documentation, demo project, Fab marketplace listing | Licensable product |

---

## 9. Open Questions

- [ ] Which specific ArUco dictionary will the training device use? (DICT_4X4, DICT_6X6, etc.)
- [ ] How many simultaneous markers need to be tracked?
- [ ] Is sub-component tracking needed (e.g., individual knobs/switches with their own markers)?
- [ ] What accuracy tolerance is acceptable for the training context?
- [ ] Will markers be on a flat surface or wrapped around curved geometry?
- [ ] Client contract language — confirm IP ownership of plugin layer before build starts

---

## 10. References

- [Meta Passthrough Camera API Sample](https://github.com/oculus-samples/Unity-PassthroughCameraApiSamples) *(Unity, but camera access pattern applies)*
- [OpenCV ArUco documentation](https://docs.opencv.org/4.x/d5/dae/tutorial_aruco_detection.html)
- [Meta XR SDK for Unreal](https://developers.meta.com/horizon/documentation/unreal/unreal-overview/)
- [One-Euro Filter](https://cristal.univ-lille.fr/~casiez/1euro/) — low-latency pose smoothing
- ADR-33, ADR-34 in this repo are unrelated (QuKi-Notes editor) — ArUco plugin lives outside app scope
