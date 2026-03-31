# evio_processor Plugin

The `evio_processor` consumes the typed hit objects produced by `evio_parser` and writes them to a ROOT file as TTrees and histograms. It also writes a human-readable per-event text summary.

The plugin operates at the **physics event level** — it receives individual `JEvent`s that have already been unfolded by `JEventUnfolder_EVIO` and contain fully decoded detector hits.

---

## Table of Contents

- [Architecture](#architecture)
- [Plugin Initialization](#plugin-initialization)
- [Output Files](#output-files)
- [Data Flow](#data-flow)
- [Configuration Parameters](#configuration-parameters)
- [Example Usage](#example-usage)

---

## Architecture

```
evio_parser plugin
    └─ JEventUnfolder_EVIO
            │  (physics-level JEvents with typed hits)
            ▼
evio_processor plugin
    └─ JEventProcessor_EVIO
            ├─ ProcessSequential(event)
            │       ├─ reads FADC250WaveformHit objects
            │       ├─ reads FADC250PulseHit objects
            │       ├─ reads FADCScalerHit objects
            │       ├─ reads TIScalerHit objects
            │       ├─ reads HelicityDecoderData objects
            │       ├─ reads MPDHit objects
            │       ├─ reads VFTDCHit objects
            │       ├─ reads FADC250HallBPulseIntegralHit objects
            │       ├─ reads FADC250HallBPulseTimeHit objects
            │       ├─ reads FADC250HallBPulsePeakHit objects
            │       ├─ fills ROOT TTrees
            │       ├─ fills ROOT histograms
            │       └─ writes a text summary
            └─ Finish()
                    └─ writes and closes ROOT file
                    └─ closes text file
```

### `JEventProcessor_EVIO`

The single processor class in this plugin. It:

- Uses `CallbackStyle::ExpertMode` and `ProcessSequential` — all ROOT writes happen on a single thread, which is required for ROOT thread safety.
- Declares all hit inputs as **optional** with `SetOptional(true)`. This means the processor will not throw an error if a given hit type is absent from an event (e.g. an event with no waveform data).
- Uses JANA2's typed `Input<T>` mechanism to retrieve hits from the `JEvent` by type.

---

## Plugin Initialization

`InitPlugin.cc` registers `JEventProcessor_EVIO` with the JANA2 application:

```cpp
extern "C" {
    void InitPlugin(JApplication* app) {
        InitJANAPlugin(app);
        app->Add(new JEventProcessor_EVIO());
    }
}
```

No additional services or parsers are registered by this plugin — it relies entirely on objects inserted into `JEvent` by `evio_parser`.

## Output Files

### ROOT file (`evio_processor.root` by default)

| Object | Class | Description |
|---|---|---|
| `waveform_tree` | `TTree` | FADC250 raw waveform samples per event |
| `pulse_tree` | `TTree` | FADC250 pulse analysis data per event |
| `m_tree` | `TTree` | Helicity decoder data |
| `h_integral` | `TH1I` | Distribution of `FADC250PulseHit::integral_sum` values |

### Text file (`evio_processor_hits.txt` by default)

Human-readable per-event dump. Each event block lists counts and field values for every hit type present. Events with no hits at all are omitted.

Example output:

```
Event 42
  Waveform hits: 3
    WF slot=3 chan=0 nsamples=200
    WF slot=3 chan=1 nsamples=200
    WF slot=3 chan=2 nsamples=200
  Pulse hits: 1
    PULSE slot=3 chan=0 integral_sum=4096
  No FADCScalerHit objects in this event
  ...
```

---

## Data Flow

This plugin is the **consumer end** of the pipeline:

```
evio_parser                             evio_processor
──────────────────────────────────      ──────────────────────────────
ModuleParser_FADC::parse()
  → EventHits_FADC::insertIntoEvent()
      → event.Insert(waveforms)    →→→  m_waveform_hits_in()   → waveform_tree
      → event.Insert(pulses)       →→→  m_pulse_hits_in()       → pulse_tree, h_integral
ModuleParser_HelicityDecoder::parse()
  → event.Insert(helicity)         →→→  m_heldec_data_in()      → m_tree
...
```

All hit types consumed by this processor are declared in `JEventProcessor_EVIO.h` as `Input<T>` members. JANA2 resolves them by type at event processing time.

---

## Configuration Parameters

All parameters are set on the JANA2 command line with `-P<name>=<value>`.

| Parameter | Default | `is_shared` | Description |
|---|---|---|---|
| `ROOT_OUT_FILENAME` | `evio_processor.root` | yes | Path/name of the ROOT output file |
| `TXT_OUT_FILENAME` | `evio_processor_hits.txt` | yes | Path/name of the text hit-summary file |

---

## Example Usage

Using the JCE wrapper ([`jce.sh`](../../../scripts/jce.sh) or [`jce.csh`](../../../scripts/jce.csh); see [Basic usage](../../../README.md#basic-usage)):

```bash
scripts/jce.sh -Pplugins=evio_processor data.evio
```

Produces `evio_processor.root` and `evio_processor_hits.txt` in the current directory.

### Custom ROOT output filename

```bash
scripts/jce.sh -Pplugins=evio_processor -PROOT_OUT_FILENAME=run_042.root data.evio
```

### With filtering and custom mapping

```bash
scripts/jce.sh -Pplugins=evio_processor -PFILTER:ENABLE=1 -PFILTER:FILE=config/filter.db -PBANKMAP:FILE=config/mapping.db -PROOT_OUT_FILENAME=run_042_filtered.root data.evio
```