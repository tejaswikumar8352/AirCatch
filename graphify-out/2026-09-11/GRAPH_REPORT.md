# Graph Report - AirCatch  (2026-09-11)

## Corpus Check
- 37 files · ~55,034 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1015 nodes · 2244 edges · 39 communities (35 shown, 4 thin omitted)
- Extraction: 96% EXTRACTED · 4% INFERRED · 0% AMBIGUOUS · INFERRED: 89 edges (avg confidence: 0.82)
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
- VirtualDisplayManager
- MouseHandlingView
- .body
- MetalVideoRenderer
- AirCatchClient/SharedModels.swift
- InputInjector
- ClientManager
- MPCAirCatchClient
- NetworkHealthMonitor
- MPCAirCatchHost
- ExtendedDisplayPosition
- String
- VideoDecoder
- AirCatchHost/SharedModels.swift
- PacketType
- Bool
- .handleTCPPacket
- CryptoManager
- Codable
- AudioPlayer
- .makeUDPStreamProcessor
- ExtendedDisplayPosition
- UDPStreamProcessor
- ExtendedDisplayResolution
- Int
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
1. `ClientManager` - 78 edges
2. `HostManager` - 70 edges
3. `NetworkManager` - 53 edges
4. `ScreenStreamer` - 39 edges
5. `MouseHandlingView` - 32 edges
6. `MetalVideoRenderer` - 28 edges
7. `VirtualDisplayManager` - 27 edges
8. `VideoStreamViewModel` - 22 edges
9. `MPCAirCatchHost` - 22 edges
10. `MPCAirCatchClient` - 21 edges

## Surprising Connections (you probably didn't know these)
- `.localModeSection` --references--> `HostManager`  [INFERRED]
  AirCatchHost/HostView.swift → AirCatchHost/HostManager.swift
- `.body` --calls--> `ContentView`  [INFERRED]
  AirCatchClient/AirCatchClientApp.swift → AirCatchClient/ContentView.swift
- `DiscoveredHost` --references--> `Network`  [EXTRACTED]
  AirCatchClient/SharedModels.swift → AirCatchHost/SharedModels.swift
- `ClientManager` --calls--> `BonjourBrowser`  [INFERRED]
  AirCatchClient/ClientManager.swift → AirCatchClient/BonjourBrowser.swift
- `.body` --references--> `ClientManager`  [INFERRED]
  AirCatchClient/ContentView.swift → AirCatchClient/ClientManager.swift

## Import Cycles
- None detected.

## Communities (39 total, 4 thin omitted)

### Community 0 - "HostManager"
Cohesion: 0.07
Nodes (23): BonjourAdvertiser, NWListener, String, UInt16, CachedFrame, HostManager, .statusDescription, InputStateCache (+15 more)

### Community 1 - "NetworkManager"
Cohesion: 0.09
Nodes (22): NetworkManager, Bool, Data, MainActor, NWConnection, NWEndpoint, Packet, PacketType (+14 more)

### Community 2 - "DisplayManager"
Cohesion: 0.32
Nodes (4): DisplayManager, Double, Int, CGDisplayMode

### Community 3 - "AirCatch"
Cohesion: 0.15
Nodes (12): AirCatch, Code Graph (graphify), Connecting over Tailscale, Features, Getting Started, How It Works, License, Project Structure (+4 more)

### Community 4 - "ScreenStreamer"
Cohesion: 0.09
Nodes (26): ScreenStreamer, StreamerError, compressionSessionCreationFailed, noDisplayFound, StreamOutput, Bool, CGDirectDisplayID, CMTime (+18 more)

### Community 7 - "VirtualDisplayManager"
Cohesion: 0.05
Nodes (46): Accelerate, OSStatus, VideoDecoderError, decodeFailed, formatDescriptionCreationFailed, sessionCreationFailed, CGVirtualDisplay, CGVirtualDisplayDescriptor (+38 more)

### Community 8 - "MouseHandlingView"
Cohesion: 0.08
Nodes (26): MouseHandlingView, .canBecomeFirstResponder, MouseInputView, Bool, CGPoint, CGRect, Context, Int (+18 more)

### Community 9 - ".body"
Cohesion: 0.05
Nodes (56): AirCatchClientApp, .body, Scene, AboutScreen, .body, ContentView, .body, DevicesBackground (+48 more)

### Community 10 - "MetalVideoRenderer"
Cohesion: 0.07
Nodes (33): MetalVideoRenderer, MetalVideoView, CGSize, Context, CVPixelBuffer, Float, Int, ObjectIdentifier (+25 more)

### Community 14 - "AirCatchClient/SharedModels.swift"
Cohesion: 0.07
Nodes (45): AirCatchConfig, AuthChallenge, AuthResponse, CodecPreference, auto, h264, hevc, ConnectionMode (+37 more)

