# FFmpeg LGPL builds

AxonPod's build of [FFmpeg](https://ffmpeg.org) 8.1 as **LGPL-2.1-or-later
shared libraries** for macOS, Linux and Windows: no `--enable-gpl`, no
`--enable-version3`, no `--enable-nonfree`, nothing enabled because it
happened to be installed. Every source is an unmodified upstream release,
pinned by version and SHA-256 in [`build.sh`](build.sh).

This repository is the build script and its releases, and the corresponding
source of the FFmpeg libraries AxonPod distributes.

## What is in it

| Component | Version | Licence | What for |
|---|---|---|---|
| FFmpeg (`libavcodec`, `libavformat`, `libavutil`, `libavfilter`, `libavdevice`, `libswscale`, `libswresample`) | 8.1.3 | LGPL-2.1-or-later | |
| OpenH264 | 2.6.0 | BSD-2-Clause | H.264 encoder (`libopenh264`) |
| SVT-AV1 | 4.2.0 | BSD-3-Clause-Clear + AOM patent licence | AV1 encoder (`libsvtav1`) |
| dav1d | 1.5.4 | BSD-2-Clause | AV1 decoder (`libdav1d`) |
| nv-codec-headers | 12.1.14.1 | MIT | NVENC / NVDEC (Windows, Linux) |
| libvpl | 2.16.0 | MIT | Intel Quick Sync (Windows, Linux) |
| AMF headers | 1.5.3 | MIT | AMD AMF (Windows) |

Plus the platforms' own hardware encoders and decoders: VideoToolbox
(macOS), Media Foundation, D3D11VA and DXVA2 (Windows), VA-API (Linux).

The decoders, demuxers and parsers of MP4/MOV (H.264, HEVC, ProRes, AV1,
AAC), MKV and the common audio files (WAV, FLAC, MP3, M4A, Ogg, ADTS AAC),
the MP4 muxer, FFmpeg's AAC encoder and the encoders above; file I/O only,
no network. The full configure line is in each build's `BUILD-INFO.txt`.

## Releases

Each [release](../../releases) (tag `<FFmpeg version>-<revision>`, e.g.
`8.1.3-1`) has:

- `ffmpeg-lgpl-<tag>-<platform>.tar.gz` for `macos-arm64`, `linux-x86_64`,
  `linux-aarch64` and `windows-x86_64`: one directory `<platform>/` with
  `lib/` (shared libraries, pkg-config files; on Windows the MinGW and
  MSVC import libraries), `include/`, `bin/` (the `ffmpeg` tool, and on
  Windows the DLLs), `share/licenses/` (every component's licence text),
  `BUILD-INFO.txt` (sources, SHA-256, configure line) and `build.sh`;
- `ffmpeg-lgpl-<tag>-source.tar.gz`: this repository at the tag and every
  upstream tarball it builds from;
- `SHA256SUMS`.

The install can be moved anywhere: the pkg-config files are relative to
their own directory (`${pcfiledir}`), the macOS libraries are named
`@rpath/<name>`, the Linux ones find each other through `$ORIGIN`, and the
Windows DLLs need nothing but Windows (MinGW's runtimes are linked in).
The Linux builds are made on Ubuntu 26.04 and link its glibc and the
system's libva and libdrm.

## Building

```sh
./build.sh            # download (once), build, verify → out/<platform>/
./build.sh --clean    # the same from fresh build directories
./build.sh --fetch    # only download and check the sources → src/
OUT=/some/dir ./build.sh
```

The tools each system needs are at the top of [`build.sh`](build.sh). The
script fails unless FFmpeg's `config.h` says LGPL 2.1 or later with GPL,
version 3 and nonfree off, the encoders are there, no static archive of an
LGPL library is left in the install, and the libraries depend on nothing
outside it but the system.

## Licences

The build script and workflow are under the [MIT licence](LICENSE). The
libraries keep their own licences (above; the texts are in each build's
`share/licenses/`). FFmpeg is LGPL-2.1-or-later: a program may link these
libraries dynamically whatever its own licence, as long as the user can
replace them and the LGPL's other conditions are met.

Patents are a separate matter from these copyright licences: H.264 and
HEVC are covered by patent pools. Cisco's royalty coverage applies only to
the OpenH264 binaries Cisco itself distributes, not to OpenH264 built from
source as here.
