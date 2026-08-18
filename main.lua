-- ============================================================
-- BMP Pro - Bildanzeige nach Regeln, fuer FrSky Ethos
--
-- Zeigt ein Bitmap an, das ueber eine geordnete Liste von Regeln
-- bestimmt wird. Jede Regel kann an Flugphasen und an eine
-- "Aktiviert durch"-Bedingung geknuepft werden - dieselbe
-- Schalterauswahl wie bei den Mixern, inklusive Invertierung (!SA)
-- und logischer Verknuepfung.
--
-- Die Regeln werden von OBEN nach UNTEN geprueft. Die erste Regel,
-- deren Bedingungen erfuellt sind, bestimmt das Bild. Passt keine
-- Regel, erscheint das Standard-Bild.
--
-- Konfiguration - eine Zeile je Regel, Details per [+] ausklappbar:
--
--   1. bild.bmp                           [+] [^] [v] [X]
--
--   1. bild.bmp                           [-] [^] [v] [X]
--          Bild                               [bild.bmp]
--          Alle Flugphasen                          [Ja]
--          Aktiviert durch                         [SA+]
--
-- Die Flugphasen-Auswahl erscheint nur, wenn "Alle Flugphasen" auf
-- Nein steht.
--
-- NUR FUER ETHOS: verwendet ausschliesslich APIs aus der offiziellen
-- Ethos-Lua-Referenz (system.*, model.*, form.*, lcd.*, storage.*).
-- Nicht kompatibel mit OpenTX/EdgeTX.
--
-- INSTALLATION
--   Lua-Datei      /scripts/BmpPro/main.lua
--   Button-Icons   /scripts/BmpPro/bitmaps/   (mask_*.png mitkopieren)
--   Eigene Bilder  /bitmaps/BmpPro/
--
-- ------------------------------------------------------------
-- ZWEI EIGENHEITEN VON ETHOS BESTIMMEN DEN AUFBAU
--
-- 1. DER SPEICHER IST EINE LISTE, KEIN WOERTERBUCH.
--    Der Schluesselname bei storage.read/write wird ignoriert - es
--    zaehlt allein die Reihenfolge der Aufrufe. Bestaetigt von FrSky
--    in ETHOS-Feedback-Community #2033, in 1.6.2 unveraendert (#5495).
--    write() und read() muessen deshalb immer gleich viele Werte in
--    gleicher Reihenfolge verarbeiten. Wie das hier geloest ist,
--    steht im Abschnitt "Persistenz".
--
-- 2. DER SPEICHER IST SEHR KLEIN.
--    Gemessen auf einer Tandem XE mit Ethos 1.6.6: bei 190 Zeichen kam alles
--    vollstaendig an, bei 200 gingen die zuletzt geschriebenen Werte
--    still verloren. Deshalb ist das Speicherformat auf jedes einzelne
--    Zeichen optimiert, und deshalb sind kurze Bilddateinamen wichtig.
--    Der aktuelle Verbrauch steht in der Konfiguration unter
--    "Widget-Informationen". Laut Issue 
--    https://github.com/FrSkyRC/ETHOS-Feedback-Community/issues/5462?utm_source=copilot.com
--    sind es 200 Zeichen, aber vermutlich zählen ein paar interne 
--    Verwaltungswerte mit, die Ethos nicht anzeigt.

--
-- Dazu kommt: Ethos kann nicht alle Flugphasen im Voraus nennen, nur
-- die gerade aktive. Sie werden daher zur Laufzeit eingesammelt -
-- siehe Abschnitt "Flugphasen".
-- ============================================================

local MAX_FM    = 20   -- maximale Anzahl Flugphasen, die geprüft werden
local MAX_RULES = 10   -- maximale Anzahl Regeln (nicht erhoehen: Storage-Limit!)
local BMP_PATH  = "/bitmaps/BmpPro"

-- Widget-Metadaten (fuer den Info-Bereich in der Konfiguration)
local SCRIPT_VERSION = "1.0.0"
local SCRIPT_AUTHOR  = "Stefan Tippl"
local GITHUB_REPO    = "darkblue-ac/Ethos_Lua_BmpPro"

-- Einrueckung der aufgeklappten Detailzeilen
local INDENT    = "       "

-- ------------------------------------------------------------
-- Storage (Details im Abschnitt "Persistenz")
--
-- Ethos ignoriert den Schluesselnamen und arbeitet ueber die
-- REIHENFOLGE der Aufrufe. Geschrieben wird deshalb:
--
--   Wert 1        Basis  "7;<regelzahl>;<fallbackbild>"
--   Wert 2..N+1   die N Regeln
--   danach        je ein Wert fuer jede Regel, die einen Schalter hat
--
-- Die Regelzahl steht in Wert 1, und jede Regel sagt selbst, ob sie
-- einen Schalter hat. read() weiss dadurch vor jedem Lesevorgang
-- genau, wie viele Werte noch kommen - die Reihenfolge bleibt sicher,
-- obwohl die Anzahl variabel ist.
-- ------------------------------------------------------------
local CFG_VERSION = 7     -- Version der Speicherstruktur, wird in Wert 1 gespeichert, und muss geändert werden, wenn sich bei einer version bzgl. Speicherung was ändert.
local SEP_REC     = ";"   -- Trenner im Basisdatensatz
local SEP_FLD     = "|"   -- Trenner innerhalb eines Regelsatzes

