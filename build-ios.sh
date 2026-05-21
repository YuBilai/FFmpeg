#!/bin/bash

# FFmpeg iOS Build Script
# 支持编译 iOS 设备 (arm64) 和模拟器 (x86_64, arm64) 的 FFmpeg 库

set -e

# 配置版本和路径
FFMPEG_VERSION="7.1"
SOURCE_DIR="$(pwd)"
BUILD_DIR="${SOURCE_DIR}/build/ios"
OUTPUT_DIR="${SOURCE_DIR}/output/ios"

# iOS 部署目标版本
IOS_DEPLOYMENT_TARGET="12.0"

# 支持的架构
ARCHS="arm64 x86_64"

# 清理并创建目录
rm -rf "${BUILD_DIR}" "${OUTPUT_DIR}"
mkdir -p "${BUILD_DIR}" "${OUTPUT_DIR}"

# 获取 Xcode 路径和工具
XCODE_PATH=$(xcode-select -p)
SDK_VERSION=$(xcrun --sdk iphoneos --show-sdk-version)
MIN_IOS_VERSION="${IOS_DEPLOYMENT_TARGET}"

echo "=========================================="
echo "FFmpeg iOS Build Script"
echo "=========================================="
echo "Xcode Path: ${XCODE_PATH}"
echo "SDK Version: ${SDK_VERSION}"
echo "Min iOS Version: ${MIN_IOS_VERSION}"
echo "Source: ${SOURCE_DIR}"
echo "Build: ${BUILD_DIR}"
echo "Output: ${OUTPUT_DIR}"
echo "=========================================="

# 编译函数
build_arch() {
    local ARCH=$1
    local BUILD_ARCH_DIR="${BUILD_DIR}/${ARCH}"
    
    echo ""
    echo ">>> Building for ${ARCH}..."
    
    # 设置 SDK 和平台
    if [ "${ARCH}" == "arm64" ]; then
        PLATFORM="iphoneos"
        HOST="aarch64-apple-darwin"
    elif [ "${ARCH}" == "x86_64" ]; then
        PLATFORM="iphonesimulator"
        HOST="x86_64-apple-darwin"
    else
        echo "Unknown architecture: ${ARCH}"
        exit 1
    fi
    
    SDK_PATH=$(xcrun --sdk ${PLATFORM} --show-sdk-path)
    CC="xcrun -sdk ${PLATFORM} clang"
    CXX="xcrun -sdk ${PLATFORM} clang++"
    
    echo "Platform: ${PLATFORM}"
    echo "SDK Path: ${SDK_PATH}"
    echo "Host: ${HOST}"
    
    # 创建构建目录
    mkdir -p "${BUILD_ARCH_DIR}"
    cd "${BUILD_ARCH_DIR}"
    
    # 设置编译标志
    CFLAGS="-arch ${ARCH} -mios-version-min=${MIN_IOS_VERSION} -isysroot ${SDK_PATH} -fembed-bitcode"
    LDFLAGS="-arch ${ARCH} -mios-version-min=${MIN_IOS_VERSION} -isysroot ${SDK_PATH}"
    
    # 设置 CPU 类型
    if [ "${ARCH}" == "arm64" ]; then
        CPU="armv8-a"
    elif [ "${ARCH}" == "x86_64" ]; then
        CPU="generic"
    else
        CPU="${ARCH}"
    fi
    
    # FFmpeg 配置选项
    CONFIGURE_FLAGS=(
        --prefix="${BUILD_ARCH_DIR}/install"
        --target-os=darwin
        --arch="${ARCH}"
        --cpu="${CPU}"
        --cc="${CC}"
        --cxx="${CXX}"
        --as="${CC}"
        --sysroot="${SDK_PATH}"
        --extra-cflags="${CFLAGS}"
        --extra-ldflags="${LDFLAGS}"
        --enable-cross-compile
        --disable-debug
        --disable-programs
        --disable-doc
        --disable-htmlpages
        --disable-manpages
        --disable-podpages
        --disable-txtpages
        --disable-ffplay
        --disable-ffmpeg
        --disable-ffprobe
        --enable-static
        --disable-shared
        --enable-pic
        --enable-small
        --disable-securetransport
        --disable-asm
        --disable-stripping
    )
    
    # 执行配置
    echo "Configuring FFmpeg for ${ARCH}..."
    "${SOURCE_DIR}/configure" "${CONFIGURE_FLAGS[@]}"
    
    # 编译
    echo "Building FFmpeg for ${ARCH}..."
    make -j$(sysctl -n hw.ncpu)
    make install
    
    cd "${SOURCE_DIR}"
    echo ">>> Finished building for ${ARCH}"
}

# 编译所有架构
for ARCH in ${ARCHS}; do
    build_arch ${ARCH}
