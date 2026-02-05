# AirCatch

Turn your iPad into a wireless display for your Mac — with full touch, keyboard, and audio support.

![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20iPadOS-blue)
![Swift](https://img.shields.io/badge/swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

AirCatch is a native screen mirroring solution that streams your Mac's display to your iPad over WiFi or the internet. Unlike Apple's Sidecar, it works on any Mac running macOS 13+ and any iPad running iPadOS 16+, with no Apple Silicon requirement on the Mac side.

---

## ✨ Features

### Display Streaming
- **Hardware-accelerated HEVC (H.265) encoding** via VideoToolbox for buttery smooth 60fps streaming
- **H.264 fallback** for compatibility when needed (remote mode adaptive codec)
- **Metal-powered rendering** on iPad with zero-copy texture display for minimal latency
- **Retina resolution support** with automatic iPad model detection
- **Virtual display mode** — create an additional display that only exists on your iPad
- **Three quality presets**: Performance (12 Mbps), Balanced (20 Mbps), Pro (32 Mbps)

### Input & Control
- **Full touch support** — tap, drag, scroll, pinch-to-zoom, and right-click (long press)
- **On-screen Mac keyboard** — draggable, resizable keyboard with all modifier keys (⌘⌥⌃⇧)
- **iOS keyboard input** — use the native iPad keyboard for quick text entry
- **Voice typing** — dictate directly to your Mac using iPad's speech recognition
- **Mouse/trackpad support** — connect a mouse to your iPad and use it naturally

### Audio
- **System audio streaming** — hear your Mac's audio on your iPad
- **48kHz stereo playback** with low-latency buffering

### Connectivity
- **Auto-discovery via Bonjour** — your Mac appears automatically on your iPad
- **PIN-based authentication** — 6-digit PIN protects against unauthorized access
- **End-to-end encryption** — AES-256-GCM encryption derived from the PIN
- **Remote mode** — connect over the internet via WebSocket relay
- **Automatic reconnection** with exponential backoff

---

## 📋 Requirements

### Mac (Host)
- macOS 13.0 Ventura or later
- Screen Recording permission (System Settings → Privacy & Security)
- Accessibility permission for input injection (prompted on first launch)

### iPad (Client)
- iPadOS 16.0 or later
- iPad only (iPhone not supported)
- Same WiFi network as Mac, or internet for remote mode

---

## 🚀 Getting Started

### Building from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/AirCatch.git
   cd AirCatch
   ```

2. Open `AirCatch.xcodeproj` in Xcode 15+

3. Build and run:
   - **AirCatchHost** — Run on your Mac
   - **AirCatchClient** — Run on your iPad

### First Connection

1. Launch **AirCatch Host** on your Mac
2. Grant Screen Recording and Accessibility permissions when prompted
3. Note the 6-digit PIN displayed in the app window
4. Launch **AirCatch** on your iPad
5. Your Mac should appear in the devices list (or tap "Remote Host" for internet mode)
6. Tap your Mac, enter the PIN, choose quality preset, and connect
7. Enjoy your extended display!

---

## 🎮 Controls

| Action | Gesture |
|--------|---------|
| Click | Tap |
| Right-click | Long press or two-finger tap |
| Double-click | Double tap |
| Drag | Tap and drag |
| Scroll | Two-finger pan |
| Zoom | Pinch |
| Show keyboard | Tap keyboard icon in toolbar |
| Voice typing | Tap microphone icon on keyboard |

---

## ⚙️ Quality Presets

| Preset | Bitrate | Best For |
|--------|---------|----------|
| **Performance** | 12 Mbps | Crowded networks, battery saving |
| **Balanced** | 20 Mbps | General use (default) |
| **Pro** | 32 Mbps | Text-heavy work, design, reading |

---

## 🌐 Remote Mode

AirCatch supports streaming over the internet using a WebSocket relay server.

### Using the Public Relay
By default, AirCatch connects to `wss://aircatch.duckdns.org/ws`. Just tap "Remote Host" on your iPad and enter your Mac's PIN.

### Self-Hosting a Relay
The relay server is included in `RemoteRelayServer/`. Deploy it to your own server:

```bash
cd RemoteRelayServer
npm install
node server.js
```

Or use Docker:
```bash
docker build -t aircatch-relay .
docker run -p 8080:8080 aircatch-relay
```

See [GCE_DEPLOYMENT_GUIDE.md](RemoteRelayServer/GCE_DEPLOYMENT_GUIDE.md) for Google Cloud deployment instructions.

---

## 🔒 Security

- **PIN-based pairing** — 6-digit PIN must match on host and client
- **AES-256-GCM encryption** — All data encrypted end-to-end using PIN-derived keys
- **HKDF key derivation** — Secure key generation from short PINs
- **Rate limiting** — Relay server blocks IPs after 5 failed attempts
- **No data stored** — Relay only forwards packets, never stores content

---

## 🏗 Architecture

```
┌─────────────────┐         UDP/TCP          ┌─────────────────┐
│   AirCatchHost  │◄───────────────────────►│  AirCatchClient │
│     (macOS)     │                          │    (iPadOS)     │
├─────────────────┤                          ├─────────────────┤
│ ScreenCaptureKit│  ← Screen Capture        │ VideoDecoder    │ ← HEVC/H.264 decode
│ VideoToolbox    │  ← HEVC (H.265) encode   │ MetalVideoView  │ ← GPU render
│ CGEvent         │  ← Input injection       │ TouchInput      │ ← Touch capture
│ AVAudioEngine   │  ← Audio capture         │ AudioPlayer     │ ← Audio playback
│ CGVirtualDisplay│  ← Virtual monitor       │ SpeechManager   │ ← Voice typing
└─────────────────┘                          └─────────────────┘
         │                                            │
         │         ┌───────────────────┐              │
         └────────►│   Relay Server    │◄─────────────┘
                   │   (WebSocket)     │
                   │   Remote Mode     │
                   └───────────────────┘
```

### Key Components

| Component | Purpose |
|-----------|---------|
| `ScreenStreamer` | Captures screen via ScreenCaptureKit, encodes to HEVC (H.265) |
| `VideoDecoder` | Hardware-accelerated HEVC/H.264 decode using VideoToolbox |
| `MetalVideoView` | Zero-copy Metal rendering with CVMetalTextureCache |
| `InputInjector` | Translates touch events to CGEvent mouse/keyboard events |
| `VirtualDisplayManager` | Creates virtual displays matching iPad resolution |
| `NetworkManager` | UDP video streaming, TCP control channel |
| `CryptoManager` | AES-256-GCM encryption/decryption |
| `BonjourAdvertiser/Browser` | mDNS service discovery |

---

## 📁 Project Structure

```
AirCatch/
├── AirCatchHost/          # macOS host app
│   ├── HostManager.swift         # Main coordinator
│   ├── ScreenStreamer.swift      # Screen capture & encode
│   ├── InputInjector.swift       # Mouse/keyboard injection
│   ├── VirtualDisplayManager.swift
│   └── NetworkManager.swift
│
├── AirCatchClient/        # iPadOS client app
│   ├── ClientManager.swift       # Main coordinator
│   ├── VideoDecoder.swift        # Hardware decode
│   ├── MetalVideoView.swift      # Metal renderer
│   ├── MouseInputView.swift      # Touch handling
│   ├── MacKeyboardView.swift     # On-screen keyboard
│   └── SpeechManager.swift       # Voice typing
│
└── RemoteRelayServer/     # WebSocket relay for internet mode
    ├── server.js
    ├── Dockerfile
    └── GCE_DEPLOYMENT_GUIDE.md
```

---

## 🐛 Troubleshooting

### Mac not appearing on iPad
- Ensure both devices are on the same WiFi network
- Check that your router allows mDNS/Bonjour traffic
- Try using the IP address directly or Remote mode

### "Screen Recording permission required"
- Go to System Settings → Privacy & Security → Screen Recording
- Enable AirCatch Host (or add it if not listed)
- Restart AirCatch Host

### Touch input not working
- Go to System Settings → Privacy & Security → Accessibility
- Enable AirCatch Host
- You may need to restart the app

### High latency or stuttering
- Try switching to "Performance" quality preset
- Move closer to your WiFi router
- Ensure no other apps are heavily using the network

### Audio not playing
- Enable audio in the connection settings before connecting
- Check that iPad volume is up and not in silent mode

---

## 📝 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

Built with:
- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) — Apple's modern screen capture framework
- [VideoToolbox](https://developer.apple.com/documentation/videotoolbox) — Hardware video encoding/decoding
- [Metal](https://developer.apple.com/metal/) — GPU-accelerated rendering
- [Network.framework](https://developer.apple.com/documentation/network) — Modern networking with UDP/TCP
- [CryptoKit](https://developer.apple.com/documentation/cryptokit) — End-to-end encryption

---

Made with ❤️ for the iPad + Mac workflow
