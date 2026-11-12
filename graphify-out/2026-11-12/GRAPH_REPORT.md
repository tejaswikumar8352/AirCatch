# Graph Report - AirCatch  (2026-11-12)

## Corpus Check
- 40 files · ~60,221 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1110 nodes · 2442 edges · 67 communities (48 shown, 18 thin omitted)
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 114 edges (avg confidence: 0.82)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `9cc9c5b8`
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
- AudioPlayer
- MetalVideoRenderer
- Foundation
- iPadDisplayPreset
- Bool
- .makeUDPStreamProcessor
- InputInjector
- String
- MPCAirCatchClient
- NetworkHealthMonitor
- MPCAirCatchHost
- ExtendedDisplayPosition
- String
- VideoDecoder
- iPadDisplayPreset
- VideoStreamViewModel
- PacketType
- .disconnect
- .handleTCPPacket
- TimeInterval
- CryptoManager
- Codable
- ConnectionOption
- CryptoManager
- VideoDecoder.swift
- HostView
- AirCatchClientApp
- UDPStreamProcessor
- ManualConnectOverlay
- MetalVideoView
- SettingsView
- ClientManager
- ContentView.swift
- View
- TouchEventType
- TouchEventType
- .body
- ConnectionState
- AtomicUInt64
- SidebarItem
- manifest.json
- launch_retry.sh
- Date
- DiscoveredHost
- Float
- Timer
- Context
- MainActor
- OSStatus
- Scene
- Date
- MCPeerID
- HostCard
- ObjectIdentifier
- Color
- NWListener
- DispatchQueue

## God Nodes (most connected - your core abstractions)
1. `ClientManager` - 97 edges
2. `HostManager` - 78 edges
3. `NetworkManager` - 56 edges
4. `ScreenStreamer` - 38 edges
5. `MouseHandlingView` - 33 edges
6. `MetalVideoRenderer` - 28 edges
7. `VirtualDisplayManager` - 27 edges
8. `PacketType` - 22 edges
9. `VideoStreamViewModel` - 22 edges
10. `PacketType` - 22 edges

## Surprising Connections (you probably didn't know these)
- `.body` --calls--> `HostView`  [INFERRED]
  AirCatchHost/AirCatchHostApp.swift → AirCatchHost/HostView.swift
- `.pinDisplay` --references--> `HostManager`  [INFERRED]
  AirCatchHost/HostView.swift → AirCatchHost/HostManager.swift
- `.body` --calls--> `ContentView`  [INFERRED]
  AirCatchClient/AirCatchClientApp.swift → AirCatchClient/ContentView.swift
- `DiscoveredHost` --references--> `Network`  [EXTRACTED]
  AirCatchClient/SharedModels.swift → AirCatchHost/SharedModels.swift
- `ClientManager` --calls--> `BonjourBrowser`  [INFERRED]
  AirCatchClient/ClientManager.swift → AirCatchClient/BonjourBrowser.swift

## Import Cycles
- None detected.

## Communities (67 total, 18 thin omitted)

### Community 0 - "HostManager"
Cohesion: 0.06
Nodes (28): DisplayManager, Double, Int, CachedFrame, HostManager, .effectiveDefaultFrameRate, .preferredFrameRate, .statusDescription (+20 more)

### Community 1 - "NetworkManager"
Cohesion: 0.08
Nodes (23): NetworkManager, Bool, Data, NWConnection, NWEndpoint, Packet, PacketType, String (+15 more)

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
Cohesion: 0.16
Nodes (19): AuthChallenge, AuthResponse, CodecPreference, auto, h264, hevc, ConnectionMode, localNetwork (+11 more)

### Community 7 - "VirtualDisplayManager"
Cohesion: 0.09
Nodes (28): HostAppDelegate, CGVirtualDisplay, CGVirtualDisplayDescriptor, CGVirtualDisplayMode, CGVirtualDisplaySettings, AnyObject, Bool, CGDirectDisplayID (+20 more)

### Community 8 - "MouseHandlingView"
Cohesion: 0.08
Nodes (26): MouseHandlingView, .canBecomeFirstResponder, MouseInputView, Bool, CGPoint, CGRect, Int, Set (+18 more)

### Community 9 - "AudioPlayer"
Cohesion: 0.22
Nodes (6): AudioPlayer, Data, Double, Int, UInt32, AVAudioFormat

