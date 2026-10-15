# Arbeitsregeln für dieses Projekt

Lua-Widget für FrSky Ethos, das Bilder nach Regeln anzeigt. Überblick:
[README.md](README.md), alle Hintergründe stehen als Kommentare in
[main.lua](main.lua).

## Bilder für Ethos

**BMP immer als 16 Bit RGB565** – das verlangt Ethos (Stand 1.6.x), andere
BMP-Varianten wie 24 Bit nimmt es nicht. Aufbau, wie ihn auch MT3D-Modules
(`scripts/widget_bilder.py`, `bmp565()`) schreibt:

* 40-Byte-Kopf (`BITMAPINFOHEADER`), 16 Bit je Pixel
* Kompression `BI_BITFIELDS` (3) mit den Masken `F800` / `07E0` / `001F`
* Zeilen von unten nach oben, auf 4 Byte aufgefüllt

**PNG**: Farbtyp RGB, 8 Bit je Kanal, ohne Palette und Interlacing ist
erprobt (so verlangt es `lcd.loadMask`). Ob `lcd.loadBitmap` auch Alpha
nimmt, ist noch offen.

Bilder in der Größe anlegen, in der das Widget sie zeichnet (steht in der
Konfiguration unter „Widget-Informationen → Widget-Größe“): Ein geladenes
Bild belegt seine volle Pixelzahl im Speicher, auch wenn es verkleinert
gezeichnet wird.

## Speicher

Ethos-Speicher ist eine Liste, kein Wörterbuch, und fasst nur rund 190
Zeichen – Einzelheiten im Kopf von `main.lua`. `write()` und `read()` müssen
immer gleich viele Werte in gleicher Reihenfolge verarbeiten; nie `nil`
schreiben.

## Sprache

Kommentare, Commit-Nachrichten und Doku auf Deutsch, knapp. Oberflächentexte
deutsch und englisch in der Tabelle `T` in `main.lua`.
