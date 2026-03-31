# evio_parser Plugin

The `evio_parser` plugin is the **data-ingestion layer** of the jana2-common-extensions framework. It is responsible for:

1. Opening EVIO files and streaming raw events through JANA2.
2. Decoding hardware-specific banks (FADC250, MPD, VFTDC, scalers, helicity decoder, …) into strongly-typed C++ hit objects.
3. Splitting EVIO block-level events into individual physics-level child events that downstream processors can consume.

It is **hardware-agnostic at its core** — all detector-specific logic lives in `module_parsers/` and is registered at plugin initialisation time, so adding support for a new module requires no changes to the framework code.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Directory Structure](#directory-structure)
- [Data Flow](#data-flow)
- [Data Objects](#data-objects)
- [Configuration Parameters](#configuration-parameters)
- [Environment Variables](#environment-variables)
- [Adding a New Module Parser](#adding-a-new-module-parser)

---

## Architecture Overview

```
EVIO File
    │
    ▼
JEventSource_EVIO          (reads file, emits block-level JEvents)
    │   └─ ProcessParallel → EvioEventParser
    │                           ├─ parseTriggerBank()
    │                           └─ parseROCBanks()
    │                               ├─ JEventService_FilterDB      (allow-list check)
    │                               ├─ JEventService_BankToModuleMap  (bank → module ID)
    │                               └─ JEventService_ModuleParsersMap → ModuleParser_X::parse()
    │                                                                        └─ PhysicsEvent*
    ▼
JEventUnfolder_EVIO        (splits block → individual physics JEvents)
    │
    ▼
Downstream JEventProcessors  (e.g. evio_processor)
```

### Key Components

| Component | File(s) | Responsibility |
|---|---|---|
| `JEventSource_EVIO` | `JEventSource_EVIO.cc/.h` | Opens the EVIO file; emits one block-level `JEvent` per EVIO event; invokes `EvioEventParser` in `ProcessParallel` |
| `EvioEventParser` | `core/EvioEventParser.cc/.h` | Parses the trigger bank and ROC banks; parses each bank using its `ModuleParser` and insert parsed hits into a `PhysicsEvent` object; later inserts the `PhysicsEvent` objects into the block-level `JEvent` |
| `JEventUnfolder_EVIO` | `JEventUnfolder_EVIO.h` | Receives a block-level `JEvent` containing `PhysicsEvent` objects; splits each one into an individual physics-level child `JEvent` and calls `insertHitsIntoEvent` on each |
| `ModuleParser` (base) | `core/ModuleParser.h` | Abstract base class all hardware parsers implement |
| `ModuleParser_FADC` etc. | `module_parsers/*/ModuleParser_*.cc/.h` | Concrete decoders for specific hardware modules; produce `EventHits` objects per event |
| `JEventService_BankToModuleMap` | `services/JEventService_BankToModuleMap.h` | Loads `mapping.db`; resolves EVIO bank tag → module ID |
| `JEventService_ModuleParsersMap` | `services/JEventService_ModuleParsersMap.h` | Registry of `ModuleParser*` instances keyed by module ID |
| `JEventService_FilterDB` | `services/JEventService_FilterDB.cc/.h` | Optional allow-list; gates which ROC IDs and bank tags are decoded |

## Directory Structure

```
src/plugins/evio_parser/
├── InitPlugin.cc                  # Plugin entry point; registers all components and module parsers
├── JEventSource_EVIO.cc/.h        # EVIO file event source
├── JEventUnfolder_EVIO.h          # Block → physics event unfolder
│
├── core/                          # Generic parsing infrastructure (hardware-agnostic)
│   ├── EvioEventParser.cc/.h      # Trigger-bank + ROC-bank orchestrator
│   ├── ModuleParser.h             # Abstract base class for all hardware parsers
│   └── data_objects/
│       ├── EventHits.h            # Abstract base: owns hits, knows how to insert into JEvent
│       ├── EvioEventWrapper.h     # JObject wrapper around evio::EvioEvent shared_ptr
│       ├── PhysicsEvent.h         # Container: event number + list of EventHits
│       └── TriggerData.h          # POD: trigger bank data
│
├── services/                      # JANA2 services (singletons shared across threads)
│   ├── JEventService_BankToModuleMap.h
│   ├── JEventService_FilterDB.cc/.h
│   └── JEventService_ModuleParsersMap.h
│
└── module_parsers/                  # Hardware-specific parsers (extend here)
    ├── CMakeLists.txt             # Aggregates MODULE_PARSERS_LIBS for the main build
    ├── InitModuleParsers.cc       # Central module parser registration function
    ├── FADC/                      # FADC250 waveform + pulse parser
    ├── FADCScaler/                # FADC scaler parser
    ├── TIScaler/                  # TI scaler parser
    ├── helicity_decoder/          # Helicity decoder parser
    ├── MPD/                       # MPD (Multi-Purpose Digitizer) parser
    └── VFTDC/                     # VFTDC TDC parser
```

**Why this layout?**

- `core/` is the stable, experiment-agnostic kernel. You should rarely need to touch it.
- `services/` are JANA2 singletons that provide shared, thread-safe configuration to all parsers.
- `module_parsers/` is the extension zone. Each hardware type gets its own subdirectory and static library so that adding or removing a module requires only local changes.

---

## Data Flow

### Block-level (inside `JEventSource_EVIO`)

1. `Emit()` reads the next EVIO event from disk, checks that it is a physics event (tag `0xFF50` or `0xFF58`), and wraps it in an `EvioEventWrapper` inserted into a block-level `JEvent`.
2. `ProcessParallel()` (called by JANA2 on a worker thread) invokes `EvioEventParser::parse()`, which:
   - Parses the **trigger bank** to extract `TriggerData` (first event number) and ROC segments.
   - Iterates **ROC banks**: for each DMA block, resolves `bank_id → module_id → ModuleParser*` and calls `ModuleParser::parse()`.
   - Merges `PhysicsEvent*` objects that share the same event number (different parsers may produce overlapping event numbers).
3. The resulting `PhysicsEvent*` vector is inserted into the block-level `JEvent`.

### Physics-level (inside `JEventUnfolder_EVIO`)

`JEventUnfolder_EVIO::Unfold()` is called once per `PhysicsEvent` in the block. It:
- Sets the child event number and run number.
- Calls `PhysicsEvent::insertHitsIntoEvent()`, which iterates each `EventHits` object and calls its `insertIntoEvent(JEvent&)` override, making typed hit objects available to downstream processors.

---

## Data Objects

### `PhysicsEvent`

Container for a single physics event. Holds:
- `int event_num` — the absolute event number computed from `TriggerData::first_event_number + event_index`.
- `std::vector<std::shared_ptr<EventHits>> hits_list` — one entry per subsystem that contributed data to this event.

Multiple `PhysicsEvent*` objects with the same event number (produced by different parsers in the same block) are **merged** by `EvioEventParser::parse()` before being handed to the unfolder.

### `EventHits` (abstract)

Base class for all per-subsystem hit containers. Derived classes (e.g. `EventHits_FADC`, `EventHits_MPD`) own their hit vectors and know how to insert them into a `JEvent`.

### `TriggerData`

Simple POD holding `uint64_t first_event_number`, extracted from the EB1 segment of the trigger bank. Used by parsers to compute absolute event numbers.

### `EvioEventWrapper`

A `JObject` that wraps a `std::shared_ptr<evio::EvioEvent>` so that JANA2's ownership model can manage the lifetime of EVIO events.

---

## Configuration Parameters

All parameters can be set on the JANA2 command line with `-P<NAME>=<value>`.

### Bank-to-module mapping

| Parameter | Default | Description |
|---|---|---|
| `BANKMAP:FILE` | `<install_prefix>/config/mapping.db` | Path to the two-column module/bank mapping file |

```bash
# Example: use a custom mapping file
jana -Pplugins=evio_parser,evio_processor -PBANKMAP:FILE=/path/to/my_mapping.db data.evio
```

### ROC/bank filtering

| Parameter | Default | Description |
|---|---|---|
| `FILTER:ENABLE` | `false` | Set to `1` or `true` to enable ROC/bank allow-list filtering |
| `FILTER:FILE` | `<install_prefix>/config/filter.db` | Path to the four-column ROC/bank filter file |

```bash
# Example: enable filtering with a custom filter file
jana -Pplugins=evio_parser,evio_processor -PFILTER:ENABLE=1 -PFILTER:FILE=/path/to/my_filter.db data.evio
```


> These examples use `jana` directly. If you are using the [jce.sh / jce.csh](../../../README.md#basic-usage) wrapper, the same parameters can be passed through it.

## Environment Variables

| Variable | Description |
|---|---|
| `JCE_CONFIG_DIR` | If set, overrides the install-prefix config directory for **all** config files (`mapping.db`, `filter.db`, `default_plugins.db`). Takes priority over the installed location. |
| `JANA_PLUGIN_PATH` | Standard JANA2 variable — colon-separated list of directories searched for plugin `.so` files. |

```bash
# Override config directory entirely
setenv JCE_CONFIG_DIR /my/experiment/config
jana -Pplugins=evio_parser,evio_processor data.evio
```

Config file resolution order (implemented in `jce_config_paths.h`):
1. `$JCE_CONFIG_DIR/<filename>` — user override, always wins.
2. `<install_prefix>/config/<filename>` — installed location (checked for existence).
3. Exception is thrown if the file is not found at either location.

---

## Adding a New Module Parser

This section is the guide for extending the plugin with support for a new hardware module.

### Step 1 — Choose a bank ID and module ID

Decide which EVIO bank tag your module produces (e.g. `350`) and assign a unique module ID (e.g. `350`). Confirm the 32-bit word layout for that hardware (block headers, event headers, data words, trailers).

### Step 2 — Create the directory layout

```bash
mkdir -p src/plugins/evio_parser/module_parsers/MyHW/data_objects
```

Use `module_parsers/FADC/` as a reference:

```
module_parsers/MyHW/
├── CMakeLists.txt
├── ModuleParser_MyHW.cc
├── ModuleParser_MyHW.h
└── data_objects/
    ├── MyHWHit.h
    └── EventHits_MyHW.h
```

### Step 3 — Define your hit class and EventHits subclass

In `data_objects/`, create two files:
 
- **`MyHWHit.h`** — a plain struct holding the per-hit fields your hardware produces (slot, channel, value, timestamp, etc.).
- **`EventHits_MyHW.h`** — subclass of `EventHits` that owns a `std::vector<MyHWHit*>` and implements `insertIntoEvent(JEvent&)` by calling `event.Insert(hits)`.
 
See `module_parsers/FADC/data_objects/` for a concrete reference.

### Step 4 — Implement `ModuleParser_MyHW`
 
Your parser class inherits from `ModuleParser` and overrides `parse()` (signature described in the [Module Parser System](#module-parser-system) section above). In the `::parse()` implementation:
 
- Retrieve raw words with `data_block->getUIntData()`.
- Walk the word array following your hardware's block/event/data/trailer structure.
- Use `getBitsInRange(word, high_bit, low_bit)` for all bit-field extraction.
- Accumulate hits per event number in a local `std::map<uint64_t, std::shared_ptr<EventHits_MyHW>>`, then push a `new PhysicsEvent(evnum, hits)` per entry into `physics_events`.
 
See `module_parsers/FADC/ModuleParser_FADC.cc` for a complete worked example.

### Step 5 — Add a `CMakeLists.txt` for the new parser

**`module_parsers/MyHW/CMakeLists.txt`**:

```cmake
add_library(myhw_parser STATIC
    ModuleParser_MyHW.cc
)

target_include_directories(myhw_parser
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/data_objects
)

target_link_libraries(myhw_parser
    PUBLIC
        core   # provides ModuleParser base class and core data objects
)

set(MYHW_INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/data_objects PARENT_SCOPE)

file(GLOB MYHW_PUBLIC_HEADERS ${CMAKE_CURRENT_SOURCE_DIR}/data_objects/*.h)
set(MYHW_PUBLIC_HEADERS ${MYHW_PUBLIC_HEADERS} PARENT_SCOPE)
```

### Step 6 — Register the new parser in `module_parsers/CMakeLists.txt`

Open `src/plugins/evio_parser/module_parsers/CMakeLists.txt` and add three lines:

```cmake
# Add subdirectory
add_subdirectory(MyHW)

# Extend the library list (inside the set() call for MODULE_PARSERS_LIBS)
set(MODULE_PARSERS_LIBS
    ...existing entries...
    myhw_parser          # <-- add this
    PARENT_SCOPE
)

# Extend include dirs
set(MODULE_PARSERS_INCLUDE_DIRS
    ...existing entries...
    ${MYHW_INCLUDE_DIR}  # <-- add this
    PARENT_SCOPE
)

# Extend headers
set(MODULE_PARSERS_HEADERS
    ...existing entries...
    ${MYHW_PUBLIC_HEADERS}  # <-- add this
    PARENT_SCOPE
)
```

### Step 7 — Register the parser instance in `module_parsers/InitModuleParsers.cc`

Open `src/plugins/evio_parser/module_parsers/InitModuleParsers.cc` and add:

```cpp
#include "ModuleParser_MyHW.h"   // at the top (with other parser includes)

// Inside InitModuleParsers(JApplication* app):
module_parsers_svc->addParser(350, new ModuleParser_MyHW());
```

### Step 8 — Add a bank-to-module mapping entry

Edit `config/mapping.db` (or whichever file is pointed to by `BANKMAP:FILE`):

```
# module  bank
  350    350
```

This tells `EvioEventParser` to route bank tag `350` to module ID `350`, which is then looked up in `JEventService_ModuleParsersMap` to retrieve your `ModuleParser_MyHW` instance.

### Step 9 — Expose hits to downstream processors

To consume `MyHWHit` objects in a downstream processor, take following actions.

**For plugins inside this repository**, linking against the `evio_parser_data_types` interface library is enough — no `find_package` or manual `include_directories` required:
```cmake
target_link_libraries(my_processor
    PRIVATE
        ${JANA_LIBRARY}
        evio_parser_data_types
)
```

**For external plugins** built outside this repository, the target is exported during installation. Point `CMAKE_PREFIX_PATH` at the install prefix and use the namespaced target:
```cmake
find_package(jana2_common_extensions REQUIRED)

target_link_libraries(my_processor
    PRIVATE
        ${JANA_LIBRARY}
        jana2_common_extensions::evio_parser_data_types
)
```

In both cases, once the target is linked you can include any hit-class header directly and declare the `Input<T>` member in your processor:
```cpp
#include "MyHWHit.h"

Input<MyHWHit> m_myhw_hits {this};
```

Follow the same pattern used in `JEventProcessor_EVIO` for `FADC250WaveformHit`, `MPDHit`, etc.

### Step 10 — Rebuild and test

```bash
cmake -S . -B build 
cmake --build build --parallel
```

Run on an EVIO file that contains bank `350` and verify that `PhysicsEvent` objects are populated with `MyHWHit` data using instructions given in [Using the Plugins with JANA2](../../../README.md#basic-usage)

---

## Notes

- `JEventSource_EVIO` currently accepts EVIO physics events with tags `0xFF50` and `0xFF58` only. Events with other tags (including run-control events `0xFFD0`–`0xFFDF`) are skipped in `Emit()`. Run numbers are extracted from prestart events (tag `0xFFD1`).
- `EvioEventParser::parse()` will throw a `JException` if an EVIO block produces zero `PhysicsEvent` objects after parsing. Ensure your parser always produces at least one object per block, even if the block contains no data of interest.
- Module parsers are **shared across threads** — `ProcessParallel` is called concurrently on multiple worker threads. Parsers must not use mutable member state; all per-event data must be local variables or heap-allocated per event.