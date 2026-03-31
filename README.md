# jana2-common-extensions

A collection of reusable plugins and libraries built on top of JANA2 for reading and decoding **EVIO-format** data produced by Jefferson Lab experiments.

This repository is designed to be **modular and extensible**, and can be adapted for any experiment using EVIO-based readout with VME/VXS hardware modules.


## Table of Contents

* [Dependencies](#dependencies)
* [Build Instructions](#build-instructions)
* [Installation Layout](#installation-layout)
* [Basic Usage](#basic-usage)
* [Configuration Files](#configuration-files)
* [Default Plugins](#default-plugins)


## Dependencies

| Dependency   | Minimum Version | Notes                            |
| ------------ | --------------- | -------------------------------- |
| CMake        | 3.16            | Build system                     |
| C++ Compiler | C++20           | GCC 11+ or Clang 13+ recommended |
| JANA2        | 2.x             | Core framework                   |
| EVIO         | v6.1.2          | Data format library              |
| ROOT         | 6.x             | Analysis and output              |

### Building JANA2

```tcsh
git clone https://github.com/JeffersonLab/JANA2.git JANA2
cd JANA2
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=`pwd`
cmake --build build --target install -j`nproc`
cd ..
```

### Building EVIO

```tcsh
git clone https://github.com/JeffersonLab/evio/
cd evio
git checkout v6.1.2
cmake -S . -B build
cmake --build build --target install --parallel
cd ..
```

### Installing ROOT

Follow the official installation guide:
[https://root.cern/install/](https://root.cern/install/)


## Build Instructions

### 1. Configure

```tcsh
cmake -S . -B build -DCMAKE_PREFIX_PATH="/path/to/JANA2;/path/to/evio;/path/to/root" -DCMAKE_INSTALL_PREFIX=`pwd`
```
> ⚠️ **Important**
> `CMAKE_INSTALL_PREFIX` must be set during the **initial CMake configuration**.
> It is embedded into generated headers (e.g., `jce_config_paths.h`) and used at runtime to locate configuration files such as `mapping.db` and `filter.db`.
> Changing it later without reconfiguring will result in incorrect paths.

### 2. Build

```bash
cmake --build build --parallel
```

### 3. Install

```bash
cmake --install build
```

## Installation Layout

After installation (with `-DCMAKE_INSTALL_PREFIX=\`pwd\``), your directory will look like:

```
config/
├── mapping.db
├── filter.db
└── default_plugins.db
include/
└── jce_config_paths.h
lib/
├── cmake/
└── plugins/
    ├── evio_parser.so
    ├── evio_processor.so
    └── ...
scripts/
├── jce.csh
└── jce.sh
templates/
```

## Basic Usage

The recommended entry point is one of the wrapper scripts (equivalent behavior; use whichever matches your shell):

```tcsh
scripts/jce.csh
```

```bash
scripts/jce.sh
```

These scripts:

* Prepends the JCE plugin path
* Loads default plugins automatically
* Forwards all arguments to `jana`

### Set Environment

```tcsh
setenv JCE_HOME /path/to/jana2-common-extensions
setenv JANA_HOME /path/to/JANA2
```

```bash
export JCE_HOME=/path/to/jana2-common-extensions
export JANA_HOME=/path/to/JANA2
```

> With the default setup (`-DCMAKE_INSTALL_PREFIX=\`pwd\``), set `JCE_HOME` to the project root.

### Run with Default Plugins

```tcsh
${JCE_HOME}/scripts/jce.csh /path/to/data.evio
```

```bash
"${JCE_HOME}/scripts/jce.sh" /path/to/data.evio
```

* Uses plugins from [default_plugins.db](#default-plugins)
* Falls back to [evio_parser](src/plugins/evio_parser/README.md) if the file is missing or empty


### Add Additional Plugins

```tcsh
${JCE_HOME}/scripts/jce.csh -Pplugins=evio_processor,my_custom_plugin /path/to/data.evio
```

```bash
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

```bash
"${JCE_HOME}/scripts/jce.sh" -Pjana:plugin_path=/my/custom/plugins -Pplugins=my_custom_plugin /path/to/data.evio
```

#### Notes

* `${JCE_HOME}/lib/plugins` is always prepended automatically
* User-provided paths are appended afterward
* Only the directory is required (not the `.so` file)

### Running Without the Wrapper (Advanced)

You can run plugins directly with `jana` if you prefer full manual control and do not want to use `default_plugins.db`.

```bash
jana -Pplugins=evio_parser,evio_processor -Pjana:plugin_path=/path/to/plugins data.evio
```

**Important:**

* `evio_parser` must always be included and listed **first**, as it provides the event source for EVIO files
* At least one event source is required by JANA; without it, no events will be processed
* You are responsible for setting plugin paths and loading all required plugins manually

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

At runtime, configuration files are resolved using the following precedence:

1. **Explicit CLI overrides (per file)**
2. **Global override via `JCE_CONFIG_DIR`**
3. **Installed defaults (`<install_prefix>/config/`)**

### Overriding Individual Config Files

The `evio_parser` plugin loads `mapping.db` and `filter.db` from <install_prefix>/config by default. You can override their individual loading paths by using following params:

```tcsh
-PBANKMAP:FILE=/custom/mapping.db
-PFILTER:FILE=/custom/filter.db
```

Similarly, the default plugins file path can be overridden with:

```tcsh
-PDEFAULT_PLUGINS:FILE=/custom/default_plugins.db
```

### Using a Global Config Directory

Instead of overriding files path individually, you can set a single environment variable:

```tcsh
setenv JCE_CONFIG_DIR /my/custom/configs
```

If set, all configuration files (`mapping.db`, `filter.db`, `default_plugins.db`) will be loaded from this directory.

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
* Falls back to `evio_parser` if empty or missing
* CLI `-Pplugins=...` values are appended (not replaced)

#### Example

```text
# Default plugins
evio_parser,evio_processor
```
