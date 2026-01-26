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

include_directories(include/)

add_executable(glut_keyhandling ${SOURCE_FILES})

target_link_libraries(glut_keyhandling -lglut -lm -lGLU -lGL)
target_compile_options(glut_keyhandling PRIVATE -O3)


