//
//  HeadlessTestAppDelegate.m
//  BatteryHelper
//
//  Created by Chris Kau on 19/11/2009.
//  Copyright 2009 Chris Kau. All rights reserved.
//

#import "AppDelegate.h"
#import "BatteryMonitor.h"


@implementation AppDelegate

@synthesize window;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    BatteryMonitor *monitor = [[BatteryMonitor alloc] init];
}

- (void)showLowBatteryWarning {
    if (![self isLowBatteryWarningShowing]) {
        [window setLevel:NSStatusWindowLevel];
        [window center];
        isLowBatteryWarningAlertShowing = YES;
        [window makeKeyAndOrderFront:nil];
    }
}

- (IBAction)closeLowBatteryWarning:(id)sender
{
    isLowBatteryWarningAlertShowing = NO;
    [window orderOut:nil];
}

- (BOOL)isLowBatteryWarningShowing
{
    return isLowBatteryWarningAlertShowing;
}


@end
