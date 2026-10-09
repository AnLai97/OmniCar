TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
# "Runner" is Vietmap Live's process (Flutter), "GOFA" is com.lumi.GOFA (Speed Bubble sources).
INSTALL_TARGET_PROCESSES = CarPlay SpringBoard Runner GOFA

include $(THEOS)/makefiles/common.mk

TWEAK_VERSION := $(shell sed -n 's/^Version: *//p' control | tr -d '\r')

# Layout: Core/ (prefs + logging, compiled into every feature), Prefs/ (settings bundle: root page,
# theme, feature-page base class) and one folder per feature under Features/<Name>/:
#   <Name>.h / <Name>.x|.xm|.m|.mm   contract + hooks        -> its own dylib OmniCar<Name>.dylib
#   Filter.plist                     processes it loads into -> copied to ./OmniCar<Name>.plist (generated)
#   feature.mk (optional)            extra frameworks:  OmniCar<Name>_FRAMEWORKS += CoreLocation
#   Prefs/*.m + Prefs/Resources/*    settings page, plist (feature* keys list it on the root page),
#                                    <lang>.lproj/<Name>.strings, icon
# Dropping a folder into Features/ is all it takes to add a feature.
# App/ is the OmniCar companion app (omnicar:// URL scheme for Shortcuts / Siri), see below.

FEATURES := $(notdir $(wildcard Features/*))

# --- Core dylib (SpringBoard only: log relay) + one tweak dylib per feature ---------------------
TWEAK_NAME = OmniCarCore $(foreach f,$(FEATURES),OmniCar$(f))

OmniCarCore_FILES = Core/Core.x Core/OmniCar.m
OmniCarCore_FRAMEWORKS = UIKit
OmniCarCore_CFLAGS = -fobjc-arc -ICore -DOMC_FEATURE=\"Core\"
$(shell cp "Core/Filter.plist" "OmniCarCore.plist")

define OMC_FEATURE
OmniCar$(1)_FILES = $(wildcard Features/$(1)/*.x) $(wildcard Features/$(1)/*.xm) $(wildcard Features/$(1)/*.m) $(wildcard Features/$(1)/*.mm) Core/OmniCar.m
OmniCar$(1)_FRAMEWORKS = UIKit
# -DOMC_FEATURE keeps each dylib's objects apart (Theos hashes the flags into the object path).
OmniCar$(1)_CFLAGS = -fobjc-arc -ICore -DOMC_FEATURE=\"$(1)\"
$$(shell cp "Features/$(1)/Filter.plist" "OmniCar$(1).plist")
endef
$(foreach f,$(FEATURES),$(eval $(call OMC_FEATURE,$(f))))
-include $(wildcard Features/*/feature.mk)

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

# --- Companion app: the omnicar:// URL scheme for Shortcuts / Siri (App/main.m) -------------------
# It only forwards the URL to SpringBoard; a feature's SpringBoard hook handles its own host
# (omnicar://splitscreen/...). Installed to /Applications; the package manager runs uicache.
APPLICATION_NAME = OmniCar

OmniCar_FILES = App/main.m
OmniCar_FRAMEWORKS = UIKit
OmniCar_CFLAGS = -fobjc-arc -ICore -IFeatures/SplitScreen
OmniCar_RESOURCE_DIRS = App/Resources
OmniCar_CODESIGN_FLAGS = -SApp/entitlements.plist

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk
include $(THEOS_MAKE_PATH)/application.mk
