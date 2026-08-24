#import "Analytics.h"

// Block Sentry Crash & Telemetry
%hook SentrySDK
+ (void)startWithOptions:(id)options
{
    [Logger info:LOG_CATEGORY_DEFAULT format:@"Blocked SentrySDK."];
    return;
}

+ (void)startWithConfigureOptions:(id)callback
{
    [Logger info:LOG_CATEGORY_DEFAULT format:@"Blocked SentrySDK."];
    return;
}

+ (BOOL)isEnabled
{
    return NO;
}
%end

// Block Firebase SDK
%hook FIRInstallations
+ (void)load
{
    [Logger info:LOG_CATEGORY_DEFAULT format:@"Blocked Firebase Installations."];
    return;
}
%end

%hook FIRAnalytics
+ (void)logEventWithName:(id)name parameters:(id)params
{
    return;
}
%end

// Block Branch Metrics
%hook Branch
+ (id)getInstance
{
    return nil;
}
+ (id)getTestInstance
{
    return nil;
}
- (void)initSessionWithLaunchOptions:(id)options isReferrable:(BOOL)referrable
{
    return;
}
%end

// Block Adjust SDK
%hook Adjust
+ (void)appDidLaunch:(id)config
{
    return;
}
+ (void)trackEvent:(id)event
{
    return;
}
%end

// Block Braze / Appboy
%hook Appboy
+ (id)sharedInstance
{
    return nil;
}
+ (void)startWithApiKey:(id)apiKey inApplication:(id)app withLaunchOptions:(id)options
{
    return;
}
%end

// Block Facebook App Events
%hook FBSDKAppEvents
+ (void)logEvent:(id)event
{
    return;
}
+ (void)activateApp
{
    return;
}
%end

// Intercept Discord Native Science & Tracking Network Calls
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler
{
    NSString *url = request.URL.absoluteString;
    if (url && ([url containsString:@"/api/v9/science"] || 
                [url containsString:@"/api/v10/science"] || 
                [url containsString:@"/api/science"] || 
                [url containsString:@"/api/v9/track"] || 
                [url containsString:@"/api/v10/track"]))
    {
        if (completionHandler)
        {
            NSHTTPURLResponse *fakeResponse = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                                          statusCode:204
                                                                         HTTPVersion:@"HTTP/1.1"
                                                                        headerFields:@{}];
            completionHandler([NSData data], fakeResponse, nil);
            return (NSURLSessionDataTask *)[[NSURLSessionTask alloc] init];
        }
    }
    return %orig(request, completionHandler);
}

%end

%ctor
{
    %init();
}