### Community 10 - "MetalVideoRenderer"
Cohesion: 0.12
Nodes (17): MetalVideoRenderer, CGSize, CVPixelBuffer, Float, Int, ObjectIdentifier, CVMetalTextureCache, MTKView (+9 more)

### Community 11 - "Foundation"
Cohesion: 0.07
Nodes (23): Accelerate, BonjourBrowser, DiscoveredHost, MainActor, String, UInt16, Void, BonjourAdvertiser (+15 more)

### Community 12 - "iPadDisplayPreset"
Cohesion: 0.18
Nodes (11): iPadDisplayPreset, .aspectRatio, .displayName, generic, iPadAir109, iPadMini6, iPadPro11, iPadPro129 (+3 more)

### Community 13 - "Bool"
Cohesion: 0.48
Nodes (3): AtomicBool, .audioEnabled, Bool

### Community 14 - ".makeUDPStreamProcessor"
Cohesion: 0.33
Nodes (3): UncheckedSendable, VideoChunkNackRequest, T

### Community 15 - "InputInjector"
Cohesion: 0.14
Nodes (13): InputInjector, .hasAccessibilityPermission, Bool, CGPoint, CGRect, Double, Int32, KeyModifiers (+5 more)

### Community 16 - "String"
Cohesion: 0.19
Nodes (5): SavedHost, NWEndpoint, String, Date, DiscoveredHost

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
Cohesion: 0.09
Nodes (26): ExtendedDisplayConfig, ExtendedDisplayPosition, above, below, .displayName, left, right, ExtendedDisplayResolution (+18 more)

### Community 21 - "String"
Cohesion: 0.14
Nodes (16): AirCatchLog, Category, general, input, network, video, DiscoveredHost, AirCatchLog (+8 more)

### Community 22 - "VideoDecoder"
Cohesion: 0.14
Nodes (14): Bool, CMTime, CVPixelBuffer, Data, Int, UInt8, Void, VideoDecoder (+6 more)

### Community 23 - "iPadDisplayPreset"
Cohesion: 0.09
Nodes (31): AuthChallenge, AuthResponse, CodecPreference, auto, h264, hevc, ConnectionMode, localNetwork (+23 more)

### Community 24 - "VideoStreamViewModel"
Cohesion: 0.18
Nodes (13): Bool, CGPoint, CGRect, CGSize, CMTime, CVPixelBuffer, Data, Error (+5 more)

### Community 25 - "PacketType"
Cohesion: 0.05
Nodes (41): PacketType, audioPCM, authChallenge, authResponse, disconnect, handshake, handshakeAck, keyEvent (+33 more)

### Community 27 - ".handleTCPPacket"
Cohesion: 0.20
Nodes (5): error, Data, Packet, ConnectionMode, HandshakeRequest

### Community 28 - "TimeInterval"
Cohesion: 0.16
Nodes (16): AirCatchConfig, KeyEvent, KeyModifiers, MediaKeyEvent, PingPacket, PongPacket, QualityReport, ScrollEvent (+8 more)

### Community 29 - "CryptoManager"
Cohesion: 0.17
Nodes (10): CryptoManager, .isReady, Bool, Data, Int, String, SymmetricKey, UInt32 (+2 more)

### Community 30 - "Codable"
Cohesion: 0.21
Nodes (18): AirCatchConfig, KeyEvent, KeyModifiers, MediaKeyEvent, PingPacket, PongPacket, QualityReport, ScrollEvent (+10 more)

### Community 31 - "ConnectionOption"
Cohesion: 0.25
Nodes (8): ConnectionOption, automatic, .displayName, .id, .includePeerToPeer, udpNetworkFramework, udpPeerToPeerAWDL, Identifiable

### Community 32 - "CryptoManager"
Cohesion: 0.25
Nodes (8): CryptoManager, .isReady, Bool, Data, Int, String, SymmetricKey, UInt32

### Community 33 - "VideoDecoder.swift"
Cohesion: 0.18
Nodes (9): VideoDecoderError, decodeFailed, formatDescriptionCreationFailed, sessionCreationFailed, CoreVideo, Error, MetalKit, OSStatus (+1 more)

### Community 34 - "HostView"
Cohesion: 0.22
Nodes (9): HostView, .connectionStatusSection, .isStreaming, .pinDisplay, .statusColor, .statusDescription, Bool, String (+1 more)

