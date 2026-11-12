# Graph Report - AirCatch  (2026-09-11)

## Corpus Check
- 40 files · ~57,976 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1052 nodes · 2332 edges · 53 communities (45 shown, 7 thin omitted)
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 114 edges (avg confidence: 0.82)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `88d13ff1`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- HostManager
- NetworkManager
- .body
- AirCatch
- ScreenStreamer
- Sendable
- AirCatchClient/SharedModels.swift
- VirtualDisplayManager
- MouseHandlingView
- HostView
- MetalVideoRenderer
- Foundation
- CryptoManager
- AirCatchClientApp
- Codable
- InputInjector
- String
- MPCAirCatchClient
- NetworkHealthMonitor
- MPCAirCatchHost
- ConnectionOption
- String
- VideoDecoder
- AirCatchHost/SharedModels.swift
- ContentView.swift
- PacketType
- Bool
- iPadDisplayPreset
- UncheckedSendable
- CryptoManager
- TimeInterval
- Int
- AudioPlayer
- .makeHandshakeRequest
- ScreenStreamer.swift
- View
- .handleTCPPacket
- BonjourAdvertiser
- DisplayManager
- ManualConnectOverlay
- ClientManager
- iPadDisplayPreset
- BonjourBrowser
- TouchEventType
- TouchEventType
- SidebarItem
- ConnectionState
- .setStreamingStateIfNeeded
- AirCatchClient/CryptoManager.swift
- manifest.json
- launch_retry.sh
- HostCard

## God Nodes (most connected - your core abstractions)
1. `ClientManager` - 90 edges
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
- `DiscoveredHost` --references--> `Network`  [EXTRACTED]
  AirCatchClient/SharedModels.swift → AirCatchHost/SharedModels.swift
- `.body` --calls--> `HostView`  [INFERRED]
  AirCatchHost/AirCatchHostApp.swift → AirCatchHost/HostView.swift
- `.pinDisplay` --references--> `HostManager`  [INFERRED]
  AirCatchHost/HostView.swift → AirCatchHost/HostManager.swift
- `ClientManager` --calls--> `BonjourBrowser`  [INFERRED]
  AirCatchClient/ClientManager.swift → AirCatchClient/BonjourBrowser.swift

## Import Cycles
- None detected.

## Communities (53 total, 7 thin omitted)

### Community 0 - "HostManager"
Cohesion: 0.08
Nodes (22): CachedFrame, HostManager, .effectiveDefaultFrameRate, .preferredFrameRate, .statusDescription, InputStateCache, Bool, CGDirectDisplayID (+14 more)

### Community 1 - "NetworkManager"
Cohesion: 0.09
Nodes (22): NetworkManager, Bool, Data, MainActor, NWConnection, NWEndpoint, Packet, PacketType (+14 more)

### Community 2 - ".body"
Cohesion: 0.25
Nodes (4): DiscoveredHost, ClientSettingsView, .body, .body

### Community 3 - "AirCatch"
Cohesion: 0.10
Nodes (20): AirCatch, Code Graph (graphify), Connecting over Tailscale, Design Notes: Why This Looks Right and Reads Fast, Features, Getting Started, Given the above, what else is worth showing off?, How It Works (+12 more)

### Community 4 - "ScreenStreamer"
Cohesion: 0.08
Nodes (26): ScreenStreamer, StreamerError, compressionSessionCreationFailed, noDisplayFound, StreamOutput, Bool, CGDirectDisplayID, CMTime (+18 more)

### Community 5 - "Sendable"
Cohesion: 0.15
Nodes (17): DiscoveredHost, KeyEvent, KeyModifiers, MediaKeyEvent, Int32, UInt16, DiscoveredHost, KeyEvent (+9 more)

### Community 6 - "AirCatchClient/SharedModels.swift"
Cohesion: 0.18
Nodes (18): AuthChallenge, AuthResponse, CodecPreference, auto, h264, hevc, ConnectionMode, localNetwork (+10 more)

### Community 7 - "VirtualDisplayManager"
Cohesion: 0.11
Nodes (25): CGVirtualDisplay, CGVirtualDisplayDescriptor, CGVirtualDisplayMode, CGVirtualDisplaySettings, AnyObject, Bool, CGDirectDisplayID, CGPoint (+17 more)

