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

## Configuration

Each rule can be configured with:

- A bitmap image
- One or more flight modes
- An activation condition based on a switch

Rules are checked from top to bottom, and the first match wins.

Note: ETHOS only reports the currently active flight mode to the widget. To make all available flight modes appear in the configuration list, you must activate each flight mode once on the radio before opening the widget configuration.

## Storage limit and sizing

ETHOS widgets have a very small storage budget. In practice, the available space for this widget is only around 190 characters, which must hold all bitmap file names, flight modes, and switch settings together.

Because of that:

- Keep bitmap file names short and descriptive, for example `thermal.bmp` instead of a long path-like name.
- Be aware that if the configuration becomes too large, the widget may silently drop the last written values when saving, especially switch-related settings.
- The widget shows the current storage usage in its information screen. If it displays `!`, the current setup no longer fits within the available storage.

For best results, keep configurations compact and use short filenames to stay safely within the available storage budget.

## Repository

- GitHub: https://github.com/darkblue-ac/Ethos_Lua_BmpPro

## Author

Created by Stefan Tippl.
