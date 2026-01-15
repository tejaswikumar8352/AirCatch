AirCatch
======

AirCatch is a Mac + iPad app pair that turns your iPad into a fast, high-quality wireless display for your Mac, with optional reverse control. The goal is simple: keep the stream sharp (Retina-class), keep motion smooth (60fps), and keep interaction responsive.

What you get
------------

On the Mac, AirCatchHost captures the screen using ScreenCaptureKit, encodes it with VideoToolbox, and streams it over the network. On the iPad, AirCatchClient receives the stream, reassembles frames, decodes them, and renders with Metal.

AirCatch also supports input back to the Mac: taps, drags, scrolling, right-click, and keyboard input.

Video and rendering
-------------------

AirCatch is built around a high-throughput, low-copy video pipeline. Frames are encoded as HEVC (including Main 4:2:2 10‑bit when supported) and sent at 60fps. On the client side, frames are decoded and displayed with a Metal-backed view.

Networking
----------

Discovery uses Bonjour with the service type `_aircatch._udp`. Video frames are transported as chunked UDP packets for throughput and low latency, while control traffic (handshake, pairing, input) goes over a reliable channel.

Audio Streaming
---------------

AirCatch streams system audio from the Mac to the iPad in high-quality stereo (48kHz). This is perfect for watching videos or gaming. 
- **Client Control**: You can toggle audio streaming on/off directly from the iPad client using the "Stream Audio" switch in the connection overlay. 
- **Low Latency**: Audio is captured via ScreenCaptureKit and streamed via UDP to minimize desync.


Input and on-screen keyboard
----------------------------

AirCatch maps iPad touch gestures into macOS input events on the host. For typing, the client includes a Mac-style on-screen keyboard overlay that can be moved and resized. The keyboard UI is translucent so the desktop remains visible underneath, and the keycaps are styled dark with white legends.

**Voice Typing**: The keyboard features a **Voice Typing** button (replacing the standard Eject key). 
- **Native Dictation**: Tap the Mic icon to start dictating. It uses iOS's native `SFSpeechRecognizer`, automatically supporting your device's current language (English, Spanish, etc.).
- **Visual Feedback**: The button turns **Red** when listening.
- **Direct Injection**: Recognized text is injected directly into the Mac as Unicode text, ensuring compatibility with all apps.

The function row follows Apple's Mac keyboard layout for F1 through F12. For media/system keys (brightness, volume, playback), the host injects AUX control button events using `NSEvent.otherEvent(with: .systemDefined, subtype: 8, ...)`.

Quality presets
---------------

AirCatch ships with three presets optimized for HEVC on Apple Silicon. All presets run at 60 FPS.

| Preset | Bitrate | When to use it |
| --- | ---: | --- |
| Performance | 10 Mbps | Light streaming, bandwidth-conscious networks |
| Balanced | 20 Mbps | Default – best balance of quality and responsiveness |
| Pro | 30 Mbps | Maximum quality for static content and reading |

How it works (at a glance)
--------------------------

The client discovers a host, connects, and sends a handshake describing its screen and streaming preferences. The host starts capture and encoding, then streams chunked frames. Each UDP chunk includes a small header so the client can reassemble complete frames before decoding.

Build
-----

**Requirements**:
- Client: iOS/iPadOS 17.0 or later
- Host: macOS 14.0 or later (Apple Silicon recommended)

Host (macOS):

```bash
xcodebuild -scheme AirCatchHost -destination 'platform=macOS'
```

Client (iPadOS):

```bash
xcodebuild -scheme AirCatchClient -destination 'generic/platform=iOS'
```

Permissions
-----------

On macOS, AirCatchHost needs **Accessibility** permission to inject input events (System Settings → Privacy & Security → Accessibility) and **Screen Recording** permission to capture the display.

On iPadOS, AirCatchClient needs:
- **Local Network** permission for discovery and connections.
- **Microphone** and **Speech Recognition** permissions for the Voice Typing feature.

License
-------

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

Copyright © 2026 Teja Chowdary.
