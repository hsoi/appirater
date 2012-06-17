/*
 This file is part of Appirater.
 
 Copyright (c) 2012, Arash Payan
 All rights reserved.
 
 Permission is hereby granted, free of charge, to any person
 obtaining a copy of this software and associated documentation
 files (the "Software"), to deal in the Software without
 restriction, including without limitation the rights to use,
 copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the
 Software is furnished to do so, subject to the following
 conditions:
 
 The above copyright notice and this permission notice shall be
 included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 OTHER DEALINGS IN THE SOFTWARE.
 */
/*
 * Appirater.m
 * appirater
 *
 * Created by Arash Payan on 9/5/09.
 * http://arashpayan.com
 * Copyright 2012 Arash Payan. All rights reserved.
 */

#import "Appirater.h"
#import <SystemConfiguration/SCNetworkReachability.h>
#include <netinet/in.h>

NSString *const kAppiraterFirstUseDate				= @"kAppiraterFirstUseDate";
NSString *const kAppiraterUseCount					= @"kAppiraterUseCount";
NSString *const kAppiraterSignificantEventCount		= @"kAppiraterSignificantEventCount";
NSString *const kAppiraterCurrentVersion			= @"kAppiraterCurrentVersion";
NSString *const kAppiraterRatedCurrentVersion		= @"kAppiraterRatedCurrentVersion";
NSString *const kAppiraterDeclinedToRate			= @"kAppiraterDeclinedToRate";
NSString *const kAppiraterReminderRequestDate		= @"kAppiraterReminderRequestDate";

NSString *templateReviewURL = @"itms-apps://ax.itunes.apple.com/WebObjects/MZStore.woa/wa/viewContentsUserReviews?type=Purple+Software&id=APP_ID";

@interface Appirater ()
- (BOOL)connectedToNetwork;
+ (Appirater*)sharedInstance;
- (void)showRatingAlert;
- (BOOL)ratingConditionsHaveBeenMet;
- (void)incrementUseCount;
- (void)hideRatingAlert;
+ (void)appWillResignActive;
@end

@implementation Appirater 

@synthesize ratingAlert;

@dynamic appName;
@dynamic message;
@dynamic messageTitle;
@dynamic cancelButton;
@dynamic rateButton;
@dynamic rateLater;


- (BOOL)connectedToNetwork {
    // Create zero addy
    struct sockaddr_in zeroAddress;
    bzero(&zeroAddress, sizeof(zeroAddress));
    zeroAddress.sin_len = sizeof(zeroAddress);
    zeroAddress.sin_family = AF_INET;
	
    // Recover reachability flags
    SCNetworkReachabilityRef defaultRouteReachability = SCNetworkReachabilityCreateWithAddress(NULL, (struct sockaddr *)&zeroAddress);
    SCNetworkReachabilityFlags flags;
	
    BOOL didRetrieveFlags = SCNetworkReachabilityGetFlags(defaultRouteReachability, &flags);
    CFRelease(defaultRouteReachability);
	
    if (!didRetrieveFlags)
    {
        NSLog(@"Error. Could not recover network reachability flags");
        return NO;
    }
	
    BOOL isReachable = flags & kSCNetworkFlagsReachable;
    BOOL needsConnection = flags & kSCNetworkFlagsConnectionRequired;
	BOOL nonWiFi = flags & kSCNetworkReachabilityFlagsTransientConnection;
	
	NSURL *testURL = [NSURL URLWithString:@"http://www.apple.com/"];
	NSURLRequest *testRequest = [NSURLRequest requestWithURL:testURL  cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20.0];
	NSURLConnection *testConnection = [[[NSURLConnection alloc] initWithRequest:testRequest delegate:self] autorelease];
	
    return ((isReachable && !needsConnection) || nonWiFi) ? (testConnection ? YES : NO) : NO;
}

+ (Appirater*)sharedInstance {
	static Appirater *appirater = nil;
	if (appirater == nil)
	{
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            appirater = [[Appirater alloc] init];
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillResignActive) name:
                UIApplicationWillResignActiveNotification object:nil];
        });
	}
	
	return appirater;
}

- (void)showRatingAlert {
	UIAlertView *alertView = [[[UIAlertView alloc] initWithTitle:self.messageTitle
														 message:self.message
														delegate:self
											   cancelButtonTitle:self.cancelButton
											   otherButtonTitles:self.rateButton, self.rateLater, nil] autorelease];
	self.ratingAlert = alertView;
	[alertView show];
}

- (BOOL)ratingConditionsHaveBeenMet {
	if (APPIRATER_DEBUG)
		return YES;
	
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	
	NSDate *dateOfFirstLaunch = [NSDate dateWithTimeIntervalSince1970:[userDefaults doubleForKey:kAppiraterFirstUseDate]];
	NSTimeInterval timeSinceFirstLaunch = [[NSDate date] timeIntervalSinceDate:dateOfFirstLaunch];
	NSTimeInterval timeUntilRate = 60.0 * 60.0 * 24.0 * ((double)APPIRATER_DAYS_UNTIL_PROMPT);
	if (timeSinceFirstLaunch < timeUntilRate)
		return NO;
	
	// check if the app has been used enough
	NSInteger useCount = [userDefaults integerForKey:kAppiraterUseCount];
	if (useCount <= APPIRATER_USES_UNTIL_PROMPT)
		return NO;
	
	// check if the user has done enough significant events
	int sigEventCount = [userDefaults integerForKey:kAppiraterSignificantEventCount];
	if (sigEventCount <= APPIRATER_SIG_EVENTS_UNTIL_PROMPT)
		return NO;
	
	// has the user previously declined to rate this version of the app?
	if ([userDefaults boolForKey:kAppiraterDeclinedToRate])
		return NO;
	
	// has the user already rated the app?
	if ([userDefaults boolForKey:kAppiraterRatedCurrentVersion])
		return NO;
	
	// if the user wanted to be reminded later, has enough time passed?
	NSDate *reminderRequestDate = [NSDate dateWithTimeIntervalSince1970:[userDefaults doubleForKey:kAppiraterReminderRequestDate]];
	NSTimeInterval timeSinceReminderRequest = [[NSDate date] timeIntervalSinceDate:reminderRequestDate];
	NSTimeInterval timeUntilReminder = 60.0* 60.0 * 24.0 * ((double)APPIRATER_TIME_BEFORE_REMINDING);
	if (timeSinceReminderRequest < timeUntilReminder)
		return NO;
	
	return YES;
}

- (void)incrementUseCount {
	// get the app's version
	NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:(NSString*)kCFBundleVersionKey];
	
	// get the version number that we've been tracking
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	NSString *trackingVersion = [userDefaults stringForKey:kAppiraterCurrentVersion];
	if (trackingVersion == nil)
	{
		trackingVersion = version;
		[userDefaults setObject:version forKey:kAppiraterCurrentVersion];
	}
	
	if (APPIRATER_DEBUG)
		NSLog(@"APPIRATER Tracking version: %@", trackingVersion);
	
	if ([trackingVersion isEqualToString:version])
	{
		// check if the first use date has been set. if not, set it.
		NSTimeInterval timeInterval = [userDefaults doubleForKey:kAppiraterFirstUseDate];
		if (timeInterval == 0)
		{
			timeInterval = [[NSDate date] timeIntervalSince1970];
			[userDefaults setDouble:timeInterval forKey:kAppiraterFirstUseDate];
		}
		
		// increment the use count
		NSInteger useCount = [userDefaults integerForKey:kAppiraterUseCount];
		if (useCount < NSIntegerMax)	// Hsoi 20-Oct-2011 - Mind rollover. If we hit max, it shouldn't matter... just don't roll over else problems will ensue
			useCount++;
		[userDefaults setInteger:useCount forKey:kAppiraterUseCount];
		if (APPIRATER_DEBUG)
			NSLog(@"APPIRATER Use count: %d", useCount);
	}
	else
	{
		// it's a new version of the app, so restart tracking
		[userDefaults setObject:version forKey:kAppiraterCurrentVersion];
		[userDefaults setDouble:[[NSDate date] timeIntervalSince1970] forKey:kAppiraterFirstUseDate];
		[userDefaults setInteger:1 forKey:kAppiraterUseCount];
		[userDefaults setInteger:0 forKey:kAppiraterSignificantEventCount];
		[userDefaults setBool:NO forKey:kAppiraterRatedCurrentVersion];
		[userDefaults setBool:NO forKey:kAppiraterDeclinedToRate];
		[userDefaults setDouble:0 forKey:kAppiraterReminderRequestDate];
	}
	
	[userDefaults synchronize];
}

