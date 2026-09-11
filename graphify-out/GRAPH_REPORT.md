# Graph Report - AirCatch  (2026-09-11)

## Corpus Check
- 40 files · ~57,761 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1063 nodes · 2331 edges · 61 communities (42 shown, 18 thin omitted)
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 116 edges (avg confidence: 0.82)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `2cf8b651`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- HostManager
- NetworkManager
- DisplayManager
- AirCatch
- ScreenStreamer
- HostView
- Int
- VirtualDisplayManager
- MouseHandlingView
- .body
- MetalVideoRenderer
- Foundation
- CryptoManager
- ScreenStreamer.swift
- AirCatchClient/SharedModels.swift
- InputInjector
- Date
- MPCAirCatchClient
- NetworkHealthMonitor
- MPCAirCatchHost
- ExtendedDisplayPosition
- String
- VideoDecoder
- AirCatchHost/SharedModels.swift
- BonjourAdvertiser
- PacketType
- Bool
- iPadDisplayPreset
- .sendControl
- CryptoManager
- Codable
- Int
- AudioPlayer
- .makeHandshakeRequest
- VideoDecoder.swift
- AppKit
- .handleTCPPacket
- SidebarItem
- UncheckedSendable
- AirCatchClient/CryptoManager.swift
- ClientManager
- iPadDisplayPreset
- BonjourBrowser
- TouchEventType
- TouchEventType
- Field
- ConnectionState
- .setStreamingStateIfNeeded
- Float
- manifest.json
- launch_retry.sh
- KeyModifiers
- PacketType
- Set
- Timer
- CGDirectDisplayID
- CGRect
- MCPeerID
- NWConnection
- ObjectIdentifier

## God Nodes (most connected - your core abstractions)
1. `ClientManager` - 89 edges
2. `HostManager` - 74 edges
3. `NetworkManager` - 53 edges
4. `ScreenStreamer` - 37 edges
5. `MouseHandlingView` - 32 edges
6. `MetalVideoRenderer` - 28 edges
7. `VirtualDisplayManager` - 27 edges
8. `MPCAirCatchHost` - 22 edges
9. `VideoStreamViewModel` - 22 edges
10. `PacketType` - 21 edges

## Surprising Connections (you probably didn't know these)
- `.body` --calls--> `ContentView`  [INFERRED]
  AirCatchClient/AirCatchClientApp.swift → AirCatchClient/ContentView.swift
- `.pinDisplay` --references--> `HostManager`  [INFERRED]
  AirCatchHost/HostView.swift → AirCatchHost/HostManager.swift
- `DiscoveredHost` --references--> `Network`  [EXTRACTED]
  AirCatchClient/SharedModels.swift → AirCatchHost/SharedModels.swift
- `ClientManager` --calls--> `BonjourBrowser`  [INFERRED]
  AirCatchClient/ClientManager.swift → AirCatchClient/BonjourBrowser.swift
- `.body` --references--> `ClientManager`  [INFERRED]
  AirCatchClient/ContentView.swift → AirCatchClient/ClientManager.swift

## Import Cycles
- None detected.

## Communities (61 total, 18 thin omitted)

### Community 0 - "HostManager"
Cohesion: 0.08
Nodes (23): CachedFrame, HostManager, .effectiveDefaultFrameRate, .preferredFrameRate, .statusDescription, InputStateCache, Bool, Data (+15 more)

### Community 1 - "NetworkManager"
Cohesion: 0.09
Nodes (22): NetworkManager, Bool, Data, MainActor, NWConnection, NWEndpoint, Packet, PacketType (+14 more)

### Community 2 - "DisplayManager"
Cohesion: 0.32
Nodes (4): DisplayManager, Double, Int, CGDisplayMode

### Community 3 - "AirCatch"
Cohesion: 0.10
Nodes (20): AirCatch, Code Graph (graphify), Connecting over Tailscale, Design Notes: Why This Looks Right and Reads Fast, Features, Getting Started, Given the above, what else is worth showing off?, How It Works (+12 more)

### Community 4 - "ScreenStreamer"
Cohesion: 0.09
Nodes (26): ScreenStreamer, StreamerError, compressionSessionCreationFailed, noDisplayFound, StreamOutput, Bool, CGDirectDisplayID, CMTime (+18 more)

### Community 5 - "HostView"
Cohesion: 0.10
Nodes (18): AirCatchClientApp, .body, Scene, AirCatchHostApp, .body, Scene, HostView, .body (+10 more)

### Community 6 - "Int"
Cohesion: 0.18
Nodes (17): AuthChallenge, AuthResponse, CodecPreference, auto, h264, hevc, ConnectionMode, localNetwork (+9 more)

