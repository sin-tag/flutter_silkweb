cmake_minimum_required(VERSION 3.10)
# Project name must match the package name in pubspec.yaml — Flutter's
# linux build looks up `<package>_plugin` to link.
set(PROJECT_NAME "flutter_silkweb")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "flutter_silkweb_plugin")

add_library(${PLUGIN_NAME} SHARED
    "webf_plugin.cc"
)

# Apply a standard set of build settings that are configured in the
# application-level CMakeLists.txt. This can be removed for plugins that want
# full control over build settings.
apply_standard_settings(${PLUGIN_NAME})

# Symbols are hidden by default to reduce the chance of accidental conflicts
# between plugins. This should not be removed; any symbols that should be
# exported should be explicitly exported with the FLUTTER_PLUGIN_EXPORT macro.
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

# Source include directories and library dependencies. Add any plugin-specific
# dependencies here.
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)

# Automatically copy shared library files during CMake configuration
find_program(NODE_EXECUTABLE node)
if(NODE_EXECUTABLE)
    message(STATUS "Running resolve_libs.js to copy shared library files...")
    execute_process(
        COMMAND ${NODE_EXECUTABLE} "${CMAKE_CURRENT_SOURCE_DIR}/resolve_libs.js"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
        RESULT_VARIABLE RESOLVE_RESULT
        OUTPUT_VARIABLE RESOLVE_OUTPUT
        ERROR_VARIABLE RESOLVE_ERROR
    )
    
    if(NOT RESOLVE_RESULT EQUAL 0)
        message(WARNING "resolve_libs.js failed: ${RESOLVE_ERROR}")
    else()
        message(STATUS "Shared library copying completed: ${RESOLVE_OUTPUT}")
    endif()
else()
    message(WARNING "Node.js not found, symbolic links will be used directly")
endif()

# List of absolute paths to libraries that should be bundled with the plugin
# Note: libwebf.so now contains statically linked QuickJS and libc++
set(flutter_silkweb_bundled_libraries
    ${CMAKE_CURRENT_SOURCE_DIR}/libwebf.so
    ${CMAKE_CURRENT_SOURCE_DIR}/libc++.so.1
    ${CMAKE_CURRENT_SOURCE_DIR}/libc++abi.so.1
    ${CMAKE_CURRENT_SOURCE_DIR}/libunwind.so.1
    PARENT_SCOPE
  )
