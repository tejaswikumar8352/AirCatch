# AirCatch

**Use your iPad as a wireless display and input device for your Mac.**

AirCatch streams your Mac's screen to your iPad in real-time with ultra-low latency, while letting you control your Mac using touch, trackpad gestures, and a full Mac-style keyboard — all wirelessly over Wi-Fi or peer-to-peer (AWDL).

![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20iPadOS-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
![License](https://img.shields.io/badge/License-Private-lightgrey)

---

## Features

### 🖥️ Screen Streaming
- **Real-time H.264 video streaming** from Mac to iPad
- **Adaptive quality presets**: Clarity (30fps), Balanced (45fps), Smooth (60fps), Max Quality (60fps)
- **Configurable bitrate**: 25-50 Mbps depending on preset
- **Letterbox/Pillarbox handling**: Black bars fill unused screen space
- **Low-latency encoding** using VideoToolbox hardware acceleration

### 🎵 Audio Streaming
- **System audio streaming** from Mac to iPad
- **PCM audio format**: 48kHz, stereo, float32
- **AVAudioEngine playback** on iPad for low-latency audio

### 🖱️ Input Control
- **Touch-to-click**: Tap on the iPad screen to click on Mac
- **Drag gestures**: Touch and drag to move windows or select
- **Two-finger scroll**: Scroll content on Mac using iPad gestures
- **Right-click**: Two-finger tap for context menus
- **Double-click**: Double-tap for double-click actions

### ⌨️ Mac Keyboard
- **Full Mac-style keyboard** rendered on iPad
- **Complete key layout**: Function row (F1-F12), number row, QWERTY, arrow keys
- **Modifier keys**: Shift, Control, Option (⌥), Command (⌘)
- **Key combinations**: Supports shortcuts like ⌘C, ⌘V, ⌘⇧4, etc.
- **Caps Lock toggle**: Visual feedback for caps lock state

### 🔌 Connection Modes
- **UDP + P2P (AWDL)**: Direct peer-to-peer connection for lowest latency
- **UDP + Network**: Standard Wi-Fi network connection

### 🔐 Security
- **PIN-based pairing**: 4-digit PIN displayed on Mac, entered on iPad
- **Secure handshake**: Connection established only after PIN verification

---

## Requirements

### Mac (Host)
- macOS 14.0 Sonoma or later
- Screen Recording permission (System Settings → Privacy & Security → Screen Recording)
- Accessibility permission for input injection (System Settings → Privacy & Security → Accessibility)

### iPad (Client)
- iPadOS 17.0 or later
- iPad only (iPhone not supported)

---

## Project Structure

```
AirCatch/
├── AirCatchHost/                    # macOS Host Application
│   ├── AirCatchHostApp.swift        # App entry point
│   ├── HostManager.swift            # Main orchestrator for streaming/clients
│   ├── ScreenStreamer.swift         # Screen & audio capture using ScreenCaptureKit
│   ├── InputInjector.swift          # Mouse/keyboard event injection via CGEvent
│   ├── NetworkManager.swift         # TCP/UDP networking with Network.framework
│   ├── BonjourAdvertiser.swift      # mDNS service advertisement
│   ├── MPCAirCatchHost.swift        # MultipeerConnectivity for P2P
│   ├── SharedModels.swift           # Protocol models (packets, events)
│   └── Info.plist                   # App configuration & permissions
│
├── AirCatchClient/                  # iPadOS Client Application
│   ├── AirCatchClientApp.swift      # App entry point
│   ├── ContentView.swift            # Main UI with device list & PIN entry
│   ├── ClientManager.swift          # Connection & state management
│   ├── VideoStreamOverlay.swift     # Full-screen video display
│   ├── MetalVideoView.swift         # Metal-accelerated video rendering
│   ├── H264Decoder.swift            # Hardware H.264 decoding
│   ├── AudioPlayer.swift            # AVAudioEngine audio playback
│   ├── InputSessionOverlay.swift    # Keyboard & trackpad overlay
│   ├── MacKeyboardView.swift        # Custom Mac-style keyboard
│   ├── MouseInputView.swift         # Touch → mouse event handling
│   ├── NetworkManager.swift         # TCP/UDP client connections
│   ├── BonjourBrowser.swift         # mDNS service discovery
│   ├── MPCAirCatchClient.swift      # MultipeerConnectivity for P2P
│   ├── SharedModels.swift           # Protocol models (packets, events)
│   └── Info.plist                   # App configuration
│
├── AirCatchHostTests/               # Unit tests for Host
├── AirCatchClientTests/             # Unit tests for Client
├── AirCatchHostUITests/             # UI tests for Host
├── AirCatchClientUITests/           # UI tests for Client
└── AirCatch.xcodeproj/              # Xcode project file
```

---

## Architecture

### Network Protocol

AirCatch uses a custom binary protocol over TCP and UDP:

```
┌─────────┬─────────────┬─────────────────┐
│ Type    │ Length      │ Payload         │
│ 1 byte  │ 4 bytes     │ N bytes         │
└─────────┴─────────────┴─────────────────┘
```

**Packet Types:**
| Type | Value | Description |
|------|-------|-------------|
| Handshake | 0x01 | Client → Host connection request |
| HandshakeAck | 0x02 | Host → Client connection accepted |
| VideoFrame | 0x03 | H.264 encoded video frame |
| TouchEvent | 0x04 | Touch/click coordinates |
| Disconnect | 0x05 | Connection termination |
| Ping/Pong | 0x06 | Latency measurement |
| KeyboardEvent | 0x07 | Key press with modifiers |
| ScrollEvent | 0x08 | Scroll delta values |
| VideoFrameChunk | 0x09 | Fragmented video for UDP |
| QualityReport | 0x0A | Client → Host quality feedback |
| PairingRequest | 0x0B | PIN-based pairing |
| PairingFailed | 0x0C | Wrong PIN notification |
| TrackpadEvent | 0x0D | Trackpad gestures |
| AudioPCM | 0x0F | Raw audio samples |

### Video Pipeline

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  ScreenCaptureKit │ ──▶ │  VideoToolbox    │ ──▶ │  Network         │
│  (Screen Capture) │     │  (H.264 Encode)  │     │  (UDP/TCP Send)  │
└──────────────────┘     └──────────────────┘     └──────────────────┘
                                                           │
                                                           ▼
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  Metal Renderer   │ ◀── │  VideoToolbox    │ ◀── │  Network         │
│  (Display)        │     │  (H.264 Decode)  │     │  (UDP/TCP Recv)  │
└──────────────────┘     └──────────────────┘     └──────────────────┘
```

### Audio Pipeline

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  ScreenCaptureKit │ ──▶ │  PCM Extraction  │ ──▶ │  Network         │
│  (Audio Capture)  │     │  (Float32 48kHz) │     │  (TCP Send)      │
└──────────────────┘     └──────────────────┘     └──────────────────┘
                                                           │
                                                           ▼
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  iPad Speakers    │ ◀── │  AVAudioEngine   │ ◀── │  Network         │
│  (Output)         │     │  (Playback)      │     │  (TCP Recv)      │
└──────────────────┘     └──────────────────┘     └──────────────────┘
```

---

## How to Use

### On Mac (Host)

1. **Build and run** `AirCatchHost` target in Xcode
2. **Grant permissions** when prompted:
   - Screen Recording: Required for capturing screen
   - Accessibility: Required for injecting mouse/keyboard events
3. The app displays a **4-digit PIN** when ready
4. Mac advertises itself via Bonjour, visible to iPads on the same network

### On iPad (Client)

1. **Build and run** `AirCatchClient` target in Xcode (iPad simulator or device)
2. **Discover hosts**: The app automatically finds Mac hosts on the network
3. **Tap Connect** on your Mac's name
4. **Enter the PIN** shown on the Mac
5. **Choose quality preset** and connection mode
6. **Tap Connect** to start streaming

### Controls (During Streaming)

| Gesture | Action |
|---------|--------|
| Single tap | Left click |
| Double tap | Double click |
| Tap and drag | Drag / select |
| Two-finger tap | Right click |
| Two-finger pan | Scroll |
| Pinch (future) | Zoom |

### Keyboard/Trackpad Mode

- Enable via the **Keyboard** or **Trackpad** buttons in device list
- Mac keyboard appears at bottom of screen
- All keys and modifier combinations work

---

## Quality Presets

| Preset | Bitrate | Frame Rate | Best For |
|--------|---------|------------|----------|
| Clarity | 35 Mbps | 30 fps | Text, documents, coding |
| Balanced | 30 Mbps | 45 fps | General use (default) |
| Smooth | 25 Mbps | 60 fps | Video, animations |
| Max | 50 Mbps | 60 fps | Maximum quality |

---

## Connection Modes

### UDP + P2P (AWDL)
- Uses Apple Wireless Direct Link for direct device-to-device connection
- Lowest latency, best for same-room usage
- Works even without Wi-Fi router

### UDP + Network
- Uses standard Wi-Fi network
- Works across different networks if routable
- Slightly higher latency than P2P

---

## Troubleshooting

### Mac not appearing in iPad's device list
- Ensure both devices are on the same Wi-Fi network
- Check that the Mac's firewall allows incoming connections
- Try "UDP + P2P (AWDL)" mode for direct connection

### "Wrong PIN" error
- The PIN refreshes periodically; ensure you're entering the current PIN
- Make sure you're connecting to the correct Mac

### No video streaming / black screen
- Grant "Screen Recording" permission in System Settings → Privacy & Security
- Restart AirCatchHost after granting permission

### Touch/keyboard not working on Mac
- Grant "Accessibility" permission in System Settings → Privacy & Security
- Restart AirCatchHost after granting permission

### Audio not playing on iPad
- Ensure iPad is not in silent mode
- Check iPad volume is turned up
- "Screen & System Audio Recording" permission required on Mac

### High latency or choppy video
- Try a lower quality preset (Clarity or Balanced)
- Use "UDP + P2P (AWDL)" for lowest latency
- Ensure strong Wi-Fi signal on both devices

---

## Technologies Used

- **ScreenCaptureKit** - High-performance screen and audio capture (macOS)
- **VideoToolbox** - Hardware H.264 encoding/decoding
- **Metal** - GPU-accelerated video rendering (iPadOS)
- **AVAudioEngine** - Low-latency audio playback (iPadOS)
- **Network.framework** - Modern TCP/UDP networking with QUIC support
- **MultipeerConnectivity** - Peer-to-peer via AWDL
- **Bonjour (mDNS)** - Zero-configuration service discovery
- **CGEvent** - System-level mouse/keyboard injection (macOS)
- **SwiftUI** - Modern declarative UI framework

---

## Future Improvements

- [ ] Touch Bar streaming (MacBook Pro)
- [ ] Multi-display support (stream specific monitor)
- [ ] Clipboard sharing between Mac and iPad
- [ ] File drag-and-drop between devices
- [ ] Apple Pencil pressure sensitivity
- [ ] Handoff integration
- [ ] USB-C wired connection mode
- [ ] iPhone support (compact layout)

---

## License

This project is private and proprietary. All rights reserved.

---

## Author

Built with ❤️ by Teja Chowdary