- (void)incrementSignificantEventCount {
	// get the app's version
	NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:(NSString*)kCFBundleVersionKey];
	
	// get the version number that we've been tracking
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	NSString *trackingVersion = [userDefaults stringForKey:kAppiraterCurrentVersion];
	if (trackingVersion == nil)
	{
		trackingVersion = version;
		[userDefaults setObject:version forKey:kAppiraterCurrentVersion];
	}
	
	if (APPIRATER_DEBUG)
		NSLog(@"APPIRATER Tracking version: %@", trackingVersion);
	
	if ([trackingVersion isEqualToString:version])
	{
		// check if the first use date has been set. if not, set it.
		NSTimeInterval timeInterval = [userDefaults doubleForKey:kAppiraterFirstUseDate];
		if (timeInterval == 0)
		{
			timeInterval = [[NSDate date] timeIntervalSince1970];
			[userDefaults setDouble:timeInterval forKey:kAppiraterFirstUseDate];
		}
		
		// increment the significant event count
		NSInteger sigEventCount = [userDefaults integerForKey:kAppiraterSignificantEventCount];
		if (sigEventCount < NSIntegerMax) // Hsoi 20-Oct-2011 - Mind rollover. If we hit max, it shouldn't matter... just don't roll over else problems will ensue
			sigEventCount++;
		[userDefaults setInteger:sigEventCount forKey:kAppiraterSignificantEventCount];
		if (APPIRATER_DEBUG)
			NSLog(@"APPIRATER Significant event count: %d", sigEventCount);
	}
	else
	{
		// it's a new version of the app, so restart tracking
		[userDefaults setObject:version forKey:kAppiraterCurrentVersion];
		[userDefaults setDouble:0 forKey:kAppiraterFirstUseDate];
		[userDefaults setInteger:0 forKey:kAppiraterUseCount];
		[userDefaults setInteger:1 forKey:kAppiraterSignificantEventCount];
		[userDefaults setBool:NO forKey:kAppiraterRatedCurrentVersion];
		[userDefaults setBool:NO forKey:kAppiraterDeclinedToRate];
		[userDefaults setDouble:0 forKey:kAppiraterReminderRequestDate];
	}
	
	[userDefaults synchronize];
}

- (void)incrementAndRate:(BOOL)canPromptForRating {
	[self incrementUseCount];
	
	if (canPromptForRating &&
		[self ratingConditionsHaveBeenMet] &&
		[self connectedToNetwork])
	{
        dispatch_async(dispatch_get_main_queue(),
                       ^{
                           [self showRatingAlert];
                       });
	}
}

- (void)incrementSignificantEventAndRate:(BOOL)canPromptForRating {
	[self incrementSignificantEventCount];
	
	if (canPromptForRating &&
		[self ratingConditionsHaveBeenMet] &&
		[self connectedToNetwork])
	{
        dispatch_async(dispatch_get_main_queue(),
                       ^{
                           [self showRatingAlert];
                       });
	}
}

+ (void)appLaunched {
	[Appirater appLaunched:YES];
}

+ (void)appLaunched:(BOOL)canPromptForRating {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0),
                   ^{
                       [[Appirater sharedInstance] incrementAndRate:canPromptForRating];
                   });
}

- (void)hideRatingAlert {
	if (self.ratingAlert.visible) {
		if (APPIRATER_DEBUG)
			NSLog(@"APPIRATER Hiding Alert");
		[self.ratingAlert dismissWithClickedButtonIndex:-1 animated:NO];
	}	
}

+ (void)appWillResignActive {
	if (APPIRATER_DEBUG)
		NSLog(@"APPIRATER appWillResignActive");
	[[Appirater sharedInstance] hideRatingAlert];
}