-- Zeichenbudget fuer die Anzeige "Speicher x / y".
--
-- 190 ist der auf einer Tandem XE mit Ethos 1.6.6 gemessene Wert, bei dem
-- nachweislich alles ankam - nicht die vermutete Obergrenze von rund
-- 200. Was Ethos intern fuer Verwaltung und Index abzieht, ist nicht
-- dokumentiert; die Differenz ist bewusst als Puffer stehengelassen.
local STORAGE_BUDGET = 190

-- ------------------------------------------------------------
-- Sprache / Uebersetzungen
--
-- system.getLocale() liefert den Sprachcode ("de", "en", "fr", ...).
-- Ist die Sprache Deutsch, zeigen wir deutsche Texte, sonst immer
-- Englisch. Die Sprache wird einmalig beim Laden bestimmt.
-- ------------------------------------------------------------
local T = {
    de = {
        widgetName   = "BMP Pro",
        imagesUnder  = "Bildordner",
        fallback     = "Standard-Bild",
        image        = "Bild",
        allPhases    = "Alle Flugphasen",
        activatedBy  = "Aktiviert durch",
        noImage      = "(kein Bild)",
        addRule      = "+ Regel hinzufügen",
        confirmTitle = "Bestätigen",
        confirmDel   = "Regel %d wirklich löschen?",
        yes          = "Ja",
        no           = "Nein",
        infoTitle    = "Widget-Informationen",
        infoRepo     = "GitHub",
        infoVersion  = "Version",
        infoAuthor   = "Autor",
        infoStorage  = "Speicher (Zeichen)",
        helpLine     = "Hilfe",
        helpTitle    = "Hilfe",
        ok           = "OK",
        helpMessage  = "BMP Pro zeigt ein Bild je nach Regel an.\n\n\z
Bilder ablegen unter:\n%s\n\n\z
Flugphasen: Ethos liefert nur die gerade aktive Phase. Damit alle \z
Phasen zur Auswahl erscheinen, einmal alle Flugphasen am Sender \z
durchschalten.\n\n\z
Regeln werden von OBEN nach UNTEN geprueft. Die erste Regel, deren \z
Bedingungen erfuellt sind, bestimmt das angezeigte Bild. Passt keine \z
Regel, wird das Standard-Bild (Fallback) angezeigt.\n\n\z
SPEICHERPLATZ - WICHTIG:\n\z
Ethos gibt jedem Widget nur rund 190 Zeichen. Da muessen ALLE \z
Bilddateinamen, Flugphasen und Schalter zusammen hineinpassen. Bei \z
10 Regeln bleiben pro Regel nur etwa 15 Zeichen, davon gehen einige \z
fuer Flugphasen und Trennzeichen ab.\n\n\z
Halte die Dateinamen deshalb kurz: \"LkwFahr.bmp\" statt \z
\"LKW_Scania_Fahrmodus_1.bmp\". Sonst gehen beim Speichern still \z
die zuletzt geschriebenen Werte verloren - zuerst die Schalter.\n\n\z
Der aktuelle Verbrauch steht unter Widget-Informationen. Erscheint \z
dort ein \"!\", passt es nicht mehr.",
        noBitmap     = ": kein Bitmap",
        ruleWord     = "Regel",
        fallbackWord = "Fallback",
    },
    en = {
        widgetName   = "BMP Pro",
        imagesUnder  = "Image folder",
        fallback     = "Default image",
        image        = "Image",
        allPhases    = "All flight modes",
        activatedBy  = "Activated by",
        noImage      = "(no image)",
        addRule      = "+ Add rule",
        confirmTitle = "Confirm",
        confirmDel   = "Really delete rule %d?",
        yes          = "Yes",
        no           = "No",
        infoTitle    = "Widget information",
        infoRepo     = "GitHub",
        infoVersion  = "Version",
        infoAuthor   = "Author",
        infoStorage  = "Storage (chars)",
        helpLine     = "Help",
        helpTitle    = "Help",
        ok           = "OK",
        helpMessage  = "BMP Pro shows an image based on rules.\n\n\z
Place images in:\n%s\n\n\z
Flight modes: Ethos only reports the currently active mode. To make \z
all modes appear for selection, cycle through every flight mode on \z
the radio once.\n\n\z
Rules are checked from TOP to BOTTOM. The first rule whose conditions \z
are met determines the displayed image. If no rule matches, the \z
default image (fallback) is shown.\n\n\z
STORAGE - IMPORTANT:\n\z
Ethos gives each widget only about 190 characters. ALL image file \z
names, flight modes and switches must fit in there together. With 10 \z
rules that leaves roughly 15 characters per rule, some of which go to \z
flight modes and separators.\n\n\z
So keep file names short: \"thermal.bmp\" instead of \z
\"glider_phase_thermal.bmp\". Otherwise the values written last are \z
silently lost when saving - the switches first.\n\n\z
Current usage is shown under Widget information. A \"!\" there means \z
it no longer fits.",
        noBitmap     = ": no bitmap",
        ruleWord     = "Rule",
        fallbackWord = "Fallback",
    },
}

-- Sprache einmalig bestimmen: Deutsch bei "de", sonst Englisch
local LANG = "en"
do
    local ok, loc = pcall(function() return system.getLocale() end)
    if ok and type(loc) == "string" and loc:sub(1, 2) == "de" then
        LANG = "de"
    end