### Community 35 - "AirCatchClientApp"
Cohesion: 0.25
Nodes (7): AirCatchClientApp, .body, Scene, AirCatchHostApp, .body, App, Scene

### Community 36 - "UDPStreamProcessor"
Cohesion: 0.22
Nodes (13): ChunkSlice, FrameAssembly, Set, TimeInterval, UInt16, UInt32, Void, UDPStreamProcessor (+5 more)

### Community 37 - "ManualConnectOverlay"
Cohesion: 0.29
Nodes (7): Field, address, pin, ManualConnectOverlay, .body, .isValidAddress, .sanitizedAddress

### Community 38 - "MetalVideoView"
Cohesion: 0.33
Nodes (3): MetalVideoView, Context, UIViewRepresentable

### Community 39 - "SettingsView"
Cohesion: 0.33
Nodes (6): .body, SettingsView, .body, .preferredFrameRateBinding, Int, Binding

### Community 40 - "ClientManager"
Cohesion: 0.10
Nodes (15): ClientManager, .connectionOption, .effectiveIncludePeerToPeer, .lastHostPacketTime, .optimizeForHostDisplay, .savedSessionToken, Double, Int32 (+7 more)

### Community 42 - "ContentView.swift"
Cohesion: 0.33
Nodes (3): ClientSettingsView, .body, SwiftUI

### Community 43 - "View"
Cohesion: 0.53
Nodes (5): AboutScreen, .body, DevicesBackground, .body, View

### Community 44 - "TouchEventType"
Cohesion: 0.20
Nodes (10): TouchEventType, began, cancelled, doubleClick, dragBegan, dragEnded, dragMoved, ended (+2 more)

### Community 45 - "TouchEventType"
Cohesion: 0.20
Nodes (10): TouchEventType, began, cancelled, doubleClick, dragBegan, dragEnded, dragMoved, ended (+2 more)

### Community 46 - ".body"
Cohesion: 0.60
Nodes (5): ContentView, .body, Sidebar, .body, String

### Community 47 - "ConnectionState"
Cohesion: 0.22
Nodes (9): ConnectionState, connected, connecting, disconnected, discovering, .displayDescription, .isConnected, streaming (+1 more)

### Community 49 - "SidebarItem"
Cohesion: 0.40
Nodes (5): SidebarItem, about, devices, settings, Hashable

### Community 62 - "HostCard"
Cohesion: 0.17
Nodes (16): DevicesScreen, .body, .header, HostCard, .body, .statusColor, .subtitle, PINEntryOverlay (+8 more)

## Knowledge Gaps
- **219 isolated node(s):** `disconnected`, `discovering`, `connecting`, `connected`, `streaming` (+214 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 367 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **18 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ClientManager` connect `ClientManager` to `HostManager`, `UDPStreamProcessor`, `MouseHandlingView`, `ContentView.swift`, `Foundation`, `Bool`, `.makeUDPStreamProcessor`, `ConnectionState`, `AtomicUInt64`, `String`, `NetworkHealthMonitor`, `.body`, `VideoStreamViewModel`, `.disconnect`, `.handleTCPPacket`, `TimeInterval`, `HostCard`, `ConnectionOption`?**
  _High betweenness centrality (0.280) - this node is a cross-community bridge._
- **Why does `Foundation` connect `Foundation` to `VideoDecoder.swift`, `UDPStreamProcessor`, `AirCatchClient/SharedModels.swift`, `VirtualDisplayManager`, `NetworkHealthMonitor`, `CryptoManager`, `Codable`?**
  _High betweenness centrality (0.174) - this node is a cross-community bridge._
- **Why does `HostManager` connect `HostManager` to `HostView`, `Foundation`, `NetworkHealthMonitor`, `MPCAirCatchHost`, `CryptoManager`?**
  _High betweenness centrality (0.169) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `ClientManager` (e.g. with `BonjourBrowser` and `.body`) actually correct?**
  _`ClientManager` has 3 INFERRED edges - model-reasoned connections that need verification._
- **Are the 4 inferred relationships involving `HostManager` (e.g. with `BonjourAdvertiser` and `CryptoManager`) actually correct?**
  _`HostManager` has 4 INFERRED edges - model-reasoned connections that need verification._
- **What connects `disconnected`, `discovering`, `connecting` to the rest of the system?**
  _219 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `HostManager` be split into smaller, more focused modules?**
  _Cohesion score 0.0642873484328529 - nodes in this community are weakly interconnected._