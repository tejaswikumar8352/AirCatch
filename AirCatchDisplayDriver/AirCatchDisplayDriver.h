//
//  AirCatchDisplayDriver.h
//  AirCatchDisplayDriver
//
//  DriverKit-based virtual display driver header.
//

#ifndef AirCatchDisplayDriver_h
#define AirCatchDisplayDriver_h

#include <Availability.h>
#include <DriverKit/IOService.iig>
#include <DriverKit/IOUserClient.iig>
#include <DriverKit/IOMemoryDescriptor.iig>

// External method selectors for user client communication
enum AirCatchDisplayDriverExternalMethod : uint64_t {
    kAirCatchDisplayDriverMethodConnectDisplay = 0,
    kAirCatchDisplayDriverMethodDisconnectDisplay = 1,
    kAirCatchDisplayDriverMethodGetDisplayInfo = 2,
    kAirCatchDisplayDriverMethodGetFramebuffer = 3,
    kAirCatchDisplayDriverMethodUpdateFramebuffer = 4,
    kAirCatchDisplayDriverMethodCount
};

// Display configuration structure
struct AirCatchDisplayConfig {
    uint32_t width;
    uint32_t height;
    uint32_t refreshRate;
    uint32_t pixelFormat;  // 0 = BGRA8888
    uint32_t reserved[4];
};

class AirCatchDisplayDriver : public IOService {
public:
    // IOService overrides
    virtual bool init() override;
    virtual void free() override;
    virtual kern_return_t Start(IOService* provider) override;
    virtual kern_return_t Stop(IOService* provider) override;
    virtual kern_return_t NewUserClient(uint32_t type, IOUserClient** userClient) override;
    
    // Display management
    virtual kern_return_t ConnectDisplay(uint32_t width, uint32_t height, uint32_t refreshRate);
    virtual kern_return_t DisconnectDisplay();
    virtual kern_return_t GetDisplayInfo(uint32_t* outWidth, uint32_t* outHeight, 
                                          uint32_t* outRefreshRate, bool* outIsConnected);
    
    // Framebuffer access
    virtual kern_return_t GetFramebuffer(IOMemoryDescriptor** outFramebuffer, uint64_t* outSize);
    virtual kern_return_t UpdateFramebuffer(uint64_t offset, uint64_t length);
};

#endif /* AirCatchDisplayDriver_h */
