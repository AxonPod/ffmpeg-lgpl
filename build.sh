#!/usr/bin/env bash
# Builds FFmpeg as LGPL-2.1-or-later shared libraries (no --enable-gpl, no
# --enable-version3, no --enable-nonfree), with the software encoders
# OpenH264 (H.264, BSD-2-Clause) and SVT-AV1 (AV1, BSD-3-Clause-Clear), the
# platform's hardware encoders, and dav1d (BSD-2-Clause) to decode AV1
# without AV1 hardware. Shared libraries only, so that a program linking
# them keeps them replaceable, as the LGPL requires.
#
#   ./build.sh            # download (once), build, install, verify
#   ./build.sh --clean    # the same from fresh build directories
#   ./build.sh --fetch    # only download and check the sources
#   JOBS=4 ./build.sh     # parallel jobs (default: every core)
#   OUT=/some/dir ./build.sh   # install into /some/dir/<platform> (default out/)
#
# Layout (next to this script; all of it is gitignored):
#
#   src/<tarball>             pinned sources, SHA-256 checked
#   build/<platform>/…        build trees
#   out/<platform>/           the install: lib/ (shared libraries,
#                             pkg-config files), include/, bin/ffmpeg (a
#                             tool for checks), share/licenses/,
#                             BUILD-INFO.txt and a copy of this script
#
# <platform> is macos-arm64, macos-x86_64, linux-x86_64, linux-aarch64 or
# windows-x86_64. The install can be moved: the pkg-config files name their
# own directory (${pcfiledir}), the macOS libraries are @rpath/<name>, the
# Linux ones find each other through $ORIGIN.
#
# Everything is enabled explicitly after --disable-autodetect and
# --disable-everything, so nothing (GPL or otherwise) comes in because it
# happens to be installed: the decoders, demuxers and parsers of MP4/MOV
# (H.264, HEVC, ProRes, AV1, AAC), MKV and the common audio files (WAV,
# FLAC, MP3, M4A with AAC or ALAC, Ogg with Vorbis, Opus or FLAC, ADTS AAC),
# the MP4 muxer and the encoders above, file I/O only (no network), the few
# filters the `ffmpeg` tool needs to convert formats. At the end the build
# is checked: config.h must say LGPL 2.1+ with GPL, version 3 and nonfree
# off, and the `ffmpeg` tool must list the encoders.
#
# Tools: a C compiler, make, pkg-config, meson + ninja (OpenH264, dav1d), cmake
# (SVT-AV1, libvpl), nasm (x86 only). macOS: `brew install nasm cmake meson
# ninja pkg-config` (Xcode's command line tools for clang). Linux (Debian/
# Ubuntu): `apt install build-essential nasm cmake meson ninja-build
# pkg-config patchelf libva-dev libdrm-dev zlib1g-dev`.
#
# Windows: MSYS2's UCRT64 shell with `pacman -S
# mingw-w64-ucrt-x86_64-{gcc,nasm,cmake,meson,ninja,pkgconf,zlib} make
# diffutils`, then this script; it builds with --enable-mediafoundation,
# --enable-d3d11va/dxva2, NVENC/NVDEC (nv-codec-headers, MIT), AMF (AMF
# headers, MIT) and QSV (libvpl, MIT). The DLLs land in bin/; MinGW's
# runtimes (libgcc, libstdc++, winpthreads) and zlib are linked into them
# statically, so they need nothing but Windows (checked). lib/ holds MSVC
# import libraries (<name>.lib, from the .def files FFmpeg writes) next to
# MinGW's, so that MSVC-built programs can link the DLLs too.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
SRC="$ROOT/src"
REPOSITORY=https://github.com/AxonPod/ffmpeg-lgpl
# The revision BUILD-INFO.txt names: a release's tag, or the commit.
REVISION=${REVISION:-$(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null || echo unknown)}

# --- Pinned sources: version, URL, SHA-256 -------------------------------

# FFmpeg 8.1.x: libavcodec 62, libavformat 62, libavutil 60.
FFMPEG_VERSION=8.1.3
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz"
FFMPEG_SHA256=7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3

OPENH264_VERSION=2.6.0
OPENH264_URL="https://github.com/cisco/openh264/archive/refs/tags/v$OPENH264_VERSION.tar.gz"
OPENH264_SHA256=558544ad358283a7ab2930d69a9ceddf913f4a51ee9bf1bfb9e377322af81a69

# SVT-AV1 4.x: the API FFmpeg 8.1's libsvtav1 wrapper builds against (as in
# Homebrew's ffmpeg@8).
SVTAV1_VERSION=4.2.0
SVTAV1_URL="https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v$SVTAV1_VERSION/SVT-AV1-v$SVTAV1_VERSION.tar.gz"
SVTAV1_SHA256=c7b13c4a84bd3751aa35fcc72be13e6875467e7c2216879251a486e5b1e4e740

DAV1D_VERSION=1.5.4
DAV1D_URL="https://downloads.videolan.org/pub/videolan/dav1d/$DAV1D_VERSION/dav1d-$DAV1D_VERSION.tar.xz"
DAV1D_SHA256=686616b7c69eb88d44459391ab25cac13b6647a3b288835c5784e71c1514a5c5

# Windows and Linux only. nv-codec-headers 12.1: the oldest FFmpeg 8.1
# accepts first, NVIDIA driver 530.41 (Linux) / 531.61 (Windows) or newer.
NVHEADERS_VERSION=12.1.14.1
NVHEADERS_URL="https://github.com/FFmpeg/nv-codec-headers/releases/download/n$NVHEADERS_VERSION/nv-codec-headers-$NVHEADERS_VERSION.tar.gz"
NVHEADERS_SHA256=043e46265517855f13bcb98b3a225b2761b2a83983b1645fa1d05876f1c3a781
AMF_VERSION=1.5.3
AMF_URL="https://github.com/GPUOpen-LibrariesAndSDKs/AMF/releases/download/v$AMF_VERSION/AMF-headers-v$AMF_VERSION.tar.gz"
AMF_SHA256=0f521ad98041f8001147cded4a660127f18b1c27a801a5cd691bda1fa48381be
LIBVPL_VERSION=2.16.0
LIBVPL_URL="https://github.com/intel/libvpl/archive/refs/tags/v$LIBVPL_VERSION.tar.gz"
LIBVPL_SHA256=d60931937426130ddad9f1975c010543f0da99e67edb1c6070656b7947f633b6

# --- Platform ------------------------------------------------------------

case "$(uname -s)" in
    Darwin) OS=macos ;;
    Linux) OS=linux ;;
    MINGW* | MSYS* | CYGWIN*) OS=windows ;;
    *) echo "unsupported system: $(uname -s)" >&2; exit 1 ;;
esac
ARCH=$(uname -m)
[ "$ARCH" = amd64 ] && ARCH=x86_64
PLATFORM="$OS-$ARCH"
OUT=${OUT:-$ROOT/out}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
PREFIX="$OUT/$PLATFORM"
BUILD="$ROOT/build/$PLATFORM"
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}

case "${1:-}" in
    --clean) rm -rf "$BUILD" "$PREFIX" ;;
    --fetch | "") ;;
    *) echo "usage: $0 [--clean | --fetch]" >&2; exit 1 ;;
esac
mkdir -p "$SRC"

need=(make pkg-config meson ninja cmake)
case "$OS" in
    macos) need+=(clang install_name_tool) ;;
    linux) need+=(cc patchelf) ;;
    windows) need+=(cc objdump) ;;
esac
case "$ARCH" in x86_64 | i?86) need+=(nasm) ;; esac
for tool in "${need[@]}"; do
    command -v "$tool" >/dev/null || { echo "missing build tool: $tool (see the top of $0)" >&2; exit 1; }
done

if [ "$OS" = macos ]; then
    # The oldest macOS the libraries run on.
    export MACOSX_DEPLOYMENT_TARGET=13.0
fi
# Only our own prefix (and, on Linux, the system's libva/libdrm): nothing
# from Homebrew or elsewhere gets found by accident.
if [ "$OS" = linux ]; then
    export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
else
    export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
fi
if [ "$OS" = windows ]; then
    # MinGW's runtimes and zlib statically: a directory searched before the
    # toolchain's that holds only their static archives (the linker takes
    # the first directory with a match, .dll.a or .a).
    STATIC="$BUILD/static-libs"
    mkdir -p "$STATIC"
    cp "$MINGW_PREFIX/lib/libwinpthread.a" "$STATIC/libwinpthread.a"
    cp "$MINGW_PREFIX/lib/libwinpthread.a" "$STATIC/libpthread.a"
    cp "$MINGW_PREFIX/lib/libz.a" "$STATIC/libz.a"
    # A Windows path (D:/…): meson and cmake are native programs, and MSYS2
    # does not convert a path inside LDFLAGS for them.
    export LDFLAGS="-static-libgcc -static-libstdc++ -L$(cygpath -m "$STATIC")"
fi

# --- Helpers -------------------------------------------------------------

sha256() {
    if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}

# fetch URL SHA256 FILE: downloads into src/ (once) and checks.
fetch() {
    local file="$SRC/$3"
    if [ ! -f "$file" ]; then
        echo "downloading $1"
        curl -fL --retry 3 -o "$file.part" "$1"
        mv "$file.part" "$file"
    fi
    local got
    got=$(sha256 "$file")
    if [ "$got" != "$2" ]; then
        echo "SHA-256 mismatch for $file: $got, expected $2" >&2
        exit 1
    fi
}

# unpack FILE DIR: a fresh copy of the source in the build tree.
unpack() {
    rm -rf "${BUILD:?}/$2"
    mkdir -p "$BUILD/$2"
    tar -xf "$SRC/$1" -C "$BUILD/$2" --strip-components 1
}

# license NAME FILES…: the licence texts into share/licenses/NAME.
license() {
    local name=$1
    shift
    mkdir -p "$PREFIX/share/licenses/$name"
    cp "$@" "$PREFIX/share/licenses/$name/"
}

# --- OpenH264 (meson) ----------------------------------------------------

build_openh264() {
    fetch "$OPENH264_URL" "$OPENH264_SHA256" "openh264-$OPENH264_VERSION.tar.gz"
    unpack "openh264-$OPENH264_VERSION.tar.gz" openh264
    meson setup "$BUILD/openh264/build" "$BUILD/openh264" \
        --prefix="$PREFIX" --libdir=lib --buildtype=release \
        --default-library=shared -Dtests=disabled
    ninja -C "$BUILD/openh264/build" -j "$JOBS" install
    license openh264 "$BUILD/openh264/LICENSE"
}

# --- dav1d (meson) -------------------------------------------------------

build_dav1d() {
    fetch "$DAV1D_URL" "$DAV1D_SHA256" "dav1d-$DAV1D_VERSION.tar.xz"
    unpack "dav1d-$DAV1D_VERSION.tar.xz" dav1d
    meson setup "$BUILD/dav1d/build" "$BUILD/dav1d" \
        --prefix="$PREFIX" --libdir=lib --buildtype=release \
        --default-library=shared -Denable_tools=false -Denable_tests=false
    ninja -C "$BUILD/dav1d/build" -j "$JOBS" install
    license dav1d "$BUILD/dav1d/COPYING"
}

# --- SVT-AV1 (cmake) -----------------------------------------------------

# LOG_QUIET: no banner on stderr each time an encoder opens (FFmpeg reports
# failures itself).

build_svtav1() {
    fetch "$SVTAV1_URL" "$SVTAV1_SHA256" "SVT-AV1-v$SVTAV1_VERSION.tar.gz"
    unpack "SVT-AV1-v$SVTAV1_VERSION.tar.gz" svt-av1
    cmake -S "$BUILD/svt-av1" -B "$BUILD/svt-av1/build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_INSTALL_NAME_DIR=@rpath \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_APPS=OFF \
        -DBUILD_TESTING=OFF \
        -DLOG_QUIET=ON
    cmake --build "$BUILD/svt-av1/build" -j "$JOBS"
    cmake --install "$BUILD/svt-av1/build"
    license svt-av1 "$BUILD/svt-av1/LICENSE.md" "$BUILD/svt-av1/PATENTS.md"
}

# --- Hardware SDK headers (Windows, Linux) -------------------------------

build_nvheaders() {
    fetch "$NVHEADERS_URL" "$NVHEADERS_SHA256" "nv-codec-headers-$NVHEADERS_VERSION.tar.gz"
    unpack "nv-codec-headers-$NVHEADERS_VERSION.tar.gz" nv-codec-headers
    make -C "$BUILD/nv-codec-headers" PREFIX="$PREFIX" install
    # No licence file in the release: the MIT notice heads each header.
    mkdir -p "$PREFIX/share/licenses/nv-codec-headers"
    awk '{ print } /\*\// { exit }' "$BUILD/nv-codec-headers/include/ffnvcodec/nvEncodeAPI.h" \
        >"$PREFIX/share/licenses/nv-codec-headers/LICENSE"
}

build_amf_headers() {
    fetch "$AMF_URL" "$AMF_SHA256" "AMF-headers-v$AMF_VERSION.tar.gz"
    unpack "AMF-headers-v$AMF_VERSION.tar.gz" amf
    rm -rf "$PREFIX/include/AMF"
    mkdir -p "$PREFIX/include"
    cp -R "$BUILD/amf/AMF" "$PREFIX/include/AMF"
    # The MIT notice heads each header.
    mkdir -p "$PREFIX/share/licenses/amf"
    awk '{ print } /\*\// { exit }' "$BUILD/amf/AMF/core/Factory.h" >"$PREFIX/share/licenses/amf/LICENSE"
}

build_libvpl() {
    fetch "$LIBVPL_URL" "$LIBVPL_SHA256" "libvpl-$LIBVPL_VERSION.tar.gz"
    unpack "libvpl-$LIBVPL_VERSION.tar.gz" libvpl
    local flags=()
    # MinGW: the dispatcher defines wcscpy_s as a macro (for old MSVC),
    # which breaks an inline function of windows.h included after it;
    # windows.h first, before the macro, leaves the sources unmodified.
    if [ "$OS" = windows ]; then flags+=(-DCMAKE_CXX_FLAGS="-include windows.h"); fi
    cmake -S "$BUILD/libvpl" -B "$BUILD/libvpl/build" -G Ninja "${flags[@]}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_TESTS=OFF \
        -DBUILD_EXAMPLES=OFF \
        -DINSTALL_EXAMPLES=OFF \
        -DBUILD_TOOLS=OFF
    cmake --build "$BUILD/libvpl/build" -j "$JOBS"
    cmake --install "$BUILD/libvpl/build"
    license libvpl "$BUILD/libvpl/LICENSE"
}

# --- FFmpeg --------------------------------------------------------------

# Shared by every platform.
FFMPEG_FLAGS=(
    --prefix="$PREFIX"
    --enable-shared
    --disable-static
    --enable-pic
    # Licence: LGPL-2.1-or-later. Never --enable-gpl, --enable-version3 or
    # --enable-nonfree (checked below).
    --disable-autodetect
    --disable-everything
    --disable-network
    --disable-debug
    --disable-doc
    --disable-programs
    --enable-ffmpeg
    --enable-pthreads
    --enable-zlib
    --enable-libopenh264
    --enable-libsvtav1
    --enable-libdav1d
    --enable-protocol=file,pipe
    # Clips (MP4/MOV), music (WAV, FLAC, MP3, M4A, Ogg, ADTS AAC), MKV.
    --enable-demuxer=mov,wav,flac,mp3,ogg,aac,matroska
    --enable-muxer=mp4,mov,null
    # Video: the clips' codecs; AV1 (dav1d, or the native decoder on AV1
    # hardware); MJPEG/PNG for cover art in music files.
    --enable-decoder=h264,hevc,prores,libdav1d,av1,mjpeg,png
    --enable-decoder=aac,aac_fixed,alac,flac,mp3,mp3float,vorbis,opus
    --enable-decoder=pcm_s16le,pcm_s16be,pcm_s24le,pcm_s24be,pcm_s32le,pcm_s32be,pcm_f32le,pcm_f32be,pcm_f64le,pcm_u8,pcm_alaw,pcm_mulaw
    --enable-parser=h264,hevc,av1,aac,mpegaudio,flac,vorbis,opus,mjpeg,png
    --enable-bsfs
    # FFmpeg's own AAC encoder (LGPL), the software video encoders.
    --enable-encoder=aac,libopenh264,libsvtav1
    # What the `ffmpeg` tool inserts to convert between formats.
    --enable-filter=buffer,buffersink,abuffer,abuffersink,format,aformat,null,anull,scale,aresample,setpts,asetpts,trim,atrim,fps,copy,hwupload,hwdownload
)

