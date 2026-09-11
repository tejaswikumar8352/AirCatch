# Graph Report - AirCatch  (2026-09-10)

## Corpus Check
- 45 files · ~64,898 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1271 nodes · 2756 edges · 67 communities (44 shown, 23 thin omitted)
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 86 edges (avg confidence: 0.81)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `626b75af`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- HostManager
- NetworkManager
- Foundation
- WebRTCHostSession
- ScreenStreamer
- server.js
- RelayClient
- VirtualDisplayManager
- MouseHandlingView
- HostView
- MetalVideoRenderer
- RelayClient
- WebRTCClientSession
- BonjourAdvertiser
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
- CGPoint
- PacketType
- .handleRelayPacket
- .handleRelayMediaPacket
- DisplayManager
- CryptoManager
- UInt16
- ScreenStreamer.swift
- AudioPlayer
- CryptoManager
- Codable
- ExtendedDisplayPosition
- UDPStreamProcessor
- AppKit
- Network
- .handleTCPPacket
- Int
- CFTimeInterval
- iPadDisplayPreset
- BonjourBrowser
- TouchEventType
- TouchEventType
- Float
- ClientManager.swift
- .setStreamingStateIfNeeded
- Bool
- manifest.json
- launch_retry.sh
- deploy.sh
- deploy_domain_tls.sh
- Int32
- KeyModifiers
- RTCVideoTrack
- Timer
- TouchEventType
- UInt16
- CGSize
- CMTime
- CVPixelBuffer
- CGDirectDisplayID
- NWConnection
- NWEndpoint
- ObjectIdentifier

## God Nodes (most connected - your core abstractions)
1. `HostManager` - 84 edges
2. `ClientManager` - 79 edges
3. `NetworkManager` - 53 edges
4. `WebRTCHostSession` - 39 edges
5. `RelayClient` - 38 edges
6. `ScreenStreamer` - 37 edges
7. `RelayClient` - 31 edges
8. `MetalVideoRenderer` - 28 edges
9. `VirtualDisplayManager` - 27 edges
10. `WebRTCClientSession` - 26 edges

## Surprising Connections (you probably didn't know these)
- `.localModeSection` --references--> `HostManager`  [INFERRED]
  AirCatchHost/HostView.swift → AirCatchHost/HostManager.swift
- `DiscoveredHost` --references--> `Network`  [EXTRACTED]
  AirCatchClient/SharedModels.swift → AirCatchHost/RelayClient.swift
- `ClientManager` --calls--> `BonjourBrowser`  [INFERRED]
  AirCatchClient/ClientManager.swift → AirCatchClient/BonjourBrowser.swift
- `.body` --calls--> `ContentView`  [INFERRED]
  AirCatchClient/AirCatchClientApp.swift → AirCatchClient/ContentView.swift
- `ContentView` --calls--> `RelayClient`  [INFERRED]
  AirCatchClient/ContentView.swift → AirCatchClient/RelayClient.swift

## Import Cycles
- None detected.

## Communities (67 total, 23 thin omitted)

### Community 0 - "HostManager"
Cohesion: 0.07
Nodes (25): CachedFrame, HostManager, .statusDescription, InputStateCache, Bool, CGRect, Data, Double (+17 more)

### Community 1 - "NetworkManager"
Cohesion: 0.09
Nodes (22): NetworkManager, Bool, Data, MainActor, NWConnection, NWEndpoint, Packet, PacketType (+14 more)

### Community 2 - "Foundation"
Cohesion: 0.21
Nodes (7): Combine, CommonCrypto, CryptoKit, Foundation, MultipeerConnectivity, Security, WebRTC

### Community 3 - "WebRTCHostSession"
Cohesion: 0.07
Nodes (29): ExternalVideoCapturer, Bool, CMTime, CVPixelBuffer, Data, Double, Int, Int64 (+21 more)

### Community 4 - "ScreenStreamer"
Cohesion: 0.09
Nodes (26): ScreenStreamer, StreamerError, compressionSessionCreationFailed, noDisplayFound, StreamOutput, Bool, CGDirectDisplayID, CMTime (+18 more)

### Community 5 - "server.js"
Cohesion: 0.05
Nodes (31): ws, dependencies, ws, description, engines, node, main, name (+23 more)

### Community 6 - "RelayClient"
Cohesion: 0.12
Nodes (19): RelayClient, .backpressureDuration, .isConnected, .isConnectedThreadSafe, Bool, Data, Error, PacketType (+11 more)