### Community 8 - "MouseHandlingView"
Cohesion: 0.09
Nodes (25): MouseHandlingView, .canBecomeFirstResponder, MouseInputView, Bool, CGPoint, CGRect, Context, Int (+17 more)

### Community 9 - "HostView"
Cohesion: 0.17
Nodes (10): HostView, .body, .connectionStatusSection, .pinDisplay, .statusColor, .statusDescription, Color, String (+2 more)

### Community 10 - "MetalVideoRenderer"
Cohesion: 0.07
Nodes (33): MetalVideoRenderer, MetalVideoView, CGSize, Context, CVPixelBuffer, Float, Int, ObjectIdentifier (+25 more)

### Community 11 - "Foundation"
Cohesion: 0.20
Nodes (8): AppKit, Combine, CoreGraphics, Foundation, IOKit.hidsystem, MultipeerConnectivity, Network, Security

### Community 12 - "CryptoManager"
Cohesion: 0.24
Nodes (8): CryptoManager, .isReady, Bool, Data, Int, String, SymmetricKey, UInt32

### Community 13 - "AirCatchClientApp"
Cohesion: 0.15
Nodes (10): AirCatchClientApp, .body, Scene, AirCatchHostApp, .body, HostAppDelegate, Scene, App (+2 more)

### Community 14 - "Codable"
Cohesion: 0.25
Nodes (12): AirCatchConfig, PingPacket, PongPacket, QualityReport, ScrollEvent, Double, TimeInterval, TouchEventType (+4 more)

### Community 15 - "InputInjector"
Cohesion: 0.14
Nodes (13): InputInjector, .hasAccessibilityPermission, Bool, CGPoint, CGRect, Double, Int32, KeyModifiers (+5 more)

### Community 16 - "String"
Cohesion: 0.26
Nodes (4): SavedHost, Date, NWEndpoint, String

### Community 17 - "MPCAirCatchClient"
Cohesion: 0.13
Nodes (17): MPCAirCatchClient, Data, Error, InputStream, MCPeerID, MCSession, MCSessionSendDataMode, MCSessionState (+9 more)

### Community 18 - "NetworkHealthMonitor"
Cohesion: 0.10
Nodes (18): BitrateCalculator, Double, Int, String, NetworkHealthMonitor, SignalQuality, excellent, fair (+10 more)

### Community 19 - "MPCAirCatchHost"
Cohesion: 0.15
Nodes (18): MPCAirCatchHost, .hasConnectedPeers, Bool, Data, Error, InputStream, MCPeerID, MCSession (+10 more)

### Community 20 - "ConnectionOption"
Cohesion: 0.05
Nodes (46): ConnectionOption, automatic, .displayName, .id, .includePeerToPeer, udpNetworkFramework, udpPeerToPeerAWDL, ExtendedDisplayConfig (+38 more)

### Community 21 - "String"
Cohesion: 0.18
Nodes (13): AirCatchLog, Category, general, input, network, video, AirCatchLog, Category (+5 more)

### Community 22 - "VideoDecoder"
Cohesion: 0.14
Nodes (13): Bool, CMTime, CVPixelBuffer, Data, Int, UInt8, VideoDecoder, VideoDecoderDelegate (+5 more)

### Community 23 - "AirCatchHost/SharedModels.swift"
Cohesion: 0.16
Nodes (19): AuthChallenge, AuthResponse, CodecPreference, auto, h264, hevc, ConnectionMode, localNetwork (+11 more)

### Community 24 - "ContentView.swift"
Cohesion: 0.24
Nodes (8): DevicesBackground, .body, .body, SavedHostCard, .body, .subtitle, SwiftUI, UIKit

### Community 25 - "PacketType"
Cohesion: 0.05
Nodes (39): PacketType, audioPCM, authChallenge, authResponse, disconnect, handshake, handshakeAck, keyEvent (+31 more)

### Community 26 - "Bool"
Cohesion: 0.33
Nodes (3): AtomicBool, .audioEnabled, Bool

### Community 27 - "iPadDisplayPreset"
Cohesion: 0.17
Nodes (11): iPadDisplayPreset, .aspectRatio, .displayName, generic, iPadAir109, iPadMini6, iPadPro11, iPadPro129 (+3 more)

### Community 29 - "CryptoManager"
Cohesion: 0.23
Nodes (8): CryptoManager, .isReady, Bool, Data, Int, String, SymmetricKey, UInt32

