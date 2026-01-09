//
//  AirCatchUserClient.cpp
//  AirCatchDisplayDriver
//
//  User client implementation for app-driver communication.
//

#include <os/log.h>
#include <DriverKit/IOUserServer.h>
#include <DriverKit/IOLib.h>
#include <DriverKit/IOBufferMemoryDescriptor.h>

#include "AirCatchUserClient.h"
#include "AirCatchDisplayDriver.h"

#define LOG_PREFIX "AirCatchUserClient"

struct AirCatchUserClient_IVars {
    AirCatchDisplayDriver* driver;
    bool isOpen;
};

// MARK: - Method Dispatch Table

static kern_return_t ExternalMethodConnectDisplay(OSObject* target, void* reference,
                                                   IOUserClientMethodArguments* arguments);
static kern_return_t ExternalMethodDisconnectDisplay(OSObject* target, void* reference,
                                                      IOUserClientMethodArguments* arguments);
static kern_return_t ExternalMethodGetDisplayInfo(OSObject* target, void* reference,
                                                   IOUserClientMethodArguments* arguments);
static kern_return_t ExternalMethodGetFramebuffer(OSObject* target, void* reference,
                                                   IOUserClientMethodArguments* arguments);
static kern_return_t ExternalMethodUpdateFramebuffer(OSObject* target, void* reference,
                                                      IOUserClientMethodArguments* arguments);

static const IOUserClientMethodDispatch sMethods[kAirCatchDisplayDriverMethodCount] = {
    // kAirCatchDisplayDriverMethodConnectDisplay
    {
        .function = ExternalMethodConnectDisplay,
        .checkCompletionExists = false,
        .checkScalarInputCount = 3,  // width, height, refreshRate
        .checkStructureInputSize = 0,
        .checkScalarOutputCount = 0,
        .checkStructureOutputSize = 0,
    },
    // kAirCatchDisplayDriverMethodDisconnectDisplay
    {
        .function = ExternalMethodDisconnectDisplay,
        .checkCompletionExists = false,
        .checkScalarInputCount = 0,
        .checkStructureInputSize = 0,
        .checkScalarOutputCount = 0,
        .checkStructureOutputSize = 0,
    },
    // kAirCatchDisplayDriverMethodGetDisplayInfo
    {
        .function = ExternalMethodGetDisplayInfo,
        .checkCompletionExists = false,
        .checkScalarInputCount = 0,
        .checkStructureInputSize = 0,
        .checkScalarOutputCount = 4,  // width, height, refreshRate, isConnected
        .checkStructureOutputSize = 0,
    },
    // kAirCatchDisplayDriverMethodGetFramebuffer
    {
        .function = ExternalMethodGetFramebuffer,
        .checkCompletionExists = false,
        .checkScalarInputCount = 0,
        .checkStructureInputSize = 0,
        .checkScalarOutputCount = 1,  // framebuffer size
        .checkStructureOutputSize = 0,
    },
    // kAirCatchDisplayDriverMethodUpdateFramebuffer
    {
        .function = ExternalMethodUpdateFramebuffer,
        .checkCompletionExists = false,
        .checkScalarInputCount = 2,  // offset, length
        .checkStructureInputSize = 0,
        .checkScalarOutputCount = 0,
        .checkStructureOutputSize = 0,
    },
};

// MARK: - Initialization

bool AirCatchUserClient::init() {
    os_log(OS_LOG_DEFAULT, LOG_PREFIX ": init called");
    
    if (!super::init()) {
        return false;
    }
    
    ivars = IONewZero(AirCatchUserClient_IVars, 1);
    if (!ivars) {
        return false;
    }
    
    ivars->driver = nullptr;
    ivars->isOpen = false;
    
    return true;
}

void AirCatchUserClient::free() {
    os_log(OS_LOG_DEFAULT, LOG_PREFIX ": free called");
    
    if (ivars) {
        IOSafeDeleteNULL(ivars, AirCatchUserClient_IVars, 1);
    }
    
    super::free();
}

// MARK: - Lifecycle

kern_return_t IMPL(AirCatchUserClient, Start) {
    os_log(OS_LOG_DEFAULT, LOG_PREFIX ": Start called");
    
    kern_return_t ret = Start(provider, SUPERDISPATCH);
    if (ret != kIOReturnSuccess) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX ": super::Start failed: 0x%x", ret);
        return ret;
    }
    
    // Get reference to our parent driver
    ivars->driver = OSDynamicCast(AirCatchDisplayDriver, provider);
    if (!ivars->driver) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX ": Failed to get driver reference");
        return kIOReturnError;
    }
    
    ivars->isOpen = true;
    
    os_log(OS_LOG_DEFAULT, LOG_PREFIX ": Start completed successfully");
    return kIOReturnSuccess;
}