### Community 7 - "VirtualDisplayManager"
Cohesion: 0.11
Nodes (26): CGVirtualDisplay, CGVirtualDisplayDescriptor, CGVirtualDisplayMode, CGVirtualDisplaySettings, AnyObject, Bool, CGDirectDisplayID, CGPoint (+18 more)

### Community 8 - "MouseHandlingView"
Cohesion: 0.11
Nodes (20): MouseHandlingView, MouseInputView, Bool, CFTimeInterval, CGPoint, CGRect, Context, Int (+12 more)

### Community 9 - "HostView"
Cohesion: 0.05
Nodes (52): AirCatchClientApp, .body, Scene, AboutScreen, .body, ContentView, DevicesBackground, .body (+44 more)

### Community 10 - "MetalVideoRenderer"
Cohesion: 0.05
Nodes (41): MetalVideoRenderer, MetalVideoView, CGSize, Context, CVPixelBuffer, Float, Int, ObjectIdentifier (+33 more)

### Community 11 - "RelayClient"
Cohesion: 0.15
Nodes (16): RelayClient, Bool, Data, Error, PacketType, SecTrust, Set, String (+8 more)

### Community 12 - "WebRTCClientSession"
Cohesion: 0.10
Nodes (22): Bool, Data, RTCDataBuffer, RTCDataChannel, RTCIceCandidate, RTCIceConnectionState, RTCIceGatheringState, RTCIceServer (+14 more)

### Community 13 - "BonjourAdvertiser"
Cohesion: 0.39
Nodes (5): BonjourAdvertiser, NWListener, String, UInt16, NWTXTRecord

### Community 14 - "AirCatchClient/SharedModels.swift"
Cohesion: 0.10
Nodes (30): AuthChallenge, AuthResponse, CodecPreference, auto, h264, hevc, ConnectionMode, localNetwork (+22 more)

### Community 15 - "InputInjector"
Cohesion: 0.14
Nodes (13): InputInjector, .hasAccessibilityPermission, Bool, CGPoint, CGRect, Double, Int32, Int64 (+5 more)

### Community 16 - "ClientManager"
Cohesion: 0.11
Nodes (15): ClientManager, .savedSessionToken, DiscoveredHost, Double, String, CFTimeInterval, ConnectionMode, Float (+7 more)

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
Cohesion: 0.18
Nodes (13): ExtendedDisplayConfig, ExtendedDisplayPosition, above, below, .displayName, left, right, StreamDisplayMode (+5 more)

### Community 21 - "String"
Cohesion: 0.11
Nodes (16): AirCatchConfig, AirCatchLog, Category, general, input, network, video, WebRTCIceServerConfig (+8 more)

### Community 22 - "VideoDecoder"
Cohesion: 0.11
Nodes (19): Bool, CMTime, CVPixelBuffer, Data, Int, OSStatus, UInt8, VideoDecoder (+11 more)

### Community 23 - "AirCatchHost/SharedModels.swift"
Cohesion: 0.11
Nodes (29): AirCatchConfig, AuthChallenge, AuthResponse, CodecPreference, auto, h264, hevc, ConnectionMode (+21 more)

### Community 25 - "PacketType"
Cohesion: 0.05
Nodes (39): PacketType, audioPCM, authChallenge, authResponse, disconnect, handshake, handshakeAck, keyEvent (+31 more)

### Community 26 - ".handleRelayPacket"
Cohesion: 0.21
Nodes (3): .audioEnabled, RelayClient, .body

### Community 27 - ".handleRelayMediaPacket"
Cohesion: 0.20
Nodes (6): error, Packet, PacketType, RTCPeerConnectionState, WebRTCSignalMessage, WebRTCClientSession

### Community 28 - "DisplayManager"
Cohesion: 0.32
Nodes (4): DisplayManager, Double, Int, CGDisplayMode

### Community 29 - "CryptoManager"
Cohesion: 0.23
Nodes (8): CryptoManager, .isReady, Bool, Data, Int, String, SymmetricKey, UInt32

### Community 30 - "UInt16"
Cohesion: 0.25
Nodes (8): MediaKeyEvent, Int32, UInt16, WebRTCSignalMessage, WebRTCSignalType, answer, candidate, offer

### Community 31 - "ScreenStreamer.swift"
Cohesion: 0.33
Nodes (5): Accelerate, AVFoundation, CoreMedia, IOSurface, ScreenCaptureKit

### Community 32 - "AudioPlayer"
Cohesion: 0.22
Nodes (6): AudioPlayer, Data, Double, Int, UInt32, AVAudioFormat

