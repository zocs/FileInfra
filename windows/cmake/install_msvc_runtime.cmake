# Use the selected Visual Studio toolchain's redistributables, never DLLs
# from System32 or a downloaded redistributable installer.
set(CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS_SKIP TRUE)
set(CMAKE_INSTALL_DEBUG_LIBRARIES FALSE)
set(CMAKE_INSTALL_DEBUG_LIBRARIES_ONLY FALSE)
include(InstallRequiredSystemLibraries)

# CMake treats vcruntime140_1.dll as optional; FileInfra and its plugins
# import it on x64. Fail the Release/Profile install if discovery is incomplete
# even when a stale copy is already present in the output directory.
set(_fileinfra_missing_runtime
  msvcp140.dll vcruntime140.dll vcruntime140_1.dll)
foreach(_fileinfra_runtime IN LISTS CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS)
  if(EXISTS "${_fileinfra_runtime}")
    get_filename_component(_fileinfra_runtime_name "${_fileinfra_runtime}" NAME)
    string(TOLOWER "${_fileinfra_runtime_name}" _fileinfra_runtime_name)
    list(REMOVE_ITEM _fileinfra_missing_runtime "${_fileinfra_runtime_name}")
  endif()
endforeach()

install(CODE "
  if(CMAKE_INSTALL_CONFIG_NAME MATCHES \"^(Release|Profile)$\")
    if(NOT \"${_fileinfra_missing_runtime}\" STREQUAL \"\")
      message(FATAL_ERROR \"Required MSVC redistributables were not found: ${_fileinfra_missing_runtime}. Install the Visual Studio C++ redistributable component.\")
    endif()
  endif()
" COMPONENT Runtime)

if(CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS)
  install(FILES ${CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS}
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    CONFIGURATIONS Profile Release
    COMPONENT Runtime)
endif()
