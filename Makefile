ARCHS = armv7 arm64
include theos/makefiles/common.mk

TWEAK_NAME = Prism
Prism_CFLAGS = -fobjc-arc
Prism_FILES = Tweak.xm MeterTable.cpp BeatVisualizerView.mm LEColorPicker.m
Prism_FRAMEWORKS = UIKit AVFoundation QuartzCore CoreGraphics CoreMedia CoreAudio AudioToolbox MediaToolbox Accelerate OpenGLES Foundation
Prism_PRIVATE_FRAMEWORKS = AppSupport MediaRemote
Prism_LIBRARIES = rocketbootstrap

export GO_EASY_ON_ME := 1

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += PrismSettings
include $(THEOS_MAKE_PATH)/aggregate.mk

before-stage::
	find . -name ".DS_STORE" -delete

after-install::
	install.exec "killall -9 backboardd Music"
