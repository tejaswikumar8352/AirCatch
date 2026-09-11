# Graph Report - AirCatch  (2026-09-10)

## Corpus Check
- 36 files · ~51,878 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1094 nodes · 2120 edges · 157 communities (37 shown, 120 thin omitted)
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 66 edges (avg confidence: 0.82)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `af8deeb1`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- HostManager
- NetworkManager
- Foundation
- Bool
- ScreenStreamer
- NetworkManager
- Bool
- VirtualDisplayManager
- MouseHandlingView
- View
- MetalVideoRenderer
- Bool
- Bool
- DiscoveredHost
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
- PacketType
- PacketType
- Bool
- RTCPeerConnectionState
- Set
- CryptoManager
- AirCatchHost/SharedModels.swift
- Void
- AudioPlayer
- CryptoManager
- Codable
- ExtendedDisplayPosition
- UDPStreamProcessor
- CGDirectDisplayID
- ExtendedDisplayResolution
- .handleTCPPacket
- Int
- CFTimeInterval
- iPadDisplayPreset
- BonjourBrowser
- TouchEventType
- TouchEventType
- Float
- ConnectionState
- .setStreamingStateIfNeeded
- String
- manifest.json
- launch_retry.sh
- RelayClient
- WebRTCSignalMessage
- CFTimeInterval
- KeyModifiers
- RTCVideoTrack
- Timer
- Context
- Data
- CGSize
- Error
- PacketType
- SecTrust
- Set
- String
- ObjectIdentifier
- URL
- URLAuthenticationChallenge
- URLCredential
- URLSession
- URLSessionTask
- URLSessionWebSocketTask
- Void
- Data
- RTCDataBuffer
- RTCDataChannel
- RTCIceCandidate
- RTCIceConnectionState
- RTCIceGatheringState
- RTCIceServer
- RTCMediaStream
- RTCPeerConnection
- RTCPeerConnectionFactory
- RTCPeerConnectionState
- RTCSignalingState
- RTCVideoTrack
- Void
- WebRTCIceServerConfig
- WebRTCSignalMessage
- Context
- RTCVideoTrack
- MCPeerID
- PacketType
- RelayClient
- RTCPeerConnectionState
- WebRTCSignalMessage
- NWListener
- Data
- Error
- PacketType
- SecTrust
- Set
- String
- TimeInterval
- URL
- URLAuthenticationChallenge
- URLCredential
- URLSession
- URLSessionTask
- URLSessionWebSocketTask
- Void
- Date
- DispatchQueue
- OSStatus
- CMTime
- CVPixelBuffer
- Data
- Double
- Int
- Int64
- RTCDataBuffer
- RTCDataChannel
- RTCIceCandidate
- RTCIceConnectionState
- RTCIceGatheringState
- RTCIceServer
- RTCMediaStream
- RTCPeerConnection
- RTCPeerConnectionFactory
- RTCPeerConnectionState
- RTCSignalingState
- RTCVideoTrack
- Void
- WebRTCIceServerConfig
- WebRTCSignalMessage
- CGRect
- CGPoint
- CMTime
- CVPixelBuffer
- Int32
- NWConnection
- NWEndpoint
- RTCDataChannelDelegate
- RTCDegradationPreference
- RTCMTLVideoView
- RTCPeerConnectionDelegate
- RTCRtpReceiver
- RTCRtpSender
- RTCVideoCapturer
- RTCVideoSource
- RTCVideoTrack
- TouchEventType
- UInt16
- URLSessionWebSocketDelegate
- WebRTCClientSession
- WebRTCHostSession

## God Nodes (most connected - your core abstractions)
1. `ClientManager` - 66 edges
2. `HostManager` - 64 edges
3. `ScreenStreamer` - 37 edges
4. `NetworkManager` - 32 edges
5. `MetalVideoRenderer` - 28 edges
6. `VirtualDisplayManager` - 27 edges
7. `MouseHandlingView` - 24 edges
8. `VideoStreamViewModel` - 22 edges
9. `MPCAirCatchHost` - 22 edges
10. `InputInjector` - 21 edges

## Surprising Connections (you probably didn't know these)
- `DiscoveredHost` --references--> `Network`  [EXTRACTED]
  AirCatchClient/SharedModels.swift → AirCatchHost/SharedModels.swift
