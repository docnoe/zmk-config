# Repository Guidelines

## Project Overview
This repository is a customized ZMK Firmware user configuration module for a 42-key split wireless Corne (CRKBD v3) keyboard powered by dual nice!nano v2 (Nordic Semiconductor nRF52840 BLE) microcontrollers. Rather than maintaining a full fork of the ZMK codebase, it functions as a modular downstream Zephyr configuration module. Upstream ZMK and Zephyr RTOS dependencies are fetched dynamically via West, and firmware binaries (`.uf2`) for both halves are compiled via GitHub Actions CI.

## Architecture & Data Flow
- **Ecosystem Integration**:
  - Zephyr RTOS and core ZMK framework are pulled downstream according to `config/west.yml`.
  - `zephyr/module.yml` declares `board_root: .`, enabling Zephyr to register the repository root and discover custom boards or shields under `boards/shields/`.
  - `build.yaml` declares target matrix combinations (`nice_nano_v2` with `corne_left` and `corne_right`).
- **Firmware Data Flow**:
  1. **Matrix Scanning (`kscan`)**: Physical key switches are periodically scanned with an 8ms debounce filter on press and release (`config/corne.conf`).
  2. **Combo Engine**: Key switch events are evaluated against combo coordinates (`combos` node in `config/corne.keymap`).
  3. **Behavior Processing**: Active layer mappings resolve key events through hold-taps (`&lt`, `&mt`), tap-dances (`&td_shift`), sticky keys (`&sk`), sticky layers (`&sl`), or macros (`&js_func`).
  4. **HID Reporting**: Resolved key codes are packed into USB/BLE HID reports with full N-Key Rollover (`CONFIG_ZMK_HID_REPORT_TYPE_NKRO=y`).
  5. **Split Inter-Chip Transport**: The peripheral right half transmits switch events wirelessly to the central left half over Bluetooth Low Energy (BLE). The central left half aggregates events and reports to the host computer over BLE or USB.

## Key Directories
- `config/`: Primary user configuration root.
  - `config/corne.keymap`: Devicetree source (DTS) defining key mappings, layers, behaviors, combos, and macros.
  - `config/corne.conf`: Kconfig options for shield runtime settings (debouncing, NKRO, macro tap timings).
  - `config/west.yml`: West manifest defining upstream ZMK dependencies and local module path.
- `boards/shields/`: Extension point for custom board or shield definitions (tracked via `.gitkeep`).
- `zephyr/`: Zephyr module declaration (`zephyr/module.yml`).
- `.github/workflows/`: GitHub Actions CI pipeline (`.github/workflows/build.yml`).

## Development Commands

### Containerized Build (Recommended)
Use the official ZMK ARM build container without needing a local Zephyr SDK installation:
```bash
# Build both left and right halves in Docker
docker run --rm -it -v "$(pwd)":/workspaces/zmk-config -w /workspaces/zmk-config \
  docker.io/zmkfirmware/zmk-build-arm:stable \
  /bin/bash -c "
    west init -l config
    west update
    west build -s /zmk/app -d build/left -b nice_nano_v2 -- -DSHIELD=corne_left -DZMK_CONFIG=/workspaces/zmk-config/config
    west build -s /zmk/app -d build/right -b nice_nano_v2 -- -DSHIELD=corne_right -DZMK_CONFIG=/workspaces/zmk-config/config
  "
```
Binaries will be placed in `build/left/zephyr/zmk.uf2` and `build/right/zephyr/zmk.uf2`.

### Local Native West Build
If a local Zephyr development environment is configured:
```bash
# 1. Initialize workspace (one time)
mkdir ../zmk-workspace && cd ../zmk-workspace
west init -l /path/to/zmk-config/config
west update
west zephyr-export
pip install -r zephyr/scripts/requirements.txt
pip install -r zmk/app/scripts/requirements.txt

# 2. Build left half (central)
west build -s zmk/app -d build/left -b nice_nano_v2 -- -DSHIELD=corne_left -DZMK_CONFIG="/path/to/zmk-config/config"

# 3. Build right half (peripheral)
west build -s zmk/app -d build/right -b nice_nano_v2 -- -DSHIELD=corne_right -DZMK_CONFIG="/path/to/zmk-config/config"
```

### Flashing Hardware
1. Connect microcontroller to host via USB-C.
2. Double-tap the hardware reset button on the nice!nano v2 (or quickly bridge `RST` to `GND` twice).
3. The board enters the UF2 bootloader and mounts as a USB mass storage device named `NICENANO`.
4. Copy the matching `.uf2` file:
```bash
# macOS
cp build/left/zephyr/zmk.uf2 /Volumes/NICENANO/

# Linux
cp build/left/zephyr/zmk.uf2 /media/$USER/NICENANO/
```
The controller will reboot automatically once flashing completes. Repeat for the right half with the right binary.

## Code Conventions & Common Patterns

### Devicetree Formatting & Layout
- Use 4 spaces for indentation in `.keymap` files. Never use tabs. Never leave trailing spaces.
- Semicolons are mandatory after node declarations, property assignments, and behavior overrides.
- Format layer key matrices strictly into 4 readable lines matching the physical Corne 3x6+3 layout (12 keys top row, 12 keys home row, 12 keys bottom row, 6 thumb keys indented).

### Behavior Cell Counts (`#binding-cells`)
Ensure `#binding-cells` accurately matches the behavior parameter signature:
- `#binding-cells = <0>`: Zero-argument behaviors, tap-dances, and macros (e.g. `td_shift: td_shift`, `js_func: function`).
- `#binding-cells = <1>`: Single-argument behaviors (e.g. `&tog 1`, `&kp A`, `&sl 5`).
- `#binding-cells = <2>`: Two-argument behaviors like layer-tap and hold-tap (e.g. `&lt 4 D`, `&mt LCTRL S`).