done

# 创建通用库 (Universal Library)
echo ""
echo ">>> Creating universal libraries..."

UNIVERSAL_DIR="${OUTPUT_DIR}/universal"
mkdir -p "${UNIVERSAL_DIR}/lib" "${UNIVERSAL_DIR}/include"

# 获取库文件列表
LIBRARIES=$(ls "${BUILD_DIR}/arm64/install/lib/"*.a 2>/dev/null | xargs -n1 basename)

for LIB in ${LIBRARIES}; do
    echo "Creating universal library: ${LIB}"
    
    # 收集所有架构的库文件
    LIB_PATHS=""
    for ARCH in ${ARCHS}; do
        ARCH_LIB="${BUILD_DIR}/${ARCH}/install/lib/${LIB}"
        if [ -f "${ARCH_LIB}" ]; then
            LIB_PATHS="${LIB_PATHS} ${ARCH_LIB}"
        fi
    done
    
    # 使用 lipo 创建通用库
    lipo -create ${LIB_PATHS} -output "${UNIVERSAL_DIR}/lib/${LIB}"
    
    # 验证通用库
    echo "  Architectures in ${LIB}:"
    lipo -info "${UNIVERSAL_DIR}/lib/${LIB}"
done

# 复制头文件
echo ""
echo ">>> Copying headers..."
cp -R "${BUILD_DIR}/arm64/install/include/"* "${UNIVERSAL_DIR}/include/"

# 复制单个架构的库（供需要单独使用的情况）
echo ""
echo ">>> Copying single architecture libraries..."
for ARCH in ${ARCHS}; do
    ARCH_OUTPUT="${OUTPUT_DIR}/${ARCH}"
    mkdir -p "${ARCH_OUTPUT}/lib" "${ARCH_OUTPUT}/include"
    cp -R "${BUILD_DIR}/${ARCH}/install/lib/"*.a "${ARCH_OUTPUT}/lib/"
    cp -R "${BUILD_DIR}/${ARCH}/install/include/"* "${ARCH_OUTPUT}/include/"
done

# 生成模块映射（用于 Swift 导入）
echo ""
echo ">>> Generating module map..."
mkdir -p "${UNIVERSAL_DIR}/modules"
cat > "${UNIVERSAL_DIR}/modules/module.modulemap" << 'EOF'
module FFmpeg {
    umbrella header "libavcodec/avcodec.h"
    umbrella header "libavformat/avformat.h"
    umbrella header "libavutil/avutil.h"
    umbrella header "libswscale/swscale.h"
    umbrella header "libswresample/swresample.h"
    umbrella header "libavfilter/avfilter.h"
    umbrella header "libavdevice/avdevice.h"
    
    export *
    link "avcodec"
    link "avformat"
    link "avutil"
    link "swscale"
    link "swresample"
    link "avfilter"
    link "avdevice"
}
EOF

# 创建 FFmpeg  umbrella header
cat > "${UNIVERSAL_DIR}/include/FFmpeg.h" << 'EOF'
#ifndef FFMPEG_H
#define FFMPEG_H

#include "libavcodec/avcodec.h"
#include "libavformat/avformat.h"
#include "libavutil/avutil.h"
#include "libavutil/opt.h"
#include "libavutil/imgutils.h"
#include "libswscale/swscale.h"
#include "libswresample/swresample.h"
#include "libavfilter/avfilter.h"
#include "libavdevice/avdevice.h"

#endif /* FFMPEG_H */
EOF

# 创建 XCFramework
echo ""
echo ">>> Creating XCFramework..."

XCFRAMEWORK_DIR="${OUTPUT_DIR}/FFmpeg.xcframework"
rm -rf "${XCFRAMEWORK_DIR}"

