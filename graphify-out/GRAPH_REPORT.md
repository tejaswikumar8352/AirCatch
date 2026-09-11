# Graph Report - AirCatch  (2026-09-11)

## Corpus Check
- 36 files · ~54,055 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1123 nodes · 2194 edges · 164 communities (41 shown, 123 thin omitted)
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 60 edges (avg confidence: 0.81)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `685aa425`
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
- .body
- MetalVideoRenderer
- Bool
- Bool
- iPadDisplayPreset
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
- PacketType
- Bool
- RTCPeerConnectionState
- .makeHandshakeRequest
- CryptoManager
- Codable
- ExtendedDisplayResolution
- AudioPlayer
- CryptoManager
- TimeInterval
- ExtendedDisplayPosition
- UDPStreamProcessor
- CGDirectDisplayID
- ExtendedDisplayResolution
- .handleTCPPacket
- ClientManager.swift
- CFTimeInterval
- iPadDisplayPreset
- BonjourBrowser
- TouchEventType
- TouchEventType
- Float
- ConnectionState
- .setStreamingStateIfNeeded
- Network
- manifest.json
- launch_retry.sh
- RelayClient
- WebRTCSignalMessage
- CFTimeInterval
- .sendControl
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
- HandshakeAck
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
- HandshakeAck
- TouchEventType
- UInt16
- URLSessionWebSocketDelegate
- WebRTCClientSession
- WebRTCHostSession
- Int64
- CGRect
- DiscoveredHost
- KeyModifiers
- Set
- Void

## God Nodes (most connected - your core abstractions)
1. `ClientManager` - 78 edges
2. `HostManager` - 69 edges
3. `ScreenStreamer` - 37 edges
4. `MouseHandlingView` - 32 edges
5. `NetworkManager` - 32 edges
6. `MetalVideoRenderer` - 28 edges
7. `VirtualDisplayManager` - 27 edges
8. `VideoStreamViewModel` - 22 edges
9. `MPCAirCatchHost` - 22 edges
10. `InputInjector` - 21 edges

## Surprising Connections (you probably didn't know these)
- `.localModeSection` --references--> `HostManager`  [INFERRED]
  AirCatchHost/HostView.swift → AirCatchHost/HostManager.swift
- `DiscoveredHost` --references--> `Network`  [EXTRACTED]
  AirCatchClient/SharedModels.swift → AirCatchHost/HostManager.swift
- `ClientManager` --calls--> `BonjourBrowser`  [INFERRED]
  AirCatchClient/ClientManager.swift → AirCatchClient/BonjourBrowser.swift
- `.body` --references--> `ClientManager`  [INFERRED]
  AirCatchClient/ContentView.swift → AirCatchClient/ClientManager.swift
- `.body` --references--> `ClientManager`  [INFERRED]
  AirCatchClient/VideoStreamOverlay.swift → AirCatchClient/ClientManager.swift

## Import Cycles
- None detected.

## Communities (164 total, 123 thin omitted)

### Community 0 - "HostManager"
Cohesion: 0.09
Nodes (19): CachedFrame, HostManager, .statusDescription, InputStateCache, Bool, CGRect, Data, Double (+11 more)

### Community 1 - "NetworkManager"
Cohesion: 0.18
Nodes (10): NetworkManager, Data, NWConnection, NWEndpoint, Packet, PacketType, String, UInt16 (+2 more)

### Community 2 - "Foundation"
Cohesion: 0.07
Nodes (25): Accelerate, BonjourAdvertiser, NWListener, String, UInt16, DisplayManager, Double, Int (+17 more)

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
Cohesion: 0.08
Nodes (27): MouseHandlingView, .canBecomeFirstResponder, MouseInputView, Bool, CGPoint, CGRect, Int, Set (+19 more)

### Community 9 - ".body"
Cohesion: 0.05
Nodes (56): AirCatchClientApp, .body, Scene, AboutScreen, .body, ContentView, .body, DevicesBackground (+48 more)

### Community 10 - "MetalVideoRenderer"
Cohesion: 0.07
Nodes (33): MetalVideoRenderer, MetalVideoView, CGSize, Context, CVPixelBuffer, Float, Int, ObjectIdentifier (+25 more)

### Community 13 - "iPadDisplayPreset"
Cohesion: 0.18
Nodes (11): iPadDisplayPreset, .aspectRatio, .displayName, generic, iPadAir109, iPadMini6, iPadPro11, iPadPro129 (+3 more)

### Community 14 - "AirCatchClient/SharedModels.swift"
Cohesion: 0.17
Nodes (16): AuthChallenge, AuthResponse, CodecPreference, auto, h264, hevc, ConnectionMode, localNetwork (+8 more)

### Community 15 - "InputInjector"
Cohesion: 0.14
Nodes (13): InputInjector, .hasAccessibilityPermission, Bool, CGPoint, CGRect, Double, Int32, KeyModifiers (+5 more)

### Community 16 - "ClientManager"
Cohesion: 0.16
Nodes (9): ClientManager, .savedSessionToken, SavedHost, DiscoveredHost, String, TimeInterval, Float, HandshakeAck (+1 more)

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
Cohesion: 0.17
Nodes (14): ExtendedDisplayConfig, ExtendedDisplayPosition, above, below, .displayName, left, right, StreamDisplayMode (+6 more)

### Community 21 - "String"
Cohesion: 0.18
Nodes (13): AirCatchLog, Category, general, input, network, video, AirCatchLog, Category (+5 more)

