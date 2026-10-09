TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
# "Runner" is Vietmap Live's process (Flutter), "GOFA" is com.lumi.GOFA (Speed Bubble sources).
INSTALL_TARGET_PROCESSES = CarPlay SpringBoard Runner GOFA

include $(THEOS)/makefiles/common.mk

TWEAK_VERSION := $(shell sed -n 's/^Version: *//p' control | tr -d '\r')

# Layout: Core/ (shared prefs + logging), Tweak.x (core ctor), Prefs/ (settings bundle: root page,
# theme, feature-page base class) and one folder per feature under Features/<Name>/ holding its
# hooks (<Name>.x), its contract header (<Name>.h) and its settings page (Prefs/*.m +
# Prefs/Resources/*). Dropping a folder into Features/ is all it takes to add a feature.

# --- Tweak: core + every feature's hooks -------------------------------------------------------
TWEAK_NAME = OmniCar

OmniCar_FILES = Tweak.x Core/OmniCar.m $(wildcard Features/*/*.x) $(wildcard Features/*/*.xm) $(wildcard Features/*/*.m) $(wildcard Features/*/*.mm)
OmniCar_FRAMEWORKS = UIKit AVFoundation ImageIO QuartzCore CoreLocation
OmniCar_CFLAGS = -fobjc-arc -ICore

# --- Settings bundle: core pages + every feature's page, resources merged from every feature ----
BUNDLE_NAME = OmniCarPrefs

OmniCarPrefs_FILES = $(wildcard Prefs/*.m) $(wildcard Features/*/Prefs/*.m)
OmniCarPrefs_FRAMEWORKS = UIKit AVFoundation AVKit UniformTypeIdentifiers CoreImage CoreMedia CoreVideo ImageIO
OmniCarPrefs_PRIVATE_FRAMEWORKS = Preferences
OmniCarPrefs_INSTALL_PATH = /Library/PreferenceBundles
# Theos rsyncs the *contents* of each dir into the bundle, so feature plists and
# <lang>.lproj/<Feature>.strings land next to the core ones.
OmniCarPrefs_RESOURCE_DIRS = Prefs/Resources $(wildcard Features/*/Prefs/Resources)
# TWEAK_VERSION is shown in the footer card, read from control.
OmniCarPrefs_CFLAGS = -fobjc-arc -ICore -IPrefs -DTWEAK_VERSION=\"$(TWEAK_VERSION)\"

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk
