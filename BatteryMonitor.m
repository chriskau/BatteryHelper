//
//  BatteryMonitor.m
//  BatteryHelper
//
//  Created by Chris Kau on 19/11/2009.
//  Copyright 2009 Chris Kau. All rights reserved.
//

#include <SystemConfiguration/SystemConfiguration.h>

#import "BatteryMonitor.h"
#import "AppDelegate.h"


static SCDynamicStoreRef _dynamicStore;
static CFDictionaryRef _batteryStatus;
static BOOL isPluggedIn;

static CFStringRef kLowBatteryWarningKey = CFSTR("State:/IOKit/LowBatteryWarning");
static CFStringRef kPowerAdapterKey = CFSTR("State:/IOKit/PowerAdapter");
static CFStringRef kInternalBatteryKey = CFSTR("State:/IOKit/PowerSources/InternalBattery-0");


/*
    BatteryHealth = Good;
    "Current Capacity" = 97;
    DesignCycleCount = 1000;
    "Hardware Serial Number" = 9G91903LR4M0A;
    "Is Charging" = 1;
    "Is Finishing Charge" = 0;
    "Is Present" = 1;
    "Max Capacity" = 100;
    Name = "InternalBattery-0";
    "Power Source State" = "AC Power";
    "Time to Empty" = 0;
    "Time to Full Charge" = 16;
    "Transport Type" = Internal;
 */

@interface BatteryMonitor ()
- (void)_lowBatteryWarning:(CFDictionaryRef)newValue;
- (void)_batteryStatusChange:(CFDictionaryRef)newValue;
- (void)_powerAdapterStatusChange:(CFDictionaryRef)newValue;
- (NSInteger)_timeToEmpty:(CFDictionaryRef)dict;
- (NSInteger)_timeToFullCharge:(CFDictionaryRef)dict;
@end


@implementation BatteryMonitor

static void scCallback(SCDynamicStoreRef store, CFArrayRef changedKeys, void *info)
{
	BatteryMonitor *self = info;

	CFIndex count = CFArrayGetCount(changedKeys);
	for (CFIndex i = 0; i < count; ++i) {
		CFStringRef key = CFArrayGetValueAtIndex(changedKeys, i);
        CFDictionaryRef newValue = SCDynamicStoreCopyValue(store, key);
        
        if (CFGetTypeID(newValue) == CFDictionaryGetTypeID()) {        
            if (CFStringCompare(key, kLowBatteryWarningKey, 0) == kCFCompareEqualTo) {
                [self _lowBatteryWarning:newValue];
            }
            else if (CFStringCompare(key, kPowerAdapterKey, 0) == kCFCompareEqualTo) {
                [self _powerAdapterStatusChange:newValue];
            }
            else if (CFStringCompare(key, kInternalBatteryKey, 0) == kCFCompareEqualTo) {
                [self _batteryStatusChange:newValue];
            }
        }

        if (newValue != nil) {
            CFRelease(newValue);            
        }
	}
}

- (id)init
{
    self = [super init];
    
    if (self != nil) {
        _delegate = (AppDelegate *)[NSApp delegate];
        
        SCDynamicStoreContext context = {0, self, NULL, NULL, NULL};
        
        _dynamicStore = SCDynamicStoreCreate(kCFAllocatorDefault,
                                        CFBundleGetIdentifier(CFBundleGetMainBundle()),
                                        scCallback,
                                        &context);
        if (!_dynamicStore) {
            NSLog(@"SCDynamicStoreCreate() failed: %s", SCErrorString(SCError()));
            [self release];
            return nil;
        }
        
        const CFStringRef keys[3] = {
            kLowBatteryWarningKey,
            kPowerAdapterKey,
            kInternalBatteryKey
        };

        CFArrayRef watchedKeys = CFArrayCreate(kCFAllocatorDefault,
                                               (const void **)keys,
                                               3,
                                               &kCFTypeArrayCallBacks);
        
        if (!SCDynamicStoreSetNotificationKeys(_dynamicStore, watchedKeys, NULL)) {
            CFRelease(watchedKeys);
            NSLog(@"SCDynamicStoreSetNotificationKeys() failed: %s", SCErrorString(SCError()));
            CFRelease(_dynamicStore);
            _dynamicStore = NULL;
            
            [self release];
            return nil;
        }

        CFRelease(watchedKeys);
        
        _runLoopSource = SCDynamicStoreCreateRunLoopSource(kCFAllocatorDefault, _dynamicStore, 0);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), _runLoopSource, kCFRunLoopDefaultMode);
        CFRelease(_runLoopSource);
        
        _batteryStatus = SCDynamicStoreCopyValue(_dynamicStore, kInternalBatteryKey);
        [self _batteryStatusChange:_batteryStatus];
        
        // Check if we're running on AC power
        CFStringRef powerSourceState = CFDictionaryGetValue(_batteryStatus, CFSTR("Power Source State"));
        if (CFStringCompare(powerSourceState, CFSTR("AC Power"), 0) == kCFCompareEqualTo) {
            isPluggedIn = YES;
        }
        
        // Check if we're already below the battery empty warning threshold
        int threshold = 10;
        CFNumberRef warningThreshold = CFNumberCreate(NULL, kCFNumberIntType, &threshold);
        CFNumberRef timeToEmpty = CFDictionaryGetValue(_batteryStatus, CFSTR("Time to Empty"));
        if (CFNumberCompare(timeToEmpty, warningThreshold, NULL) == kCFCompareLessThan) {
            [self _lowBatteryWarning:_batteryStatus];
        }
    }
    
    return self;
}

- (void)dealloc
{
    if (_runLoopSource != nil) {
		CFRunLoopRemoveSource(CFRunLoopGetCurrent(), _runLoopSource, kCFRunLoopDefaultMode);
        CFRunLoopSourceInvalidate(_runLoopSource);
    }

	if (_dynamicStore != nil)
		CFRelease(_dynamicStore);
    
    [super dealloc];
}


#pragma mark -
#pragma mark Handle Notifications

- (void)_lowBatteryWarning:(CFDictionaryRef)newValue {
    [_delegate showLowBatteryWarning];
}

- (void)_batteryStatusChange:(CFDictionaryRef)newValue
{
    if (newValue) {
        NSInteger currentCapacity = [[(NSDictionary *)newValue objectForKey:@"Current Capacity"] integerValue];

        if (isPluggedIn) {
            NSInteger timeToFullCharge = [self _timeToFullCharge:newValue];
            if (timeToFullCharge <= 0) return;
            NSInteger hours = timeToFullCharge / 60;
            NSInteger minutes = timeToFullCharge - (hours * 60);
            NSLog(@"Current battery charge: %d%%  Estimated time until full: %d:%02d", currentCapacity, hours, minutes);
        }
        else {
            NSInteger timeToEmpty = [self _timeToEmpty:newValue];
            if (timeToEmpty <= 0) return;
            NSInteger hours = timeToEmpty / 60;
            NSInteger minutes = timeToEmpty - (hours * 60);
            NSLog(@"Current battery charge: %d%%  Estimated time remaining: %d:%02d", currentCapacity, hours, minutes);
            
            if (timeToEmpty <= 10) [_delegate showLowBatteryWarning];
        }
    }
}

- (void)_powerAdapterStatusChange:(CFDictionaryRef)newValue
{
    if (newValue != nil) {
        isPluggedIn = YES;
        
        if ([_delegate isLowBatteryWarningShowing]) {
            [_delegate closeLowBatteryWarning:nil];
        }
    }
    else {
        isPluggedIn = NO;
    }
}

- (NSInteger)_timeToEmpty:(CFDictionaryRef)dict
{
    return [[(NSDictionary *)dict objectForKey:@"Time to Empty"] integerValue];
}

- (NSInteger)_timeToFullCharge:(CFDictionaryRef)dict
{
    [[(NSDictionary *)dict objectForKey:@"Time to Full Charge"] integerValue];
}

@end
