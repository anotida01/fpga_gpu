cmake_minimum_required(VERSION 3.23.0)
project(fbview)
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# fbview — minimal C-ABI shared library that serializes a raw framebuffer
# buffer (the DUT's 15-bit {cc,cc,cc} word layout) to a PNG. v1 exports exactly
# one symbol, fbview_save_png. It is a *viewer* of data: it renders exactly the
# word it is handed, applying only the documented 5-bit->8-bit rescale.

include_directories(include/)

add_library(fbview SHARED
    src/fbview_save.cpp
)

target_include_directories(fbview PRIVATE include/)
target_link_libraries(fbview PRIVATE -lm)
target_compile_options(fbview PRIVATE -O3)

# libpng is OPTIONAL — only used by fbview_save_png() for off-sim image output.
# find_package(...) is QUIET so a missing libpng still builds; the
# fbview_save_png symbol is ALWAYS present (when libpng is absent the function
# simply returns FBVIEW_FEATURE_UNAVAILABLE), so the ABI is stable across host
# environments and a DPI-C import does not need to feature-detect the symbol.
find_package(PNG QUIET)
if(PNG_FOUND)
    target_include_directories(fbview PRIVATE ${PNG_INCLUDE_DIRS})
    target_link_libraries(fbview PRIVATE ${PNG_LIBRARIES})
    target_compile_definitions(fbview PRIVATE FBVIEW_HAVE_PNG)
    message(STATUS "fbview: libpng ENABLED  (${PNG_LIBRARIES}) — fbview_save_png active")
else()
    message(STATUS "fbview: libpng MISSING — fbview_save_png stub (returns FBVIEW_FEATURE_UNAVAILABLE)")
endif()
