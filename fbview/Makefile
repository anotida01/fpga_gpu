# fbview/Makefile — CMake-free build for the framebuffer->PNG shared library.
#
#   Usage:               make            (builds build/libfbview.so)
#   Build gui_driver:    make gui_driver (builds build/gui_driver over the lib)
#   Clean:               make clean
#   Info:                make info
#   Override C++ compiler: CXX=clang++ make
#   Override output:       OUT_DIR=out make
#   Force libpng ON:       WITH_PNG=1 make    (will fail if pkg-config can't find it)
#   Force libpng OFF:      WITH_PNG=0 make    (fbview_save_png becomes a stub)
#   Force SDL2 ON:         WITH_SDL2=1 make   (will fail if pkg-config can't find it)
#   Force SDL2 OFF:        WITH_SDL2=0 make   (display symbols become stubs)
#   Override pkg-config:   PKG_CONFIG=/path/to/pkg-config make
#
# The source set is fbview_save.cpp (PNG save) + fbview_gui.cpp (live display).
#
# libpng and SDL2 are both OPTIONAL: detected via pkg-config (the standard on
# Linux/macOS). When present we compile with -DFBVIEW_HAVE_PNG / -DFBVIEW_HAVE_SDL2
# and link the lib; when absent the same TU compiles into a stub (the affected
# functions return FBVIEW_FEATURE_UNAVAILABLE) and the lib is not linked. The
# public ABI is identical in either case; the two gates are independent (four
# legal build combos: PNG on/off x SDL2 on/off).

CXX          ?= g++
CC           ?= gcc
CXXFLAGS     ?= -g -shared -fPIC -O3 -std=c++11 -Iinclude
LDLIBS       := -lm
PKG_CONFIG   ?= pkg-config

OUT_DIR  ?= build
TARGET   := $(OUT_DIR)/libfbview.so
GUI_DRV  := $(OUT_DIR)/gui_driver

SRCS := \
    src/fbview_save.cpp \
    src/fbview_gui.cpp

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

# ---- Optional SDL2 detection (pkg-config) ----------------------------------
# WITH_SDL2=0: deliberately skip detection; build succeeds and the four display
#              symbols are still exported (return FBVIEW_FEATURE_UNAVAILABLE).
# WITH_SDL2=1: a missing SDL2 turns into a hard error.
# Default:     auto-detect via pkg-config; treat absence as a no-op (stub).
ifeq ($(WITH_SDL2),0)
  HAVE_SDL2 := 0
else ifeq ($(WITH_SDL2),1)
  HAVE_SDL2 := $(shell $(PKG_CONFIG) --exists sdl2 2>/dev/null && echo 1 || echo 1_missing)
else
  HAVE_SDL2 := $(shell $(PKG_CONFIG) --exists sdl2 2>/dev/null && echo 1 || echo 0)
endif

ifneq ($(WITH_SDL2),)
  ifeq ($(WITH_SDL2),1)
    SDL2_OVR := 1
  else
    SDL2_OVR := 0
  endif
else
  SDL2_OVR := auto
endif

ifeq ($(HAVE_SDL2),1)
  CXXFLAGS += -DFBVIEW_HAVE_SDL2 $(shell $(PKG_CONFIG) --cflags sdl2)
  LDLIBS   += $(shell $(PKG_CONFIG) --libs   sdl2)
  SDL2_STATUS := ENABLED
else ifeq ($(HAVE_SDL2),1_missing)
  $(error WITH_SDL2=1 was requested but pkg-config cannot find sdl2 (install libsdl2-dev / sdl2-devel))
else
  # HAVE_SDL2=0 -> stub branch, no -DFBVIEW_HAVE_SDL2, no SDL2 link.
  SDL2_STATUS := STUB
endif

.PHONY: all clean info gui_driver
all: $(TARGET)

gui_driver: $(TARGET) $(GUI_DRV)

$(GUI_DRV): tests/gui_driver.c $(TARGET) $(MAKEFILE_LIST) | $(OUT_DIR)
	# -rpath $ORIGIN: at runtime, find libfbview.so next to the driver (same OUT_DIR).
	$(CC) -O2 -Iinclude tests/gui_driver.c -o $@ -L$(OUT_DIR) -lfbview $(LDLIBS) -Wl,-rpath,\$$ORIGIN

info:
	@echo "fbview: libpng $(PNG_STATUS) SDL2 $(SDL2_STATUS)  (WITH_PNG=$(PNG_OVR) WITH_SDL2=$(SDL2_OVR) CXX=$(CXX) OUT_DIR=$(OUT_DIR))"

$(TARGET): $(SRCS) | $(OUT_DIR)
	@echo "fbview: libpng $(PNG_STATUS) SDL2 $(SDL2_STATUS)  (WITH_PNG=$(PNG_OVR) WITH_SDL2=$(SDL2_OVR) CXX=$(CXX) OUT_DIR=$(OUT_DIR))"
	$(CXX) $(CXXFLAGS) $(SRCS) -o $@ $(LDLIBS)

$(OUT_DIR):
	mkdir -p $(OUT_DIR)

clean:
	rm -f $(TARGET) $(GUI_DRV)
