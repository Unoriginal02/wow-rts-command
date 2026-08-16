cmake_minimum_required(VERSION 3.20)
project(rts_client_mod CXX)

# Wow.exe 3.3.5a is x86. A 64-bit DLL cannot load into it and a 64-bit injector
# cannot CreateRemoteThread into it, so make the mistake impossible to miss.
if(NOT CMAKE_SIZEOF_VOID_P EQUAL 4)
    message(FATAL_ERROR
        "rts_client_mod must be built 32-bit.\n"
        "Reconfigure with:  cmake -S . -B build -G \"Visual Studio 17 2022\" -A Win32")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Static CRT: the injected DLL must not depend on a VC++ redistributable being
# present, since it loads into a 2010-era client.
cmake_policy(SET CMP0091 NEW)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

add_library(rts_core SHARED
    src/dllmain.cpp
    src/MainThreadHook.cpp
    src/Log.cpp
    src/LuaApi.cpp
    src/ObjectManager.cpp
    src/Publisher.cpp
    src/World.cpp
    src/Camera.cpp
    src/CursorRay.cpp
    src/GroundRing.cpp
    src/CVarChannel.cpp
    src/Highlight.cpp
    src/Circle.cpp
)
target_include_directories(rts_core PRIVATE src)
target_compile_definitions(rts_core PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
set_target_properties(rts_core PROPERTIES OUTPUT_NAME "rts_core" PREFIX "")

add_executable(injector injector/main.cpp)
target_compile_definitions(injector PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)

# Put both next to each other; the injector looks for the DLL beside itself.
set_target_properties(rts_core injector PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY         "${CMAKE_BINARY_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG   "${CMAKE_BINARY_DIR}/bin"
    LIBRARY_OUTPUT_DIRECTORY         "${CMAKE_BINARY_DIR}/bin"
)
