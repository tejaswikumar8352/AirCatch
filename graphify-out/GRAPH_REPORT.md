# Graph Report - AirCatch  (2026-09-10)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 1250 nodes · 2778 edges · 54 communities (48 shown, 6 thin omitted)
- Extraction: 96% EXTRACTED · 4% INFERRED · 0% AMBIGUOUS · INFERRED: 108 edges (avg confidence: 0.82)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `44cbe9d3`
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
- ContentView
- MetalVideoRenderer
- RelayClient
- WebRTCClientSession
- AirCatchHost/SharedModels.swift
- AirCatchClient/SharedModels.swift
- InputInjector
- ClientManager
- MPCAirCatchClient
- NetworkHealthMonitor
- MPCAirCatchHost
- ExtendedDisplayPosition
- String
- VideoDecoder
- Int
- VideoStreamViewModel
- PacketType
- Bool
- .handleRelayPacket
- PacketType
- CryptoManager
- Codable
- SwiftUI
- AudioPlayer
- CryptoManager
- TimeInterval
- ExtendedDisplayPosition
- UDPStreamProcessor
- VideoDecoder.swift
- KeyEvent
- .handleTCPPacket
- Int
- HostView
- iPadDisplayPreset
- BonjourBrowser
- TouchEventType
- TouchEventType
- WebRTCVideoView
- ConnectionState
- .setStreamingStateIfNeeded
- ConnectionOption
- manifest.json
- launch_retry.sh
- deploy.sh
- deploy_domain_tls.sh

## God Nodes (most connected - your core abstractions)
1. `HostManager` - 84 edges
2. `ClientManager` - 79 edges
3. `NetworkManager` - 53 edges
4. `WebRTCHostSession` - 41 edges
5. `ScreenStreamer` - 39 edges
6. `RelayClient` - 38 edges
7. `RelayClient` - 31 edges
8. `MetalVideoRenderer` - 28 edges
9. `WebRTCClientSession` - 28 edges
10. `VirtualDisplayManager` - 27 edges

## Surprising Connections (you probably didn't know these)
- `.localModeSection` --references--> `HostManager`  [INFERRED]
  AirCatchHost/HostView.swift → AirCatchHost/HostManager.swift
- `DiscoveredHost` --references--> `Network`  [EXTRACTED]
  AirCatchClient/SharedModels.swift → AirCatchHost/BonjourAdvertiser.swift
- `.body` --calls--> `HostView`  [INFERRED]
  AirCatchHost/AirCatchHostApp.swift → AirCatchHost/HostView.swift
- `.body` --calls--> `ContentView`  [INFERRED]
  AirCatchClient/AirCatchClientApp.swift → AirCatchClient/ContentView.swift
- `HostManager` --calls--> `BonjourAdvertiser`  [INFERRED]
  AirCatchHost/HostManager.swift → AirCatchHost/BonjourAdvertiser.swift

## Import Cycles
- None detected.

## Communities (54 total, 6 thin omitted)

### Community 0 - "HostManager"
Cohesion: 0.08
Nodes (21): CachedFrame, HostManager, .statusDescription, InputStateCache, Bool, CGDirectDisplayID, CGRect, Data (+13 more)

### Community 1 - "NetworkManager"
Cohesion: 0.08
Nodes (23): NetworkManager, Bool, Data, MainActor, NWConnection, NWEndpoint, Packet, PacketType (+15 more)

### Community 2 - "Foundation"
Cohesion: 0.07
Nodes (25): Accelerate, BonjourAdvertiser, NWListener, String, UInt16, DisplayManager, Double, Int (+17 more)

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
Nodes (20): RelayClient, .backpressureDuration, .isConnected, .isConnectedThreadSafe, Bool, Data, Error, PacketType (+12 more)

### Community 7 - "VirtualDisplayManager"
Cohesion: 0.11
Nodes (25): CGVirtualDisplay, CGVirtualDisplayDescriptor, CGVirtualDisplayMode, CGVirtualDisplaySettings, AnyObject, Bool, CGDirectDisplayID, CGPoint (+17 more)

### Community 8 - "MouseHandlingView"
Cohesion: 0.10
Nodes (21): MouseHandlingView, MouseInputView, Bool, CFTimeInterval, CGPoint, CGRect, Context, Int (+13 more)

### Community 9 - "ContentView"
Cohesion: 0.11
Nodes (32): AboutScreen, .body, ContentView, .body, DevicesBackground, .body, DevicesScreen, .body (+24 more)

