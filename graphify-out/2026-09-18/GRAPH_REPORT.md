# Graph Report - AirCatch  (2026-09-11)

## Corpus Check
- 41 files · ~59,031 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1070 nodes · 2361 edges · 47 communities (41 shown, 5 thin omitted)
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 115 edges (avg confidence: 0.82)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `88d13ff1`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- HostManager
- NetworkManager
- ExtendedDisplayPosition
- AirCatch
- ScreenStreamer
- Implement keyframe-request loss recovery + real loss reporting
- AirCatchClient/SharedModels.swift
- VirtualDisplayManager
- MouseHandlingView
- BitrateCalculator
- MetalVideoRenderer
- Foundation
- CryptoManager
- HostView
- Codable
- InputInjector
- String
- MPCAirCatchClient
- NetworkHealthMonitor
- MPCAirCatchHost
- ExtendedDisplayPosition
- String
- VideoDecoder
- AirCatchHost/SharedModels.swift
- SignalQuality
- PacketType
- .sendControl
- CryptoManager
- TimeInterval
- .makeHandshakeRequest
- ScreenStreamer.swift
- .handleTCPPacket
- BonjourAdvertiser
- DisplayManager
- Field
- ClientManager
- BonjourBrowser
- TouchEventType
- TouchEventType
- SidebarItem
- Bool
- .setStreamingStateIfNeeded
- AirCatchClient/CryptoManager.swift
- manifest.json
- launch_retry.sh
- .body

## God Nodes (most connected - your core abstractions)
1. `ClientManager` - 92 edges
2. `HostManager` - 77 edges
3. `NetworkManager` - 53 edges
4. `ScreenStreamer` - 40 edges
5. `MouseHandlingView` - 32 edges
6. `MetalVideoRenderer` - 28 edges
7. `VirtualDisplayManager` - 27 edges
8. `PacketType` - 22 edges
9. `VideoStreamViewModel` - 22 edges
10. `MPCAirCatchHost` - 22 edges

## Surprising Connections (you probably didn't know these)
- `.body` --calls--> `ContentView`  [INFERRED]
  AirCatchClient/AirCatchClientApp.swift → AirCatchClient/ContentView.swift
- `DiscoveredHost` --references--> `Network`  [EXTRACTED]
  AirCatchClient/SharedModels.swift → AirCatchHost/SharedModels.swift
- `.pinDisplay` --references--> `HostManager`  [INFERRED]
  AirCatchHost/HostView.swift → AirCatchHost/HostManager.swift
- `ClientManager` --calls--> `BonjourBrowser`  [INFERRED]
  AirCatchClient/ClientManager.swift → AirCatchClient/BonjourBrowser.swift
- `.body` --references--> `ClientManager`  [INFERRED]
  AirCatchClient/ContentView.swift → AirCatchClient/ClientManager.swift

## Import Cycles
- None detected.

## Communities (47 total, 5 thin omitted)

### Community 0 - "HostManager"
Cohesion: 0.07
Nodes (23): CachedFrame, HostManager, .effectiveDefaultFrameRate, .preferredFrameRate, .statusDescription, InputStateCache, Bool, CGDirectDisplayID (+15 more)

### Community 1 - "NetworkManager"
Cohesion: 0.09
Nodes (22): NetworkManager, Bool, Data, MainActor, NWConnection, NWEndpoint, Packet, PacketType (+14 more)

### Community 2 - "ExtendedDisplayPosition"
Cohesion: 0.18
Nodes (13): ExtendedDisplayConfig, ExtendedDisplayPosition, above, below, .displayName, left, right, StreamDisplayMode (+5 more)

### Community 3 - "AirCatch"
Cohesion: 0.10
Nodes (20): AirCatch, Code Graph (graphify), Connecting over Tailscale, Design Notes: Why This Looks Right and Reads Fast, Features, Getting Started, Given the above, what else is worth showing off?, How It Works (+12 more)

### Community 4 - "ScreenStreamer"
Cohesion: 0.08
Nodes (26): ScreenStreamer, StreamerError, compressionSessionCreationFailed, noDisplayFound, StreamOutput, Bool, CGDirectDisplayID, CMTime (+18 more)

### Community 5 - "Implement keyframe-request loss recovery + real loss reporting"
Cohesion: 0.20
Nodes (9): 1. Keyframe request protocol (new packet type), 2. Host: force keyframe on request, 3. Client: detect loss, request keyframe, 4. Real loss numbers in QualityReport, Files touched, Goal, Implement keyframe-request loss recovery + real loss reporting, Out of scope (noted for later) (+1 more)

