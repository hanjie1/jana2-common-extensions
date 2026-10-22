# jana2-common-extensions

A collection of reusable plugins and libraries built on top of JANA2 for reading and decoding **EVIO-format** data produced by Jefferson Lab experiments.

This repository is designed to be **modular and extensible**, and can be adapted for any experiment using EVIO-based readout with VME/VXS hardware modules.


## Table of Contents

* [Dependencies](#dependencies)
* [Build Instructions](#build-instructions)
* [Manual Build](#manual-build-advanced)
* [Running Tests](#running-tests)
* [Docker Environment](#docker-environment)
* [Installation Layout](#installation-layout)
* [Basic Usage](#basic-usage)
* [Logging](#logging)
* [Configuration Files](#configuration-files)
* [Default Plugins](#default-plugins)
* [Experiment Extension Example](https://github.com/RaiqaRasool/hallc_recon_jce) — detector translators, mappings, and CSV writers


## Dependencies

| Dependency   | Minimum Version | Notes                            |
| ------------ | --------------- | -------------------------------- |
| CMake        | 3.22            | Build system                     |
| C++ Compiler | C++20           | GCC 11+ or Clang 13+ recommended |
| Git          | Any recent version | Downloads pinned dependencies |
| Boost        | System-provided | Required by EVIO                 |
| LZ4          | System-provided | Required by EVIO                 |
| JANA2        | v2026.03.01     | Downloaded by the superbuild     |
| EVIO         | v6.1.2          | Downloaded by the superbuild     |
| ROOT         | 6.x             | Optional; required only for `evio_processor` |

## Build Instructions

Use `RelWithDebInfo` for optimized processing with debug symbols for profiling.
`Release` is also suitable for optimized runs. An empty CMake build type is not
equivalent to an optimized build. The JCE superbuild defaults to `RelWithDebInfo` when no type is selected and
forwards the selected type to JANA2, EVIO, and JCE; rebuild and install after changing it.

The recommended build uses the in-repository superbuild. It downloads the
pinned JANA2 and EVIO releases, builds them in dependency order, and installs
JANA2, EVIO, and JCE into one prefix:

```tcsh
cmake -S superbuild -B build-super
cmake --build build-super --parallel
setenv JCE_HOME `pwd`/jce-stack
```

The superbuild downloads pinned JANA2 `v2026.03.01` and EVIO `v6.1.2`
releases, then builds this JCE checkout against them. By default it installs to
`jce-stack/` in the repository root. The EVIO compatibility patch ignores the shell's `CODA`
environment variable for EVIO and bundled Disruptor, keeping their installation
in the selected stack without changing your shell environment. Override that location with
`-DCMAKE_INSTALL_PREFIX=/another/path` when configuring. An experiment can use
the complete installation with:

```tcsh
cmake -S . -B build -DCMAKE_PREFIX_PATH=${JCE_HOME}
```

### Offline build

Point the superbuild at existing JANA2 and EVIO source trees. Both must be
supplied to avoid downloading those projects:

```tcsh
cmake -S superbuild -B build-super \
  -DJANA_SOURCE_DIR=/path/to/JANA2 \
  -DEVIO_SOURCE_DIR=/path/to/evio
cmake --build build-super --parallel
```

The superbuild never modifies either source checkout. It copies EVIO into its
own build workspace before applying the install-prefix compatibility patch.
EVIO continues to manage its own Disruptor dependency. Boost and LZ4 must
already be installed on the system.

### Optional ROOT processor

ROOT is intentionally not downloaded or built by the superbuild. To include
`evio_processor`, install ROOT separately, make it discoverable through
`CMAKE_PREFIX_PATH`, and enable the processor:

```tcsh
cmake -S superbuild -B build-super \
  -DJCE_SUPERBUILD_EVIO_PROCESSOR=ON \
  -DCMAKE_PREFIX_PATH=/path/to/root
cmake --build build-super --parallel
```

Follow the [official ROOT installation guide](https://root.cern/install/) when
an existing ROOT installation is not available.

See [the superbuild contract](docs/superbuild.md) for version overrides,
system prerequisites, and failure behavior.


## Manual Build (advanced)

Use this path when JANA2 and EVIO are already installed or managed separately.

### Build JANA2 separately

```tcsh
git clone --branch v2026.03.01 https://github.com/JeffersonLab/JANA2.git JANA2
cmake -S JANA2 -B JANA2/build -DCMAKE_INSTALL_PREFIX=/path/to/JANA2
cmake --build JANA2/build --target install --parallel
```

### Build EVIO separately

```tcsh
git clone --branch v6.1.2 https://github.com/JeffersonLab/evio.git evio
cmake -S evio -B evio/build
cmake --build evio/build --target install --parallel
```

### Build JCE against separate installations

Set `CMAKE_INSTALL_PREFIX` during the initial configuration because it is
embedded into generated runtime configuration paths:

```tcsh
cmake -S . -B build \
  -DBUILD_TESTING=ON \
  -DCMAKE_PREFIX_PATH="/path/to/JANA2;/path/to/evio" \
  -DCMAKE_INSTALL_PREFIX=/path/to/JCE
cmake --build build --parallel
cmake --install build
```

To include `evio_processor`, also pass `-DJCE_BUILD_EVIO_PROCESSOR=ON` and add
the ROOT installation to `CMAKE_PREFIX_PATH`.

For this advanced split-prefix layout, set `JCE_HOME` to the JCE installation
and `JANA_HOME` to the separate JANA2 installation. The installed wrappers use
`JANA_HOME` only when `${JCE_HOME}/bin/jana` is not present.

## Running Tests

Tests are disabled in the default user superbuild. Developers should use a
separate build directory and opt in explicitly:

```tcsh
cmake -S superbuild -B build-super-tests \
  -DCMAKE_INSTALL_PREFIX=`pwd`/jce-test-stack \
  -DJCE_SUPERBUILD_BUILD_TESTING=ON
cmake --build build-super-tests --target check --parallel
```

The `check` target builds the complete stack, installs it into the test prefix,
and runs the JCE tests with failure output enabled. To inspect or rerun tests
directly:

```tcsh
ctest --test-dir build-super-tests/jce-build -N
ctest --test-dir build-super-tests/jce-build --output-on-failure
```

## Docker Environment

The [Docker environment](docker/README.md) provides a shared Linux setup for
building, running tests, and single-worker profiling. It reuses the pinned
superbuild using the usual `build-super/` and `jce-stack/` paths in the checkout.

## Installation Layout

After the recommended superbuild installs to `${JCE_HOME}`, the shared prefix
contains JANA2, EVIO, and JCE:

```
bin/
└── jana
config/
├── mapping.db
├── filter.db
└── default_plugins.db
include/
├── JANA/
├── eviocc.h
└── jce_config_paths.h
lib/
├── cmake/
└── plugins/
    ├── evio_parser.so
    ├── evio_common_modules.so
    ├── detector_translation.so
    ├── evio_processor.so  # only with JCE_BUILD_EVIO_PROCESSOR=ON
    └── ...
scripts/
├── jce.csh
└── jce.sh
templates/
```

## Basic Usage

The recommended entry point is one of the wrapper scripts (equivalent behavior; use whichever matches your shell):

```tcsh
${JCE_HOME}/scripts/jce.csh /path/to/data.evio
```

```tcsh
"${JCE_HOME}/scripts/jce.sh" /path/to/data.evio
```

These scripts:

* Prepends the JCE plugin path
* Loads default plugins automatically
* Forwards all arguments to `jana`

### Set Environment

```tcsh
setenv JCE_HOME `pwd`/jce-stack
setenv PATH "${JCE_HOME}/bin:${PATH}"
```

Run this from the repository root when using the default prefix. `JANA_HOME` is
not needed for a superbuild installation because the wrapper finds
`${JCE_HOME}/bin/jana` directly. Adding `bin` to `PATH` is optional and supports
advanced direct use.

### Run with Default Plugins

```tcsh
${JCE_HOME}/scripts/jce.csh /path/to/data.evio
```

```tcsh
"${JCE_HOME}/scripts/jce.sh" /path/to/data.evio
```

* Uses plugins from [default_plugins.db](#default-plugins)
* Falls back to [evio_parser](src/plugins/evio_parser/README.md) `evio_common_modules`, and `detector_translation` if the file is missing or empty


### Configuration Directories for Default Plugins

Core defaults come from `${JCE_HOME}/config/default_plugins.db`. Append config
roots using a colon-separated list (left to right):

```bash
export JCE_CONFIG_DIR=/path/to/hallc/config:/path/to/compton/config
"${JCE_HOME}/scripts/jce.sh" /path/to/data.evio
```

In tcsh, use `setenv JCE_CONFIG_DIR /path/to/hallc/config:/path/to/compton/config`.
Each directory's optional `default_plugins.db` appends to core defaults, followed
by `-Pplugins`. Names are deduplicated in first-occurrence order; `evio_parser`
is always first. Empty path entries are ignored. Missing directories produce
warnings (yellow on a terminal) and are skipped.

Override only the core directory with `-PJCE:CORE_CONFIG_DIR=/path/to/core/config`,
or only the core plugin file with `-PDEFAULT_PLUGINS:FILE=/path/to/default_plugins.db`.
The file parameter takes precedence over the directory parameter. Appended
directories and CLI plugins still apply. Missing or empty core plugin files use
`evio_parser,evio_common_modules,detector_translation`; missing files warn. There is no core override
environment variable.

`JCE_CONFIG_DIR` now extends core defaults for plugin selection, bank mapping,
and filtering. Translation catalogs keep their existing setup-plugin registration.
See [Configuration layers](docs/configuration-layers.md).

### Add Additional Plugins

```tcsh
${JCE_HOME}/scripts/jce.csh -Pplugins=evio_processor,my_custom_plugin /path/to/data.evio
```

```tcsh
"${JCE_HOME}/scripts/jce.sh" -Pplugins=evio_processor,my_custom_plugin /path/to/data.evio
```

### Using Plugins from External Directories

If your plugin is not located in `${JCE_HOME}/lib/plugins`, you must provide its path manually.

You can:

* Set `JANA_PLUGIN_PATH`, or
* Pass it at runtime using `-Pjana:plugin_path`

#### Example

```tcsh
${JCE_HOME}/scripts/jce.csh -Pjana:plugin_path=/my/custom/plugins -Pplugins=my_custom_plugin /path/to/data.evio
```

```tcsh
"${JCE_HOME}/scripts/jce.sh" -Pjana:plugin_path=/my/custom/plugins -Pplugins=my_custom_plugin /path/to/data.evio
```

#### Notes

* `${JCE_HOME}/lib/plugins` is always prepended automatically
* User-provided paths are appended afterward
* Only the directory is required (not the `.so` file)

### Running Without the Wrapper (Advanced)

You can run plugins directly with `jana` if you prefer full manual control and do not want to use `default_plugins.db`.

```tcsh
"${JCE_HOME}/bin/jana" -Pplugins=evio_parser,evio_common_modules,detector_translation \
  -Pjana:plugin_path="${JCE_HOME}/lib/plugins" data.evio
```

**Important:**

* `evio_parser` must always be included and listed **first**, as it provides the event source for EVIO files
* At least one event source is required by JANA; without it, no events will be processed
* You are responsible for setting plugin paths and loading all required plugins manually

## Logging

### Adding log statements

Include the logger header if it is not already available transitively:

```cpp
#include <JANA/JLogger.h>
```

Add the log:

```cpp
LOG_WARN(GetLogger()) << "ModuleParser_MyHW::parse: unexpected word count " << nwords << LOG_END;
```

Available macros (in increasing severity):

```cpp
LOG_TRACE, LOG_DEBUG, LOG_INFO, LOG_WARN, LOG_ERROR, LOG_FATAL
```

All log statements must end with `LOG_END`.

---

### Log levels

Messages are shown only if their severity is **at or above** the configured level:

| Level          | Visible messages                       |
| -------------- | -------------------------------------- |
| TRACE          | TRACE, DEBUG, INFO, WARN, ERROR, FATAL |
| DEBUG          | DEBUG, INFO, WARN, ERROR, FATAL        |
| INFO (default) | INFO, WARN, ERROR, FATAL               |
| WARN           | WARN, ERROR, FATAL                     |
| ERROR          | ERROR, FATAL                           |
| FATAL          | FATAL                                  |
| OFF            | none                                   |

For example, `LOG_DEBUG` only appears when the level is `DEBUG` or `TRACE`.

---

### Global log level

Set logging level for all JANA2 components:

```tcsh
"${JCE_HOME}/scripts/jce.sh" -Pjana:global_loglevel=WARN data.evio
```

This give logs on the given level for both the internal jana components and plugin components. Default is `INFO`.

---

### evio_parser log level

To get only evio_parser logs at a certain level use `-PEVIO_PARSER:loglevel`:

```tcsh
"${JCE_HOME}/scripts/jce.sh" -PEVIO_PARSER:loglevel=DEBUG data.evio
```

Use `TRACE` for maximum detail.

---

### Custom components log level

A component can define its own logging namespace via `SetPrefix`:

```cpp
MyProcessor::MyProcessor() : JEventProcessor() {
    SetPrefix("MY_PROCESSOR");
}

void MyProcessor::Process(const JEvent& event) {
    LOG_INFO(GetLogger()) << "Processing event " << event.GetEventNumber() << LOG_END;
}
```

Then configure it:

```tcsh
"${JCE_HOME}/scripts/jce.sh" -PMY_PROCESSOR:loglevel=DEBUG \
  -Pplugins=my_plugin data.evio
```


## Configuration Files

Configuration files are installed under:

```
<install_prefix>/config/
```

| File                 | Purpose                           | Used By                |
|----------------------|-----------------------------------|------------------------|
| `mapping.db`         | Maps EVIO banks to module IDs     | `src/plugins/evio_parser` |
| `filter.db`          | Defines ROC/bank filtering rules  | `src/plugins/evio_parser` |
| `default_plugins.db` | Specifies default plugins to load | `scripts/jce.csh`, `scripts/jce.sh` |

At runtime, installed core files load first, followed by files from the
colon-separated `JCE_CONFIG_DIR` directory list, left to right. Override the
core directory using `-PJCE:CORE_CONFIG_DIR=/path/to/core/config`.

Plugin names append with deduplication. Bank routes are keyed by bank ID: equal
routes are ignored, while a later conflicting route wins with a warning showing
both source locations. Conflicting routes inside one mapping file are errors.
Filter rows form a union, ignoring exact duplicates; appending broadens the
allow-list. Filtering remains disabled unless `FILTER:ENABLE` is set.

Missing appended directories warn and are skipped; missing individual appended
files are optional. Required core mapping/filter files and explicit replacement
files must exist and be readable. Empty mapping additions are valid; malformed
mapping/filter rows fail with file/line diagnostics.

### Overriding Individual Config Files

The `evio_parser` plugin loads `mapping.db` and `filter.db` from <install_prefix>/config by default. You can override their individual loading paths by using following params:

```tcsh
-PBANKMAP:FILE=/custom/mapping.db
-PFILTER:FILE=/custom/filter.db
```

All three file parameters replace **only the core file**. Files in
`JCE_CONFIG_DIR` still append, even when a file parameter is supplied:

| Parameter | Core file it replaces | What still appends |
|---|---|---|
| `DEFAULT_PLUGINS:FILE` | `default_plugins.db` | Directory plugin lists, then `-Pplugins` |
| `BANKMAP:FILE` | `mapping.db` | Directory mapping files; later routes win |
| `FILTER:FILE` | `filter.db` | Directory filter files; allowed rows are combined |

```bash
export JCE_CONFIG_DIR=/my/experiment/config
"${JCE_HOME}/scripts/jce.sh" -PBANKMAP:FILE=/custom/mapping.db data.evio
# Mapping input: /custom/mapping.db, then /my/experiment/config/mapping.db
```

To use only an explicit mapping/filter file, clear the directory list for that
run. This also disables directory additions for default plugins:

```bash
JCE_CONFIG_DIR= "${JCE_HOME}/scripts/jce.sh" \
  -PFILTER:ENABLE=1 -PFILTER:FILE=/custom/filter.db data.evio
```

For tcsh, run `unsetenv JCE_CONFIG_DIR` before the command. Filtering still
requires `FILTER:ENABLE`; appending filter files broadens the allow-list.

### Appending Configuration Directories

Attach one or more configuration directories:

```tcsh
setenv JCE_CONFIG_DIR /my/hallc/config:/my/compton/config
```

Each directory contributes its optional `mapping.db`, `filter.db`, and
`default_plugins.db` files after the core files.

> **Note:** The filenames must remain the same inside the directory.

For more details on plugin-specific configuration, see
[`src/plugins/evio_parser/README.md`](src/plugins/evio_parser/README.md).

---

### Default Plugins

The file:

```
<install_prefix>/config/default_plugins.db
```

controls which plugins are loaded by default.

#### Rules

* Supports comments using `#`
* Empty lines are ignored
* Falls back to `evio_parser,evio_common_modules,detector_translation` if empty or missing
* CLI `-Pplugins=...` values are appended (not replaced)

#### Example

```text
# Default plugins
evio_parser,evio_common_modules,detector_translation,evio_processor
```

Detector mappings, detector-specific DigiHits, translators, and CSV row formats
are owned by experiment plugins. JCE no longer builds or installs the HMS
example. The default plugin list loads only `evio_parser,evio_common_modules,detector_translation`;
experiment setup plugins request generic translation and register their routes.
Detector-hit consumers link their experiment's data-types target rather than
obtaining detector-specific headers through JCE's common raw-hit umbrella.
After upgrading an existing installation, use a clean JCE prefix or remove the
obsolete HMS plugin, headers, and config tree from that prefix; CMake installation
does not uninstall files removed from source. Rebuild experiment plugins and their consumers
against the updated JCE registration API and their DigiHit schemas.