### Community 10 - "MetalVideoRenderer"
Cohesion: 0.10
Nodes (20): MetalVideoRenderer, MetalVideoView, CGSize, Context, CVPixelBuffer, Float, Int, ObjectIdentifier (+12 more)

### Community 11 - "RelayClient"
Cohesion: 0.15
Nodes (15): RelayClient, Bool, Data, Error, PacketType, SecTrust, Set, String (+7 more)

### Community 12 - "WebRTCClientSession"
Cohesion: 0.10
Nodes (22): Bool, Data, RTCDataBuffer, RTCDataChannel, RTCIceCandidate, RTCIceConnectionState, RTCIceGatheringState, RTCIceServer (+14 more)

### Community 13 - "AirCatchHost/SharedModels.swift"
Cohesion: 0.14
Nodes (20): AirCatchConfig, DiscoveredHost, KeyEvent, KeyModifiers, MediaKeyEvent, PingPacket, PongPacket, QualityReport (+12 more)

### Community 14 - "AirCatchClient/SharedModels.swift"
Cohesion: 0.10
Nodes (26): AuthChallenge, AuthResponse, CodecPreference, auto, h264, hevc, ConnectionMode, localNetwork (+18 more)

### Community 15 - "InputInjector"
Cohesion: 0.14
Nodes (13): InputInjector, .hasAccessibilityPermission, Bool, CGPoint, CGRect, Double, Int32, Int64 (+5 more)

### Community 16 - "ClientManager"
Cohesion: 0.13
Nodes (13): ClientManager, .savedSessionToken, CFTimeInterval, DiscoveredHost, Double, Float, Int32, KeyModifiers (+5 more)

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
Nodes (15): AirCatchConfig, AirCatchLog, Category, general, input, network, video, WebRTCIceServerConfig (+7 more)

### Community 22 - "VideoDecoder"
Cohesion: 0.15
Nodes (12): Bool, CMTime, CVPixelBuffer, Data, Int, OSStatus, UInt8, VideoDecoder (+4 more)

### Community 23 - "Int"
Cohesion: 0.15
Nodes (18): AuthChallenge, AuthResponse, CodecPreference, auto, h264, hevc, ConnectionMode, localNetwork (+10 more)

### Community 24 - "VideoStreamViewModel"
Cohesion: 0.17
Nodes (13): Bool, CGPoint, CGRect, CGSize, CMTime, CVPixelBuffer, Data, Error (+5 more)

### Community 25 - "PacketType"
Cohesion: 0.10
Nodes (20): PacketType, audioPCM, authChallenge, authResponse, disconnect, handshake, handshakeAck, keyEvent (+12 more)

### Community 26 - "Bool"
Cohesion: 0.16
Nodes (6): AtomicBool, .audioEnabled, .isRelaySessionActive, Bool, RelayClient, RTCPeerConnectionState

### Community 27 - ".handleRelayPacket"
Cohesion: 0.18
Nodes (7): error, Packet, PacketType, WebRTCSignalMessage, UncheckedSendable, VideoChunkNackRequest, T

### Community 28 - "PacketType"
Cohesion: 0.11
Nodes (19): PacketType, audioPCM, authChallenge, authResponse, disconnect, handshake, handshakeAck, keyEvent (+11 more)

### Community 29 - "CryptoManager"
Cohesion: 0.23
Nodes (8): CryptoManager, .isReady, Bool, Data, Int, String, SymmetricKey, UInt32

### Community 30 - "Codable"
Cohesion: 0.18
Nodes (13): MediaKeyEvent, Int32, WebRTCSignalMessage, WebRTCSignalType, answer, candidate, offer, WebRTCSignalMessage (+5 more)

### Community 31 - "SwiftUI"
Cohesion: 0.14
Nodes (11): AirCatchClientApp, .body, Scene, AirCatchHostApp, .body, HostAppDelegate, Scene, App (+3 more)

### Community 32 - "AudioPlayer"
Cohesion: 0.22
Nodes (6): AudioPlayer, Data, Double, Int, UInt32, AVAudioFormat

### Community 33 - "CryptoManager"
Cohesion: 0.24
Nodes (8): CryptoManager, .isReady, Bool, Data, Int, String, SymmetricKey, UInt32

### Community 34 - "TimeInterval"
Cohesion: 0.27
Nodes (9): PingPacket, PongPacket, QualityReport, ScrollEvent, Double, TimeInterval, TouchEventType, UInt32 (+1 more)

### Community 35 - "ExtendedDisplayPosition"
Cohesion: 0.18
Nodes (13): ExtendedDisplayConfig, ExtendedDisplayPosition, above, below, .displayName, left, right, StreamDisplayMode (+5 more)