### Community 15 - "InputInjector"
Cohesion: 0.14
Nodes (13): InputInjector, .hasAccessibilityPermission, Bool, CGPoint, CGRect, Double, Int32, KeyModifiers (+5 more)

### Community 16 - "ClientManager"
Cohesion: 0.13
Nodes (13): ClientManager, .savedSessionToken, SavedHost, Date, DiscoveredHost, Double, Float, String (+5 more)

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
Cohesion: 0.14
Nodes (17): AirCatchLog, Category, general, input, network, video, DiscoveredHost, AirCatchLog (+9 more)

### Community 22 - "VideoDecoder"
Cohesion: 0.14
Nodes (13): Bool, CMTime, CVPixelBuffer, Data, Int, UInt8, VideoDecoder, VideoDecoderDelegate (+5 more)

### Community 23 - "AirCatchHost/SharedModels.swift"
Cohesion: 0.17
Nodes (18): AuthChallenge, AuthResponse, CodecPreference, auto, h264, hevc, ConnectionMode, localNetwork (+10 more)

### Community 25 - "PacketType"
Cohesion: 0.05
Nodes (37): PacketType, audioPCM, authChallenge, authResponse, disconnect, handshake, handshakeAck, keyEvent (+29 more)

### Community 26 - "Bool"
Cohesion: 0.20
Nodes (4): AtomicBool, .audioEnabled, Bool, KeyModifiers

### Community 28 - ".handleTCPPacket"
Cohesion: 0.17
Nodes (7): Data, Int32, Packet, PacketType, PongPacket, ConnectionMode, HandshakeRequest

### Community 29 - "CryptoManager"
Cohesion: 0.10
Nodes (18): CryptoManager, .isReady, Bool, Data, Int, String, SymmetricKey, UInt32 (+10 more)

### Community 30 - "Codable"
Cohesion: 0.20
Nodes (18): AirCatchConfig, KeyEvent, KeyModifiers, MediaKeyEvent, PingPacket, PongPacket, QualityReport, ScrollEvent (+10 more)

### Community 32 - "AudioPlayer"
Cohesion: 0.22
Nodes (6): AudioPlayer, Data, Double, Int, UInt32, AVAudioFormat

### Community 34 - ".makeUDPStreamProcessor"
Cohesion: 0.33
Nodes (3): UncheckedSendable, VideoChunkNackRequest, T

### Community 35 - "ExtendedDisplayPosition"
Cohesion: 0.18
Nodes (13): ExtendedDisplayConfig, ExtendedDisplayPosition, above, below, .displayName, left, right, StreamDisplayMode (+5 more)

### Community 36 - "UDPStreamProcessor"
Cohesion: 0.25
Nodes (11): ChunkSlice, error, FrameAssembly, Set, UInt16, UInt32, Void, UDPStreamProcessor (+3 more)

### Community 38 - "ExtendedDisplayResolution"
Cohesion: 0.33
Nodes (6): ExtendedDisplayResolution, .displayName, matched, native, retina, standard

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
- **189 isolated node(s):** `id`, `targets`, `AVFoundation`, `disconnected`, `discovering` (+184 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 318 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **4 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ClientManager` connect `ClientManager` to `AudioPlayer`, `NetworkManager`, `.makeUDPStreamProcessor`, `UDPStreamProcessor`, `Int`, `MouseHandlingView`, `.body`, `BonjourBrowser`, `MetalVideoRenderer`, `AirCatchClient/SharedModels.swift`, `ConnectionState`, `.setStreamingStateIfNeeded`, `ConnectionOption`, `NetworkHealthMonitor`, `Bool`, `.handleTCPPacket`?**
  _High betweenness centrality (0.266) - this node is a cross-community bridge._
- **Why does `Foundation` connect `VirtualDisplayManager` to `UDPStreamProcessor`, `BonjourBrowser`, `AirCatchClient/SharedModels.swift`, `NetworkHealthMonitor`, `AirCatchHost/SharedModels.swift`, `CryptoManager`?**
  _High betweenness centrality (0.214) - this node is a cross-community bridge._
- **Why does `HostManager` connect `HostManager` to `ScreenStreamer`, `VirtualDisplayManager`, `.body`, `NetworkHealthMonitor`, `MPCAirCatchHost`, `CryptoManager`?**
  _High betweenness centrality (0.213) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `ClientManager` (e.g. with `BonjourBrowser` and `.body`) actually correct?**
  _`ClientManager` has 3 INFERRED edges - model-reasoned connections that need verification._
- **Are the 4 inferred relationships involving `HostManager` (e.g. with `BonjourAdvertiser` and `CryptoManager`) actually correct?**
  _`HostManager` has 4 INFERRED edges - model-reasoned connections that need verification._
- **What connects `id`, `targets`, `AVFoundation` to the rest of the system?**
  _189 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `HostManager` be split into smaller, more focused modules?**
  _Cohesion score 0.075 - nodes in this community are weakly interconnected._