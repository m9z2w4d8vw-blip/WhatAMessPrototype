#import "WAMPresetGalleryController.h"
#import "WAMPresetModel.h"
#import "WAMPresetCardView.h"
#import "WAMBaseListController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <spawn.h>

@interface WAMPresetGalleryController () <UIDocumentPickerDelegate>
@end

@implementation WAMPresetGalleryController {
    UIScrollView *_scroll;
    UIStackView *_stack;
    UISegmentedControl *_modeControl;
    BOOL _dark;
    BOOL _exportMode;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Presets";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    _dark = (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);

    _modeControl = [[UISegmentedControl alloc] initWithItems:@[@"Light", @"Dark"]];
    _modeControl.selectedSegmentIndex = _dark ? 1 : 0;
    [_modeControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = _modeControl;

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                      target:self action:@selector(saveCurrentTapped)];

    UIBarButtonItem *imp = [[UIBarButtonItem alloc] initWithTitle:@"Import" style:UIBarButtonItemStylePlain
                                                           target:self action:@selector(importTapped)];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *exp = [[UIBarButtonItem alloc] initWithTitle:@"Export" style:UIBarButtonItemStylePlain
                                                           target:self action:@selector(exportTapped)];
    self.toolbarItems = @[imp, flex, exp];

    _scroll = [UIScrollView new];
    _scroll.alwaysBounceVertical = YES;
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_scroll];

    _stack = [UIStackView new];
    _stack.axis = UILayoutConstraintAxisVertical;
    _stack.spacing = 18;
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_scroll addSubview:_stack];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_scroll.topAnchor constraintEqualToAnchor:g.topAnchor],
        [_scroll.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [_scroll.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [_scroll.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],
        [_stack.topAnchor constraintEqualToAnchor:_scroll.topAnchor constant:18],
        [_stack.bottomAnchor constraintEqualToAnchor:_scroll.bottomAnchor constant:-24],
        [_stack.leadingAnchor constraintEqualToAnchor:_scroll.leadingAnchor constant:16],
        [_stack.trailingAnchor constraintEqualToAnchor:_scroll.trailingAnchor constant:-16],
        [_stack.widthAnchor constraintEqualToAnchor:_scroll.widthAnchor constant:-32],
    ]];

    [self rebuildCards];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.toolbarHidden = NO;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.navigationController.toolbarHidden = YES;
}

#pragma mark - Import / export

- (void)exportTapped {
    [self setExportMode:YES];
}

- (void)cancelExport {
    [self setExportMode:NO];
}

- (void)setExportMode:(BOOL)on {
    _exportMode = on;
    self.navigationItem.prompt = on ? @"Tap a preset to export" : nil;
    self.navigationItem.rightBarButtonItem = on
        ? [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelExport)]
        : [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(saveCurrentTapped)];
    [self.navigationController setToolbarHidden:on animated:YES];
    [self rebuildCards];
}

- (void)shareExportURL:(NSURL *)url {
    if (!url) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Export Failed!"
            message:@"Couldn't create the preset file." preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    av.popoverPresentationController.barButtonItem = self.toolbarItems.lastObject;
    [self presentViewController:av animated:YES completion:nil];
}

- (void)importTapped {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeData, UTTypeContent] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (!urls.count) return;
    BOOL ok = [WAMPresetStore importSettingsFromURL:urls.firstObject];
    if (ok) { [self rebuildCards]; [self refreshSettingsPagesBehind]; [self offerRestart]; }
    else {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Import Failed"
            message:@"Not a valid WhatAMess preset!" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
    }
}

- (void)rebuildCards {
    for (UIView *v in _stack.arrangedSubviews) { [_stack removeArrangedSubview:v]; [v removeFromSuperview]; }

    CGFloat width = self.view.bounds.size.width - 32;
    if (width <= 0) width = UIScreen.mainScreen.bounds.size.width - 32;
    CGFloat height = [WAMPresetCardView heightForWidth:width showsConvList:YES];

    NSArray<WAMPreset *> *user = [WAMPresetStore userPresets];

    if (_exportMode) {
        [self addSectionHeader:@"This Device"];
        [self addExportCard:[WAMPresetStore currentLookPreset] height:height current:YES];
        if (user.count) {
            [self addSectionHeader:@"Your Presets"];
            for (WAMPreset *p in user) [self addExportCard:p height:height current:NO];
        }
        return;
    }

    [self addSectionHeader:@"Built-In"];
    for (WAMPreset *p in [WAMPresetStore builtinPresets]) [self addCardForPreset:p height:height deletable:NO];

    if (user.count) {
        [self addSectionHeader:@"Your Presets"];
        for (WAMPreset *p in user) [self addCardForPreset:p height:height deletable:YES];
    }
}

