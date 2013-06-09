#import <UIKit/UIKit.h>

#import <PebbleKit/PebbleKit.h>
#import <libactivator/libactivator.h>
#import <StoreKit/StoreKit.h>
#import <objc/runtime.h>

#import "common.h"

#define PAEventNameTopButton @"com.rpetrich.pebbleactivator.top-button"
#define PAEventNameMiddleButton @"com.rpetrich.pebbleactivator.middle-button"
#define PAEventNameBottomButton @"com.rpetrich.pebbleactivator.bottom-button"

@interface PebbleSettingsViewController : LASettingsViewController
@end

@implementation PebbleSettingsViewController

- (id)init
{
	if ((self = [super init])) {
		self.navigationItem.title = @"PebbleActivator";
	}
	return self;
}

- (NSString *)eventNameForIndexPath:(NSIndexPath *)indexPath
{
	switch (indexPath.row) {
		case 0:
			return PAEventNameTopButton;
		case 1:
			return PAEventNameMiddleButton;
		case 2:
			return PAEventNameBottomButton;
		default:
			return nil;
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	return @"Button Events";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return 3;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
	NSString *eventName = [self eventNameForIndexPath:indexPath];
	cell.textLabel.text = [LASharedActivator localizedTitleForEventName:eventName];
	cell.detailTextLabel.text = [LASharedActivator localizedDescriptionForEventName:eventName];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	[super tableView:tableView didSelectRowAtIndexPath:indexPath];
	NSString *eventName = [self eventNameForIndexPath:indexPath];
	UIViewController *vc = [[LAEventSettingsController alloc] initWithModes:LASharedActivator.availableEventModes eventName:eventName];
	[self.navigationController pushViewController:vc animated:YES];
	[vc release];
}

@end

@interface PebbleActivatorAppDelegate : NSObject<UIApplicationDelegate, PBPebbleCentralDelegate, SKStoreProductViewControllerDelegate> {
@private
	UIWindow *window;
	UINavigationController *navigationController;
	UIViewController *viewController;
	NSMutableDictionary *connectedWatches;
	BOOL (^updateHandler)(PBWatch *watch, NSDictionary *update);
}

- (void)connectToWatch:(PBWatch *)watch;
- (void)disconnectFromWatch:(PBWatch *)watch;
@property (nonatomic, readonly) NSArray *connectedWatches;
- (void)pushListenerTitlesToWatch:(PBWatch *)watch;

- (void)installLatestVersionOfApp;

@end

@implementation PebbleActivatorAppDelegate

- (id)init
{
	if ((self = [super init])) {
		window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
		navigationController = [[UINavigationController alloc] init];
		viewController = [[PebbleSettingsViewController alloc] init];
		connectedWatches = [[NSMutableDictionary alloc] init];
		updateHandler = [^(PBWatch *watch, NSDictionary *update) {
			NSLog(@"Recieved Update: %@", update);
			id returnVersion = [update objectForKey:@(WATCH_RETURN_VERSION)];
			if (returnVersion) {
				[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(versionRequestTimedOutForWatch:) object:watch];
				if ([returnVersion integerValue] != WATCH_VERSION_CURRENT) {
					[self disconnectFromWatch:watch];
					[self installLatestVersionOfApp];
					return YES;
				}
			}
			id keyPressed = [update objectForKey:@(WATCH_KEY_PRESSED)];
			if (keyPressed) {
				NSString *eventName;
				switch ([keyPressed integerValue]) {
					case WATCH_KEY_PRESSED_UP:
						eventName = PAEventNameTopButton;
						break;
					case WATCH_KEY_PRESSED_SELECT:
						eventName = PAEventNameMiddleButton;
						break;
					case WATCH_KEY_PRESSED_DOWN:
						eventName = PAEventNameBottomButton;
						break;
					default:
						eventName = nil;
						break;
				}
				if (eventName) {
					NSLog(@"Sending event %@", eventName);
					[LASharedActivator sendEventToListener:[LAEvent eventWithName:eventName mode:LASharedActivator.currentEventMode]];
				}
			}
			if ([update objectForKey:@(WATCH_REQUEST_TEXT)]) {
				[self pushListenerTitlesToWatch:watch];
			}
			return YES;
		} copy];
	}
	return self;
}

- (void)dealloc
{
	[updateHandler release];
	[connectedWatches release];
	[viewController release];
	[navigationController release];
	[window release];
	[super dealloc];
}

- (void)applicationDidFinishLaunching:(UIApplication *)application
{
	if ([window respondsToSelector:@selector(setRootViewController:)])
		[window setRootViewController:navigationController];
	else
		[window addSubview:navigationController.view];
	[application beginBackgroundTaskWithExpirationHandler:^{
		NSLog(@"Background task expiration!");
	}];
	[navigationController pushViewController:viewController animated:NO];
	[window makeKeyAndVisible];
	[[PBPebbleCentral defaultCentral] setDelegate:self];
	for (PBWatch *watch in [PBPebbleCentral defaultCentral].connectedWatches) {
		[self connectToWatch:watch];
	}
}

- (void)installLatestVersionOfApp
{
	id app = [objc_getClass("LSApplicationProxy") applicationProxyForIdentifier:@"com.getpebble.ios"];
	if (!app) {
		SKStoreProductViewController *pvc = [[[SKStoreProductViewController alloc] init] autorelease];
		pvc.delegate = self;
		[pvc loadProductWithParameters:@{ SKStoreProductParameterITunesItemIdentifier: @"592012721" } completionBlock:^(BOOL result, NSError *error) {
			if (result) {
				[viewController presentModalViewController:pvc animated:YES];
			}
		}];
	} else {
		UIDocumentInteractionController *dic = [UIDocumentInteractionController interactionControllerWithURL:[[NSBundle mainBundle] URLForResource:@"activator" withExtension:@"pbw"]];
		dic.UTI = @"com.getpebble.bundle.watchface";
		[dic _openDocumentWithApplication:app];
	}
}

- (void)versionRequestTimedOutForWatch:(PBWatch *)watch
{
	[self disconnectFromWatch:watch];
	[self installLatestVersionOfApp];
}

- (void)launchAppOrInstallOnWatch:(PBWatch *)watch
{
	[watch appMessagesLaunch:^(PBWatch *watch, NSError *error) {
		[self performSelector:@selector(versionRequestTimedOutForWatch:) withObject:watch afterDelay:1.0];
		[watch appMessagesPushUpdate:@{ @(ACTIVATOR_REQUEST_VERSION): @(WATCH_VERSION_CURRENT) } onSent:^(PBWatch *watch, NSDictionary *update, NSError *error) {
			if (error) {
				[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(versionRequestTimedOutForWatch:) object:watch];
				[self disconnectFromWatch:watch];
				[self installLatestVersionOfApp];
			}
		}];
	}];
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
	for (PBWatch *watch in [PBPebbleCentral defaultCentral].connectedWatches) {
		[self connectToWatch:watch];
	}
	for (PBWatch *watch in self.connectedWatches) {
		[self launchAppOrInstallOnWatch:watch];
	}
}

- (void)connectToWatch:(PBWatch *)watch
{
	if ([connectedWatches objectForKey:@[watch]])
		return;
	[watch appMessagesGetIsSupported:^(PBWatch *watch, BOOL isAppMessagesSupported) {
		if (isAppMessagesSupported) {
			if ([connectedWatches objectForKey:@[watch]])
				return;
			static uint8_t bytes[] = MY_UUID;
			NSData *uuid = [NSData dataWithBytesNoCopy:bytes length:sizeof(bytes) freeWhenDone:NO];
			[watch appMessagesSetUUID:uuid];
			id handle = [watch appMessagesAddReceiveUpdateHandler:updateHandler];
			[connectedWatches setObject:handle forKey:@[watch]];
			NSLog(@"Connected to watch: %@", watch);
			if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
				[self launchAppOrInstallOnWatch:watch];
			}
			[self pushListenerTitlesToWatch:watch];
		}
	}];
}

