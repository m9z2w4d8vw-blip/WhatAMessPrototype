TARGET = iphone:clang:latest:15.0
FINALPACKAGE = 1
INSTALL_TARGET_PROCESSES = com.apple.MobileSMS

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WhatAMess

WhatAMess_FILES = Tweak.x WAMFilterTweak.x WAMDebugLog.m WAMPresetModel.m WAMPresetPreviewView.m WAMPresetCardView.m WAMGradientBuilderController.m WAMFilterModel.m WAMManageFilteringController.m WAMFilterLogViewController.m
WhatAMess_CFLAGS = -fobjc-arc
WhatAMess_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += WhatAMessPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk
