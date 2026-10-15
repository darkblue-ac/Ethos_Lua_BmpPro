# BMP Pro for FrSky ETHOS

BMP Pro is a Lua widget for FrSky ETHOS that displays different bitmap images based on configurable rules. It is designed for radio setups where you want to show specific images depending on flight mode, switch position, or other rule-based conditions.

## What it does

The widget evaluates a list of rules from top to bottom. The first rule whose conditions are met determines which bitmap is shown. If none of the rules match, a fallback/default image is displayed.

## Features

- Rule-based bitmap selection
- Supports flight mode conditions
- Supports switch-based activation, including inversion and logical combinations
- Fallback image support
- Built-in widget information and storage usage display
- Available in German and English

## Compatibility

- FrSky ETHOS only
- Not compatible with OpenTX or EdgeTX

## Installation

1. Copy the widget file to:
   - `/scripts/BmpPro/main.lua`
2. Copy the button mask images from the repository's [bitmaps](bitmaps/) folder to:
   - `/scripts/BmpPro/bitmaps/`
3. Place your own bitmap files in:
   - `/bitmaps/BmpPro/`
4. Add the widget in ETHOS and configure your rules.

## Image format

- **BMP must be 16-bit RGB565** (BI_BITFIELDS, masks `F800`/`07E0`/`001F`). Other BMP variants such as 24-bit are not accepted by ETHOS.
- **PNG**: RGB, 8 bits per channel, no palette.
- Create images in the size the widget draws them. The configuration shows it under *Widget information → Widget size*. A loaded image takes its full pixel count in memory, even when drawn smaller.

## Configuration

Each rule can be configured with:

- A bitmap image
- One or more flight modes
- An activation condition based on a switch

Rules are checked from top to bottom, and the first match wins.

Note: ETHOS only reports the currently active flight mode to the widget. To make all available flight modes appear in the configuration list, you must activate each flight mode once on the radio before opening the widget configuration.

## Storage limit and sizing

ETHOS widgets have a very small storage budget. Measured on a Tandem XE with ETHOS 1.6.6, the space for this widget is around 210 characters, which must hold all bitmap file names, flight modes, and switch settings together. The `.bmp` extension is not stored.

Because of that:

- Keep bitmap file names short and descriptive, for example `thermal.bmp` instead of a long path-like name.
- If the configuration becomes too large, the last rules are silently dropped when saving.
- The widget shows the current storage usage in its information screen. Switches are stored as text and counted exactly. If it displays `!`, the current setup no longer fits within the available storage.
- A rule marked with `!` in its header has a stored switch that no longer exists. It stays inactive until you select the switch again.

For best results, keep configurations compact and use short filenames to stay safely within the available storage budget.

## Repository

- GitHub: https://github.com/darkblue-ac/Ethos_Lua_BmpPro

## Author

Created by Stefan Tippl.