- (void)disconnectFromWatch:(PBWatch *)watch
{
	id handle = [connectedWatches objectForKey:@[watch]];
	if (handle) {
		[watch appMessagesRemoveUpdateHandler:handle];
		[connectedWatches removeObjectForKey:@[watch]];
		NSLog(@"Disconnected from watch: %@", watch);
	}
}

- (NSArray *)connectedWatches
{
	NSMutableArray *result = [NSMutableArray array];
	for (NSArray *key in connectedWatches) {
		[result addObject:key[0]];
	}
	return result;
}

static inline NSString *AssignedListenerTitleForEvent(NSString *eventName, NSString *eventMode)
{
	LAEvent *event = [LAEvent eventWithName:eventName mode:eventMode];
	NSString *listenerName = [LASharedActivator assignedListenerNameForEvent:event];
	if (!listenerName)
		return @"(unassigned)";
	return [LASharedActivator localizedTitleForListenerName:listenerName] ?: @"";
}

- (void)pushListenerTitlesToWatch:(PBWatch *)watch
{
	NSString *eventMode = LASharedActivator.currentEventMode;
	NSDictionary *update = @{
		@(ACTIVATOR_SET_TEXT): AssignedListenerTitleForEvent(PAEventNameTopButton, eventMode),
		@(ACTIVATOR_SET_TEXT_MIDDLE): AssignedListenerTitleForEvent(PAEventNameMiddleButton, eventMode),
		@(ACTIVATOR_SET_TEXT_BOTTOM): AssignedListenerTitleForEvent(PAEventNameBottomButton, eventMode)
	};
	[watch appMessagesPushUpdate:update onSent:NULL];
}

// PBPebbleCentralDelegate

- (void)pebbleCentral:(PBPebbleCentral *)central watchDidConnect:(PBWatch *)watch isNew:(BOOL)isNew
{
	[self connectToWatch:watch];
}

- (void)pebbleCentral:(PBPebbleCentral *)central watchDidDisconnect:(PBWatch *)watch
{
	[self disconnectFromWatch:watch];
}

// SKStoreProductViewControllerDelegate

- (void)productViewControllerDidFinish:(SKStoreProductViewController *)storeController
{
	[storeController.presentingViewController dismissModalViewControllerAnimated:YES];
}

@end

int main(int argc, char *argv[])
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int result = UIApplicationMain(argc, argv, nil, @"PebbleActivatorAppDelegate");
    [pool drain];
    return result;
}
