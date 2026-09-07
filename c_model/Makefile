# c_model/Makefile — CMake-free build for the DPI-C golden shared library.
#
#   Usage:               make            (builds build/libcmodel_golden.so)
#   Clean:               make clean
#   Override C++ compiler: CXX=clang++ make
#   Override output:       OUT_DIR=out make
#
# The source set is the headless math core (no GL/GLUT, no display). It is the
# same TU list as the `cmodel_golden` target in CMakeLists.txt.

CXX     ?= g++
CXXFLAGS ?= -shared -fPIC -O3 -std=c++11 -Iinclude
LDLIBS  := -lm

OUT_DIR  ?= build
TARGET   := $(OUT_DIR)/libcmodel_golden.so

SRCS := \
    src/cmodel_core.cpp \
    src/struct.cpp \
    src/matrix.cpp \
    src/transform.cpp \
    src/obj.cpp \
    src/algorithms.cpp \
    src/mif.cpp \
    src/cmodel_golden.cpp

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRCS) | $(OUT_DIR)
	$(CXX) $(CXXFLAGS) $(SRCS) -o $@ $(LDLIBS)

$(OUT_DIR):
	mkdir -p $(OUT_DIR)

clean:
	rm -f $(TARGET)
