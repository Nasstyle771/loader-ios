#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "Logger.h"

%hook CADisplayLink

- (void)setPreferredFrameRateRange:(CAFrameRateRange)range
{
    if (@available(iOS 15.0, *))
    {
        %orig(CAFrameRateRangeMake(80.0f, 120.0f, 120.0f));
    }
    else
    {
        %orig(range);
    }
}

%end

%hook UIScrollView

- (void)setDecelerationRate:(UIScrollViewDecelerationRate)decelerationRate
{
    %orig(UIScrollViewDecelerationRateNormal);
}

%end

%ctor
{
    [Logger info:LOG_CATEGORY_DEFAULT format:@"ProMotion 120 FPS hooks initialized."];
}