### Community 30 - "TimeInterval"
Cohesion: 0.26
Nodes (10): AirCatchConfig, PingPacket, PongPacket, QualityReport, ScrollEvent, Double, TimeInterval, TouchEventType (+2 more)

### Community 32 - "AudioPlayer"
Cohesion: 0.20
Nodes (6): AudioPlayer, Data, Double, Int, UInt32, AVAudioFormat

### Community 34 - "ScreenStreamer.swift"
Cohesion: 0.13
Nodes (14): Accelerate, OSStatus, VideoDecoderError, decodeFailed, formatDescriptionCreationFailed, sessionCreationFailed, AVFoundation, CoreMedia (+6 more)

### Community 35 - "View"
Cohesion: 0.44
Nodes (7): AboutScreen, .body, ContentView, Sidebar, .body, String, View

### Community 36 - ".handleTCPPacket"
Cohesion: 0.22
Nodes (13): ChunkSlice, error, FrameAssembly, Data, Packet, Set, UInt16, UInt32 (+5 more)

### Community 37 - "BonjourAdvertiser"
Cohesion: 0.39
Nodes (5): BonjourAdvertiser, NWListener, String, UInt16, NWTXTRecord

### Community 38 - "DisplayManager"
Cohesion: 0.32
Nodes (4): DisplayManager, Double, Int, CGDisplayMode

### Community 39 - "ManualConnectOverlay"
Cohesion: 0.29
Nodes (7): Field, address, pin, ManualConnectOverlay, .body, .isValidAddress, .sanitizedAddress

### Community 40 - "ClientManager"
Cohesion: 0.10
Nodes (15): ClientManager, .connectionOption, .effectiveIncludePeerToPeer, .optimizeForHostDisplay, .savedSessionToken, Double, Float, Int32 (+7 more)

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

### Community 46 - "SidebarItem"
Cohesion: 0.40
Nodes (5): SidebarItem, about, devices, settings, Hashable

### Community 47 - "ConnectionState"
Cohesion: 0.25
Nodes (8): ConnectionState, connected, connecting, disconnected, discovering, .displayDescription, .isConnected, streaming

### Community 62 - "HostCard"
Cohesion: 0.20
Nodes (12): DevicesScreen, .header, HostCard, .body, .statusColor, .subtitle, PINEntryOverlay, .body (+4 more)

## Knowledge Gaps
- **205 isolated node(s):** `id`, `targets`, `AVFoundation`, `disconnected`, `discovering` (+200 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 336 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **7 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ClientManager` connect `ClientManager` to `HostManager`, `.body`, `MouseHandlingView`, `MetalVideoRenderer`, `Foundation`, `String`, `NetworkHealthMonitor`, `ConnectionOption`, `ContentView.swift`, `Bool`, `Int`, `AudioPlayer`, `.makeHandshakeRequest`, `View`, `.handleTCPPacket`, `BonjourBrowser`, `ConnectionState`, `.setStreamingStateIfNeeded`, `HostCard`?**
  _High betweenness centrality (0.339) - this node is a cross-community bridge._
- **Why does `Foundation` connect `Foundation` to `ScreenStreamer.swift`, `AirCatchClient/SharedModels.swift`, `VirtualDisplayManager`, `BonjourBrowser`, `AirCatchClient/CryptoManager.swift`, `NetworkHealthMonitor`, `AirCatchHost/SharedModels.swift`?**
  _High betweenness centrality (0.166) - this node is a cross-community bridge._
- **Why does `HostManager` connect `HostManager` to `NetworkManager`, `ScreenStreamer`, `BonjourAdvertiser`, `HostView`, `Foundation`, `NetworkHealthMonitor`, `MPCAirCatchHost`, `CryptoManager`?**
  _High betweenness centrality (0.141) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `ClientManager` (e.g. with `BonjourBrowser` and `.body`) actually correct?**
  _`ClientManager` has 3 INFERRED edges - model-reasoned connections that need verification._
- **Are the 4 inferred relationships involving `HostManager` (e.g. with `BonjourAdvertiser` and `CryptoManager`) actually correct?**
  _`HostManager` has 4 INFERRED edges - model-reasoned connections that need verification._
- **What connects `id`, `targets`, `AVFoundation` to the rest of the system?**
  _205 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `HostManager` be split into smaller, more focused modules?**
  _Cohesion score 0.07825507825507826 - nodes in this community are weakly interconnected._