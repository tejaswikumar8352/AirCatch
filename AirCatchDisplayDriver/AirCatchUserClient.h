//
//  AirCatchUserClient.h
//  AirCatchDisplayDriver
//
//  User client header for app-driver communication.
//

#ifndef AirCatchUserClient_h
#define AirCatchUserClient_h

#include <DriverKit/IOUserClient.iig>

// Forward declaration
class AirCatchDisplayDriver;

class AirCatchUserClient : public IOUserClient {
public:
    virtual bool init() override;
    virtual void free() override;
    virtual kern_return_t Start(IOService* provider) override;
    virtual kern_return_t Stop(IOService* provider) override;
    virtual kern_return_t ExternalMethod(uint64_t selector,
                                          IOUserClientMethodArguments* arguments,
                                          const IOUserClientMethodDispatch* dispatch,
                                          OSObject* target,
                                          void* reference) override;
    virtual kern_return_t ClientClose();
};

#endif /* AirCatchUserClient_h */