### Community 6 - "AirCatchClient/SharedModels.swift"
Cohesion: 0.10
Nodes (30): AuthChallenge, AuthResponse, CodecPreference, auto, h264, hevc, ConnectionMode, localNetwork (+22 more)

### Community 7 - "VirtualDisplayManager"
Cohesion: 0.11
Nodes (25): CGVirtualDisplay, CGVirtualDisplayDescriptor, CGVirtualDisplayMode, CGVirtualDisplaySettings, AnyObject, Bool, CGDirectDisplayID, CGPoint (+17 more)

### Community 8 - "MouseHandlingView"
Cohesion: 0.08
Nodes (25): MouseHandlingView, .canBecomeFirstResponder, MouseInputView, Bool, CGPoint, CGRect, Context, Int (+17 more)

### Community 9 - "BitrateCalculator"
Cohesion: 0.39
Nodes (4): BitrateCalculator, Double, Int, String

### Community 10 - "MetalVideoRenderer"
Cohesion: 0.07
Nodes (33): MetalVideoRenderer, MetalVideoView, CGSize, Context, CVPixelBuffer, Float, Int, ObjectIdentifier (+25 more)

### Community 11 - "Foundation"
Cohesion: 0.20
Nodes (8): AppKit, Combine, CoreGraphics, Foundation, IOKit.hidsystem, MultipeerConnectivity, Network, Security

### Community 12 - "CryptoManager"
Cohesion: 0.24
Nodes (8): CryptoManager, .isReady, Bool, Data, Int, String, SymmetricKey, UInt32

### Community 13 - "HostView"
Cohesion: 0.08
Nodes (21): AirCatchClientApp, .body, Scene, AirCatchHostApp, .body, HostAppDelegate, Scene, HostView (+13 more)

### Community 14 - "Codable"
Cohesion: 0.16
Nodes (20): AirCatchConfig, DiscoveredHost, KeyEvent, KeyModifiers, MediaKeyEvent, PingPacket, PongPacket, QualityReport (+12 more)

### Community 15 - "InputInjector"
Cohesion: 0.14
Nodes (13): InputInjector, .hasAccessibilityPermission, Bool, CGPoint, CGRect, Double, Int32, KeyModifiers (+5 more)

### Community 16 - "String"
Cohesion: 0.12
Nodes (13): .savedSessionToken, ConnectionOption, automatic, .displayName, .id, .includePeerToPeer, udpNetworkFramework, udpPeerToPeerAWDL (+5 more)

### Community 17 - "MPCAirCatchClient"
Cohesion: 0.13
Nodes (17): MPCAirCatchClient, Data, Error, InputStream, MCPeerID, MCSession, MCSessionSendDataMode, MCSessionState (+9 more)

### Community 18 - "NetworkHealthMonitor"
Cohesion: 0.21
Nodes (7): NetworkHealthMonitor, Bool, Date, Double, Int, Timer, ObservableObject

### Community 19 - "MPCAirCatchHost"
Cohesion: 0.15
Nodes (18): MPCAirCatchHost, .hasConnectedPeers, Bool, Data, Error, InputStream, MCPeerID, MCSession (+10 more)

### Community 20 - "ExtendedDisplayPosition"
Cohesion: 0.09
Nodes (26): ExtendedDisplayConfig, ExtendedDisplayPosition, above, below, .displayName, left, right, ExtendedDisplayResolution (+18 more)

### Community 21 - "String"
Cohesion: 0.18
Nodes (13): AirCatchLog, Category, general, input, network, video, AirCatchLog, Category (+5 more)

### Community 22 - "VideoDecoder"
Cohesion: 0.08
Nodes (21): AudioPlayer, Data, Double, Int, UInt32, Bool, CMTime, CVPixelBuffer (+13 more)

### Community 23 - "AirCatchHost/SharedModels.swift"
Cohesion: 0.10
Nodes (29): AuthChallenge, AuthResponse, CodecPreference, auto, h264, hevc, ConnectionMode, localNetwork (+21 more)

### Community 24 - "SignalQuality"
Cohesion: 0.29
Nodes (7): SignalQuality, excellent, fair, good, .maxBitrate, poor, unknown

### Community 25 - "PacketType"
Cohesion: 0.05
Nodes (41): PacketType, audioPCM, authChallenge, authResponse, disconnect, handshake, handshakeAck, keyEvent (+33 more)

### Community 28 - ".sendControl"
Cohesion: 0.14
Nodes (7): Double, Int32, KeyModifiers, PacketType, TouchEventType, UncheckedSendable, T

### Community 29 - "CryptoManager"
Cohesion: 0.23
Nodes (8): CryptoManager, .isReady, Bool, Data, Int, String, SymmetricKey, UInt32