- (void)addExportCard:(WAMPreset *)preset height:(CGFloat)height current:(BOOL)current {
    WAMPresetCardView *card = [[WAMPresetCardView alloc] initWithPreset:preset dark:_dark];
    card.exportMode = YES;
    __weak typeof(self) ws = self;
    card.onApply = ^(WAMPreset *p) {
        NSURL *url = current ? [WAMPresetStore exportSettingsToTempFile]
                             : [WAMPresetStore exportPresetToTempFile:p];
        [ws setExportMode:NO];
        [ws shareExportURL:url];
    };
    [card.heightAnchor constraintEqualToConstant:height].active = YES;
    [_stack addArrangedSubview:card];
}

- (void)addSectionHeader:(NSString *)title {
    UILabel *l = [UILabel new];
    l.text = [title uppercaseString];
    l.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    l.textColor = [UIColor secondaryLabelColor];
    [_stack addArrangedSubview:l];
}

- (void)addCardForPreset:(WAMPreset *)preset height:(CGFloat)height deletable:(BOOL)deletable {
    WAMPresetCardView *card = [[WAMPresetCardView alloc] initWithPreset:preset dark:_dark];
    NSString *applied = [WAMPresetStore appliedPresetIdentifier];
    card.applied = (applied && [applied isEqualToString:preset.identifier]);
    __weak typeof(self) ws = self;
    card.onApply = ^(WAMPreset *p) { [ws promptApplyScopeFor:p]; };
    if (deletable) {
        card.onDelete = ^(WAMPreset *p) { [ws confirmDelete:p]; };
        card.onRename = ^(WAMPreset *p) { [ws promptRename:p]; };
    }
    [card.heightAnchor constraintEqualToConstant:height].active = YES;
    [_stack addArrangedSubview:card];
}

- (void)modeChanged:(UISegmentedControl *)sc {
    _dark = (sc.selectedSegmentIndex == 1);
    for (UIView *v in _stack.arrangedSubviews) {
        if ([v isKindOfClass:[WAMPresetCardView class]]) ((WAMPresetCardView *)v).darkAppearance = _dark;
    }
}

#pragma mark - Apply

- (void)promptApplyScopeFor:(WAMPreset *)preset {
    WAMPresetAppearance appearance = WAMPresetAppearanceBoth;
    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"Apply “%@”?", preset.name]
        message:@"Applies to both light and dark mode. Where should it take effect?"
        preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Conversation List" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a){ [self apply:preset scope:WAMPresetScopeConvList appearance:appearance]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Chats" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a){ [self apply:preset scope:WAMPresetScopeChats appearance:appearance]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Both" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a){ [self apply:preset scope:WAMPresetScopeBoth appearance:appearance]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)apply:(WAMPreset *)preset scope:(WAMPresetScope)scope appearance:(WAMPresetAppearance)appearance {
    [WAMPresetStore applyPreset:preset scope:scope appearance:appearance];
    [self refreshSettingsPagesBehind];
    [self rebuildCards];
    [self offerRestart];
}

- (void)refreshSettingsPagesBehind {
    for (UIViewController *vc in self.navigationController.viewControllers) {
        if (vc != self && [vc isKindOfClass:[WAMBaseListController class]]) {
            [(WAMBaseListController *)vc wamReloadSpecifiersFromDisk];
        }
    }
}

- (void)offerRestart {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Preset Applied!"
        message:@"Restart Messages now to see all changes?"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Restart" style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *a){ [WAMPresetStore restartMessages]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Save / delete user presets

- (void)saveCurrentTapped {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Save Your Current Look"
        message:@"Save your current settings as a preset that can be selected and exported."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf){ tf.placeholder = @"Enter Name"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a){
            NSString *name = alert.textFields.firstObject.text;
            WAMPreset *snap = [WAMPresetStore snapshotOfCurrentSettingsNamed:name];
            [WAMPresetStore saveUserPreset:snap];
            [self rebuildCards];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)promptRename:(WAMPreset *)preset {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Rename Preset"
        message:nil
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf){
        tf.placeholder = @"New Name";
        tf.text = preset.name;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a){
            NSString *name = [alert.textFields.firstObject.text
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (!name.length) return;
            preset.name = name;
            [WAMPresetStore saveUserPreset:preset];
            [self rebuildCards];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmDelete:(WAMPreset *)preset {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"Delete “%@”?", preset.name]
        message:@"This removes the saved preset. Your current settings are unchanged. This CAN'T be undone!"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *a){
            [WAMPresetStore deleteUserPresetWithIdentifier:preset.identifier];
            [self rebuildCards];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