kern_return_t IMPL(AirCatchUserClient, Stop) {
    os_log(OS_LOG_DEFAULT, LOG_PREFIX ": Stop called");
    
    ivars->isOpen = false;
    ivars->driver = nullptr;
    
    return Stop(provider, SUPERDISPATCH);
}

kern_return_t AirCatchUserClient::ClientClose() {
    os_log(OS_LOG_DEFAULT, LOG_PREFIX ": ClientClose called");
    
    ivars->isOpen = false;
    
    // Terminate the user client
    kern_return_t ret = Terminate(0);
    if (ret != kIOReturnSuccess) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX ": Terminate failed: 0x%x", ret);
    }
    
    return ret;
}

// MARK: - External Method Dispatch

kern_return_t IMPL(AirCatchUserClient, ExternalMethod) {
    os_log(OS_LOG_DEFAULT, LOG_PREFIX ": ExternalMethod called, selector=%llu", selector);
    
    if (selector >= kAirCatchDisplayDriverMethodCount) {
        return kIOReturnBadArgument;
    }
    
    return ExternalMethod(selector, arguments, &sMethods[selector], this, nullptr);
}

// MARK: - External Method Implementations

static kern_return_t ExternalMethodConnectDisplay(OSObject* target, void* reference,
                                                   IOUserClientMethodArguments* arguments) {
    AirCatchUserClient* client = OSDynamicCast(AirCatchUserClient, target);
    if (!client || !client->ivars->driver) {
        return kIOReturnError;
    }
    
    uint32_t width = (uint32_t)arguments->scalarInput[0];
    uint32_t height = (uint32_t)arguments->scalarInput[1];
    uint32_t refreshRate = (uint32_t)arguments->scalarInput[2];
    
    os_log(OS_LOG_DEFAULT, LOG_PREFIX ": ConnectDisplay %ux%u @ %uHz", width, height, refreshRate);
    
    return client->ivars->driver->ConnectDisplay(width, height, refreshRate);
}

static kern_return_t ExternalMethodDisconnectDisplay(OSObject* target, void* reference,
                                                      IOUserClientMethodArguments* arguments) {
    AirCatchUserClient* client = OSDynamicCast(AirCatchUserClient, target);
    if (!client || !client->ivars->driver) {
        return kIOReturnError;
    }
    
    os_log(OS_LOG_DEFAULT, LOG_PREFIX ": DisconnectDisplay");
    
    return client->ivars->driver->DisconnectDisplay();
}

static kern_return_t ExternalMethodGetDisplayInfo(OSObject* target, void* reference,
                                                   IOUserClientMethodArguments* arguments) {
    AirCatchUserClient* client = OSDynamicCast(AirCatchUserClient, target);
    if (!client || !client->ivars->driver) {
        return kIOReturnError;
    }
    
    uint32_t width, height, refreshRate;
    bool isConnected;
    
    kern_return_t ret = client->ivars->driver->GetDisplayInfo(&width, &height, &refreshRate, &isConnected);
    if (ret != kIOReturnSuccess) {
        return ret;
    }
    
    arguments->scalarOutput[0] = width;
    arguments->scalarOutput[1] = height;
    arguments->scalarOutput[2] = refreshRate;
    arguments->scalarOutput[3] = isConnected ? 1 : 0;
    
    return kIOReturnSuccess;
}

static kern_return_t ExternalMethodGetFramebuffer(OSObject* target, void* reference,
                                                   IOUserClientMethodArguments* arguments) {
    AirCatchUserClient* client = OSDynamicCast(AirCatchUserClient, target);
    if (!client || !client->ivars->driver) {
        return kIOReturnError;
    }
    
    IOMemoryDescriptor* framebuffer = nullptr;
    uint64_t size = 0;
    
    kern_return_t ret = client->ivars->driver->GetFramebuffer(&framebuffer, &size);
    if (ret != kIOReturnSuccess) {
        return ret;
    }
    
    // Return the memory descriptor to the client
    arguments->structureOutput = framebuffer;
    arguments->scalarOutput[0] = size;
    
    return kIOReturnSuccess;
}

static kern_return_t ExternalMethodUpdateFramebuffer(OSObject* target, void* reference,
                                                      IOUserClientMethodArguments* arguments) {
    AirCatchUserClient* client = OSDynamicCast(AirCatchUserClient, target);
    if (!client || !client->ivars->driver) {
        return kIOReturnError;
    }
    
    uint64_t offset = arguments->scalarInput[0];
    uint64_t length = arguments->scalarInput[1];
    
    return client->ivars->driver->UpdateFramebuffer(offset, length);
}
