#import <UIKit/UIKit.h>

typedef NS_OPTIONS(NSUInteger, WAMPresetScope) {
    WAMPresetScopeConvList = 1 << 0,
    WAMPresetScopeChats    = 1 << 1,
    WAMPresetScopeBoth     = WAMPresetScopeConvList | WAMPresetScopeChats,
};

typedef NS_ENUM(NSUInteger, WAMPresetAppearance) {
    WAMPresetAppearanceLight = 0,
    WAMPresetAppearanceDark,
    WAMPresetAppearanceBoth,
};

typedef NS_ENUM(NSUInteger, WAMGradientDirection) {
    WAMGradientDirectionVertical = 0,
    WAMGradientDirectionDiagonal,
    WAMGradientDirectionHorizontal,
};

@interface WAMPreset : NSObject

@property (nonatomic, copy)   NSString *identifier;
@property (nonatomic, copy)   NSString *name;
@property (nonatomic, copy)   NSString *subtitle;
@property (nonatomic, assign) BOOL builtin;
@property (nonatomic, copy)   NSString *chatBgImage;
@property (nonatomic, copy)   NSString *chatBgImageDark;
@property (nonatomic, copy)   NSString *convBgImage;
@property (nonatomic, copy)   NSString *convBgImageDark;
@property (nonatomic, copy)   NSArray<NSString *> *lightGradient;
@property (nonatomic, copy)   NSArray<NSString *> *darkGradient;
@property (nonatomic, copy)   NSDictionary<NSString *, id> *lightValues;
@property (nonatomic, copy)   NSDictionary<NSString *, id> *darkValues;

+ (instancetype)presetWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryRepresentation;

- (UIColor *)backgroundColorForDark:(BOOL)dark;
- (UIColor *)sentColorForDark:(BOOL)dark;
- (UIColor *)receivedColorForDark:(BOOL)dark;
- (UIColor *)sentTextColorForDark:(BOOL)dark;
- (UIColor *)receivedTextColorForDark:(BOOL)dark;
- (UIColor *)titleColorForDark:(BOOL)dark;
- (UIColor *)previewColorForDark:(BOOL)dark;
- (UIColor *)tintColorForDark:(BOOL)dark;
- (BOOL)blurEnabledForDark:(BOOL)dark;
- (CGFloat)backgroundBlurForDark:(BOOL)dark convList:(BOOL)convList;

- (id)valueForBaseKey:(NSString *)baseKey dark:(BOOL)dark;

@end

@interface WAMPresetStore : NSObject

+ (NSArray<WAMPreset *> *)builtinPresets;
+ (NSArray<WAMPreset *> *)userPresets;
+ (NSString *)appliedPresetIdentifier;
+ (NSArray<WAMPreset *> *)allPresets;

+ (WAMPreset *)snapshotOfCurrentSettingsNamed:(NSString *)name;
+ (WAMPreset *)snapshotOfContact:(NSString *)contactName named:(NSString *)name;
+ (void)saveUserPreset:(WAMPreset *)preset;
+ (void)deleteUserPresetWithIdentifier:(NSString *)identifier;

+ (NSArray<NSString *> *)baseKeysForScope:(WAMPresetScope)scope;

+ (void)applyPreset:(WAMPreset *)preset scope:(WAMPresetScope)scope appearance:(WAMPresetAppearance)appearance;
+ (void)applyPreset:(WAMPreset *)preset toContact:(NSString *)contactName appearance:(WAMPresetAppearance)appearance;

+ (WAMPreset *)currentLookPreset;
+ (WAMPreset *)currentLookPresetForContact:(NSString *)contactName;
+ (NSURL *)exportSettingsToTempFile;
+ (NSURL *)exportPresetToTempFile:(WAMPreset *)preset;
+ (BOOL)importSettingsFromURL:(NSURL *)url;

+ (void)setGradientBackground:(NSArray<NSString *> *)stops direction:(WAMGradientDirection)direction
                         chat:(BOOL)isChat dark:(BOOL)dark;
+ (void)setGradientBackground:(NSArray<NSString *> *)stops direction:(WAMGradientDirection)direction
                   forContact:(NSString *)contactName dark:(BOOL)dark;

+ (void)restartMessages;

+ (NSArray<NSString *> *)lastGradientStops;
+ (WAMGradientDirection)lastGradientDirection;
+ (void)saveLastGradientStops:(NSArray<NSString *> *)stops direction:(WAMGradientDirection)direction;

@end

UIColor *WAMColorFromHex(NSString *hex);
NSString *WAMHexFromColor(UIColor *color);

NSString *WAMPresetImagePath(NSString *name);

UIImage *WAMPresetBackgroundImage(WAMPreset *preset, BOOL dark, BOOL convList, CGSize size);

UIImage *WAMPresetPreviewBackgroundImage(WAMPreset *preset, BOOL dark, BOOL convList, CGSize size);

UIImage *WAMGradientImage(NSArray<NSString *> *hexStops, CGSize size, WAMGradientDirection direction);
