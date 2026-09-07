cmake_minimum_required(VERSION 3.23.0)
project(glut_keyhandling)
set(CMAKE_CXX_STANDARD 11)

set(CMAKE_SOURCE_DIR src/)
set(SOURCE_FILES ${SOURCE_FILES} ./${CMAKE_SOURCE_DIR}/main.cpp)
set(SOURCE_FILES ${SOURCE_FILES} ./${CMAKE_SOURCE_DIR}/renderer.cpp)
set(SOURCE_FILES ${SOURCE_FILES} ./${CMAKE_SOURCE_DIR}/animate.cpp)
set(SOURCE_FILES ${SOURCE_FILES} ./${CMAKE_SOURCE_DIR}/algorithms.cpp)
set(SOURCE_FILES ${SOURCE_FILES} ./${CMAKE_SOURCE_DIR}/obj.cpp)
set(SOURCE_FILES ${SOURCE_FILES} ./${CMAKE_SOURCE_DIR}/struct.cpp)
set(SOURCE_FILES ${SOURCE_FILES} ./${CMAKE_SOURCE_DIR}/xiaolin.cpp)
set(SOURCE_FILES ${SOURCE_FILES} ./${CMAKE_SOURCE_DIR}/transform.cpp)
set(SOURCE_FILES ${SOURCE_FILES} ./${CMAKE_SOURCE_DIR}/matrix.cpp)
set(SOURCE_FILES ${SOURCE_FILES} ./${CMAKE_SOURCE_DIR}/mif.cpp)
# Shared renderer state (globals, TRI/CCW, fb_write, zb_*). Linked by BOTH
# targets — this is what lets the pure-math TUs (transform/obj/algorithms/mif)
# link in the headless cmodel_golden target without duplicating definitions.
set(SOURCE_FILES ${SOURCE_FILES} ./${CMAKE_SOURCE_DIR}/cmodel_core.cpp)

include_directories(include/)

add_executable(glut_keyhandling ${SOURCE_FILES})

target_link_libraries(glut_keyhandling -lglut -lm -lGLU -lGL)
target_compile_options(glut_keyhandling PRIVATE -O3)

# cmodel_golden — headless shared library with the public C-ABI for DPI-C use
# from Phase B (UVM scoreboard). Pure math: no GL/GLUT, no display, no animation.
add_library(cmodel_golden SHARED
    ./${CMAKE_SOURCE_DIR}/cmodel_core.cpp
    ./${CMAKE_SOURCE_DIR}/struct.cpp
    ./${CMAKE_SOURCE_DIR}/matrix.cpp
    ./${CMAKE_SOURCE_DIR}/transform.cpp
    ./${CMAKE_SOURCE_DIR}/obj.cpp
    ./${CMAKE_SOURCE_DIR}/algorithms.cpp
    ./${CMAKE_SOURCE_DIR}/mif.cpp
    ./${CMAKE_SOURCE_DIR}/cmodel_golden.cpp
)

target_include_directories(cmodel_golden PRIVATE include/)
target_link_libraries(cmodel_golden -lm)
target_compile_options(cmodel_golden PRIVATE -O3)

# libpng is OPTIONAL — only used by cmodel_save_image() for off-sim image
# capture. find_package(...) is QUIET so a missing libpng still builds; the
# cmodel_save_image symbol is ALWAYS present (when libpng is absent the
# function simply returns CMODEL_FEATURE_UNAVAILABLE), so the ABI is stable
# across host environments and Phase B's DPI-C import does not need to
# feature-detect the symbol's presence.
find_package(PNG QUIET)
if(PNG_FOUND)
    target_include_directories(cmodel_golden PRIVATE ${PNG_INCLUDE_DIRS})
    target_link_libraries(cmodel_golden ${PNG_LIBRARIES})
    target_compile_definitions(cmodel_golden PRIVATE CMODEL_HAVE_LIBPNG)
    message(STATUS "cmodel_golden: libpng ENABLED  (${PNG_LIBRARIES}) — cmodel_save_image active")
else()
    message(STATUS "cmodel_golden: libpng MISSING — cmodel_save_image stub (returns CMODEL_FEATURE_UNAVAILABLE)")
endif()