build_ffmpeg() {
    fetch "$FFMPEG_URL" "$FFMPEG_SHA256" "ffmpeg-$FFMPEG_VERSION.tar.xz"
    unpack "ffmpeg-$FFMPEG_VERSION.tar.xz" ffmpeg
    local flags=("${FFMPEG_FLAGS[@]}")
    case "$OS" in
        macos)
            flags+=(
                --cc=clang
                --enable-videotoolbox
                --enable-audiotoolbox
                --enable-encoder=h264_videotoolbox,hevc_videotoolbox
                --enable-hwaccel=h264_videotoolbox,hevc_videotoolbox,prores_videotoolbox,av1_videotoolbox
                # Install names @rpath/libavcodec.62.dylib…: a program finds
                # them through its own rpath, wherever it carries them; room
                # for install_name_tool.
                --install-name-dir=@rpath
                --extra-ldflags=-Wl,-headerpad_max_install_names
                --extra-ldexeflags=-Wl,-rpath,@loader_path/../lib
            )
            ;;
        linux)
            flags+=(
                --enable-vaapi
                --enable-libdrm
                --enable-ffnvcodec --enable-nvenc --enable-nvdec --enable-cuda
                --enable-libvpl
                --enable-encoder=h264_vaapi,hevc_vaapi,h264_nvenc,hevc_nvenc,h264_qsv,hevc_qsv
                --enable-hwaccel=h264_vaapi,hevc_vaapi,av1_vaapi,h264_nvdec,hevc_nvdec,av1_nvdec
            )
            ;;
        windows)
            # Windows threads, not winpthreads.
            flags=("${flags[@]/--enable-pthreads/--enable-w32threads}")
            flags+=(
                --extra-ldflags="$LDFLAGS"
                --enable-mediafoundation
                --enable-d3d11va --enable-dxva2
                --enable-ffnvcodec --enable-nvenc --enable-nvdec --enable-cuda
                --enable-amf
                --enable-libvpl
                --enable-encoder=h264_mf,hevc_mf,h264_nvenc,hevc_nvenc,h264_amf,hevc_amf,h264_qsv,hevc_qsv
                --enable-hwaccel=h264_d3d11va,h264_d3d11va2,hevc_d3d11va,hevc_d3d11va2,av1_d3d11va,av1_d3d11va2,h264_dxva2,hevc_dxva2,h264_nvdec,hevc_nvdec,av1_nvdec
            )
            ;;
    esac
    (cd "$BUILD/ffmpeg" && ./configure "${flags[@]}" --extra-cflags="-I$PREFIX/include" --extra-ldflags="-L$PREFIX/lib")
    make -C "$BUILD/ffmpeg" -j "$JOBS"
    make -C "$BUILD/ffmpeg" install
    license ffmpeg "$BUILD/ffmpeg/COPYING.LGPLv2.1" "$BUILD/ffmpeg/LICENSE.md" "$BUILD/ffmpeg/CREDITS"
}

