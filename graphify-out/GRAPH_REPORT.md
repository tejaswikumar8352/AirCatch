# Graph Report - AirCatch  (2026-09-11)

## Corpus Check
- 40 files · ~57,761 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1050 nodes · 2328 edges · 51 communities (46 shown, 4 thin omitted)
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 113 edges (avg confidence: 0.82)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `78ca6452`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- HostManager
- NetworkManager
- DisplayManager
- AirCatch
- ScreenStreamer
- HostView
- VideoStreamViewModel
- VirtualDisplayManager
- MouseHandlingView
- View
- MetalVideoRenderer
- Foundation
- CryptoManager
- VideoDecoder.swift
- AirCatchClient/SharedModels.swift
- InputInjector
- String
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
- MetalVideoView
- .sendControl
- CryptoManager
- Codable
- Network
- AudioPlayer
- BitrateCalculator
- VideoDecoderError
- ExtendedDisplayPosition
- .handleTCPPacket
- SidebarItem
- ExtendedDisplayResolution
- AirCatchClient/CryptoManager.swift
- ClientManager
- iPadDisplayPreset
- BonjourBrowser
- TouchEventType
- TouchEventType
- ConnectionState
- .setStreamingStateIfNeeded
- ConnectionOption
- manifest.json
- launch_retry.sh

## God Nodes (most connected - your core abstractions)
1. `ClientManager` - 89 edges
2. `HostManager` - 75 edges
3. `NetworkManager` - 53 edges
4. `ScreenStreamer` - 39 edges
5. `MouseHandlingView` - 32 edges
6. `MetalVideoRenderer` - 28 edges
7. `VirtualDisplayManager` - 27 edges
8. `VideoStreamViewModel` - 22 edges
9. `MPCAirCatchHost` - 22 edges
10. `MPCAirCatchClient` - 21 edges

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

## Communities (51 total, 4 thin omitted)

### Community 0 - "HostManager"
Cohesion: 0.08
Nodes (22): CachedFrame, HostManager, .effectiveDefaultFrameRate, .preferredFrameRate, .statusDescription, InputStateCache, Bool, CGDirectDisplayID (+14 more)

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
Cohesion: 0.08
Nodes (27): ScreenStreamer, StreamerError, compressionSessionCreationFailed, noDisplayFound, StreamOutput, Bool, CGDirectDisplayID, CMTime (+19 more)

### Community 5 - "HostView"
Cohesion: 0.08
Nodes (21): AirCatchClientApp, .body, Scene, AirCatchHostApp, .body, HostAppDelegate, Scene, HostView (+13 more)

### Community 6 - "VideoStreamViewModel"
Cohesion: 0.17
Nodes (12): Bool, CGPoint, CGRect, CGSize, CMTime, CVPixelBuffer, Data, Error (+4 more)

### Community 7 - "VirtualDisplayManager"
Cohesion: 0.11
Nodes (25): CGVirtualDisplay, CGVirtualDisplayDescriptor, CGVirtualDisplayMode, CGVirtualDisplaySettings, AnyObject, Bool, CGDirectDisplayID, CGPoint (+17 more)

### Community 8 - "MouseHandlingView"
Cohesion: 0.08
Nodes (26): MouseHandlingView, .canBecomeFirstResponder, MouseInputView, Bool, CGPoint, CGRect, Context, Int (+18 more)

### Community 9 - "View"
Cohesion: 0.11
Nodes (32): AboutScreen, .body, ContentView, DevicesBackground, .body, DevicesScreen, .header, Field (+24 more)

### Community 10 - "MetalVideoRenderer"
Cohesion: 0.12
Nodes (17): MetalVideoRenderer, CGSize, CVPixelBuffer, Float, Int, ObjectIdentifier, CVMetalTextureCache, MTKView (+9 more)

### Community 11 - "Foundation"
Cohesion: 0.16
Nodes (8): AppKit, Combine, CoreGraphics, Foundation, IOKit.hidsystem, MultipeerConnectivity, ScreenCaptureKit, Security

### Community 12 - "CryptoManager"
Cohesion: 0.24
Nodes (8): CryptoManager, .isReady, Bool, Data, Int, String, SymmetricKey, UInt32

### Community 13 - "VideoDecoder.swift"
Cohesion: 0.24
Nodes (6): Accelerate, AVFoundation, CoreMedia, CoreVideo, MetalKit, VideoToolbox

### Community 14 - "AirCatchClient/SharedModels.swift"
Cohesion: 0.07
Nodes (47): AirCatchConfig, AuthChallenge, AuthResponse, CodecPreference, auto, h264, hevc, ConnectionMode (+39 more)

### Community 15 - "InputInjector"
Cohesion: 0.14
Nodes (13): InputInjector, .hasAccessibilityPermission, Bool, CGPoint, CGRect, Double, Int32, KeyModifiers (+5 more)

### Community 16 - "String"
Cohesion: 0.17
Nodes (9): SavedHost, Date, DiscoveredHost, NWEndpoint, String, ClientSettingsView, .body, .body (+1 more)

### Community 17 - "MPCAirCatchClient"
Cohesion: 0.13
Nodes (17): MPCAirCatchClient, Data, Error, InputStream, MCPeerID, MCSession, MCSessionSendDataMode, MCSessionState (+9 more)

### Community 18 - "NetworkHealthMonitor"
Cohesion: 0.13
Nodes (14): NetworkHealthMonitor, SignalQuality, excellent, fair, good, .maxBitrate, poor, unknown (+6 more)

### Community 19 - "MPCAirCatchHost"
Cohesion: 0.15
Nodes (18): MPCAirCatchHost, .hasConnectedPeers, Bool, Data, Error, InputStream, MCPeerID, MCSession (+10 more)

### Community 20 - "ExtendedDisplayPosition"
Cohesion: 0.11
Nodes (20): ExtendedDisplayConfig, ExtendedDisplayPosition, above, below, .displayName, left, right, ExtendedDisplayResolution (+12 more)

### Community 21 - "String"
Cohesion: 0.18
Nodes (13): AirCatchLog, Category, general, input, network, video, AirCatchLog, Category (+5 more)

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

### Community 27 - "MetalVideoView"
Cohesion: 0.33
Nodes (3): MetalVideoView, Context, UIViewRepresentable

### Community 28 - ".sendControl"
Cohesion: 0.15
Nodes (6): Double, Int32, PacketType, TouchEventType, ConnectionMode, HandshakeRequest

### Community 29 - "CryptoManager"
Cohesion: 0.23
Nodes (8): CryptoManager, .isReady, Bool, Data, Int, String, SymmetricKey, UInt32

### Community 30 - "Codable"
Cohesion: 0.20
Nodes (18): AirCatchConfig, KeyEvent, KeyModifiers, MediaKeyEvent, PingPacket, PongPacket, QualityReport, ScrollEvent (+10 more)

### Community 31 - "Network"
Cohesion: 0.48
Nodes (5): DiscoveredHost, DiscoveredHost, Equatable, Identifiable, Network

### Community 32 - "AudioPlayer"
Cohesion: 0.20
Nodes (6): AudioPlayer, Data, Double, Int, UInt32, AVAudioFormat

### Community 33 - "BitrateCalculator"
Cohesion: 0.48
Nodes (4): BitrateCalculator, Double, Int, String

### Community 34 - "VideoDecoderError"
Cohesion: 0.33
Nodes (6): OSStatus, VideoDecoderError, decodeFailed, formatDescriptionCreationFailed, sessionCreationFailed, Error

### Community 35 - "ExtendedDisplayPosition"
Cohesion: 0.18
Nodes (13): ExtendedDisplayConfig, ExtendedDisplayPosition, above, below, .displayName, left, right, StreamDisplayMode (+5 more)

### Community 36 - ".handleTCPPacket"
Cohesion: 0.14
Nodes (17): AtomicInt, ChunkSlice, error, FrameAssembly, Data, Int, Packet, Set (+9 more)

### Community 37 - "SidebarItem"
Cohesion: 0.40
Nodes (5): SidebarItem, about, devices, settings, Hashable

### Community 38 - "ExtendedDisplayResolution"
Cohesion: 0.33
Nodes (6): ExtendedDisplayResolution, .displayName, matched, native, retina, standard

### Community 40 - "ClientManager"
Cohesion: 0.13
Nodes (9): ClientManager, .connectionOption, .optimizeForHostDisplay, .savedSessionToken, Float, TimeInterval, Timer, HandshakeAck (+1 more)

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

### Community 47 - "ConnectionState"
Cohesion: 0.25
Nodes (8): ConnectionState, connected, connecting, disconnected, discovering, .displayDescription, .isConnected, streaming

### Community 49 - "ConnectionOption"
Cohesion: 0.33
Nodes (6): ConnectionOption, .displayName, .id, .includePeerToPeer, udpNetworkFramework, udpPeerToPeerAWDL

## Knowledge Gaps
- **203 isolated node(s):** `id`, `targets`, `AVFoundation`, `disconnected`, `discovering` (+198 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 334 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **4 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ClientManager` connect `ClientManager` to `AudioPlayer`, `HostManager`, `.handleTCPPacket`, `VideoStreamViewModel`, `MouseHandlingView`, `View`, `BonjourBrowser`, `ConnectionState`, `.setStreamingStateIfNeeded`, `String`, `ConnectionOption`, `NetworkHealthMonitor`, `Bool`, `.sendControl`?**
  _High betweenness centrality (0.327) - this node is a cross-community bridge._
- **Why does `Foundation` connect `Foundation` to `.handleTCPPacket`, `ScreenStreamer`, `AirCatchClient/CryptoManager.swift`, `VirtualDisplayManager`, `BonjourBrowser`, `VideoDecoder.swift`, `AirCatchClient/SharedModels.swift`, `AirCatchHost/SharedModels.swift`?**
  _High betweenness centrality (0.167) - this node is a cross-community bridge._
- **Why does `HostManager` connect `HostManager` to `ScreenStreamer`, `HostView`, `Foundation`, `NetworkHealthMonitor`, `MPCAirCatchHost`, `BonjourAdvertiser`, `CryptoManager`?**
  _High betweenness centrality (0.144) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `ClientManager` (e.g. with `BonjourBrowser` and `.body`) actually correct?**
  _`ClientManager` has 3 INFERRED edges - model-reasoned connections that need verification._
- **Are the 4 inferred relationships involving `HostManager` (e.g. with `BonjourAdvertiser` and `CryptoManager`) actually correct?**
  _`HostManager` has 4 INFERRED edges - model-reasoned connections that need verification._
- **What connects `id`, `targets`, `AVFoundation` to the rest of the system?**
  _203 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `HostManager` be split into smaller, more focused modules?**
  _Cohesion score 0.07689873417721518 - nodes in this community are weakly interconnected._