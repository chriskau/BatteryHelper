//
//  BatteryMonitor.h
//  BatteryHelper
//
//  Created by Chris Kau on 19/11/2009.
//  Copyright 2009 Chris Kau. All rights reserved.
//

#import <SystemConfiguration/SystemConfiguration.h>
#import "AppDelegate.h"


@interface BatteryMonitor : NSObject {
    CFRunLoopSourceRef _runLoopSource;
    AppDelegate *_delegate;
}

@end