+ (void)appEnteredForeground:(BOOL)canPromptForRating {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0),
                   ^{
                       [[Appirater sharedInstance] incrementAndRate:canPromptForRating];
                   });
}

+ (void)userDidSignificantEvent:(BOOL)canPromptForRating {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0),
                   ^{
                       [[Appirater sharedInstance] incrementSignificantEventAndRate:canPromptForRating];
                   });
}

+ (void)rateApp {
#if TARGET_IPHONE_SIMULATOR
	NSLog(@"APPIRATER NOTE: iTunes App Store is not supported on the iOS simulator. Unable to open App Store page.");
#else
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	NSString *reviewURL = [templateReviewURL stringByReplacingOccurrencesOfString:@"APP_ID" withString:[NSString stringWithFormat:@"%d", APPIRATER_APP_ID]];
	[userDefaults setBool:YES forKey:kAppiraterRatedCurrentVersion];
	[userDefaults synchronize];
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:reviewURL]];
#endif
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
#pragma unused(alertView)

	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	
	switch (buttonIndex) {
		case 0:
		{
			// they don't want to rate it
			[userDefaults setBool:YES forKey:kAppiraterDeclinedToRate];
			[userDefaults synchronize];
			break;
		}
		case 1:
		{
			// they want to rate it
			[Appirater rateApp];
			break;
		}
		case 2:
			// remind them later
			[userDefaults setDouble:[[NSDate date] timeIntervalSince1970] forKey:kAppiraterReminderRequestDate];
			[userDefaults synchronize];
			break;
		default:
			break;
	}
}


#pragma mark -
#pragma mark --- Accessors ---

- (NSString*)appName
{
	NSString*	theString = appName;
	if (theString == nil)
	{
		// Hsoi 20-Oct-2011 - A typical "setAppName" might be to use something other than the kCFBundleNameKey
		theString = [[[NSBundle mainBundle] infoDictionary] objectForKey:(NSString*)kCFBundleNameKey];
	}
	
	return theString;
}

- (void)setAppName:(NSString*)inString
{
	[appName release];
	appName = [inString copy];
}


- (NSString*)message
{
	NSString*	theString = message;
	if (theString == nil)
	{
		theString = [NSString stringWithFormat:NSLocalizedStringFromTable(@"If you enjoy using %@, would you mind taking a moment to rate it? It won't take more than a minute. Thanks for your support!", @"Appirater", nil), self.appName];
	}
	
	return theString;
}

- (void)setMessage:(NSString*)inString
{
	[message release];
	message = [inString copy];
}


- (NSString*)messageTitle
{
	NSString*	theString = messageTitle;
	if (theString == nil)
	{
		theString = [NSString stringWithFormat:NSLocalizedStringFromTable(@"Rate %@", @"Appirater", nil), self.appName];
	}
	
	return theString;
}

- (void)setMessageTitle:(NSString*)inString
{
	[messageTitle release];
	messageTitle = [inString copy];
}


- (NSString*)cancelButton
{
	NSString*	theString = cancelButton;
	if (theString == nil)
	{
		theString = NSLocalizedStringFromTable(@"No, Thanks", @"Appirater", nil);
	}
	
	return theString;
}

- (void)setCancelButton:(NSString*)inString
{
	[cancelButton release];
	cancelButton = [inString copy];
}


- (NSString*)rateButton
{
	NSString*	theString = rateButton;
	if (theString == nil)
	{
		theString = [NSString stringWithFormat:NSLocalizedStringFromTable(@"Rate %@", @"Appirater", nil), self.appName];
	}
	
	return theString;
}

- (void)setRateButton:(NSString*)inString
{
	[rateButton release];
	rateButton = [inString copy];
}



- (NSString*)rateLater
{
	NSString*	theString = rateLater;
	if (theString == nil)
	{
		theString = NSLocalizedStringFromTable(@"Remind me later, @"Appirater", nil);
	}
	
	return theString;
}

- (void)setRateLater:(NSString*)inString
{
	[rateLater release];
	rateLater = [inString copy];
}



@end