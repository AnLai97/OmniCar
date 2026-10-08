TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = OmniCarPrefs

OmniCarPrefs_FILES = OMCRootListController.m
OmniCarPrefs_FRAMEWORKS = UIKit
OmniCarPrefs_PRIVATE_FRAMEWORKS = Preferences
OmniCarPrefs_INSTALL_PATH = /Library/PreferenceBundles
# Version shown in the footer card, read from ../control.
OmniCarPrefs_CFLAGS = -fobjc-arc -DTWEAK_VERSION=\"$(shell sed -n 's/^Version: *//p' ../control | tr -d '\r')\"

include $(THEOS_MAKE_PATH)/bundle.mk
