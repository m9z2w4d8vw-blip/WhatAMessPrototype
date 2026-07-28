#import <Foundation/Foundation.h>
#import "WAMChatViewController.h"
#import "WAMBaseListController.h"
#import "WAMPresetModel.h"
#import "WAMGradientBuilderController.h"

@implementation WAMChatViewController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"ChatView" target:self];
    }
    return _specifiers;
}

#pragma mark - Background

- (void)createChatGradient {
    BOOL dark = [self isEditingDarkMode];
    WAMGradientBuilderController *b = [[WAMGradientBuilderController alloc] initWithStops:nil];
    b.onDone = ^(NSArray<NSString *> *stops, WAMGradientDirection direction){
        if (stops.count >= 2) [WAMPresetStore setGradientBackground:stops direction:direction chat:YES dark:dark];
        [self dismissViewControllerAnimated:YES completion:nil];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:b];
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Color Pickers

- (void)pickMessageBarButtonColor {
    [self showColorPickerForKey:@"messageBarButtonColor" defaultColor:[UIColor systemBlueColor]];
}

- (void)pickLinkPreviewBackgroundColor {
    [self showColorPickerForKey:@"linkPreviewBackgroundColor" defaultColor:[UIColor darkGrayColor]];
}

- (void)pickLinkPreviewTextColor {
    [self showColorPickerForKey:@"linkPreviewTextColor" defaultColor:[UIColor whiteColor]];
}

#pragma mark - Image Picker

- (void)pickChatBgImage {
    NSString *path = [self isEditingDarkMode]
        ? WAMJBPath(@"/var/mobile/Library/Preferences/com.oakstheawesome.whatamessprefs/chat_background_dark.jpg")
        : WAMJBPath(@"/var/mobile/Library/Preferences/com.oakstheawesome.whatamessprefs/chat_background.jpg");
    [self showImagePickerForDestinationPath:path];
}

@end