### Community 7 - "VirtualDisplayManager"
Cohesion: 0.09
Nodes (28): HostAppDelegate, CGVirtualDisplay, CGVirtualDisplayDescriptor, CGVirtualDisplayMode, CGVirtualDisplaySettings, AnyObject, Bool, CGDirectDisplayID (+20 more)

### Community 8 - "MouseHandlingView"
Cohesion: 0.08
Nodes (26): MouseHandlingView, .canBecomeFirstResponder, MouseInputView, Bool, CGPoint, CGRect, Context, Int (+18 more)

### Community 9 - ".body"
Cohesion: 0.12
Nodes (32): ClientSettingsView, AboutScreen, .body, ContentView, .body, DevicesBackground, .body, DevicesScreen (+24 more)

### Community 10 - "MetalVideoRenderer"
Cohesion: 0.07
Nodes (32): MetalVideoRenderer, MetalVideoView, CGSize, Context, CVPixelBuffer, Float, Int, ObjectIdentifier (+24 more)

### Community 11 - "Foundation"
Cohesion: 0.23
Nodes (5): Combine, Foundation, MultipeerConnectivity, ScreenCaptureKit, Security

### Community 12 - "CryptoManager"
Cohesion: 0.24
Nodes (8): CryptoManager, .isReady, Bool, Data, Int, String, SymmetricKey, UInt32

### Community 13 - "ScreenStreamer.swift"
Cohesion: 0.33
Nodes (4): Accelerate, AVFoundation, CoreMedia, IOSurface

### Community 14 - "AirCatchClient/SharedModels.swift"
Cohesion: 0.17
Nodes (20): AirCatchConfig, KeyEvent, KeyModifiers, MediaKeyEvent, Packet, PingPacket, PongPacket, QualityReport (+12 more)

### Community 15 - "InputInjector"
Cohesion: 0.14
Nodes (13): InputInjector, .hasAccessibilityPermission, Bool, CGPoint, CGRect, Double, Int32, KeyModifiers (+5 more)

### Community 17 - "MPCAirCatchClient"
Cohesion: 0.13
Nodes (17): MPCAirCatchClient, Data, Error, InputStream, MCPeerID, MCSession, MCSessionSendDataMode, MCSessionState (+9 more)

### Community 18 - "NetworkHealthMonitor"
Cohesion: 0.10
Nodes (18): BitrateCalculator, Double, Int, String, NetworkHealthMonitor, SignalQuality, excellent, fair (+10 more)

### Community 19 - "MPCAirCatchHost"
Cohesion: 0.15
Nodes (18): MPCAirCatchHost, .hasConnectedPeers, Bool, Data, Error, InputStream, MCPeerID, MCSession (+10 more)

### Community 20 - "ExtendedDisplayPosition"
Cohesion: 0.05
Nodes (45): ConnectionOption, .displayName, .id, .includePeerToPeer, udpNetworkFramework, udpPeerToPeerAWDL, ExtendedDisplayConfig, ExtendedDisplayPosition (+37 more)

### Community 21 - "String"
Cohesion: 0.14
Nodes (18): AirCatchLog, Category, general, input, network, video, DiscoveredHost, AirCatchLog (+10 more)

### Community 22 - "VideoDecoder"
Cohesion: 0.14
Nodes (13): Bool, CMTime, CVPixelBuffer, Data, Int, UInt8, VideoDecoder, VideoDecoderDelegate (+5 more)

### Community 23 - "AirCatchHost/SharedModels.swift"
Cohesion: 0.17
Nodes (18): AuthChallenge, AuthResponse, CodecPreference, auto, h264, hevc, ConnectionMode, localNetwork (+10 more)

### Community 24 - "BonjourAdvertiser"
Cohesion: 0.39
Nodes (5): BonjourAdvertiser, NWListener, String, UInt16, NWTXTRecord

### Community 25 - "PacketType"
Cohesion: 0.05
Nodes (39): PacketType, audioPCM, authChallenge, authResponse, disconnect, handshake, handshakeAck, keyEvent (+31 more)

### Community 26 - "Bool"
Cohesion: 0.25
Nodes (4): AtomicBool, .audioEnabled, Bool, KeyModifiers

### Community 27 - "iPadDisplayPreset"
Cohesion: 0.17
Nodes (11): iPadDisplayPreset, .aspectRatio, .displayName, generic, iPadAir109, iPadMini6, iPadPro11, iPadPro129 (+3 more)

### Community 28 - ".sendControl"
Cohesion: 0.18
Nodes (4): Double, Int32, TouchEventType, PacketType