end

-- tr(key): liefert den uebersetzten Text zum Schluessel
local function tr(key)
    local tab = T[LANG] or T.en
    return tab[key] or T.en[key] or key
end

-- Button-Icons (Masken), relativer Pfad "bitmaps/...".
-- Ethos zeichnet die Maske selbst in den Button (icon-Parameter), die
-- Farbe kommt vom Theme. Einmalig laden, mit pcall abgesichert:
-- fehlen die Dateien, faellt der Button auf ein Textzeichen zurueck.
local ICON_DIR = "bitmaps/"

local function loadMaskSafe(file)
    local ok, mask = pcall(function() return lcd.loadMask(ICON_DIR .. file) end)
    if ok and mask ~= nil then return mask end
    return nil
end

-- Alle Masken sind invertiert (undurchsichtige Flaeche, Symbol als
-- Aussparung) -> Ethos zeichnet einen dunklen Button mit hellem Symbol.
local iconPlus   = loadMaskSafe("mask_plus.png")
local iconMinus  = loadMaskSafe("mask_minus.png")
local iconUp     = loadMaskSafe("mask_up.png")
local iconDown   = loadMaskSafe("mask_down.png")
local iconDelete = loadMaskSafe("mask_delete.png")

-- ------------------------------------------------------------
-- Hilfsfunktionen
-- ------------------------------------------------------------

-- buildPath(filename)
-- Baut den vollständigen Pfad zum Bitmap zusammen
local function buildPath(filename)
    if filename == nil or filename == "" then return nil end
    if string.find(filename, "/") then return filename end
    return BMP_PATH .. "/" .. filename
end