### Community 30 - "TimeInterval"
Cohesion: 0.15
Nodes (18): AirCatchConfig, DiscoveredHost, KeyEvent, KeyModifiers, MediaKeyEvent, PingPacket, PongPacket, QualityReport (+10 more)

### Community 34 - "ScreenStreamer.swift"
Cohesion: 0.14
Nodes (13): Accelerate, VideoDecoderError, decodeFailed, formatDescriptionCreationFailed, sessionCreationFailed, AVFoundation, CoreMedia, CoreVideo (+5 more)

### Community 36 - ".handleTCPPacket"
Cohesion: 0.15
Nodes (17): AtomicInt, ChunkSlice, error, FrameAssembly, Data, Int, Packet, Set (+9 more)

### Community 37 - "BonjourAdvertiser"
Cohesion: 0.39
Nodes (5): BonjourAdvertiser, NWListener, String, UInt16, NWTXTRecord

### Community 38 - "DisplayManager"
Cohesion: 0.32
Nodes (4): DisplayManager, Double, Int, CGDisplayMode

### Community 39 - "Field"
Cohesion: 0.67
Nodes (3): Field, address, pin

### Community 40 - "ClientManager"
Cohesion: 0.12
Nodes (9): ClientManager, .connectionOption, .effectiveIncludePeerToPeer, .optimizeForHostDisplay, DiscoveredHost, Float, Timer, HandshakeAck (+1 more)

### Community 43 - "BonjourBrowser"
Cohesion: 0.23
Nodes (7): BonjourBrowser, DiscoveredHost, MainActor, String, UInt16, Void, NWBrowser

### Community 44 - "TouchEventType"
Cohesion: 0.20
Nodes (10): TouchEventType, began, cancelled, doubleClick, dragBegan, dragEnded, dragMoved, ended (+2 more)

### Community 45 - "TouchEventType"
Cohesion: 0.20
Nodes (10): TouchEventType, began, cancelled, doubleClick, dragBegan, dragEnded, dragMoved, ended (+2 more)

### Community 46 - "SidebarItem"
Cohesion: 0.40
Nodes (5): SidebarItem, about, devices, settings, Hashable

### Community 47 - "Bool"
Cohesion: 0.17
Nodes (11): AtomicBool, .audioEnabled, ConnectionState, connected, connecting, disconnected, discovering, .displayDescription (+3 more)

### Community 62 - ".body"
Cohesion: 0.12
Nodes (32): ClientSettingsView, .body, AboutScreen, .body, ContentView, .body, DevicesBackground, .body (+24 more)

## Knowledge Gaps
- **215 isolated node(s):** `id`, `targets`, `AVFoundation`, `disconnected`, `discovering` (+210 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 348 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **5 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ClientManager` connect `ClientManager` to `HostManager`, `.makeHandshakeRequest`, `NetworkManager`, `.handleTCPPacket`, `MouseHandlingView`, `MetalVideoRenderer`, `BonjourBrowser`, `Codable`, `Bool`, `.setStreamingStateIfNeeded`, `String`, `NetworkHealthMonitor`, `VideoDecoder`, `.sendControl`, `.body`?**
  _High betweenness centrality (0.329) - this node is a cross-community bridge._
- **Why does `Foundation` connect `Foundation` to `ScreenStreamer.swift`, `.handleTCPPacket`, `AirCatchClient/SharedModels.swift`, `VirtualDisplayManager`, `BitrateCalculator`, `BonjourBrowser`, `AirCatchClient/CryptoManager.swift`, `AirCatchHost/SharedModels.swift`?**
  _High betweenness centrality (0.173) - this node is a cross-community bridge._
- **Why does `HostManager` connect `HostManager` to `ScreenStreamer`, `BonjourAdvertiser`, `Foundation`, `HostView`, `NetworkHealthMonitor`, `MPCAirCatchHost`, `CryptoManager`?**
  _High betweenness centrality (0.152) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `ClientManager` (e.g. with `BonjourBrowser` and `.body`) actually correct?**
  _`ClientManager` has 3 INFERRED edges - model-reasoned connections that need verification._
- **Are the 4 inferred relationships involving `HostManager` (e.g. with `BonjourAdvertiser` and `CryptoManager`) actually correct?**
  _`HostManager` has 4 INFERRED edges - model-reasoned connections that need verification._
- **What connects `id`, `targets`, `AVFoundation` to the rest of the system?**
  _215 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `HostManager` be split into smaller, more focused modules?**
  _Cohesion score 0.07437518819632641 - nodes in this community are weakly interconnected._