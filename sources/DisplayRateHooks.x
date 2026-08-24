#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "Logger.h"

@interface RCTDisplayLink : NSObject
@end

static const float kMin120FrameRate = 80.0f;
static const float kPreferred120FrameRate = 120.0f;
static const float kMax120FrameRate = 120.0f;

%hook CADisplayLink

- (void)setPreferredFrameRateRange:(CAFrameRateRange)range
{
    if (@available(iOS 15.0, *))
    {
        CAFrameRateRange proMotionRange = CAFrameRateRangeMake(kMin120FrameRate,
                                                              kPreferred120FrameRate,
                                                              kMax120FrameRate);
        %orig(proMotionRange);
    }
    else
    {
        %orig(range);
    }
}

- (void)setPreferredFramesPerSecond:(NSInteger)preferredFramesPerSecond
{
    %orig(120);
}

%end

%hook UIScreen

- (NSInteger)maximumFramesPerSecond
{
    NSInteger orig = %orig;
    return orig > 60 ? orig : 120;
}

%end

%hook UIScrollView

- (void)setDecelerationRate:(UIScrollViewDecelerationRate)decelerationRate
{
    %orig(UIScrollViewDecelerationRateNormal);
}

%end

// Uncap React Native internal display link timer if available
%hook RCTDisplayLink

- (void)registerModuleForFrameUpdates:(id)module
{
    %orig;
    Ivar displayLinkIvar = class_getInstanceVariable([self class], "_displayLink");
    if (displayLinkIvar)
    {
        CADisplayLink *displayLink = (CADisplayLink *)object_getIvar(self, displayLinkIvar);
        if (displayLink)
        {
            if (@available(iOS 15.0, *))
            {
                [displayLink setPreferredFrameRateRange:CAFrameRateRangeMake(kMin120FrameRate,
                                                                             kPreferred120FrameRate,
                                                                             kMax120FrameRate)];
            }
        }
    }
}

%end

%ctor
{
    [Logger info:LOG_CATEGORY_DEFAULT format:@"ProMotion 120 FPS engine initialized."];
}
