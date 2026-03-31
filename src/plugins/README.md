# src/plugins/

This directory contains all JANA2 plugins in the jana2-common-extensions project. Each subdirectory builds into a self-contained shared library (`.so`) that JANA2 loads at runtime via `JANA_PLUGIN_PATH`.

---

## Table of Contents

- [How the Build System Wires Plugins Together](#how-the-build-system-wires-plugins-together)
- [Anatomy of a Plugin](#anatomy-of-a-plugin)
- [Adding a New Plugin](#adding-a-new-plugin)
  - [Step 1 — Create the plugin directory](#step-1--create-the-plugin-directory)
  - [Step 2 — Write InitPlugin.cc](#step-2--write-initplugincc)
  - [Step 3 — Implement your processor](#step-3--implement-your-processor)
  - [Step 4 — Write the plugin CMakeLists.txt](#step-4--write-the-plugin-cmakeliststxt)
  - [Step 5 — Register in the plugins CMakeLists](#step-5--register-in-the-plugins-cmakelists)
  - [Step 6 — Build, install, and run](#step-6--build-install-and-run)
- [Consuming Hit Types from evio_parser](#consuming-hit-types-from-evio_parser)

## How the Build System Wires Plugins Together

```
CMakeLists.txt                     ← project root: finds JANA2, EVIO, ROOT
└── src/plugins/CMakeLists.txt     ← registers every plugin subdirectory
        ├── add_subdirectory(evio_parser)
        ├── add_subdirectory(evio_processor)
        └── add_subdirectory(my_plugin)    ← the one line you add
```

`src/plugins/CMakeLists.txt` is the **only file outside your own plugin directory** you need to edit. The project-root `CMakeLists.txt` does not change.

After installation every `.so` lands under:

```
<install_prefix>/lib/plugins/
    evio_parser.so
    evio_processor.so
    my_plugin.so
```

---

## Anatomy of a Plugin

The minimum layout mirrors `evio_processor/`:

```
src/plugins/my_plugin/
├── CMakeLists.txt      # shared-library target via add_jana_plugin()
├── InitPlugin.cc       # required entry point — JANA2 calls InitPlugin() on load
├── MyProcessor.h
└── MyProcessor.cc
```

### `InitPlugin.cc`

JANA2 looks for a C-linkage `InitPlugin(JApplication*)` symbol in every `.so` it loads. `InitJANAPlugin(app)` must always be the first call; everything else is registered with `app->Add(...)` after it:

```cpp
extern "C" {
    void InitPlugin(JApplication* app) {
        InitJANAPlugin(app);
        app->Add(new MyProcessor());
    }
}
```

---

## Adding a New Plugin

Most new plugins will follow the `evio_processor` pattern exactly: a single `JEventProcessor` that reads hit types produced by `evio_parser` and writes some output. The steps below reflect that pattern.

> **Note:** `evio_parser` is the JANA2 event source for this framework — it is responsible for reading EVIO files and producing the hit objects that all other plugins consume. It must always be loaded alongside your plugin. A plugin cannot receive any data without it.

### Step 1 — Create the plugin directory

```bash
mkdir -p src/plugins/my_plugin
```

### Step 2 — Write `InitPlugin.cc`

```cpp
#include <JANA/JApplication.h>
#include "MyProcessor.h"

extern "C" {
    void InitPlugin(JApplication* app) {
        InitJANAPlugin(app);
        app->Add(new MyProcessor());
    }
}
```

### Step 3 — Implement your processor

Model this directly on `evio_processor/JEventProcessor_EVIO.h/.cc`. The key patterns to carry over:

**`MyProcessor.h`**:
```cpp
#pragma once
#include <JANA/JEventProcessor.h>
#include "FADC250PulseHit.h"    // from evio_parser_data_types

class MyProcessor : public JEventProcessor {
public:
    MyProcessor();
    void Init()                                  override;
    void ProcessSequential(const JEvent& event)  override;
    void Finish()                                override;

private:
    Input<FADC250PulseHit> m_pulse_hits {this};
    // add further Input<T> members for any other hit types you need
};
```

**`MyProcessor.cc`**:
```cpp
#include "MyProcessor.h"

MyProcessor::MyProcessor() {
    SetTypeName(NAME_OF_THIS);
    SetCallbackStyle(CallbackStyle::ExpertMode);
    m_pulse_hits.SetOptional(true);  // don't throw if absent from an event
}

void MyProcessor::Init()   { /* open files, create histograms, etc. */ }
void MyProcessor::Finish() { /* write and close output */              }

void MyProcessor::ProcessSequential(const JEvent& event) {
    for (const auto* hit : m_pulse_hits()) {
        // your analysis here
    }
}
```

Three patterns that must be preserved:

| Pattern | Where | Why |
|---|---|---|
| `SetCallbackStyle(CallbackStyle::ExpertMode)` | constructor | required when using `ProcessSequential` |
| `Input<T> m_x {this}` | class member | JANA2 resolves objects by type from the `JEvent` at runtime |
| `SetOptional(true)` | constructor | prevents a hard error when a hit type is absent from an event |

### Step 4 — Write the plugin `CMakeLists.txt`

```cmake
add_jana_plugin(my_plugin
    SOURCES
        InitPlugin.cc
        MyProcessor.cc
)

target_link_libraries(my_plugin
    PRIVATE
        ${JANA_LIBRARY}
        evio_parser_data_types   # gives access to all hit-class headers
)
```

If your plugin also writes ROOT output, add the ROOT targets:

```cmake
target_link_libraries(my_plugin
    PRIVATE
        ${JANA_LIBRARY}
        evio_parser_data_types
        ROOT::Core
        ...
)
```

`add_jana_plugin()` handles the install destination automatically — after `cmake --install`, the `.so` appears in `<install_prefix>/lib/plugins/` alongside the other plugins.

### Step 5 — Register in the plugins CMakeLists

Open `src/plugins/CMakeLists.txt` and add one line:

```cmake
add_subdirectory(evio_parser)
add_subdirectory(evio_processor)
add_subdirectory(my_plugin)      # <-- add this
```

That is the only change required outside your own plugin directory.

### Step 6 — Build, install, and run

```bash
# Reconfigure to pick up the new subdirectory
cmake -S . -B build \
  -DCMAKE_PREFIX_PATH="<path/to/JANA2>;<path/to/evio>;<path/to/ROOT>" \
  -DCMAKE_INSTALL_PREFIX=`pwd`

cmake --build build --parallel
cmake --install build
```

Load the plugin using [`jce.sh`](../../scripts/jce.sh) or [`jce.csh`](../../scripts/jce.csh)

```bash
scripts/jce.sh -Pplugins=my_plugin /path/to/data.evio
```

---

## Consuming Hit Types from evio_parser

Linking against `evio_parser_data_types` (as shown in Step 4) gives your plugin access to every hit-class header without any manual `include_directories` entries.

If you add a new hardware module to `evio_parser` (see [evio_parser/README.md → Adding a New Module Parser](evio_parser/README.md#adding-a-new-module-parser)), its hit type becomes available to any plugin linking `evio_parser_data_types` automatically — no changes to this directory are needed.