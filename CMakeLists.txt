cmake_minimum_required(VERSION 3.20)
project(RDNA2_Ray_Accelerator_Research CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Optimization flags
add_compile_options(-O3 -march=native -Wall -Wextra -Wno-unused-parameter -Wno-missing-field-initializers)

# Include paths
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/common
    /home/folk/.local/include
    /usr/include
)

# Common library
add_library(common STATIC
    common/vk_context.cpp
    common/vk_buffer.cpp
    common/vk_bvh.cpp
    common/vk_timer.cpp
    common/vk_shader.cpp
)
target_link_libraries(common PUBLIC vulkan)

# Subdirectories
add_subdirectory(exp0_probe)
add_subdirectory(exp1_visbuf)
add_subdirectory(exp2_occlusion)
add_subdirectory(exp3_spatial)
add_subdirectory(exp4_integration)
add_subdirectory(expA_async)
add_subdirectory(expB_shadows)
add_subdirectory(expC_reflections)
add_subdirectory(expD_screenspace)
add_subdirectory(expE_fullframe)
