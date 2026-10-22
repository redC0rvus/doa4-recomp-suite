# Third-party notices

This suite's own code is BSD-3-Clause (`LICENSE`). It contains no game code or data: you supply your own Dead or Alive 4 disc image, and `tools/setup.ps1` builds everything on your machine. Dead or Alive is a trademark of Koei Tecmo; this project is not affiliated with or endorsed by Koei Tecmo or Microsoft.

## What is redistributed
- **This repository:** the suite's own source, plus `patches/sdk/*.patch` (changes to the ReXGlue SDK, released under the SDK's BSD-3-Clause license below).
- **The SDK source snapshot** (`deps.lock` `sdk_archive_url`): an unmodified source copy of the ReXGlue SDK at the locked commit with all its submodules. Every component keeps its own license file inside the archive.

No binaries are distributed. Players build locally, so the binary-distribution terms of the licenses below (LGPL relinking, GPL source offers, notice-in-documentation clauses) apply only to anyone who redistributes a built copy.

## ReXGlue SDK
- **ReXGlue SDK:** BSD-3-Clause. Copyright (c) 2026, Tom Clay. Portions derived from the Xenia project, Copyright (c) 2022, Ben Vanik and Xenia project contributors (BSD-3-Clause). <https://github.com/rexglue/rexglue-sdk>

## Components built from the SDK snapshot
Built into the game runtime (`rexruntime`, `rexgpu-xenos` DLLs), the `rexglue` codegen tool, or both:

| Component | License | Notes |
|---|---|---|
| FFmpeg (libavcodec, libavutil) | LGPL-2.1-or-later | Only audio decoders are built (WMA Pro, XMA, MP3); no GPL-only parts enabled |
| libmspack | LGPL-2.1 | LZX decompression |
| PowerPC disassembler (`thirdparty/disasm`, from GNU binutils) | GPL-2.0-or-later | `rexglue` codegen tool only, not the game runtime |
| SDL3 | Zlib | |
| Dear ImGui | MIT | |
| {fmt} | MIT | |
| spdlog | MIT | |
| toml++ | MIT | |
| SIMDe | MIT | |
| inja | MIT | |
| o1heap | MIT | |
| RenderDoc in-application API header | MIT | |
| aes_128 | MIT | |
| disruptorplus | MIT | header-only |
| xxHash | BSD-2-Clause | |
| CLI11 | BSD-3-Clause | |
| Tracy | BSD-3-Clause | |
| UTF8-CPP | BSL-1.0 | |
| tiny-AES-c | Unlicense (public domain) | |
| stb_image | MIT or public domain | |
| DirectX Shader Compiler headers, DXBC checksum, PE headers, crypto routines (`thirdparty/dxc`, `dxbc`, `pe`, `crypto`) | per-file notices (Microsoft, AMD, RSA Data Security and others) | see each file's header and `crypto/des/LICENSE` |

In the snapshot but not built here (D3D12 only, `REXGLUE_USE_VULKAN` off): Vulkan-Headers (Apache-2.0 or MIT), Vulkan-Loader (Apache-2.0), Vulkan Memory Allocator (MIT), SPIRV-Headers (MIT-style Khronos license), SPIRV-Tools (Apache-2.0), glslang (BSD-3-Clause and others), MoltenVK (Apache-2.0, macOS), Catch2 (BSL-1.0, SDK tests only), FidelityFX (MIT, fetched only when `REXGLUE_ENABLE_FIDELITYFX` is on; off here).

## Tools this suite calls but does not ship
Visual Studio / MSVC Build Tools, LLVM/Clang, CMake, Ninja, Python and Git are installed separately by the user under their own licenses. RenderDoc (MIT) is optional, for frame captures.