-- splitString(str, sep)
-- Zerlegt einen String an einem festen Trennzeichen. Anders als
-- string.gmatch bleiben LEERE Felder erhalten - das ist fuer das
-- Konfigurationsformat zwingend noetig.
local function splitString(str, sep)
    local out, pos = {}, 1
    while true do
        local s, e = string.find(str, sep, pos, true)
        if s == nil then
            out[#out + 1] = string.sub(str, pos)
            break
        end
        out[#out + 1] = string.sub(str, pos, s - 1)
        pos = e + 1
    end
    return out
end

-- slotList(line, widths)
-- Wrapper um form.getFieldSlots(). Die Ethos-Referenz indiziert die
-- Rueckgabe ab 0 (Beispiel: form.getFieldSlots(line, {...})[0]).
-- Damit das Script unabhaengig von der Firmware-Variante korrekt
-- liegt, ermitteln wir die Basis und liefern eine 1-basierte Liste.
local function slotList(line, widths)
    local ok, raw = pcall(function() return form.getFieldSlots(line, widths) end)
    if not ok or type(raw) ~= "table" then return {} end

    local base = (raw[0] ~= nil) and 0 or 1
    local out = {}
    for i = 1, #widths do
        out[i] = raw[base + i - 1]
    end
    return out
end

-- ============================================================
-- FLUGPHASEN in Ethos
--
-- Ethos bietet KEINE Funktion, um alle Flugphasen im Voraus zu lesen
-- (model.getFlightMode existiert nicht - das ist EdgeTX). Verfuegbar
-- ist nur die AKTIVE Phase ueber die Source CURRENT_FLIGHT_MODE:
--   :value()       -> Index der aktiven Phase (0..)
--   :stringValue() -> Name der aktiven Phase
--
-- Daher sammeln wir die Phasen zur Laufzeit: Beim Durchschalten wird
-- jedes Index->Name-Paar gemerkt. Der INDEX ist der stabile Schluessel
-- (Auswahl wird per Index gespeichert, uebersteht Umbenennungen). Der
-- Name dient nur zur Anzeige und wird bei Umbenennung einfach zum
-- schon bekannten Index aktualisiert - es entsteht KEIN neuer Eintrag,
-- also auch keine "Geister-Phasen" durch Tipp-Zwischenstaende.
-- ============================================================

-- getActiveFm(widget) -> index, name
-- Liefert Index UND Namen der aktuell aktiven Flugphase.
local function getActiveFm(widget)
    local idx, name = 0, nil
    if widget.fmSource then
        local okV, v = pcall(function() return widget.fmSource:value() end)
        if okV and type(v) == "number" then idx = math.floor(v + 0.5) end
        local okN, n = pcall(function() return widget.fmSource:stringValue() end)
        if okN and type(n) == "string" and n ~= "" then name = n end
    end
    if idx < 0 or idx >= MAX_FM then idx = 0 end
    return idx, name
end

-- rememberFm(widget, idx, name)
-- Traegt die aktive Phase in die bekannte Liste ein. Existiert der
-- Index schon, wird nur der Name aktualisiert (kein Duplikat, keine
-- Geister-Eintraege). Neue Indizes werden sortiert eingefuegt.
--
-- Die Liste ist reine Laufzeitinformation und wird NICHT gespeichert -
-- die Namen wuerden Platz kosten, den die Regeln brauchen, und sind
-- nach einmaligem Durchschalten ohnehin wieder da. Deshalb wird hier
-- auch kein model.dirty() ausgeloest: das wuerde bei jeder erstmalig
-- gesehenen Flugphase das komplette Modell sichern, fuer Daten, die
-- dabei gar nicht mitgeschrieben werden.
local function rememberFm(widget, idx, name)
    if type(idx) ~= "number" then return end
    widget.fmList = widget.fmList or {}
    for _, fm in ipairs(widget.fmList) do
        if fm.index == idx then
            -- schon bekannt: nur Namen aktualisieren, falls einer kam
            if name ~= nil and name ~= "" then fm.name = name end
            return
        end
    end
    if #widget.fmList >= MAX_FM then return end
    table.insert(widget.fmList, { index = idx, name = name or ("FM" .. idx) })
    table.sort(widget.fmList, function(a, b) return a.index < b.index end)
end

-- ensureRulePhasesListed(widget)
-- Sorgt dafuer, dass jeder Flugphasen-Index, den irgendeine Regel
-- benutzt, auch in der Auswahlliste auftaucht - selbst wenn die Phase
-- in dieser Sitzung noch nicht aktiv war. Angezeigt wird dann "FM<n>",
-- bis der echte Name das erste Mal gesehen wurde. Ohne das koennte
-- eine einmal gesetzte Flugphase in der Konfiguration unsichtbar und
-- damit nicht mehr abwaehlbar sein.
local function ensureRulePhasesListed(widget)
    widget.fmList = widget.fmList or {}
    for _, r in ipairs(widget.rules or {}) do
        for k, v in pairs(r.phasesSet or {}) do
            if v == true and type(k) == "number" then
                local idx   = math.floor(k)
                local found = false
                for _, fm in ipairs(widget.fmList) do
                    if fm.index == idx then found = true; break end
                end
                if not found and idx >= 0 and idx < MAX_FM then
                    widget.fmList[#widget.fmList + 1] = { index = idx, name = "FM" .. idx }
                end
            end
        end
    end
    table.sort(widget.fmList, function(a, b) return a.index < b.index end)
end

-- parsePhasesMask(str) / buildPhasesMask(set)
--
-- Die ausgewaehlten Flugphasen werden als EINE ZAHL gespeichert.
-- Jede Phase hat einen eigenen Zahlenwert, der sich verdoppelt:
--   Phase 0 = 1, Phase 1 = 2, Phase 2 = 4, Phase 3 = 8, ...
-- Ausgewaehlte Phasen werden addiert. "Phase 1 und 2" ergibt 2+4 = 6.
-- Weil jede Phase ihren eigenen Wert hat, laesst sich aus der Summe
-- eindeutig zurueckrechnen, welche Phasen gemeint waren.
--
-- Das spart Platz: "0,1,2,3" waeren 7 Zeichen, "15" sind 2. Im
-- knappen Speicher zaehlt jedes Zeichen.
local function buildPhasesMask(set)
    local m = 0
    for k, v in pairs(set or {}) do
        if v == true and type(k) == "number" then
            local i = math.floor(k)
            if i >= 0 and i < MAX_FM then m = m + (1 << i) end
        end
    end
    if m == 0 then return "" end
    return tostring(m)
end

local function parsePhasesMask(str)
    local set = {}
    local m = math.floor(tonumber(str) or 0)
    if m <= 0 then return set end
    for i = 0, MAX_FM - 1 do
        if ((m >> i) & 1) == 1 then set[i] = true end
    end
    return set
end

-- confirmDialog(fn, message)
-- Öffnet einen Bestätigungsdialog bevor eine destruktive Aktion
-- (Regel löschen) ausgeführt wird
local function confirmDialog(fn, message)
    return function()
        return form.openDialog({
            title   = tr("confirmTitle"),
            message = message,
            width   = 400,
            buttons = {
                { label = tr("no"),  action = function() return true end },
                { label = tr("yes"), action = function() fn(); return true end },
            },
            options = TEXT_LEFT
        })
    end
end

-- newRule()
-- Erzeugt eine neue, leere Regel mit Standardwerten
local function newRule()
    return {
        image            = "",
        allPhases        = true,
        phasesSet        = {},
        expanded         = false, -- nur UI-Zustand, wird nicht gespeichert
        activationSwitch = nil,   -- "Aktiviert durch", wie bei Mixern (form.addSwitchField)
    }
end

-- ruleTitleText(widget, idx)
-- Baut den Text der Statuszeile einer Regel.
local function ruleTitleText(widget, idx)
    local rule = widget.rules[idx]
    if rule == nil then return "" end
    return string.format("%d. %s", idx,
        (rule.image ~= "" and rule.image) or tr("noImage"))
end

-- ------------------------------------------------------------
-- Ethos Widget Lifecycle
-- ------------------------------------------------------------

-- create()
-- Erstellt eine neue Widget-Instanz
local function create()
    local fmSource = nil
    local ok, src = pcall(function()
        return system.getSource({
            category = CATEGORY_FLIGHT_VALUE,
            member   = CURRENT_FLIGHT_MODE
        })
    end)
    if ok then fmSource = src end

    return {
        rules           = {},   -- geordnete Liste von Regeln
        fallbackImage   = "",   -- Bild, wenn keine Regel passt
        cache           = {},   -- [dateipfad] = geladenes Bitmap-Objekt
        fmList          = {},   -- Liste { index=<n>, name=<Name> } der bekannten Flugmodi
        fmSource        = fmSource,
        activeFm        = 0,    -- INDEX des aktuell aktiven Flugmodus
        activeRuleIndex = nil,  -- Index der aktuell greifenden Regel (nil = Fallback)
        activeBitmap    = nil,  -- zuletzt zur Anzeige bestimmtes Bitmap
        loaded          = false,-- true, sobald read() gelaufen ist
        everConfigured  = false,-- true, sobald der Nutzer etwas geaendert hat
    }
end

-- init(widget)
-- Initialisiert Flugphasen und aktuellen Zustand
local function init(widget)
    local idx, nm = getActiveFm(widget)
    widget.activeFm = idx
    rememberFm(widget, idx, nm)
end

-- Vorab-Deklarationen:
--   configure     ruft sich nach strukturellen Aenderungen selbst auf
--   storageUsage  wird erst unter "Persistenz" definiert, aber schon
--                 in der Konfiguration zur Anzeige gebraucht
local configure
local storageUsage

-- configure(widget)
-- Baut das Konfigurationsmenue auf: Standard-Bild, Regelliste,
-- Info-Bereich. Ruft sich nach strukturellen Aenderungen (Regel
-- hinzufuegen, verschieben, loeschen, auf-/zuklappen) selbst neu auf.
--
-- Jeder Setter markiert widget.everConfigured - daran erkennt write(),
-- dass es eine echte Konfiguration gibt und nicht bloss den leeren
-- Anfangszustand ueberschreiben wuerde.
function configure(widget)
    -- Aktive Phase mitnehmen, damit sie in der Liste aktuell ist, und
    -- alle von Regeln benutzten Phasen sichtbar halten.
    local afIdx, afName = getActiveFm(widget)
    rememberFm(widget, afIdx, afName)
    ensureRulePhasesListed(widget)

    local lineFallback = form.addLine(tr("fallback"))
    form.addBitmapField(lineFallback, nil, BMP_PATH,
        function() return widget.fallbackImage or "" end,
        function(v)
            widget.fallbackImage   = v
            widget.everConfigured  = true
            widget.cache = {}
            lcd.invalidate()
        end)

    for i = 1, #widget.rules do
        local idx = i
        local rule = widget.rules[idx]

        -- EINE Zeile pro Regel: Bildname + 4 Buttons mit Abstaenden:
        --   [+/-]   (Abstand)   [^] [v]   (Abstand)   [Papierkorb]
        local lHeader = form.addLine(ruleTitleText(widget, idx))

        -- Slot-Layout: Button, Luecke, Button, Button, Luecke, Button.
        -- Die Luecken-Slots (gap) werden nicht mit einem Button belegt
        -- und erzeugen so den optischen Abstand zwischen den Gruppen.
        local bw  = 44   -- Button-Breite
        local gap = 16   -- Abstand zwischen den Gruppen
        local slots = slotList(lHeader, { bw, gap, bw, bw, gap, bw })

        -- btnProps(icon, text, press): bei vorhandener Maske wird sie
        -- als "icon" gesetzt, sonst dient der Text als Rueckfallebene.
        local function btnProps(icon, text, press)
            if icon ~= nil then
                return { icon = icon, press = press }
            else
                return { text = text, press = press }
            end
        end

        -- [+/-] Details ein-/ausblenden (Neuaufbau noetig)
        form.addButton(lHeader, slots[1],
            btnProps(rule.expanded and iconMinus or iconPlus, rule.expanded and "-" or "+",
                function()
                    rule.expanded = not rule.expanded
                    form.clear()
                    configure(widget)
                    return true
                end))

        -- slots[2] = Luecke (bleibt leer)

        -- [^] nach oben (Neuaufbau noetig)
        form.addButton(lHeader, slots[3],
            btnProps(iconUp, "^",
                function()
                    if idx > 1 then
                        widget.rules[idx], widget.rules[idx - 1] = widget.rules[idx - 1], widget.rules[idx]
                        widget.everConfigured = true
                        pcall(function() model.dirty() end)
                        form.clear()
                        configure(widget)
                    end
                    return true
                end))

        -- [v] nach unten
        form.addButton(lHeader, slots[4],
            btnProps(iconDown, "v",
                function()
                    if idx < #widget.rules then
                        widget.rules[idx], widget.rules[idx + 1] = widget.rules[idx + 1], widget.rules[idx]
                        widget.everConfigured = true
                        pcall(function() model.dirty() end)
                        form.clear()
                        configure(widget)
                    end
                    return true
                end))

        -- slots[5] = Luecke (bleibt leer)

        -- [Papierkorb] loeschen
        form.addButton(lHeader, slots[6],
            btnProps(iconDelete, "X",
                confirmDialog(
                    function()
                        table.remove(widget.rules, idx)
                        widget.everConfigured = true
                        pcall(function() model.dirty() end)
                        form.clear()
                        configure(widget)
                    end,
                    string.format(tr("confirmDel"), idx)
                )))

        -- Detailzeilen nur bei aufgeklappter Regel
        if rule.expanded then
            -- Bild aendern erfordert KEINEN Neuaufbau (nur Wert setzen).
            local lImg = form.addLine(INDENT .. tr("image"))
            form.addBitmapField(lImg, nil, BMP_PATH,
                function() return rule.image or "" end,
                function(v)
                    rule.image            = v
                    widget.everConfigured = true
                    widget.cache = {}
                    lcd.invalidate()
                end)

            -- "Alle Flugphasen" blendet die Flugphasen-Liste ein/aus,
            -- daher ist hier ein Neuaufbau noetig.
            local lAll = form.addLine(INDENT .. tr("allPhases"))
            form.addBooleanField(lAll, nil,
                function() return rule.allPhases end,
                function(v)
                    rule.allPhases        = v
                    widget.everConfigured = true
                    form.clear()
                    configure(widget)
                end)

            if not rule.allPhases then
                for _, fm in ipairs(widget.fmList or {}) do
                    local key = fm.index
                    local lFm = form.addLine(INDENT .. INDENT .. fm.name)
                    -- WICHTIG: KEIN Neuaufbau. Ein Flugphasen-Schalter aendert
                    -- nur einen Wert - die Liste selbst bleibt gleich. Damit
                    -- bleibt die Ansicht exakt stehen, nichts springt.
                    form.addBooleanField(lFm, nil,
                        function() return rule.phasesSet[key] == true end,
                        function(v)
                            if v then
                                rule.phasesSet[key] = true
                            else
                                rule.phasesSet[key] = nil
                            end
                            widget.everConfigured = true
                        end)
                end
            end

            -- "Aktiviert durch" - kein Neuaufbau noetig.
            local lAct = form.addLine(INDENT .. tr("activatedBy"))
            form.addSwitchField(lAct, nil,
                function() return rule.activationSwitch end,
                function(v)
                    rule.activationSwitch = v
                    widget.everConfigured = true
                end)
        end
    end

    if #widget.rules < MAX_RULES then
        local lAdd = form.addLine("")
        form.addButton(lAdd, nil, {
            text = tr("addRule"),
            press = function()
                table.insert(widget.rules, newRule())
                widget.everConfigured = true
                pcall(function() model.dirty() end)
                form.clear()
                configure(widget)
                return true
            end
        })
    end

    -- Info-Panel: Hilfe + GitHub, Version, Autor (wie im color-value Widget)
    local okPanel, infoPanel = pcall(function() return form.addExpansionPanel(tr("infoTitle")) end)
    if okPanel and infoPanel then
        pcall(function() infoPanel:open(false) end)

        -- Hilfe-Zeile mit "?"-Button, oeffnet ein Popup mit Erklaerungen
        -- (Bildpfad, Flugphasen durchschalten, Regel-Reihenfolge).
        local lHelp = infoPanel:addLine(tr("helpLine"))
        form.addButton(lHelp, nil, {
            text = "?",
            press = function()
                local w = 400
                local okW, ww = pcall(function() return (lcd.getWindowSize()) end)
                if okW and type(ww) == "number" and ww > 0 then
                    w = math.floor(ww * 0.9)
                end
                return form.openDialog({
                    title   = tr("helpTitle"),
                    message = string.format(tr("helpMessage"), BMP_PATH),
                    width   = w,
                    buttons = { { label = tr("ok"), action = function() return true end } },
                    options = TEXT_LEFT,
                    closeWhenClickOutside = true,
                })
            end
        })

        local lPath = infoPanel:addLine(tr("imagesUnder"))
        form.addStaticText(lPath, nil, BMP_PATH)

        -- Speicherverbrauch. Ethos gibt jedem Widget nur wenige
        -- hundert Zeichen. Steht hier ein "!", passt die Konfiguration
        -- nicht mehr sicher hinein und die zuletzt geschriebenen Werte
        -- gehen beim Speichern verloren.
        local chars = storageUsage(widget)
        local lMem  = infoPanel:addLine(tr("infoStorage"))
        form.addStaticText(lMem, nil, string.format("%d / %d%s",
            chars, STORAGE_BUDGET, (chars > STORAGE_BUDGET) and "  !" or ""))

        local l1 = infoPanel:addLine(tr("infoRepo"))
        form.addStaticText(l1, nil, GITHUB_REPO)
        local l2 = infoPanel:addLine(tr("infoVersion"))
        form.addStaticText(l2, nil, SCRIPT_VERSION)
        local l3 = infoPanel:addLine(tr("infoAuthor"))
        form.addStaticText(l3, nil, SCRIPT_AUTHOR)
    end
end

-- ============================================================
-- Persistenz
--
-- Der Schluesselname wird von Ethos ignoriert: storage.write haengt
-- Werte in Aufrufreihenfolge an eine Liste, storage.read liest sie in
-- derselben Reihenfolge zurueck. Der "Schluessel" dient hier nur der
-- Lesbarkeit. Daraus folgen zwei Regeln, an denen der ganze Abschnitt
-- haengt:
--
-- REGEL 1: write() und read() muessen dieselbe Anzahl Werte in
-- derselben Reihenfolge verarbeiten. Die Anzahl darf variabel sein -
-- aber beide Seiten muessen sie aus derselben gespeicherten
-- Information ableiten koennen. Deshalb steht die Regelzahl im ersten
-- Wert, und jede Regel sagt selbst, ob ein Schalterwert folgt.
--
-- REGEL 2: sparsam sein. Der Speicher fasst nur wenige hundert
-- Zeichen, und JEDER Wert kostet Platz - auch ein leerer String und
-- auch ein Schalterobjekt, das gar keine Zeichen enthaelt. Deshalb
-- wird nur geschrieben, was es wirklich gibt.
--
-- AUFBAU:
--   Wert 1        "7;<regelzahl>;<fallbackbild>"
--   Wert 2..N+1   Regel: "<bild>|<flags>|<phasenmaske>"
--   danach        je ein Schalterobjekt, in aufsteigender Regelnummer,
--                 nur fuer Regeln mit Schalter
--
--   <flags> ist eine Ziffer: 1 = alle Flugphasen, 2 = hat Schalter,
--   also 0..3. Fehlt das Feld, gilt 1. Felder mit Standardwert am
--   Ende entfallen: "bild.bmp" allein heisst alle Phasen, kein
--   Schalter.
-- ============================================================

-- sanitizeField(s)
-- Entfernt die Trennzeichen aus einem Wert, damit das Format nicht
-- kaputtgeht (Dateinamen mit ";" oder "|" sind extrem selten,
-- wuerden aber den Regelsatz zerlegen).
local function sanitizeField(s)
    s = tostring(s or "")
    s = s:gsub("[;|\t\r\n]", "_")
    return s
end

-- packBase(widget) -> string
local function packBase(widget)
    return table.concat({
        tostring(CFG_VERSION),
        tostring(math.min(#widget.rules, MAX_RULES)),
        sanitizeField(widget.fallbackImage),
    }, SEP_REC)
end

-- packRule(rule) -> string
local function packRule(r)
    local img  = sanitizeField(r.image)
    local mask = buildPhasesMask(r.phasesSet)
    local flags = 0
    if r.allPhases then flags = flags + 1 end
    if r.activationSwitch ~= nil then flags = flags + 2 end

    if mask ~= "" then
        return img .. SEP_FLD .. flags .. SEP_FLD .. mask
    elseif flags ~= 1 then
        return img .. SEP_FLD .. flags
    elseif img == "" then
        -- Eine noch leere Regel darf keinen leeren String ergeben:
        -- daran erkennt read() einen verlorengegangenen Wert.
        return SEP_FLD .. "1"
    end
    return img
end

-- unpackRule(str) -> rule
local function unpackRule(str)
    local p     = splitString(str or "", SEP_FLD)
    local flags = math.floor(tonumber(p[2]) or 1)
    return {
        image            = p[1] or "",
        allPhases        = ((flags & 1) == 1),
        hasSwitch        = ((flags & 2) == 2),   -- nur waehrend read()
        phasesSet        = parsePhasesMask(p[3] or ""),
        expanded         = false,
        activationSwitch = nil,
    }
end

-- storageUsage(widget) -> Zeichen
-- Rechnet nach, wie viele Zeichen write() erzeugen wuerde.
function storageUsage(widget)
    local chars = #packBase(widget)
    for i = 1, math.min(#widget.rules, MAX_RULES) do
        chars = chars + #packRule(widget.rules[i])
    end
    return chars
end

-- safeWrite(label, value)
-- Kapselt storage.write in pcall, damit ein misslungener Schreibvorgang
-- nicht den Rest mitreisst. Das Label wird von Ethos ignoriert (siehe
-- oben) und steht nur zur Lesbarkeit im Code.
local function safeWrite(label, value)
    pcall(function() storage.write(label, value) end)
end

-- read(widget)
-- Liest genau so viele Werte, wie write() geschrieben hat: erst die
-- Basis, daraus die Regelzahl, dann die Regeln, und daraus wiederum,
-- wie viele Schalterwerte folgen.
local function read(widget)
    local function rd(label)
        local ok, v = pcall(function() return storage.read(label) end)
        if ok then return v end
        return nil
    end
    local function rdStr(label)
        local v = rd(label)
        if type(v) == "string" then return v end
        return ""
    end

    widget.rules         = {}
    widget.fmList        = {}
    widget.fallbackImage = ""

    -- ---- Wert 1: Basis
    local parts = splitString(rdStr("cfg"), SEP_REC)
    local count = 0
    if (tonumber(parts[1]) or 0) == CFG_VERSION then
        count                = tonumber(parts[2]) or 0
        widget.fallbackImage = parts[3] or ""
    end
    if count < 0 then count = 0 end
    if count > MAX_RULES then count = MAX_RULES end

    -- ---- Werte 2..N+1: die Regeln
    for i = 1, count do
        local rec = rdStr("r" .. i)
        -- Ein leerer Wert heisst: der Speicher ist beim Schreiben
        -- ausgegangen. Hier abbrechen statt eine leere Regel
        -- einzusetzen - die wuerde zur Laufzeit auf jede Flugphase
        -- passen und alle folgenden Regeln blockieren.
        if rec == "" then break end
        widget.rules[i] = unpackRule(rec)
    end

    -- ---- danach: ein Schalter je Regel, die einen hat.
    -- Wurde oben abgebrochen, sind auch die Schalterwerte nicht mehr
    -- verlaesslich - dann werden sie gar nicht erst gelesen.
    if #widget.rules == count then
        for i = 1, #widget.rules do
            local r = widget.rules[i]
            if r.hasSwitch then
                local v = rd("sw" .. i)
                if v ~= nil and v ~= false and v ~= true and type(v) ~= "string" then
                    r.activationSwitch = v
                end
            end
        end
    end
    for _, r in ipairs(widget.rules) do r.hasSwitch = nil end

    -- Benutzte Flugphasen sichtbar halten (Namen werden nicht
    -- gespeichert; sie erscheinen als "FM<n>" bis zum ersten Auftreten)
    ensureRulePhasesListed(widget)

    widget.cache           = {}
    widget.activeRuleIndex = nil
    widget.activeFm        = 0
    widget.activeBitmap    = nil
    widget.loaded          = true
    return true
end

-- write(widget)
-- Schreibt genau die Werte, die es wirklich gibt - in der Reihenfolge,
-- in der read() sie erwartet.
local function write(widget)
    -- Ethos ruft write() auch ohne vorheriges read() auf (z.B. direkt
    -- nach dem Anlegen des Widgets). Dann darf eine bestehende
    -- Konfiguration nicht durch einen leeren Zustand ersetzt werden.
    -- Geprueft wird ueber ein Flag, NICHT ueber storage.read - Lesen
    -- ausserhalb von read() wuerde die Positionen verschieben.
    if not widget.loaded and not widget.everConfigured then
        return true
    end

    local n = math.min(#widget.rules, MAX_RULES)

    safeWrite("cfg", packBase(widget))
    for i = 1, n do
        safeWrite("r" .. i, packRule(widget.rules[i]))
    end
    for i = 1, n do
        local sw = widget.rules[i].activationSwitch
        if sw ~= nil then
            safeWrite("sw" .. i, sw)
        end
    end

    return true
end

-- ------------------------------------------------------------
-- Laufzeit
-- ------------------------------------------------------------

-- wakeup(widget)
-- Prüft regelmäßig Flugphase + Schalterbedingungen und ermittelt
-- die aktuell greifende Regel
local function wakeup(widget)
    local fmIdx, fmName = getActiveFm(widget)
    widget.activeFm = fmIdx
    rememberFm(widget, fmIdx, fmName)

    local newRuleIndex = nil
    for i = 1, #widget.rules do
        local rule = widget.rules[i]
        local phaseOk = rule.allPhases or (rule.phasesSet[widget.activeFm] == true)
        local switchOk = true

        if rule.activationSwitch then
            local ok, val = pcall(function() return rule.activationSwitch:value() end)
            if ok then
                -- value() kann je nach Quelle eine Zahl ODER einen
                -- Wahrheitswert liefern - beides muss behandelt werden.
                if type(val) == "number" then
                    switchOk = val > 0
                elseif type(val) == "boolean" then
                    switchOk = val
                else
                    -- Unbekannter Typ -> Bedingung ignorieren statt
                    -- die Regel dauerhaft zu blockieren
                    switchOk = true
                end
            else
                switchOk = true
            end
        end
        -- Ist kein Schalter gewählt, gilt die Bedingung als
        -- "irrelevant" (switchOk bleibt true)

        if phaseOk and switchOk then
            newRuleIndex = i
            break
        end
    end

    local selectedBitmap = widget.fallbackImage
    if newRuleIndex and widget.rules[newRuleIndex] then
        selectedBitmap = widget.rules[newRuleIndex].image
    end

    if newRuleIndex ~= widget.activeRuleIndex
        or selectedBitmap ~= widget.activeBitmap then
        widget.activeRuleIndex = newRuleIndex
        widget.activeBitmap    = selectedBitmap
        lcd.invalidate()
    end
end

-- loadCached(widget, filename)
-- Laedt ein Bitmap und haelt es im Cache. Schluessel ist der
-- DATEIPFAD und nicht der Regel-Index - sonst wuerde nach dem
-- Verschieben einer Regel das Bild der alten Position weiterbenutzt.
local function loadCached(widget, filename)
    local fullPath = buildPath(filename)
    if fullPath == nil then return nil end

    widget.cache = widget.cache or {}
    local entry = widget.cache[fullPath]
    if entry == nil then
        local ok, bmp = pcall(function() return lcd.loadBitmap(fullPath) end)
        if ok and bmp ~= nil then
            entry = bmp
        else
            entry = false   -- Fehlversuch merken, nicht bei jedem paint neu laden
        end
        widget.cache[fullPath] = entry
    end

    if entry == false then return nil end
    return entry
end

-- paint(widget)
-- Rendert das Widget: Bild der aktiven Regel oder Fallback-Bild
local function paint(widget)
    local w, h = lcd.getWindowSize()
    local idx  = widget.activeRuleIndex

    local bmpName
    if idx and widget.rules[idx] then
        bmpName = widget.rules[idx].image
    else
        bmpName = widget.fallbackImage
    end

    local bmp = nil
    if bmpName and bmpName ~= "" then
        bmp = loadCached(widget, bmpName)
    end

    if bmp ~= nil then
        lcd.drawBitmap(0, 0, bmp, w, h)
    else
        lcd.color(lcd.RGB(60, 60, 60))
        lcd.drawFilledRectangle(0, 0, w, h)
        lcd.color(lcd.RGB(180, 180, 180))
        lcd.font(FONT_STD)
        local label = idx and (tr("ruleWord") .. " " .. idx) or tr("fallbackWord")
        lcd.drawText(w / 2, h / 2, label .. tr("noBitmap"), CENTERED)
    end
end

-- initWidget()
-- Registriert das Widget im Ethos-System
local function initWidget()
    system.registerWidget({
        key       = "BmpPro",
        name      = tr("widgetName"),
        create    = create,
        init      = init,
        configure = configure,
        paint     = paint,
        wakeup    = wakeup,
        read      = read,
        write     = write,
        title     = false,
    })
end

return { init = initWidget }