### Community 22 - "VideoDecoder"
Cohesion: 0.11
Nodes (19): Bool, CMTime, CVPixelBuffer, Data, Int, OSStatus, UInt8, VideoDecoder (+11 more)

### Community 23 - "AirCatchHost/SharedModels.swift"
Cohesion: 0.19
Nodes (16): AirCatchConfig, AuthChallenge, AuthResponse, CodecPreference, auto, h264, hevc, ConnectionMode (+8 more)

### Community 25 - "PacketType"
Cohesion: 0.05
Nodes (37): PacketType, audioPCM, authChallenge, authResponse, disconnect, handshake, handshakeAck, keyEvent (+29 more)

### Community 26 - "Bool"
Cohesion: 0.48
Nodes (3): AtomicBool, .audioEnabled, Bool

### Community 29 - "CryptoManager"
Cohesion: 0.23
Nodes (8): CryptoManager, .isReady, Bool, Data, Int, String, SymmetricKey, UInt32

### Community 30 - "Codable"
Cohesion: 0.22
Nodes (16): KeyEvent, KeyModifiers, MediaKeyEvent, PingPacket, PongPacket, ScrollEvent, Double, Int32 (+8 more)

### Community 31 - "ExtendedDisplayResolution"
Cohesion: 0.33
Nodes (6): ExtendedDisplayResolution, .displayName, matched, native, retina, standard

### Community 32 - "AudioPlayer"
Cohesion: 0.20
Nodes (6): AudioPlayer, Data, Double, Int, UInt32, AVAudioFormat

### Community 33 - "CryptoManager"
Cohesion: 0.24
Nodes (8): CryptoManager, .isReady, Bool, Data, Int, String, SymmetricKey, UInt32

### Community 34 - "TimeInterval"
Cohesion: 0.18
Nodes (16): AirCatchConfig, KeyEvent, KeyModifiers, MediaKeyEvent, PingPacket, PongPacket, ScrollEvent, Double (+8 more)

### Community 35 - "ExtendedDisplayPosition"
Cohesion: 0.18
Nodes (13): ExtendedDisplayConfig, ExtendedDisplayPosition, above, below, .displayName, left, right, StreamDisplayMode (+5 more)

### Community 36 - "UDPStreamProcessor"
Cohesion: 0.25
Nodes (13): ChunkSlice, error, FrameAssembly, Data, Set, UInt16, UInt32, Void (+5 more)

### Community 38 - "ExtendedDisplayResolution"
Cohesion: 0.33
Nodes (6): ExtendedDisplayResolution, .displayName, matched, native, retina, standard

### Community 40 - "ClientManager.swift"
Cohesion: 0.23
Nodes (4): AtomicInt, Int, UncheckedSendable, T

### Community 42 - "iPadDisplayPreset"
Cohesion: 0.17
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

### Community 49 - "Network"
Cohesion: 0.17
Nodes (11): ConnectionOption, .displayName, .id, .includePeerToPeer, udpNetworkFramework, udpPeerToPeerAWDL, DiscoveredHost, DiscoveredHost (+3 more)

### Community 55 - ".sendControl"
Cohesion: 0.18
Nodes (5): Double, Int32, KeyModifiers, TouchEventType, PacketType

### Community 136 - "HandshakeAck"
Cohesion: 0.70
Nodes (4): HandshakeAck, Bool, ExtendedDisplayPosition, StreamDisplayMode

### Community 152 - "HandshakeAck"
Cohesion: 0.70
Nodes (4): HandshakeAck, Bool, ExtendedDisplayPosition, StreamDisplayMode

## Knowledge Gaps
- **179 isolated node(s):** `disconnected`, `discovering`, `connecting`, `connected`, `streaming` (+174 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 425 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **123 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Foundation` connect `Foundation` to `VirtualDisplayManager`, `ClientManager.swift`, `BonjourBrowser`, `AirCatchClient/SharedModels.swift`, `Network`, `NetworkHealthMonitor`, `AirCatchHost/SharedModels.swift`?**
  _High betweenness centrality (0.280) - this node is a cross-community bridge._
- **Why does `ClientManager` connect `ClientManager` to `UDPStreamProcessor`, `.handleTCPPacket`, `ClientManager.swift`, `.body`, `MouseHandlingView`, `BonjourBrowser`, `MetalVideoRenderer`, `ConnectionState`, `.setStreamingStateIfNeeded`, `Network`, `NetworkHealthMonitor`, `.sendControl`, `Bool`, `.makeHandshakeRequest`?**
  _High betweenness centrality (0.264) - this node is a cross-community bridge._
- **Why does `HostManager` connect `HostManager` to `NetworkHealthMonitor`, `.body`, `Foundation`, `MPCAirCatchHost`?**
  _High betweenness centrality (0.128) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `ClientManager` (e.g. with `BonjourBrowser` and `.body`) actually correct?**
  _`ClientManager` has 3 INFERRED edges - model-reasoned connections that need verification._
- **Are the 3 inferred relationships involving `HostManager` (e.g. with `BonjourAdvertiser` and `MPCAirCatchHost`) actually correct?**
  _`HostManager` has 3 INFERRED edges - model-reasoned connections that need verification._
- **What connects `disconnected`, `discovering`, `connecting` to the rest of the system?**
  _179 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `HostManager` be split into smaller, more focused modules?**
  _Cohesion score 0.08561643835616438 - nodes in this community are weakly interconnected._