# Graph Report - AirCatch  (2026-11-12)

## Corpus Check
- 40 files · ~60,221 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1083 nodes · 2432 edges · 44 communities (39 shown, 4 thin omitted)
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
- iPadDisplayPreset
- AirCatchClient/SharedModels.swift
- VirtualDisplayManager
- MouseHandlingView
- AudioPlayer
- MetalVideoRenderer
- BonjourBrowser
- ExtendedDisplayResolution
- VideoDecoderError
- ClientManager.swift
- InputInjector
- ClientManager
- MPCAirCatchClient
- NetworkHealthMonitor
- MPCAirCatchHost
- ExtendedDisplayPosition
- String
- VideoDecoder
- AirCatchHost/SharedModels.swift
- AirCatchClient/CryptoManager.swift
- PacketType
- .disconnect
- .handleTCPPacket
- CryptoManager
- Codable
- ConnectionOption
- CryptoManager
- ScreenStreamer.swift
- HostView
- Foundation
- .sendControl
- TouchEventType
- TouchEventType
- AtomicUInt64
- SidebarItem
- manifest.json
- launch_retry.sh
- .body

## God Nodes (most connected - your core abstractions)
1. `ClientManager` - 97 edges
2. `HostManager` - 78 edges
3. `NetworkManager` - 56 edges
4. `ScreenStreamer` - 39 edges
5. `MouseHandlingView` - 33 edges
6. `MetalVideoRenderer` - 28 edges
7. `VirtualDisplayManager` - 27 edges
8. `PacketType` - 22 edges
9. `VideoStreamViewModel` - 22 edges
10. `MPCAirCatchHost` - 22 edges

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

## Communities (44 total, 4 thin omitted)

### Community 0 - "HostManager"
Cohesion: 0.07
Nodes (23): CachedFrame, HostManager, .effectiveDefaultFrameRate, .preferredFrameRate, .statusDescription, InputStateCache, Bool, CGDirectDisplayID (+15 more)

### Community 1 - "NetworkManager"
Cohesion: 0.08
Nodes (23): NetworkManager, Bool, Data, MainActor, NWConnection, NWEndpoint, Packet, PacketType (+15 more)

### Community 2 - "ExtendedDisplayPosition"
Cohesion: 0.18
Nodes (13): ExtendedDisplayConfig, ExtendedDisplayPosition, above, below, .displayName, left, right, StreamDisplayMode (+5 more)

### Community 3 - "AirCatch"
Cohesion: 0.10
Nodes (20): AirCatch, Code Graph (graphify), Connecting over Tailscale, Design Notes: Why This Looks Right and Reads Fast, Features, Getting Started, Given the above, what else is worth showing off?, How It Works (+12 more)

### Community 4 - "ScreenStreamer"
Cohesion: 0.09
Nodes (26): ScreenStreamer, StreamerError, compressionSessionCreationFailed, noDisplayFound, StreamOutput, Bool, CGDirectDisplayID, CMTime (+18 more)

### Community 5 - "iPadDisplayPreset"
Cohesion: 0.14
Nodes (13): iPadDisplayPreset, .aspectRatio, .displayName, generic, iPadAir109, iPadMini6, iPadPro11, iPadPro129 (+5 more)

### Community 6 - "AirCatchClient/SharedModels.swift"
Cohesion: 0.07
Nodes (46): AirCatchConfig, AuthChallenge, AuthResponse, CodecPreference, auto, h264, hevc, ConnectionMode (+38 more)

### Community 7 - "VirtualDisplayManager"
Cohesion: 0.06
Nodes (37): BonjourAdvertiser, NWListener, String, UInt16, DisplayManager, Double, Int, CGVirtualDisplay (+29 more)

### Community 8 - "MouseHandlingView"
Cohesion: 0.07
Nodes (26): MouseHandlingView, .canBecomeFirstResponder, MouseInputView, Bool, CGPoint, CGRect, Context, Int (+18 more)

### Community 9 - "AudioPlayer"
Cohesion: 0.22
Nodes (6): AudioPlayer, Data, Double, Int, UInt32, AVAudioFormat

### Community 10 - "MetalVideoRenderer"
Cohesion: 0.07
Nodes (33): MetalVideoRenderer, MetalVideoView, CGSize, Context, CVPixelBuffer, Float, Int, ObjectIdentifier (+25 more)

### Community 11 - "BonjourBrowser"
Cohesion: 0.23
Nodes (7): BonjourBrowser, DiscoveredHost, MainActor, String, UInt16, Void, NWBrowser

### Community 12 - "ExtendedDisplayResolution"
Cohesion: 0.33
Nodes (6): ExtendedDisplayResolution, .displayName, matched, native, retina, standard

### Community 13 - "VideoDecoderError"
Cohesion: 0.40
Nodes (5): VideoDecoderError, decodeFailed, formatDescriptionCreationFailed, sessionCreationFailed, Error

### Community 14 - "ClientManager.swift"
Cohesion: 0.19
Nodes (5): AtomicInt, Int, UncheckedSendable, VideoChunkNackRequest, T

### Community 15 - "InputInjector"
Cohesion: 0.14
Nodes (13): InputInjector, .hasAccessibilityPermission, Bool, CGPoint, CGRect, Double, Int32, KeyModifiers (+5 more)

### Community 16 - "ClientManager"
Cohesion: 0.09
Nodes (26): ClientManager, .connectionOption, .effectiveIncludePeerToPeer, .lastHostPacketTime, .optimizeForHostDisplay, .savedSessionToken, ConnectionState, connected (+18 more)

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
Cohesion: 0.11
Nodes (20): ExtendedDisplayConfig, ExtendedDisplayPosition, above, below, .displayName, left, right, ExtendedDisplayResolution (+12 more)

