TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = CarPlay SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = OmniCar

OmniCar_FILES = Tweak.x
OmniCar_FRAMEWORKS = UIKit
OmniCar_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += omnicarprefs
include $(THEOS_MAKE_PATH)/aggregate.mk
