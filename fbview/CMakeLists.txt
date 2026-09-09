cmake_minimum_required(VERSION 3.23.0)
project(fbview)
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# fbview — minimal C-ABI shared library that serializes a raw framebuffer
# buffer (the DUT's 15-bit {cc,cc,cc} word layout): PNG save (fbview_save_png)
# and live display (fbview_open/update/is_open/close). It is a *viewer* of data:
# it renders exactly the word it is handed, applying only the documented
# 5-bit->8-bit rescale.

include_directories(include/)

add_library(fbview SHARED
    src/fbview_save.cpp
    src/fbview_gui.cpp
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

# SDL2 is OPTIONAL — only used by the four live-display symbols (see
# fbview_gui.cpp). find_package(...) QUIET so a missing SDL2 still builds; the
# four display symbols are ALWAYS present (when SDL2 is absent they return
# FBVIEW_FEATURE_UNAVAILABLE), so the ABI is stable across host environments.
# The gate is independent of FBVIEW_HAVE_PNG above — any of the four
# (PNG on/off) x (SDL2 on/off) build combos is legal.
find_package(SDL2 QUIET)
if(SDL2_FOUND)
    target_include_directories(fbview PRIVATE ${SDL2_INCLUDE_DIRS})
    target_link_libraries(fbview PRIVATE ${SDL2_LIBRARIES})
    target_compile_definitions(fbview PRIVATE FBVIEW_HAVE_SDL2)
    message(STATUS "fbview: SDL2 ENABLED  (${SDL2_LIBRARIES}) — fbview_open/update/is_open/close active")
else()
    message(STATUS "fbview: SDL2 MISSING — display symbols stub (return FBVIEW_FEATURE_UNAVAILABLE)")
endif()

# gui_driver — live-GUI acceptance helper (see tests/gui_driver.c). Plain C,
# links the fbview library only (no GL, no GTK); builds in every combo — in the
# SDL2-absent build it still *links* (the ABI is stable) and exits 1 at runtime
# with a "SDL2 not available" message.
add_executable(fbview_gui_driver tests/gui_driver.c)
target_link_libraries(fbview_gui_driver PRIVATE fbview -lm)