- `.localModeSection` --references--> `HostManager`  [INFERRED]
  AirCatchHost/HostView.swift → AirCatchHost/HostManager.swift
- `ClientManager` --calls--> `BonjourBrowser`  [INFERRED]
  AirCatchClient/ClientManager.swift → AirCatchClient/BonjourBrowser.swift
- `.body` --references--> `ClientManager`  [INFERRED]
  AirCatchClient/VideoStreamOverlay.swift → AirCatchClient/ClientManager.swift
- `HostManager` --calls--> `MPCAirCatchHost`  [INFERRED]
  AirCatchHost/HostManager.swift → AirCatchHost/MPCAirCatchHost.swift

## Import Cycles
- None detected.

## Communities (157 total, 120 thin omitted)

### Community 0 - "HostManager"
Cohesion: 0.08
Nodes (24): BonjourAdvertiser, NWListener, String, UInt16, CachedFrame, HostManager, .statusDescription, InputStateCache (+16 more)

### Community 1 - "NetworkManager"
Cohesion: 0.18
Nodes (10): NetworkManager, Data, NWConnection, NWEndpoint, Packet, PacketType, String, UInt16 (+2 more)

### Community 2 - "Foundation"
Cohesion: 0.06
Nodes (27): Accelerate, OSStatus, VideoDecoderError, decodeFailed, formatDescriptionCreationFailed, sessionCreationFailed, DisplayManager, Double (+19 more)

### Community 4 - "ScreenStreamer"
Cohesion: 0.09
Nodes (26): ScreenStreamer, StreamerError, compressionSessionCreationFailed, noDisplayFound, StreamOutput, Bool, CGDirectDisplayID, CMTime (+18 more)

### Community 5 - "NetworkManager"
Cohesion: 0.16
Nodes (13): NetworkManager, Bool, Data, MainActor, NWConnection, NWEndpoint, Packet, PacketType (+5 more)

### Community 7 - "VirtualDisplayManager"
Cohesion: 0.11
Nodes (26): CGVirtualDisplay, CGVirtualDisplayDescriptor, CGVirtualDisplayMode, CGVirtualDisplaySettings, AnyObject, Bool, CGDirectDisplayID, CGPoint (+18 more)

### Community 8 - "MouseHandlingView"
Cohesion: 0.10
Nodes (22): MouseHandlingView, MouseInputView, Bool, CGPoint, CGRect, Int, Set, TouchEventType (+14 more)

### Community 9 - "View"
Cohesion: 0.05
Nodes (53): AirCatchClientApp, .body, Scene, AboutScreen, .body, ContentView, .body, DevicesBackground (+45 more)

### Community 10 - "MetalVideoRenderer"
Cohesion: 0.07
Nodes (33): MetalVideoRenderer, MetalVideoView, CGSize, Context, CVPixelBuffer, Float, Int, ObjectIdentifier (+25 more)

### Community 14 - "AirCatchClient/SharedModels.swift"
Cohesion: 0.07
Nodes (46): AirCatchConfig, AuthChallenge, AuthResponse, CodecPreference, auto, h264, hevc, ConnectionMode (+38 more)

### Community 15 - "InputInjector"
Cohesion: 0.14
Nodes (13): InputInjector, .hasAccessibilityPermission, Bool, CGPoint, CGRect, Double, Int32, Int64 (+5 more)

### Community 16 - "ClientManager"
Cohesion: 0.12
Nodes (10): ClientManager, Double, Int32, TouchEventType, ConnectionMode, Float, HandshakeAck, HandshakeRequest (+2 more)

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
Cohesion: 0.14
Nodes (13): Bool, CMTime, CVPixelBuffer, Data, Int, UInt8, VideoDecoder, VideoDecoderDelegate (+5 more)

### Community 23 - "Int"
Cohesion: 0.16
Nodes (18): AuthChallenge, AuthResponse, CodecPreference, auto, h264, hevc, ConnectionMode, localNetwork (+10 more)

### Community 25 - "PacketType"
Cohesion: 0.05
Nodes (37): PacketType, audioPCM, authChallenge, authResponse, disconnect, handshake, handshakeAck, keyEvent (+29 more)