### Community 33 - "CryptoManager"
Cohesion: 0.24
Nodes (8): CryptoManager, .isReady, Bool, Data, Int, String, SymmetricKey, UInt32

### Community 34 - "Codable"
Cohesion: 0.13
Nodes (25): KeyEvent, KeyModifiers, MediaKeyEvent, PingPacket, PongPacket, QualityReport, ScrollEvent, Double (+17 more)

### Community 35 - "ExtendedDisplayPosition"
Cohesion: 0.09
Nodes (26): ExtendedDisplayResolution, .displayName, matched, native, retina, standard, ExtendedDisplayConfig, ExtendedDisplayPosition (+18 more)

### Community 36 - "UDPStreamProcessor"
Cohesion: 0.31
Nodes (11): ChunkSlice, FrameAssembly, Set, TimeInterval, UInt32, Void, UDPStreamProcessor, VideoReassembler (+3 more)

### Community 37 - "AppKit"
Cohesion: 0.40
Nodes (3): AppKit, CoreGraphics, IOKit.hidsystem

### Community 38 - "Network"
Cohesion: 0.36
Nodes (5): DiscoveredHost, DiscoveredHost, Equatable, Identifiable, Network

### Community 42 - "iPadDisplayPreset"
Cohesion: 0.17
Nodes (11): iPadDisplayPreset, .aspectRatio, .displayName, generic, iPadAir109, iPadMini6, iPadPro11, iPadPro129 (+3 more)

### Community 43 - "BonjourBrowser"
Cohesion: 0.25
Nodes (7): BonjourBrowser, DiscoveredHost, MainActor, String, UInt16, Void, NWBrowser

### Community 44 - "TouchEventType"
Cohesion: 0.20
Nodes (10): TouchEventType, began, cancelled, doubleClick, dragBegan, dragEnded, dragMoved, ended (+2 more)

### Community 45 - "TouchEventType"
Cohesion: 0.20
Nodes (10): TouchEventType, began, cancelled, doubleClick, dragBegan, dragEnded, dragMoved, ended (+2 more)

### Community 47 - "ClientManager.swift"
Cohesion: 0.18
Nodes (10): ConnectionState, connected, connecting, disconnected, discovering, .displayDescription, .isConnected, streaming (+2 more)

### Community 49 - "Bool"
Cohesion: 0.21
Nodes (9): AtomicBool, .isRelaySessionActive, ConnectionOption, .displayName, .id, .includePeerToPeer, udpNetworkFramework, udpPeerToPeerAWDL (+1 more)

## Knowledge Gaps
- **214 isolated node(s):** `id`, `targets`, `AVFoundation`, `disconnected`, `discovering` (+209 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 410 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **23 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Foundation` connect `Foundation` to `WebRTCHostSession`, `AppKit`, `Network`, `VirtualDisplayManager`, `BonjourBrowser`, `AirCatchClient/SharedModels.swift`, `ClientManager.swift`, `NetworkHealthMonitor`, `VideoDecoder`, `AirCatchHost/SharedModels.swift`, `ScreenStreamer.swift`?**
  _High betweenness centrality (0.294) - this node is a cross-community bridge._
- **Why does `ClientManager` connect `ClientManager` to `AudioPlayer`, `UDPStreamProcessor`, `.handleTCPPacket`, `Int`, `HostView`, `MouseHandlingView`, `BonjourBrowser`, `MetalVideoRenderer`, `ClientManager.swift`, `.setStreamingStateIfNeeded`, `Bool`, `NetworkHealthMonitor`, `.handleRelayPacket`, `.handleRelayMediaPacket`?**
  _High betweenness centrality (0.200) - this node is a cross-community bridge._
- **Why does `HostManager` connect `HostManager` to `Foundation`, `HostView`, `BonjourAdvertiser`, `NetworkHealthMonitor`, `MPCAirCatchHost`, `CryptoManager`?**
  _High betweenness centrality (0.153) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `HostManager` (e.g. with `BonjourAdvertiser` and `CryptoManager`) actually correct?**
  _`HostManager` has 4 INFERRED edges - model-reasoned connections that need verification._
- **What connects `id`, `targets`, `AVFoundation` to the rest of the system?**
  _214 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `HostManager` be split into smaller, more focused modules?**
  _Cohesion score 0.07046442461679249 - nodes in this community are weakly interconnected._
- **Should `NetworkManager` be split into smaller, more focused modules?**
  _Cohesion score 0.08961748633879782 - nodes in this community are weakly interconnected._