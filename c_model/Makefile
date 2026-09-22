# c_model/Makefile — CMake-free build for the DPI-C golden shared library.
#
#   Usage:               make            (builds build/libcmodel_golden.so)
#   Self-test (host):    make selftest   (builds+runs build/cmodel_selftest)
#   Mesh emitter (host): make gen        (builds build/cmodel_gen_mesh)
#   Clean:               make clean
#   Override C++ compiler: CXX=clang++ make
#   Override output:       OUT_DIR=out make
#   Force libpng ON:      WITH_PNG=1 make    (will fail if pkg-config can't find it)
#   Force libpng OFF:     WITH_PNG=0 make    (cmodel_save_image becomes a stub)
#   Override pkg-config:  PKG_CONFIG=/path/to/pkg-config make
#
# The source set is the headless math core (no GL/GLUT, no display). It is the
# same TU list as the `cmodel_golden` target in CMakeLists.txt.
#
# libpng is OPTIONAL: detected via pkg-config (the standard on Linux/macOS).
# When present we compile cmodel_golden.cpp with -DCMODEL_HAVE_LIBPNG and link
# against libpng; when absent the same TU compiles into a stub (cmodel_save_image
# returns CMODEL_FEATURE_UNAVAILABLE) and no libpng is linked. The public ABI is
# identical in either case.

CXX          ?= g++
CXXFLAGS     ?= -g -shared -fPIC -O3 -std=c++11 -Iinclude
# Host binaries (selftest, gen_mesh) link the same TUs as executables:
# same warning/std flags, but no -shared/-fPIC and a lighter -O.
HOSTCXXFLAGS := -g -O2 -std=c++11 -Iinclude
LDLIBS       := -lm
PKG_CONFIG   ?= pkg-config

OUT_DIR  ?= build
TARGET   := $(OUT_DIR)/libcmodel_golden.so

# The .so stays the default goal even though the host-tool rules below appear
# earlier in the file (make's default goal is the first target it sees).
.DEFAULT_GOAL := all

SRCS := \
    src/cmodel_core.cpp \
    src/struct.cpp \
    src/matrix.cpp \
    src/transform.cpp \
    src/obj.cpp \
    src/algorithms.cpp \
    src/mif.cpp \
    src/cmodel_golden.cpp

# ---- Optional libpng detection (pkg-config) --------------------------------
# With WITH_PNG=0 we deliberately skip detection; the build succeeds and the
# cmodel_save_image symbol is still exported (it returns CMODEL_FEATURE_UNAVAILABLE).
# With WITH_PNG=1 a missing libpng turns into a hard error (useful to pin a
# "libpng-must-be-present" CI job).
#
# Default: try to auto-detect via pkg-config; treat absence as a no-op (stub).
ifeq ($(WITH_PNG),0)
  HAVE_LIBPNG := 0
else ifeq ($(WITH_PNG),1)
  HAVE_LIBPNG := $(shell $(PKG_CONFIG) --exists libpng 2>/dev/null && echo 1 || echo 1_missing)
else
  HAVE_LIBPNG := $(shell $(PKG_CONFIG) --exists libpng 2>/dev/null && echo 1 || echo 0)
endif

ifeq ($(HAVE_LIBPNG),1)
  CXXFLAGS     += -DCMODEL_HAVE_LIBPNG $(shell $(PKG_CONFIG) --cflags libpng)
  HOSTCXXFLAGS += -DCMODEL_HAVE_LIBPNG $(shell $(PKG_CONFIG) --cflags libpng)
  LDLIBS       += $(shell $(PKG_CONFIG) --libs   libpng)
  PNG_STATUS := ENABLED
else ifeq ($(HAVE_LIBPNG),1_missing)
  $(error WITH_PNG=1 was requested but pkg-config cannot find libpng (install libpng-dev / libpng-devel))
else
  # HAVE_LIBPNG=0 → stub branch, no -DCMODEL_HAVE_LIBPNG, no libpng link.
  PNG_STATUS := STUB
endif

# ---- Host tools ------------------------------------------------------------
# Self-test binary: links the same TUs as the shared library and runs
# cmodel_selftest() as a host process — the "golden of the golden"
# (README §7.6). Mesh emitter: directed/random test-mesh generator for the
# per-vertex stimulus flow.
SELFTEST_BIN := $(OUT_DIR)/cmodel_selftest
GEN_MESH_BIN := $(OUT_DIR)/cmodel_gen_mesh

$(SELFTEST_BIN): $(SRCS) src/cmodel_selftest_host.cpp | $(OUT_DIR)
	@echo "cmodel_selftest: libpng $(PNG_STATUS)  (CXX=$(CXX) OUT_DIR=$(OUT_DIR))"
	$(CXX) $(HOSTCXXFLAGS) $(SRCS) src/cmodel_selftest_host.cpp -o $@ $(LDLIBS)

$(GEN_MESH_BIN): $(SRCS) src/cmodel_gen_mesh.cpp | $(OUT_DIR)
	@echo "cmodel_gen_mesh: libpng $(PNG_STATUS)  (CXX=$(CXX) OUT_DIR=$(OUT_DIR))"
	$(CXX) $(HOSTCXXFLAGS) $(SRCS) src/cmodel_gen_mesh.cpp -o $@ $(LDLIBS)

.PHONY: all clean info selftest gen
all: $(TARGET)

selftest: $(SELFTEST_BIN)
	./$(SELFTEST_BIN)

gen: $(GEN_MESH_BIN)

info:
	@echo "cmodel_golden: libpng $(PNG_STATUS)  (CXX=$(CXX) OUT_DIR=$(OUT_DIR))"

$(TARGET): $(SRCS) | $(OUT_DIR)
	@echo "cmodel_golden: libpng $(PNG_STATUS)  (CXX=$(CXX) OUT_DIR=$(OUT_DIR))"
	$(CXX) $(CXXFLAGS) $(SRCS) -o $@ $(LDLIBS)

$(OUT_DIR):
	mkdir -p $(OUT_DIR)

clean:
	rm -f $(TARGET) $(SELFTEST_BIN) $(GEN_MESH_BIN)