### Community 29 - "CryptoManager"
Cohesion: 0.23
Nodes (8): CryptoManager, .isReady, Bool, Data, Int, String, SymmetricKey, UInt32

### Community 30 - "Codable"
Cohesion: 0.20
Nodes (17): AirCatchConfig, KeyEvent, KeyModifiers, MediaKeyEvent, PingPacket, PongPacket, QualityReport, ScrollEvent (+9 more)

### Community 32 - "AudioPlayer"
Cohesion: 0.22
Nodes (6): AudioPlayer, Data, Double, Int, UInt32, AVAudioFormat

### Community 34 - "VideoDecoder.swift"
Cohesion: 0.20
Nodes (9): OSStatus, VideoDecoderError, decodeFailed, formatDescriptionCreationFailed, sessionCreationFailed, CoreVideo, Error, MetalKit (+1 more)

### Community 35 - "AppKit"
Cohesion: 0.40
Nodes (3): AppKit, CoreGraphics, IOKit.hidsystem

### Community 36 - ".handleTCPPacket"
Cohesion: 0.21
Nodes (14): ChunkSlice, error, FrameAssembly, Data, Packet, UInt16, UInt32, Void (+6 more)

### Community 37 - "SidebarItem"
Cohesion: 0.40
Nodes (5): SidebarItem, about, devices, settings, Hashable

### Community 40 - "ClientManager"
Cohesion: 0.11
Nodes (15): ClientManager, .connectionOption, .optimizeForHostDisplay, .savedSessionToken, SavedHost, DiscoveredHost, NWEndpoint, String (+7 more)

### Community 42 - "iPadDisplayPreset"
Cohesion: 0.18
Nodes (11): iPadDisplayPreset, .aspectRatio, .displayName, generic, iPadAir109, iPadMini6, iPadPro11, iPadPro129 (+3 more)

### Community 43 - "BonjourBrowser"
Cohesion: 0.23
Nodes (7): BonjourBrowser, DiscoveredHost, MainActor, String, UInt16, Void, NWBrowser

### Community 44 - "TouchEventType"
Cohesion: 0.20
Nodes (10): TouchEventType, began, cancelled, doubleClick, dragBegan, dragEnded, dragMoved, ended (+2 more)

### Community 45 - "TouchEventType"
Cohesion: 0.20
Nodes (10): TouchEventType, began, cancelled, doubleClick, dragBegan, dragEnded, dragMoved, ended (+2 more)

### Community 46 - "Field"
Cohesion: 0.67
Nodes (3): Field, address, pin

### Community 47 - "ConnectionState"
Cohesion: 0.25
Nodes (8): ConnectionState, connected, connecting, disconnected, discovering, .displayDescription, .isConnected, streaming

## Knowledge Gaps
- **203 isolated node(s):** `disconnected`, `discovering`, `connecting`, `connected`, `streaming` (+198 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 345 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **18 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ClientManager` connect `ClientManager` to `HostManager`, `.makeHandshakeRequest`, `.handleTCPPacket`, `MouseHandlingView`, `.body`, `MetalVideoRenderer`, `BonjourBrowser`, `Foundation`, `ConnectionState`, `.setStreamingStateIfNeeded`, `NetworkHealthMonitor`, `ExtendedDisplayPosition`, `Bool`, `.sendControl`, `Int`?**
  _High betweenness centrality (0.260) - this node is a cross-community bridge._
- **Why does `Foundation` connect `Foundation` to `VideoDecoder.swift`, `AppKit`, `AirCatchClient/CryptoManager.swift`, `VirtualDisplayManager`, `BonjourBrowser`, `ScreenStreamer.swift`, `AirCatchClient/SharedModels.swift`, `NetworkHealthMonitor`, `AirCatchHost/SharedModels.swift`?**
  _High betweenness centrality (0.208) - this node is a cross-community bridge._
- **Why does `HostManager` connect `HostManager` to `HostView`, `Foundation`, `NetworkHealthMonitor`, `MPCAirCatchHost`, `BonjourAdvertiser`?**
  _High betweenness centrality (0.137) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `ClientManager` (e.g. with `BonjourBrowser` and `.body`) actually correct?**
  _`ClientManager` has 3 INFERRED edges - model-reasoned connections that need verification._
- **Are the 3 inferred relationships involving `HostManager` (e.g. with `BonjourAdvertiser` and `MPCAirCatchHost`) actually correct?**
  _`HostManager` has 3 INFERRED edges - model-reasoned connections that need verification._
- **What connects `disconnected`, `discovering`, `connecting` to the rest of the system?**
  _203 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `HostManager` be split into smaller, more focused modules?**
  _Cohesion score 0.07561728395061729 - nodes in this community are weakly interconnected._