### Community 26 - "Bool"
Cohesion: 0.25
Nodes (4): AtomicBool, .audioEnabled, Bool, DiscoveredHost

### Community 29 - "CryptoManager"
Cohesion: 0.23
Nodes (8): CryptoManager, .isReady, Bool, Data, Int, String, SymmetricKey, UInt32

### Community 30 - "AirCatchHost/SharedModels.swift"
Cohesion: 0.19
Nodes (15): AirCatchConfig, DiscoveredHost, MediaKeyEvent, PingPacket, PongPacket, QualityReport, ScrollEvent, Double (+7 more)

### Community 32 - "AudioPlayer"
Cohesion: 0.22
Nodes (6): AudioPlayer, Data, Double, Int, UInt32, AVAudioFormat

### Community 33 - "CryptoManager"
Cohesion: 0.24
Nodes (8): CryptoManager, .isReady, Bool, Data, Int, String, SymmetricKey, UInt32

### Community 34 - "Codable"
Cohesion: 0.44
Nodes (7): KeyEvent, KeyModifiers, KeyEvent, KeyModifiers, Codable, OptionSet, Sendable

### Community 35 - "ExtendedDisplayPosition"
Cohesion: 0.18
Nodes (13): ExtendedDisplayConfig, ExtendedDisplayPosition, above, below, .displayName, left, right, StreamDisplayMode (+5 more)

### Community 36 - "UDPStreamProcessor"
Cohesion: 0.25
Nodes (13): ChunkSlice, FrameAssembly, Data, TimeInterval, UInt16, UInt32, UDPStreamProcessor, VideoReassembler (+5 more)

### Community 38 - "ExtendedDisplayResolution"
Cohesion: 0.33
Nodes (6): ExtendedDisplayResolution, .displayName, matched, native, retina, standard

### Community 39 - ".handleTCPPacket"
Cohesion: 0.32
Nodes (4): error, Packet, UncheckedSendable, T

### Community 40 - "Int"
Cohesion: 0.25
Nodes (3): AtomicInt, Int, VideoChunkNackRequest

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

### Community 47 - "ConnectionState"
Cohesion: 0.25
Nodes (8): ConnectionState, connected, connecting, disconnected, discovering, .displayDescription, .isConnected, streaming

### Community 49 - "String"
Cohesion: 0.18
Nodes (9): .savedSessionToken, ConnectionOption, .displayName, .id, .includePeerToPeer, udpNetworkFramework, udpPeerToPeerAWDL, String (+1 more)

## Knowledge Gaps
- **176 isolated node(s):** `disconnected`, `discovering`, `connecting`, `connected`, `streaming` (+171 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 421 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **120 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Foundation` connect `Foundation` to `NetworkHealthMonitor`, `VirtualDisplayManager`, `AirCatchClient/SharedModels.swift`, `AirCatchHost/SharedModels.swift`?**
  _High betweenness centrality (0.301) - this node is a cross-community bridge._
- **Why does `ClientManager` connect `ClientManager` to `Foundation`, `UDPStreamProcessor`, `.handleTCPPacket`, `Int`, `View`, `MouseHandlingView`, `BonjourBrowser`, `MetalVideoRenderer`, `ConnectionState`, `.setStreamingStateIfNeeded`, `String`, `NetworkHealthMonitor`, `Bool`?**
  _High betweenness centrality (0.182) - this node is a cross-community bridge._
- **Why does `HostManager` connect `HostManager` to `NetworkHealthMonitor`, `View`, `Foundation`, `MPCAirCatchHost`?**
  _High betweenness centrality (0.091) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `ClientManager` (e.g. with `BonjourBrowser` and `.body`) actually correct?**
  _`ClientManager` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 3 inferred relationships involving `HostManager` (e.g. with `BonjourAdvertiser` and `MPCAirCatchHost`) actually correct?**
  _`HostManager` has 3 INFERRED edges - model-reasoned connections that need verification._
- **What connects `disconnected`, `discovering`, `connecting` to the rest of the system?**
  _176 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `HostManager` be split into smaller, more focused modules?**
  _Cohesion score 0.07859649122807018 - nodes in this community are weakly interconnected._