### Layer Structure & State Management
The keymap consists of 7 layers (0 through 6):
- **Layer 0 (`default_layer`)**: Base QWERTY layout with balanced home-row mod-taps (`&mt`), layer-tap keys (`&lt 4 D`, `&lt 5 F`, `&lt 6 C`, `&lt 4 K`, `&lt 3 SPACE`, `&lt 6 ENTER`), and tap-dance shift (`&td_shift`).
- **Layer 1 (`no_sticky_shift`)**: Alternate base layer replacing `&td_shift` with standard `&kp LEFT_SHIFT`. Toggled with `&tog 1` on key position 24.
- **Layer 2 (`steno`)**: Raw alpha and number layer without mod-taps for gaming or steno input. Toggled with `&tog 2` on key position 0.
- **Layer 3 (`layer_2`)**: Number row (`1-0`), symbols (`!@#$%^&*`), and macOS word-deletion thumb keys (`LA(BACKSPACE)`, `LA(DELETE)`).
- **Layer 4 (`layer_3`)**: Programming symbols (`()`, `{}`, `[]`, `<>`, `+`, `=`, `-`, `_`, `|`, `\`, `~`), and tab/bracket navigation (`LG(LBKT)`, `LG(RBKT)`).
- **Layer 5 (`layer_4`)**: 3x3 window manager grid shortcuts on the left (`LC(LA(N1))` through `LC(LA(N9))`), 3x3 numeric keypad on the right, and `&js_func` macro (`() => {\n`).
- **Layer 6 (`layer_5`)**: Function keys (`F1`-`F12`), volume controls (`C_VOL_UP`, `C_VOL_DN`), and directional navigation cluster (`LEFT`, `DOWN`, `UP`, `RIGHT`, `HOME`, `END`, `PG_UP`, `PG_DN`).

### Global Behavior Overrides
- `&mt`: Configured with `flavor = "balanced"` and `quick-tap-ms = <200>` to prevent accidental hold activations during fast typing.
- `&lt`: Configured with `quick-tap-ms = <200>` for responsive tapping.
- `&sk`: Configured with `quick-release` and `release-after-ms = <300>`.

### Combos & Shortcuts
- Key positions follow the 42-key index: Left half (`0-5`, `12-17`, `24-29`, thumbs `36-38`), Right half (`6-11`, `18-23`, `30-35`, thumbs `39-41`).
- `clearbt`: Positions `<0 24>` (`&bt BT_CLR_ALL`) to wipe BLE bonds.
- `comb_paren`: Positions `<15 6>` (`&kp LEFT_PARENTHESIS`).
- `comb_brace`: Positions `<15 18>` (`&kp LEFT_BRACE`).
- `comb_bracket`: Positions `<15 30>` (`&kp LEFT_BRACKET`).

### Split Sync & Bluetooth Troubleshooting
- If Bluetooth communication desyncs between halves or connections with the host drop:
  1. Flash `settings_reset-nice_nano_v2-zmk.uf2` to both halves to clear internal flash NVS bonding keys.
  2. Flash `corne_left-nice_nano_v2-zmk.uf2` to the left half and `corne_right-nice_nano_v2-zmk.uf2` to the right half.
  3. Power on both halves simultaneously in proximity before reconnecting to the host device.

## Important Files
- `build.yaml`: GitHub Actions matrix declaring build targets (`board: nice_nano_v2`, `shield: corne_left` and `corne_right`).
- `config/corne.keymap`: Core Devicetree file containing key bindings, behaviors, combos, and macros.
- `config/corne.conf`: Kconfig options for debouncing, NKRO, and macro timings.
- `config/west.yml`: West workspace manifest anchoring dependencies to upstream ZMK `main`.
- `zephyr/module.yml`: Module declaration designating the repository root as Zephyr `board_root`.
- `.github/workflows/build.yml`: CI/CD workflow triggering the upstream ZMK reusable build workflow.

## Runtime/Tooling Preferences
- **Build Toolchain**: Zephyr West meta-tool with CMake (>= 3.20.5), Ninja (>= 1.8), and Device Tree Compiler `dtc` (>= 1.4.6).
- **Environment**: Containerized builds using `zmkfirmware/zmk-build-arm:stable` are preferred over host SDK setups.
- **Python**: 3.8+ required when running West natively.
- **Formatting Constraints**: No trailing whitespace. 4 spaces indentation for Devicetree (`.keymap`), 2 spaces for YAML (`.yml`/`.yaml`), `KEY=value` for Kconfig (`.conf`). Plain dash "-" instead of em dash.

## Testing & QA
- **CI Build Validation**:
  - Pushes and pull requests trigger `.github/workflows/build.yml`.
  - Reusable workflow `zmkfirmware/zmk/.github/workflows/build-user-config.yml@main` compiles every target in `build.yaml`.
  - The build pipeline acts as the primary quality gate: any Devicetree syntax error, unknown keycode constant, mismatched `#binding-cells`, or matrix count mismatch breaks the build.
- **Static Integrity Checks Before Committing**:
  - Key count per layer: Verify that each layer in `config/corne.keymap` contains exactly 42 key bindings.
  - Combo boundaries: Verify that all combo `key-positions` indices are integers in the range `[0..41]`.
  - Header bindings: Ensure any newly introduced key codes or behavior bindings match available symbols in `<dt-bindings/zmk/keys.h>`, `<dt-bindings/zmk/bt.h>`, or `<behaviors.dtsi>`.
- **Physical Verification**:
  - Download `firmware.zip` artifact from the GitHub Actions run.
  - Flash both controllers and test modifier rolls, layer transitions, thumb-cluster tap-dance, and BLE host pairing.