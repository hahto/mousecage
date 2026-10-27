#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>

#include "core.h"

static NSString *const kTargetOwnerName   = @"League Of Legends";
static NSString *const kEnabledDefaultKey = @"enabled";
static NSString *const kAccessibilitySettingsURL =
    @"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility";

typedef NS_ENUM(NSInteger, AppStatus) {
    AppStatusUnknown,
    AppStatusNoPermission,
    AppStatusThreadError,
    AppStatusDisabled,
    AppStatusWaiting,
    AppStatusLocked,
};

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong) NSStatusItem *statusItem;
@property (strong) NSMenuItem *statusMenuItem;
@property (strong) NSMenuItem *enabledMenuItem;
@property (strong) NSMenuItem *permissionMenuItem;
@property (strong) NSTimer *refreshTimer;
@property (assign) BOOL coreRunning;
@property (assign) BOOL threadFailed;
@property (assign) AppStatus shownStatus;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults registerDefaults:@{ kEnabledDefaultKey: @YES }];
    ml_set_enabled([defaults boolForKey:kEnabledDefaultKey]);

    self.statusItem = [[NSStatusBar systemStatusBar]
        statusItemWithLength:NSVariableStatusItemLength];
    [self buildMenu];

    // Shows the system "grant Accessibility access" prompt once if needed.
    // After that, refresh: keeps retrying until the user flips the switch.
    NSDictionary *options = @{ (__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES };
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);

    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                         target:self
                                                       selector:@selector(refresh:)
                                                       userInfo:nil
                                                        repeats:YES];
    self.refreshTimer.tolerance = 0.2;
    [self refresh:nil];
}

- (void)buildMenu {
    NSMenu *menu = [[NSMenu alloc] init];

    // No action -> greyed out, works as a status line.
    self.statusMenuItem = [[NSMenuItem alloc] initWithTitle:@""
                                                     action:nil
                                              keyEquivalent:@""];
    [menu addItem:self.statusMenuItem];

    self.permissionMenuItem = [[NSMenuItem alloc] initWithTitle:@"Open Accessibility Settings…"
                                                         action:@selector(openAccessibilitySettings:)
                                                  keyEquivalent:@""];
    self.permissionMenuItem.target = self;
    [menu addItem:self.permissionMenuItem];

    [menu addItem:[NSMenuItem separatorItem]];

    self.enabledMenuItem = [[NSMenuItem alloc] initWithTitle:@"Enabled"
                                                      action:@selector(toggleEnabled:)
                                               keyEquivalent:@""];
    self.enabledMenuItem.target = self;
    [menu addItem:self.enabledMenuItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSString *version = [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"];
    NSMenuItem *versionItem = [[NSMenuItem alloc]
        initWithTitle:[NSString stringWithFormat:@"Mouselock %@", version ?: @"dev"]
               action:nil
        keyEquivalent:@""];
    [menu addItem:versionItem];

    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Quit"
                                             action:@selector(terminate:)
                                      keyEquivalent:@"q"]];

    self.statusItem.menu = menu;
}

- (void)tryStartCore {
    if (self.coreRunning)
        return;
    // Cheap to call repeatedly: fails fast in CGEventTapCreate until access is granted.
    ml_result result = ml_start(kTargetOwnerName.UTF8String);
    self.coreRunning  = (result == ML_OK);
    self.threadFailed = (result == ML_ERR_THREAD);
}

- (AppStatus)currentStatus {
    if (!self.coreRunning)
        return self.threadFailed ? AppStatusThreadError : AppStatusNoPermission;
    if (!ml_is_enabled())
        return AppStatusDisabled;
    return ml_is_target_focused() ? AppStatusLocked : AppStatusWaiting;
}

- (void)refresh:(NSTimer *)timer {
    [self tryStartCore];

    AppStatus status = [self currentStatus];
    if (status == self.shownStatus)
        return;
    self.shownStatus = status;

    NSString *symbolName;
    NSString *statusText;
    switch (status) {
    case AppStatusNoPermission:
        symbolName = @"exclamationmark.triangle";
        statusText = @"Needs Accessibility access";
        break;
    case AppStatusThreadError:
        symbolName = @"exclamationmark.triangle";
        statusText = @"Failed to start, try relaunching";
        break;
    case AppStatusDisabled:
        symbolName = @"cursorarrow.slash";
        statusText = @"Disabled: Not listening";
        break;
    case AppStatusWaiting:
        symbolName = @"cursorarrow";
        statusText = [NSString stringWithFormat:@"Waiting for %@", kTargetOwnerName];
        break;
    case AppStatusLocked:
    case AppStatusUnknown:
        symbolName = @"cursorarrow.rays";
        statusText = [NSString stringWithFormat:@"Locked to %@", kTargetOwnerName];
        break;
    }

    NSImage *icon = [NSImage imageWithSystemSymbolName:symbolName
                              accessibilityDescription:statusText];
    icon.template = YES;
    self.statusItem.button.image = icon;
    self.statusItem.button.title = icon ? @"" : @"ML";  // fallback if the symbol is missing
    self.statusItem.button.toolTip = statusText;

    self.statusMenuItem.title = statusText;
    self.permissionMenuItem.hidden = (status != AppStatusNoPermission);
    self.enabledMenuItem.state = ml_is_enabled() ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)toggleEnabled:(id)sender {
    bool enabled = !ml_is_enabled();
    ml_set_enabled(enabled);
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kEnabledDefaultKey];
    [self refresh:nil];
}

- (void)openAccessibilitySettings:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:kAccessibilitySettingsURL]];
}

@end

int main(void) {
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        // NSApplication.delegate is weak: this local is what keeps the delegate
        // alive, which works because -run never returns.
        AppDelegate *appDelegate = [[AppDelegate alloc] init];
        application.delegate = appDelegate;
        // LSUIElement in Info.plist does this for the bundle; this covers
        // running the bare binary from a terminal.
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [application run];
    }
    return 0;
}
