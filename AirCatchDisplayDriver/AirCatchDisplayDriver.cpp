//
//  AirCatchDisplayDriver.cpp
//  AirCatchDisplayDriver
//
//  Created by tejachowdary on 1/9/26.
//

#include <os/log.h>

#include <DriverKit/IOUserServer.h>
#include <DriverKit/IOLib.h>

#include "AirCatchDisplayDriver.h"

kern_return_t
IMPL(AirCatchDisplayDriver, Start)
{
    kern_return_t ret;
    ret = Start(provider, SUPERDISPATCH);
    os_log(OS_LOG_DEFAULT, "Hello World");
    return ret;
}