### Community 21 - "String"
Cohesion: 0.18
Nodes (13): AirCatchLog, Category, general, input, network, video, AirCatchLog, Category (+5 more)

### Community 22 - "VideoDecoder"
Cohesion: 0.13
Nodes (15): Bool, CMTime, CVPixelBuffer, Data, Int, OSStatus, UInt8, Void (+7 more)

### Community 23 - "AirCatchHost/SharedModels.swift"
Cohesion: 0.18
Nodes (19): AirCatchConfig, AuthChallenge, AuthResponse, CodecPreference, auto, h264, hevc, ConnectionMode (+11 more)

### Community 25 - "PacketType"
Cohesion: 0.05
Nodes (41): PacketType, audioPCM, authChallenge, authResponse, disconnect, handshake, handshakeAck, keyEvent (+33 more)

### Community 26 - ".disconnect"
Cohesion: 0.20
Nodes (3): AtomicBool, .audioEnabled, Bool

### Community 27 - ".handleTCPPacket"
Cohesion: 0.15
Nodes (15): ChunkSlice, error, FrameAssembly, Data, Packet, Set, UInt16, UInt32 (+7 more)

### Community 29 - "CryptoManager"
Cohesion: 0.23
Nodes (8): CryptoManager, .isReady, Bool, Data, Int, String, SymmetricKey, UInt32

### Community 30 - "Codable"
Cohesion: 0.18
Nodes (18): DiscoveredHost, KeyEvent, KeyModifiers, MediaKeyEvent, PingPacket, PongPacket, QualityReport, ScrollEvent (+10 more)

### Community 31 - "ConnectionOption"
Cohesion: 0.25
Nodes (8): ConnectionOption, automatic, .displayName, .id, .includePeerToPeer, udpNetworkFramework, udpPeerToPeerAWDL, Identifiable

### Community 32 - "CryptoManager"
Cohesion: 0.25
Nodes (8): CryptoManager, .isReady, Bool, Data, Int, String, SymmetricKey, UInt32

### Community 33 - "ScreenStreamer.swift"
Cohesion: 0.23
Nodes (7): Accelerate, AVFoundation, CoreMedia, CoreVideo, IOSurface, MetalKit, VideoToolbox

### Community 34 - "HostView"
Cohesion: 0.07
Nodes (26): AirCatchClientApp, .body, Scene, AirCatchHostApp, .body, HostAppDelegate, Scene, HostView (+18 more)

### Community 36 - "Foundation"
Cohesion: 0.21
Nodes (7): DiscoveredHost, Combine, Foundation, MultipeerConnectivity, Network, ScreenCaptureKit, Security

### Community 40 - ".sendControl"
Cohesion: 0.18
Nodes (5): Double, Int32, KeyModifiers, PacketType, TouchEventType

### Community 44 - "TouchEventType"
Cohesion: 0.20
Nodes (10): TouchEventType, began, cancelled, doubleClick, dragBegan, dragEnded, dragMoved, ended (+2 more)

### Community 45 - "TouchEventType"
Cohesion: 0.20
Nodes (10): TouchEventType, began, cancelled, doubleClick, dragBegan, dragEnded, dragMoved, ended (+2 more)

### Community 49 - "SidebarItem"
Cohesion: 0.40
Nodes (5): SidebarItem, about, devices, settings, Hashable

### Community 62 - ".body"
Cohesion: 0.11
Nodes (34): ClientSettingsView, AboutScreen, .body, ContentView, .body, DevicesBackground, .body, DevicesScreen (+26 more)

## Knowledge Gaps
- **211 isolated node(s):** `id`, `targets`, `AVFoundation`, `disconnected`, `discovering` (+206 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 343 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **4 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ClientManager` connect `ClientManager` to `HostManager`, `NetworkManager`, `AirCatchClient/SharedModels.swift`, `.sendControl`, `AudioPlayer`, `MouseHandlingView`, `BonjourBrowser`, `MetalVideoRenderer`, `ClientManager.swift`, `AtomicUInt64`, `NetworkHealthMonitor`, `.disconnect`, `.handleTCPPacket`, `.body`, `ConnectionOption`?**
  _High betweenness centrality (0.338) - this node is a cross-community bridge._
- **Why does `Foundation` connect `Foundation` to `ScreenStreamer.swift`, `AirCatchClient/SharedModels.swift`, `VirtualDisplayManager`, `BonjourBrowser`, `ClientManager.swift`, `NetworkHealthMonitor`, `AirCatchHost/SharedModels.swift`, `AirCatchClient/CryptoManager.swift`?**
  _High betweenness centrality (0.175) - this node is a cross-community bridge._
- **Why does `HostManager` connect `HostManager` to `HostView`, `ScreenStreamer`, `Foundation`, `VirtualDisplayManager`, `NetworkHealthMonitor`, `MPCAirCatchHost`, `CryptoManager`?**
  _High betweenness centrality (0.157) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `ClientManager` (e.g. with `BonjourBrowser` and `.body`) actually correct?**
  _`ClientManager` has 3 INFERRED edges - model-reasoned connections that need verification._
- **Are the 4 inferred relationships involving `HostManager` (e.g. with `BonjourAdvertiser` and `CryptoManager`) actually correct?**
  _`HostManager` has 4 INFERRED edges - model-reasoned connections that need verification._
- **What connects `id`, `targets`, `AVFoundation` to the rest of the system?**
  _211 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `HostManager` be split into smaller, more focused modules?**
  _Cohesion score 0.07359781121751026 - nodes in this community are weakly interconnected._