#import <Preferences/Preferences.h>
#import <UIKit/UIKit.h>

NSString *WAMJBPath(NSString *suffix);

#define kWAMPrefsPlistPath WAMJBPath(@"/var/mobile/Library/Preferences/com.oakstheawesome.whatamessprefs.plist")
#define kWAMPrefsDomain    @"com.oakstheawesome.whatamessprefs"
#define kWAMPrefsChanged   "com.oakstheawesome.whatamessprefs/prefsChanged"

@interface WAMBaseListController : PSListController
    <UIColorPickerViewControllerDelegate,
     UIImagePickerControllerDelegate,
     UINavigationControllerDelegate>
{
    NSString *_currentColorKey;
    NSString *_currentImageDestPath;
}

- (NSMutableDictionary *)readPrefs;
- (void)writePrefs:(NSDictionary *)prefs;
- (void)saveValue:(id)value forKey:(NSString *)key;
- (void)postNotification;

- (void)wamReloadSpecifiersFromDisk;

- (void)showColorPickerForKey:(NSString *)key defaultColor:(UIColor *)defaultColor;
- (void)showColorPickerForKeyDirect:(NSString *)key defaultColor:(UIColor *)defaultColor;

- (void)showImagePickerForDestinationPath:(NSString *)destPath;

- (NSString *)hexFromColor:(UIColor *)color;
- (UIColor *)colorFromHex:(NSString *)hexString;

- (BOOL)isEditingDarkMode;
- (NSString *)keyForBase:(NSString *)baseKey;
@end
