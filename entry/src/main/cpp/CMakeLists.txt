cmake_minimum_required(VERSION 3.16)
project(archiveextract LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 17)

set(ZIP_DEPS "${CMAKE_CURRENT_SOURCE_DIR}/../../../../third_party/zip-deps/${OHOS_ARCH}")
if(NOT EXISTS "${ZIP_DEPS}/lib/libcrypto.a")
  message(FATAL_ERROR "Run scripts/build-zip-deps.sh first")
endif()

set(OPENSSL_ROOT_DIR "${ZIP_DEPS}")
set(OPENSSL_USE_STATIC_LIBS TRUE)
set(OPENSSL_INCLUDE_DIR "${ZIP_DEPS}/include" CACHE PATH "" FORCE)
set(OPENSSL_CRYPTO_LIBRARY "${ZIP_DEPS}/lib/libcrypto.a" CACHE FILEPATH "" FORCE)
set(OPENSSL_SSL_LIBRARY "${ZIP_DEPS}/lib/libssl.a" CACHE FILEPATH "" FORCE)
set(ENABLE_COMMONCRYPTO OFF CACHE BOOL "" FORCE)
set(ENABLE_GNUTLS OFF CACHE BOOL "" FORCE)
set(ENABLE_BZIP2 OFF CACHE BOOL "" FORCE)
set(ENABLE_LZMA OFF CACHE BOOL "" FORCE)
set(ENABLE_ZSTD OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(BUILD_REGRESS OFF CACHE BOOL "" FORCE)
set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(BUILD_DOC OFF CACHE BOOL "" FORCE)
set(LIBZIP_DO_INSTALL OFF CACHE BOOL "" FORCE)
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../../../../third_party/libzip" libzip-build)

add_library(archiveextract SHARED archive_extract.cpp)
target_include_directories(archiveextract PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../../../../third_party/libzip/lib"
  "${CMAKE_CURRENT_BINARY_DIR}/libzip-build"
  "${ZIP_DEPS}/include")
target_link_libraries(archiveextract PRIVATE zip "${ZIP_DEPS}/lib/libcrypto.a" libace_napi.z.so z m dl)
target_compile_options(archiveextract PRIVATE -Wall -Wextra)