# 为每个架构创建 framework
for ARCH in ${ARCHS}; do
    echo "Creating framework for ${ARCH}..."
    ARCH_FRAMEWORK="${BUILD_DIR}/${ARCH}/FFmpeg.framework"
    rm -rf "${ARCH_FRAMEWORK}"
    mkdir -p "${ARCH_FRAMEWORK}/Headers"
    
    # 创建通用库（合并所有 .a 文件）
    ARCH_LIBS=""
    for LIB in libavcodec.a libavformat.a libavutil.a libswscale.a libswresample.a libavfilter.a libavdevice.a; do
        ARCH_LIBS="${ARCH_LIBS} ${BUILD_DIR}/${ARCH}/install/lib/${LIB}"
    done
    
    # 使用 libtool 创建单个动态库
    libtool -static -o "${ARCH_FRAMEWORK}/FFmpeg" ${ARCH_LIBS}
    
    # 复制头文件
    cp -R "${BUILD_DIR}/${ARCH}/install/include/"* "${ARCH_FRAMEWORK}/Headers/"
    cp "${UNIVERSAL_DIR}/include/FFmpeg.h" "${ARCH_FRAMEWORK}/Headers/"
    
    # 创建 Info.plist
    cat > "${ARCH_FRAMEWORK}/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>FFmpeg</string>
    <key>CFBundleIdentifier</key>
    <string>org.ffmpeg.FFmpeg</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>FFmpeg</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>${FFMPEG_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>${IOS_DEPLOYMENT_TARGET}</string>
</dict>
</plist>
PLIST
done

# 创建 XCFramework
XCFRAMEWORK_CMD="xcodebuild -create-xcframework"
for ARCH in ${ARCHS}; do
    if [ "${ARCH}" == "arm64" ]; then
        PLATFORM="iphoneos"
    else
        PLATFORM="iphonesimulator"
    fi
    XCFRAMEWORK_CMD="${XCFRAMEWORK_CMD} -framework ${BUILD_DIR}/${ARCH}/FFmpeg.framework"
done
XCFRAMEWORK_CMD="${XCFRAMEWORK_CMD} -output ${XCFRAMEWORK_DIR}"

echo "Creating XCFramework with command:"
echo "${XCFRAMEWORK_CMD}"
eval "${XCFRAMEWORK_CMD}"

echo ""
echo "XCFramework created at: ${XCFRAMEWORK_DIR}"

# 验证 XCFramework
echo ""
echo ">>> Verifying XCFramework..."
lipo -info "${XCFRAMEWORK_DIR}/ios-arm64/FFmpeg.framework/FFmpeg"
lipo -info "${XCFRAMEWORK_DIR}/ios-x86_64-simulator/FFmpeg.framework/FFmpeg"

# 生成使用说明
cat > "${OUTPUT_DIR}/README.md" << EOF
# FFmpeg iOS Build

## 构建信息
- FFmpeg 版本: ${FFMPEG_VERSION}
- iOS 部署目标: ${IOS_DEPLOYMENT_TARGET}
- 支持的架构: ${ARCHS}
- 构建日期: $(date)

## 目录结构

### FFmpeg.xcframework (推荐)
苹果官方的 XCFramework 格式，同时支持真机 (arm64) 和模拟器 (x86_64)。
这是集成到 Xcode 项目的推荐方式。

### universal/
包含通用库 (fat library)，同时支持 arm64 (设备) 和 x86_64 (模拟器)。

### arm64/
仅包含 arm64 架构的库（用于真机）。

### x86_64/
仅包含 x86_64 架构的库（用于模拟器）。

## 使用方法

### 方法 1: 使用 XCFramework (推荐)

1. 将 FFmpeg.xcframework 拖入 Xcode 项目
2. 在 "General" -> "Frameworks, Libraries, and Embedded Content" 中添加 FFmpeg.xcframework
3. 确保 "Embed & Sign" 被选中
4. 导入头文件：
\`\`\`objc
#import <FFmpeg/FFmpeg.h>
\`\`\`

### 方法 2: 使用静态库

1. 导入库文件
将 universal/lib 下的所有 .a 文件添加到 Xcode 项目的 "Link Binary with Libraries" 中。

2. 添加头文件路径
在 Build Settings 中设置 Header Search Paths 为 universal/include 的路径。

3. 链接系统框架
需要链接以下系统框架：
- Foundation.framework
- CoreMedia.framework
- CoreVideo.framework
- VideoToolbox.framework (可选，用于硬件解码)
- AudioToolbox.framework

4. 导入头文件
\`\`\`objc
#import "FFmpeg.h"
// 或单独导入
#import "libavcodec/avcodec.h"
#import "libavformat/avformat.h"
\`\`\`

## 包含的库
- libavcodec - 编解码器库
- libavformat - 格式处理库
- libavutil - 工具库
- libswscale - 视频缩放和颜色转换库
- libswresample - 音频重采样库
- libavfilter - 滤镜库
- libavdevice - 设备库

## 编译配置
$(cat "${BUILD_DIR}/arm64/ffbuild/config.mak" 2>/dev/null | grep -E "^(CC|CXX|CFLAGS|LDFLAGS)" || echo "Config not available")
EOF

echo ""
echo "=========================================="
echo "Build completed successfully!"
echo "=========================================="
echo ""
echo "Output locations:"
echo "  Universal library: ${UNIVERSAL_DIR}/"
echo "  ARM64 library:     ${OUTPUT_DIR}/arm64/"
echo "  x86_64 library:    ${OUTPUT_DIR}/x86_64/"
echo ""
echo "Libraries built:"
ls -la "${UNIVERSAL_DIR}/lib/"
echo ""
echo "See ${OUTPUT_DIR}/README.md for usage instructions."
