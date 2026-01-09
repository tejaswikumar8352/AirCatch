# AirCatch Display Driver (DriverKit)

This is a DriverKit-based virtual display driver that creates a virtual monitor on your Mac, allowing you to extend your display to an iPad without any physical external monitor connected.

## Requirements

### Apple Developer Program
- **Paid Apple Developer membership** ($99/year)
- You need to request special entitlements from Apple

### System Requirements
- macOS 12.0 or later
- Apple Silicon or Intel Mac with System Integrity Protection (SIP) modifications for development

## Setup Instructions

### 1. Request Entitlements from Apple

Before you can use DriverKit, you must request the necessary entitlements:

1. Go to [Apple Developer Contact](https://developer.apple.com/contact/request/system-extension/)
2. Select **"DriverKit"**
3. Explain your use case:
   > "I am developing a virtual display driver to extend a Mac's display to an iPad over the network, similar to Apple's Sidecar feature. The driver creates a virtual framebuffer that the main application captures and streams to the iPad client."

4. Apple will review and (if approved) add entitlements to your provisioning profile

### 2. Add DriverKit Target to Xcode Project

1. Open the AirCatch Xcode project
2. File → New → Target
3. Select **"DriverKit"** → **"Driver"**
4. Name it: `AirCatchDisplayDriver`
5. Bundle Identifier: `com.aircatch.displaydriver`

### 3. Add Files to Target

Copy these files into the new target:
- `AirCatchDisplayDriver.iig`
- `AirCatchDisplayDriver.cpp`
- `AirCatchDisplayDriver.h`
- `AirCatchUserClient.iig`
- `AirCatchUserClient.cpp`
- `AirCatchUserClient.h`
- `Info.plist` (replace the generated one)
- `AirCatchDisplayDriver.entitlements`

### 4. Configure Build Settings

In the DriverKit target's Build Settings:

```
DRIVERKIT_DEPLOYMENT_TARGET = 21.0
CODE_SIGN_ENTITLEMENTS = AirCatchDisplayDriver/AirCatchDisplayDriver.entitlements
PRODUCT_BUNDLE_IDENTIFIER = com.aircatch.displaydriver
```

### 5. Embed Driver in Host App

1. Select the **AirCatchHost** target
2. Go to **General** → **Frameworks, Libraries, and Embedded Content**
3. Click **+** and add `AirCatchDisplayDriver.dext`
4. Set **Embed** to "Embed & Sign"

### 6. Update Host App Entitlements

The `AirCatchHost.entitlements` file has already been updated with:
- `com.apple.developer.system-extension.install` - To install the driver
- `com.apple.developer.driverkit.userclient-access` - To communicate with the driver

### 7. Development Mode (Testing Without Entitlements)

For local development/testing, you can disable System Integrity Protection (SIP):

⚠️ **Warning:** Only do this on a development machine, not a production system.

```bash
# Boot into Recovery Mode (hold Command+R on Intel, or power button on Apple Silicon)
# Open Terminal from Utilities menu
csrutil disable
# Reboot

# Enable DriverKit development mode
systemextensionsctl developer on
```

To re-enable SIP when done:
```bash
# Boot into Recovery Mode
csrutil enable
```

## How It Works

### Driver Architecture

```
┌─────────────────────┐     ┌──────────────────────┐
│   AirCatchHost App  │────▶│  DriverKitClient.swift│
│   (Swift/SwiftUI)   │     │  (IOKit Connection)   │
└─────────────────────┘     └───────────┬───────────┘
                                        │
                                        ▼
                            ┌───────────────────────┐
                            │  AirCatchUserClient   │
                            │  (DriverKit Boundary) │
                            └───────────┬───────────┘
                                        │
                                        ▼
                            ┌───────────────────────┐
                            │  AirCatchDisplayDriver│
                            │  (Virtual Framebuffer)│
                            └───────────┬───────────┘
                                        │
                                        ▼
                            ┌───────────────────────┐
                            │   macOS Display       │
                            │   Subsystem           │
                            │  (Recognizes as       │
                            │   real display)       │
                            └───────────────────────┘
```

### Communication Flow

1. **Host App** calls `DriverKitClient.shared.connectDisplay()`
2. **DriverKitClient** uses IOKit to send command to driver
3. **AirCatchUserClient** receives the command and forwards to driver
4. **AirCatchDisplayDriver** creates a virtual framebuffer
5. **macOS** sees this as a new connected display
6. **ScreenCaptureKit** can now capture this "display"
7. **Video stream** is sent to iPad client

## External Method Reference

| Method | Selector | Input | Output |
|--------|----------|-------|--------|
| ConnectDisplay | 0 | width, height, refreshRate | - |
| DisconnectDisplay | 1 | - | - |
| GetDisplayInfo | 2 | - | width, height, refreshRate, isConnected |
| GetFramebuffer | 3 | - | size, memoryDescriptor |
| UpdateFramebuffer | 4 | offset, length | - |

## Troubleshooting

### "Extension blocked by System Policy"
- Open System Settings → Privacy & Security
- Scroll down and click "Allow" for the blocked extension
- Restart the app

### Driver doesn't appear
- Make sure the .dext is embedded in the app bundle
- Check Console.app for errors with filter: `AirCatch`
- Verify entitlements match between driver and host app

### "Could not communicate with driver"
- Driver may not be running
- Check: `systemextensionsctl list`
- Try reinstalling: `systemextensionsctl uninstall <team-id> com.aircatch.displaydriver`

## Resources

- [Apple DriverKit Documentation](https://developer.apple.com/documentation/driverkit)
- [Creating a DriverKit Driver](https://developer.apple.com/documentation/driverkit/creating_a_driver_using_the_driverkit_sdk)
- [System Extensions Framework](https://developer.apple.com/documentation/systemextensions)
