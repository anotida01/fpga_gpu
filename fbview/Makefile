# fbview/Makefile — CMake-free build for the framebuffer->PNG shared library.
#
#   Usage:               make            (builds build/libfbview.so)
#   Clean:               make clean
#   Info:                make info
#   Override C++ compiler: CXX=clang++ make
#   Override output:       OUT_DIR=out make
#   Force libpng ON:      WITH_PNG=1 make    (will fail if pkg-config can't find it)
#   Force libpng OFF:     WITH_PNG=0 make    (fbview_save_png becomes a stub)
#   Override pkg-config:  PKG_CONFIG=/path/to/pkg-config make
#
# The source set is the single TU fbview_save.cpp (v1: PNG save only). The
# live-GUI half (fbview_gui.cpp) is a separate work order and is NOT in SRCS.
#
# libpng is OPTIONAL: detected via pkg-config (the standard on Linux/macOS).
# When present we compile fbview_save.cpp with -DFBVIEW_HAVE_PNG and link
# against libpng; when absent the same TU compiles into a stub (fbview_save_png
# returns FBVIEW_FEATURE_UNAVAILABLE) and no libpng is linked. The public ABI
# is identical in either case.

CXX          ?= g++
CXXFLAGS     ?= -g -shared -fPIC -O3 -std=c++11 -Iinclude
LDLIBS       := -lm
PKG_CONFIG   ?= pkg-config

OUT_DIR  ?= build
TARGET   := $(OUT_DIR)/libfbview.so

SRCS := \
    src/fbview_save.cpp

# ---- Optional libpng detection (pkg-config) --------------------------------
# WITH_PNG=0: deliberately skip detection; build succeeds and fbview_save_png
#             is still exported (returns FBVIEW_FEATURE_UNAVAILABLE).
# WITH_PNG=1: a missing libpng turns into a hard error (pin a "must-be-present" job).
# Default:    auto-detect via pkg-config; treat absence as a no-op (stub).
ifeq ($(WITH_PNG),0)
  HAVE_LIBPNG := 0
else ifeq ($(WITH_PNG),1)
  HAVE_LIBPNG := $(shell $(PKG_CONFIG) --exists libpng 2>/dev/null && echo 1 || echo 1_missing)
else
  HAVE_LIBPNG := $(shell $(PKG_CONFIG) --exists libpng 2>/dev/null && echo 1 || echo 0)
endif

ifneq ($(WITH_PNG),)
  ifeq ($(WITH_PNG),1)
    PNG_OVR := 1
  else
    PNG_OVR := 0
  endif
else
  PNG_OVR := auto
endif

ifeq ($(HAVE_LIBPNG),1)
  CXXFLAGS += -DFBVIEW_HAVE_PNG $(shell $(PKG_CONFIG) --cflags libpng)
  LDLIBS   += $(shell $(PKG_CONFIG) --libs   libpng)
  PNG_STATUS := ENABLED
else ifeq ($(HAVE_LIBPNG),1_missing)
  $(error WITH_PNG=1 was requested but pkg-config cannot find libpng (install libpng-dev / libpng-devel))
else
  # HAVE_LIBPNG=0 -> stub branch, no -DFBVIEW_HAVE_PNG, no libpng link.
  PNG_STATUS := STUB
endif

.PHONY: all clean info
all: $(TARGET)

info:
	@echo "fbview: libpng $(PNG_STATUS)  (WITH_PNG=$(PNG_OVR) CXX=$(CXX) OUT_DIR=$(OUT_DIR))"

$(TARGET): $(SRCS) | $(OUT_DIR)
	@echo "fbview: libpng $(PNG_STATUS)  (WITH_PNG=$(PNG_OVR) CXX=$(CXX) OUT_DIR=$(OUT_DIR))"
	$(CXX) $(CXXFLAGS) $(SRCS) -o $@ $(LDLIBS)

$(OUT_DIR):
	mkdir -p $(OUT_DIR)

clean:
	rm -f $(TARGET)
