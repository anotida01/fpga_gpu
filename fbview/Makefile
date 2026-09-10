# fbview/Makefile — CMake-free build for the framebuffer->display shared library.
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
#   Force SDL2 OFF:        WITH_SDL2=0 make   (then SDL1 auto may still apply)
#   Force SDL1 ON:         WITH_SDL1=1 make   (will fail if pkg-config can't find it)
#   Force SDL1 OFF:        WITH_SDL1=0 make   (then SDL2 auto may still apply)
#   Force pure stub:       WITH_SDL2=0 WITH_SDL1=0 make
#   Override pkg-config:   PKG_CONFIG=/path/to/pkg-config make
#
# The source set is fbview_save.cpp (PNG save) + ONE display backend:
#   src/fbview_gui.cpp      (SDL2 backend; its #else is the five stub definitions)
#   src/fbview_gui_sdl1.cpp (SDL1 backend; plain TU, selected INSTEAD of the above)
#
# libpng and the display backend are both OPTIONAL: detected via pkg-config (the
# standard on Linux/macOS). Display backend auto-precedence: SDL2 (pkg-config
# sdl2) -> SDL1 (pkg-config sdl) -> stub. When present the chosen backend is
# compiled in and linked; in the stub case fbview_gui.cpp's #else compiles and
# the five display symbols return FBVIEW_FEATURE_UNAVAILABLE. Never both
# backends in one build (that would duplicate the five display symbols). The
# public ABI is identical in every build (six symbols, same return codes).

CXX          ?= g++
CC           ?= gcc
CXXFLAGS     ?= -g -shared -fPIC -O3 -std=c++11 -Iinclude
LDLIBS       := -lm
PKG_CONFIG   ?= pkg-config

OUT_DIR  ?= build
TARGET   := $(OUT_DIR)/libfbview.so
GUI_DRV  := $(OUT_DIR)/gui_driver

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

# ---- Optional display backend (pkg-config): SDL2 -> SDL1 -> stub ------------
# WITH_SDL2=1 / WITH_SDL1=1: hard-require that backend (error if absent), and it
#   wins over the auto-precedence. Forcing BOTH is a conflict (error).
# WITH_SDL2=0 / WITH_SDL1=0: explicitly skip that backend (the other may still
#   be picked by auto; both = 0 forces the pure stub).
# Default (auto): SDL2 if pkg-config finds `sdl2`, else SDL1 if it finds `sdl`,
#   else the pure stub (fbview_gui.cpp's #else provides the five stub symbols).
# Exactly ONE display backend is compiled per build: the SRCS list below picks
# src/fbview_gui.cpp (SDL2 or stub) or src/fbview_gui_sdl1.cpp (SDL1).
SDL2_FOUND := $(shell $(PKG_CONFIG) --exists sdl2 2>/dev/null && echo 1 || echo 0)
SDL1_FOUND := $(shell $(PKG_CONFIG) --exists sdl  2>/dev/null && echo 1 || echo 0)

# DL_BACKEND = sdl2 | sdl1 | (empty = pure stub); DL_ERR non-empty => hard error.
DL_BACKEND :=
DL_ERR     :=

ifeq ($(WITH_SDL2),1)
  ifeq ($(WITH_SDL1),1)
    DL_ERR := WITH_SDL2=1 and WITH_SDL1=1 conflict: pick one display backend
  else
    ifeq ($(SDL2_FOUND),1)
      DL_BACKEND := sdl2
    else
      DL_ERR := WITH_SDL2=1 was requested but pkg-config cannot find sdl2 (install libsdl2-dev / sdl2-devel)
    endif
  endif
else ifeq ($(WITH_SDL1),1)
  ifeq ($(SDL1_FOUND),1)
    DL_BACKEND := sdl1
  else
    DL_ERR := WITH_SDL1=1 was requested but pkg-config cannot find sdl (SDL1) (install libsdl1.2-dev / SDL-devel)
  endif
else ifeq ($(WITH_SDL2)$(WITH_SDL1),00)
  DL_BACKEND :=            # pure stub
else ifeq ($(WITH_SDL2),0)
  ifeq ($(SDL1_FOUND),1)
    DL_BACKEND := sdl1
  endif
else ifeq ($(WITH_SDL1),0)
  ifeq ($(SDL2_FOUND),1)
    DL_BACKEND := sdl2
  endif
else
  ifeq ($(SDL2_FOUND),1)
    DL_BACKEND := sdl2
  else
    ifeq ($(SDL1_FOUND),1)
      DL_BACKEND := sdl1
    endif
  endif
endif

ifneq ($(DL_ERR),)
  $(error $(DL_ERR))
endif

# Apply the chosen backend (macro + flags + the one backend TU in SRCS).
ifeq ($(DL_BACKEND),sdl2)
  SRCS := src/fbview_save.cpp src/fbview_gui.cpp
  CXXFLAGS += -DFBVIEW_HAVE_SDL2 $(shell $(PKG_CONFIG) --cflags sdl2)
  LDLIBS   += $(shell $(PKG_CONFIG) --libs   sdl2)
  DL_STATUS := SDL2 ENABLED
else ifeq ($(DL_BACKEND),sdl1)
  SRCS := src/fbview_save.cpp src/fbview_gui_sdl1.cpp
  CXXFLAGS += -DFBVIEW_HAVE_SDL1 $(shell $(PKG_CONFIG) --cflags sdl)
  LDLIBS   += $(shell $(PKG_CONFIG) --libs   sdl)
  DL_STATUS := SDL1 ENABLED
else
  SRCS := src/fbview_save.cpp src/fbview_gui.cpp   # stub branch (its #else)
  DL_STATUS := SDL STUB (no SDL2, no SDL1)
endif

# Override echoes (auto = not set).
ifneq ($(WITH_SDL2),)
  WS2 := $(WITH_SDL2)
else
  WS2 := auto
endif
ifneq ($(WITH_SDL1),)
  WS1 := $(WITH_SDL1)
else
  WS1 := auto
endif

.PHONY: all clean info gui_driver
all: $(TARGET)

gui_driver: $(TARGET) $(GUI_DRV)

$(GUI_DRV): tests/gui_driver.c $(TARGET) $(MAKEFILE_LIST) | $(OUT_DIR)
	# -rpath $ORIGIN: at runtime, find libfbview.so next to the driver (same OUT_DIR).
	$(CC) -O2 -Iinclude tests/gui_driver.c -o $@ -L$(OUT_DIR) -lfbview $(LDLIBS) -Wl,-rpath,\$$ORIGIN

info:
	@echo "fbview: libpng $(PNG_STATUS) $(DL_STATUS)  (WITH_PNG=$(PNG_OVR) WITH_SDL2=$(WS2) WITH_SDL1=$(WS1) CXX=$(CXX) OUT_DIR=$(OUT_DIR))"

$(TARGET): $(SRCS) $(MAKEFILE_LIST) | $(OUT_DIR)
	@echo "fbview: libpng $(PNG_STATUS) $(DL_STATUS)  (WITH_PNG=$(PNG_OVR) WITH_SDL2=$(WS2) WITH_SDL1=$(WS1) CXX=$(CXX) OUT_DIR=$(OUT_DIR))"
	$(CXX) $(CXXFLAGS) $(SRCS) -o $@ $(LDLIBS)

$(OUT_DIR):
	mkdir -p $(OUT_DIR)

clean:
	rm -f $(TARGET) $(GUI_DRV)