### Community 36 - "UDPStreamProcessor"
Cohesion: 0.31
Nodes (11): ChunkSlice, FrameAssembly, Set, TimeInterval, UInt16, UInt32, Void, UDPStreamProcessor (+3 more)

### Community 37 - "VideoDecoder.swift"
Cohesion: 0.17
Nodes (10): VideoDecoderDelegate, VideoDecoderError, decodeFailed, formatDescriptionCreationFailed, sessionCreationFailed, AnyObject, CoreVideo, Error (+2 more)

### Community 38 - "KeyEvent"
Cohesion: 0.24
Nodes (10): DiscoveredHost, HandshakeAck, KeyEvent, KeyModifiers, Bool, ExtendedDisplayPosition, StreamDisplayMode, UInt16 (+2 more)

### Community 39 - ".handleTCPPacket"
Cohesion: 0.24
Nodes (3): Data, ConnectionMode, HandshakeRequest

### Community 41 - "HostView"
Cohesion: 0.22
Nodes (9): HostView, .body, .connectionStatusSection, .localModeSection, .relayModeSection, .statusColor, .statusDescription, Color (+1 more)

### Community 42 - "iPadDisplayPreset"
Cohesion: 0.18
Nodes (11): iPadDisplayPreset, .aspectRatio, .displayName, generic, iPadAir109, iPadMini6, iPadPro11, iPadPro129 (+3 more)

### Community 43 - "BonjourBrowser"
Cohesion: 0.29
Nodes (7): BonjourBrowser, DiscoveredHost, MainActor, String, UInt16, Void, NWBrowser

### Community 44 - "TouchEventType"
Cohesion: 0.20
Nodes (10): TouchEventType, began, cancelled, doubleClick, dragBegan, dragEnded, dragMoved, ended (+2 more)

### Community 45 - "TouchEventType"
Cohesion: 0.20
Nodes (10): TouchEventType, began, cancelled, doubleClick, dragBegan, dragEnded, dragMoved, ended (+2 more)

### Community 46 - "WebRTCVideoView"
Cohesion: 0.39
Nodes (5): Coordinator, Context, RTCVideoTrack, WebRTCVideoView, RTCMTLVideoView

### Community 47 - "ConnectionState"
Cohesion: 0.25
Nodes (8): ConnectionState, connected, connecting, disconnected, discovering, .displayDescription, .isConnected, streaming

### Community 49 - "ConnectionOption"
Cohesion: 0.33
Nodes (6): ConnectionOption, .displayName, .id, .includePeerToPeer, udpNetworkFramework, udpPeerToPeerAWDL

## Knowledge Gaps
- **214 isolated node(s):** `.statusDescription`, `.isDataChannelOpen`, `auto`, `h264`, `hevc` (+209 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 392 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ClientManager` connect `ClientManager` to `AudioPlayer`, `Foundation`, `UDPStreamProcessor`, `.handleTCPPacket`, `Int`, `ContentView`, `MouseHandlingView`, `BonjourBrowser`, `WebRTCClientSession`, `ConnectionState`, `.setStreamingStateIfNeeded`, `ConnectionOption`, `NetworkHealthMonitor`, `VideoStreamViewModel`, `Bool`, `.handleRelayPacket`?**
  _High betweenness centrality (0.206) - this node is a cross-community bridge._
- **Why does `Foundation` connect `Foundation` to `WebRTCHostSession`, `VideoDecoder.swift`, `VirtualDisplayManager`, `AirCatchHost/SharedModels.swift`, `AirCatchClient/SharedModels.swift`, `NetworkHealthMonitor`?**
  _High betweenness centrality (0.195) - this node is a cross-community bridge._
- **Why does `HostManager` connect `HostManager` to `NetworkManager`, `Foundation`, `WebRTCHostSession`, `ScreenStreamer`, `HostView`, `NetworkHealthMonitor`, `MPCAirCatchHost`, `CryptoManager`?**
  _High betweenness centrality (0.195) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `HostManager` (e.g. with `BonjourAdvertiser` and `CryptoManager`) actually correct?**
  _`HostManager` has 4 INFERRED edges - model-reasoned connections that need verification._
- **What connects `.statusDescription`, `.isDataChannelOpen`, `auto` to the rest of the system?**
  _214 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `HostManager` be split into smaller, more focused modules?**
  _Cohesion score 0.0768025078369906 - nodes in this community are weakly interconnected._
- **Should `NetworkManager` be split into smaller, more focused modules?**
  _Cohesion score 0.08499743983614952 - nodes in this community are weakly interconnected._