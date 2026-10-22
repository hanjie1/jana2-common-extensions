# JCE Superbuild

## Purpose

The in-repository superbuild provides one entry point for downloading, building,
and installing compatible JANA2, EVIO, and JCE versions into a shared prefix.
The normal JCE build remains available for developers and managed installations
that provide their own dependencies.

## Main Flow

1. Configure `superbuild/` with an installation prefix.
2. Build the generated project.
3. The superbuild downloads and installs JANA2 `v2026.03.01`, then EVIO
   `v6.1.2`, and finally builds this JCE checkout against both installations.
4. Downstream experiments use the resulting prefix through
   `CMAKE_PREFIX_PATH`.

## Expected Behavior

- For single-configuration generators, an unset or empty `CMAKE_BUILD_TYPE`
  defaults to `RelWithDebInfo`. Explicit types such as `Release` and `Debug`
  are preserved. The selected type is forwarded to JANA2, EVIO, and JCE.
- All three projects install into the selected `CMAKE_INSTALL_PREFIX`.
- Git tags are pinned by default and can be overridden with
  `JCE_JANA_GIT_TAG` or `JCE_EVIO_GIT_TAG`.
- Existing dependency checkouts can be selected with `JANA_SOURCE_DIR` and
  `EVIO_SOURCE_DIR`. Supplying both prevents JANA2 and EVIO downloads.
- EVIO remains responsible for managing its own Disruptor dependency.
- JANA examples and tests, EVIO examples, and JCE tests are disabled by
  default to keep the user build focused on installable runtime components.
- Developers can set `JCE_SUPERBUILD_BUILD_TESTING=ON` to build JCE tests and
  add the outer `check` target.
- The ROOT-based `evio_processor` remains disabled by default. Set
  `JCE_SUPERBUILD_EVIO_PROCESSOR=ON` and make ROOT discoverable through the
  outer `CMAKE_PREFIX_PATH` to include it.
- EVIO is patched only in the superbuild's working source tree so that its
  CMake build honors the shared installation prefix, exports only discovered
  dependency include paths instead of hard-coded `/usr/local/include`, and uses
  the discovered LZ4 header directory. The patch also installs EVIO’s bundled
  `.hpp` headers required by its public C++ headers. For offline builds, EVIO
  is first copied into the superbuild workspace so the original checkout is
  not modified. The patch clears `CODA` from EVIO's configure environment so
  EVIO and bundled Disruptor do not redirect installation to an existing CODA
  stack. The calling shell environment and `DESTDIR` staging remain unchanged.

## Failure Behavior

- Configuration fails when Git is unavailable.
- Download or build failures stop the dependent projects; JCE is not built
  against a partial dependency installation.
- System dependencies required by EVIO, including Boost and LZ4, must already
  be discoverable by CMake.
- A supplied dependency source directory must contain a `CMakeLists.txt` and
  must be compatible with the superbuild's configure options. The EVIO source
  must also accept the included `v6.1.2` install-prefix patch.

## Key Components

- `superbuild/CMakeLists.txt`
- `superbuild/patches/evio-respect-install-prefix.patch`
- Root `CMakeLists.txt` for the normal JCE build

## Verification

Configure without building to validate the outer project:

```tcsh
cmake -S superbuild -B build-super
```

The default installation prefix is `` `pwd`/jce-stack `` when configuring from
the repository root. Pass `-DCMAKE_INSTALL_PREFIX=/another/path` to override it.

Build the complete stack when network access and system dependencies are
available:

```tcsh
cmake --build build-super --parallel
```

Build and run JCE tests in a separate developer build:

```tcsh
cmake -S superbuild -B build-super-tests \
  -DCMAKE_INSTALL_PREFIX=`pwd`/jce-test-stack \
  -DJCE_SUPERBUILD_BUILD_TESTING=ON
cmake --build build-super-tests --target check --parallel
```

To avoid downloading JANA2 and EVIO, prepare both source trees in advance:

```tcsh
cmake -S superbuild -B build-super \
  -DJANA_SOURCE_DIR=/path/to/JANA2 \
  -DEVIO_SOURCE_DIR=/path/to/evio
cmake --build build-super --parallel
```

ROOT is intentionally not downloaded or built by the superbuild. To build the
optional `evio_processor`, provide an existing ROOT installation:

```tcsh
cmake -S superbuild -B build-super \
  -DJCE_SUPERBUILD_EVIO_PROCESSOR=ON \
  -DCMAKE_PREFIX_PATH=/path/to/root
cmake --build build-super --parallel
```