# Every dylib named @rpath/<file> and every reference between them too (meson
# and cmake may record absolute paths), so that a program can carry them.
fix_install_names() {
    local file id dep
    for file in "$PREFIX"/lib/*.dylib "$PREFIX/bin/ffmpeg"; do
        [ -L "$file" ] && continue
        if [ "${file%.dylib}" != "$file" ]; then
            id=$(otool -D "$file" | tail -n 1)
            install_name_tool -id "@rpath/$(basename "$id")" "$file"
        fi
        for dep in $(otool -L "$file" | awk 'NR > 1 { print $1 }' | grep "^$PREFIX/lib/" || true); do
            install_name_tool -change "$dep" "@rpath/$(basename "$dep")" "$file"
        done
        # install_name_tool invalidates the linker's ad-hoc signature.
        codesign --force --sign - "$file" 2>/dev/null
    done
}

# The libraries find the ones they link (OpenH264…) next to themselves, the
# tool in ../lib: a program's RUNPATH covers only its own direct
# dependencies. (patchelf: configure's flags pass through
# two shells and make, which mangle a literal $ORIGIN.)
set_runpaths() {
    local file
    for file in "$PREFIX"/lib/*.so*; do
        [ -L "$file" ] || patchelf --set-rpath '$ORIGIN' "$file"
    done
    patchelf --set-rpath '$ORIGIN/../lib' "$PREFIX/bin/ffmpeg"
}

# The pkg-config files relative to their own directory instead of naming
# the prefix, so that the install can be moved (pkg-config and pkgconf
# both know ${pcfiledir}).
relocate_pkgconfig() {
    local pc
    for pc in "$PREFIX"/lib/pkgconfig/*.pc; do
        sed -e "s|$PREFIX|\${pcfiledir}/../..|g" "$pc" >"$pc.tmp"
        mv "$pc.tmp" "$pc"
    done
}

# --- Checks --------------------------------------------------------------

verify() {
    local config="$BUILD/ffmpeg/config.h" bad=0
    for want in '#define CONFIG_GPL 0' '#define CONFIG_VERSION3 0' '#define CONFIG_NONFREE 0' \
        '#define FFMPEG_LICENSE "LGPL version 2.1 or later"'; do
        grep -qF "$want" "$config" || { echo "check failed: $want not in config.h" >&2; bad=1; }
    done
    local encoders
    encoders=$("$PREFIX/bin/ffmpeg" -hide_banner -encoders 2>/dev/null)
    for want in libopenh264 libsvtav1 aac; do
        grep -q " $want " <<<"$encoders" || { echo "check failed: no $want encoder" >&2; bad=1; }
    done
    "$PREFIX/bin/ffmpeg" -hide_banner -decoders 2>/dev/null | grep -q " libdav1d " ||
        { echo "check failed: no libdav1d decoder" >&2; bad=1; }
    # No static archive of an LGPL library: linking one into a program
    # would make the whole program a derivative (the LGPL's replaceability
    # needs shared libraries). MinGW's import libraries (*.dll.a) are fine.
    local static
    static=$(find "$PREFIX/lib" "$PREFIX/bin" \( -name 'libav*.a' -o -name 'libsw*.a' -o -name 'libpostproc*.a' \) ! -name '*.dll.a' 2>/dev/null)
    [ -z "$static" ] || { echo "check failed: static archives of LGPL libraries: $static" >&2; bad=1; }
    if [ "$OS" = windows ]; then
        # Nothing but our DLLs and Windows' own: no MinGW runtime or zlib DLL.
        local refs
        refs=$(for f in "$PREFIX"/bin/*.dll "$PREFIX/bin/ffmpeg.exe"; do
            objdump -p "$f" | awk '/DLL Name:/ { print $3 }' | while read -r dll; do
                [ ! -f "$PREFIX/bin/$dll" ] && [ -f "$MINGW_PREFIX/bin/$dll" ] && echo "$(basename "$f") → $dll"
            done
        done || true)
        [ -z "$refs" ] || { echo "check failed: MinGW libraries: $refs" >&2; bad=1; }
    fi
    if [ "$OS" = macos ]; then
        # Nothing but our prefix (@rpath) and the system.
        local refs
        refs=$(for f in "$PREFIX"/lib/*.dylib "$PREFIX/bin/ffmpeg"; do otool -L "$f" | awk 'NR > 1 { print $1 }'; done |
            sort -u | grep -v -e '^@rpath/' -e '^/usr/lib/' -e '^/System/Library/' || true)
        [ -z "$refs" ] || { echo "check failed: foreign libraries: $refs" >&2; bad=1; }
    fi
    [ "$bad" = 0 ] || exit 1
    "$PREFIX/bin/ffmpeg" -hide_banner -L | head -n 3
}

# BUILD-INFO.txt and a copy of this script in the install: what a program
# shipping the libraries points to (the LGPL's "complete corresponding
# source": these tarballs and this script).
write_build_info() {
    local configure
    configure=$("$PREFIX/bin/ffmpeg" -hide_banner -buildconf 2>&1 | sed -n 's/^ *\(--.*\)$/\1/p' |
        sed -e "s|$ROOT/||g" -e "s|$OUT/||g" | tr '\n' ' ')
    cp "$ROOT/build.sh" "$PREFIX/build.sh"
    cat >"$PREFIX/BUILD-INFO.txt" <<EOF
FFmpeg $FFMPEG_VERSION ($PLATFORM), LGPL build by AxonPod
Build script: build.sh (a copy is next to this file), $REPOSITORY, revision $REVISION
Licence: LGPL-2.1-or-later (FFmpeg); avcodec_license(): $(grep FFMPEG_LICENSE "$BUILD/ffmpeg/config.h" | cut -d'"' -f2)
Built: $(date -u +%Y-%m-%d)

Sources (unmodified upstream releases):
  FFmpeg $FFMPEG_VERSION     $FFMPEG_URL
                    sha256 $FFMPEG_SHA256
  OpenH264 $OPENH264_VERSION   $OPENH264_URL
                    sha256 $OPENH264_SHA256
  SVT-AV1 $SVTAV1_VERSION    $SVTAV1_URL
                    sha256 $SVTAV1_SHA256
  dav1d $DAV1D_VERSION      $DAV1D_URL
                    sha256 $DAV1D_SHA256
EOF
    if [ "$OS" != macos ]; then
        cat >>"$PREFIX/BUILD-INFO.txt" <<EOF
  nv-codec-headers $NVHEADERS_VERSION $NVHEADERS_URL
                    sha256 $NVHEADERS_SHA256
  libvpl $LIBVPL_VERSION    $LIBVPL_URL
                    sha256 $LIBVPL_SHA256
EOF
        if [ "$OS" = windows ]; then
            cat >>"$PREFIX/BUILD-INFO.txt" <<EOF
  AMF headers $AMF_VERSION $AMF_URL
                    sha256 $AMF_SHA256
EOF
        fi
    fi
    cat >>"$PREFIX/BUILD-INFO.txt" <<EOF

FFmpeg configure:
  ./configure $configure

Libraries:
$(cd "$PREFIX" && find lib bin -maxdepth 1 -type f \( -name '*.dylib' -o -name '*.so*' -o -name '*.dll' \) | sed 's|^|  |' | sort)
EOF
}

# --- Main ----------------------------------------------------------------

# Every source, for every platform (the source archive of a release).
fetch_all() {
    fetch "$FFMPEG_URL" "$FFMPEG_SHA256" "ffmpeg-$FFMPEG_VERSION.tar.xz"
    fetch "$OPENH264_URL" "$OPENH264_SHA256" "openh264-$OPENH264_VERSION.tar.gz"
    fetch "$SVTAV1_URL" "$SVTAV1_SHA256" "SVT-AV1-v$SVTAV1_VERSION.tar.gz"
    fetch "$DAV1D_URL" "$DAV1D_SHA256" "dav1d-$DAV1D_VERSION.tar.xz"
    fetch "$NVHEADERS_URL" "$NVHEADERS_SHA256" "nv-codec-headers-$NVHEADERS_VERSION.tar.gz"
    fetch "$AMF_URL" "$AMF_SHA256" "AMF-headers-v$AMF_VERSION.tar.gz"
    fetch "$LIBVPL_URL" "$LIBVPL_SHA256" "libvpl-$LIBVPL_VERSION.tar.gz"
}

if [ "${1:-}" = --fetch ]; then
    fetch_all
    exit 0
fi

started=$(date +%s)
mkdir -p "$BUILD" "$PREFIX"
build_openh264
build_svtav1
build_dav1d
if [ "$OS" != macos ]; then
    build_nvheaders
    build_libvpl
    if [ "$OS" = windows ]; then build_amf_headers; fi
fi
build_ffmpeg
if [ "$OS" = macos ]; then fix_install_names; fi
if [ "$OS" = linux ]; then set_runpaths; fi
verify
write_build_info
relocate_pkgconfig
if [ "$OS" = windows ]; then
    # The MSVC import libraries (FFmpeg writes <name>.lib into bin/ with
    # dlltool) next to MinGW's, where MSVC's linker looks.
    for lib in "$PREFIX"/bin/*.lib; do mv "$lib" "$PREFIX/lib/"; done
fi
echo "FFmpeg $FFMPEG_VERSION installed in $PREFIX ($(($(date +%s) - started)) s)"
