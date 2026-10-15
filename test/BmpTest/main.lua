-- ============================================================
-- BMP Test - Messwidget fuer BMP Pro, fuer FrSky Ethos
--
-- Beantwortet auf der echten Funke drei Fragen, von denen das
-- naechste Speicherformat von BMP Pro abhaengt. Eigenes Widget, damit
-- keine BMP-Pro-Konfiguration angefasst wird.
--
--   Test 1  Schalter als Text
--           Laesst sich ein Schalter aus form.addSwitchField als
--           "Kategorie.Nummer.Optionen" ablegen und mit
--           system.getSource() wieder aufbauen? Kein Neustart noetig:
--           Original und Nachbau stehen nebeneinander, beim Umlegen
--           muessen beide Werte gleich laufen.
--
--   Test 2  Speichergrenze
--           Schreibt Z Zeichen, aufgeteilt auf W Werte, danach eine
--           Endmarke. Nach dem Neustart steht da, was angekommen ist.
--           Vergleich W = 1 gegen W = 11 bei gleichem Z zeigt, was
--           jeder einzelne Wert zusaetzlich kostet.
--
--   Test 3  BMP oder PNG
--           Dasselbe Bild einmal als .bmp, einmal als .png: Ladezeit,
--           Zeichenzeit, Dateigroesse, Pixelgroesse.
--
-- INSTALLATION
--   /scripts/BmpTest/main.lua
--   Testbilder in /bitmaps/BmpPro/ (gleicher Ordner wie BMP Pro)
--
-- Am besten als Vollbild-Widget anlegen - es zeigt viel Text.
-- ============================================================

local BMP_PATH = "/bitmaps/BmpPro"
local MAX_SW   = 3

-- Speicherformat dieses Widgets (Liste, siehe BMP Pro):
--   Wert 1   "<test>;<zeichen>;<werte>"
--   Test 2:  danach <werte> Werte mit zusammen <zeichen> Zeichen, dann "E"
--   sonst:   nichts weiter

-- Testmuster: Position i traegt einen festen Buchstaben, damit ein
-- abgeschnittener oder verschobener Wert auffaellt.
local function pattern(from, to)
    local t = {}
    for i = from, to do t[#t + 1] = string.char(65 + (i - 1) % 26) end
    return table.concat(t)
end

-- parts(total, n): Laengen von n moeglichst gleich grossen Teilen
local function parts(total, n)
    local out, base, rest = {}, total // n, total % n
    for i = 1, n do out[i] = base + ((i <= rest) and 1 or 0) end
    return out
end

local function call(obj, method)
    local ok, v = pcall(function() return obj[method](obj) end)
    if ok then return v end
    return nil
end

-- encodeSwitch(sw) -> "c.m.o" oder nil
local function encodeSwitch(sw)
    if sw == nil then return nil end
    local c, m, o = call(sw, "category"), call(sw, "member"), call(sw, "options")
    if type(c) ~= "number" or type(m) ~= "number" then return nil end
    if type(o) == "number" and o ~= 0 then
        return string.format("%d.%d.%d", c, m, o)
    end
    return string.format("%d.%d", c, m)
end

-- decodeSwitch("c.m.o") -> Source oder nil
local function decodeSwitch(s)
    if type(s) ~= "string" then return nil end
    local c, m, o = s:match("^(%-?%d+)%.(%-?%d+)%.?(%-?%d*)$")
    if c == nil then return nil end
    local spec = { category = tonumber(c), member = tonumber(m) }
    if o ~= "" then spec.options = tonumber(o) end
    local ok, src = pcall(function() return system.getSource(spec) end)
    if ok then return src end
    return nil
end

local function fmtVal(v)
    if type(v) == "number" then return string.format("%d", math.floor(v + 0.5)) end
    return tostring(v)
end

local function fileSize(path)
    local ok, size = pcall(function()
        local f = io.open(path, "rb")
        if f == nil then return nil end
        local n = f:seek("end")
        f:close()
        return n
    end)
    if ok then return size end
    return nil
end

-- ------------------------------------------------------------

local function create()
    return {
        test     = 1,
        chars    = 190,
        values   = 1,
        sw       = {},          -- Test 1: Schalter aus der Konfiguration
        bmpFile  = "",          -- Test 3
        pngFile  = "",
        result   = nil,         -- Test 2: was read() gefunden hat
        timing   = {},          -- Test 3: Messwerte je Datei
        lastMeas = -100,
        loaded   = false,
        touched  = false,
    }
end

local configure

function configure(widget)
    local l = form.addLine("Test")
    form.addChoiceField(l, nil,
        { { "1 Schalter als Text", 1 }, { "2 Speichergrenze", 2 }, { "3 BMP oder PNG", 3 } },
        function() return widget.test end,
        function(v)
            widget.test = v
            widget.touched = true
            form.clear()
            configure(widget)
        end)

    if widget.test == 1 then
        for i = 1, MAX_SW do
            local idx = i
            local ls = form.addLine("Schalter " .. i)
            form.addSwitchField(ls, nil,
                function() return widget.sw[idx] end,
                function(v) widget.sw[idx] = v end)
        end
        form.addStaticText(form.addLine("Tipp"), nil, "normal, invertiert, logisch")
    elseif widget.test == 2 then
        local lc = form.addLine("Zeichen gesamt")
        form.addNumberField(lc, nil, 1, 600,
            function() return widget.chars end,
            function(v) widget.chars = v; widget.touched = true end)
        local lv = form.addLine("Anzahl Werte")
        form.addNumberField(lv, nil, 1, 30,
            function() return widget.values end,
            function(v) widget.values = v; widget.touched = true end)
        form.addStaticText(form.addLine("Danach"), nil, "Konfig. schliessen, Neustart")
    else
        local lb = form.addLine("Bild als BMP")
        form.addBitmapField(lb, nil, BMP_PATH,
            function() return widget.bmpFile end,
            function(v) widget.bmpFile = v; widget.timing = {}; widget.lastMeas = -100 end)
        local lp = form.addLine("Bild als PNG")
        form.addBitmapField(lp, nil, BMP_PATH,
            function() return widget.pngFile end,
            function(v) widget.pngFile = v; widget.timing = {}; widget.lastMeas = -100 end)
    end
end

local function read(widget)
    local function rd()
        local ok, v = pcall(function() return storage.read("v") end)
        if ok then return v end
        return nil
    end
    local head = rd()
    local t, z, w = 0, 0, 0
    if type(head) == "string" then
        t, z, w = head:match("^(%d+);(%d+);(%d+)$")
        t, z, w = tonumber(t) or 0, tonumber(z) or 0, tonumber(w) or 0
    end
    if t >= 1 and t <= 3 then
        widget.test, widget.chars, widget.values = t, math.max(z, 1), math.max(w, 1)
    end

    if t == 2 then
        local res = { chars = z, values = w, gotValues = 0, gotChars = 0, intact = true }
        local pos = 1
        for i, len in ipairs(parts(z, w)) do
            local v = rd()
            if type(v) == "string" and v ~= "" then
                res.gotValues = res.gotValues + 1
                res.gotChars  = res.gotChars + #v
                if v ~= pattern(pos, pos + len - 1) then res.intact = false end
            else
                res.intact = false
            end
            pos = pos + len
        end
        res.endMark = (rd() == "E")
        widget.result = res
    end
    widget.loaded = true
    return true
end

local function write(widget)
    if not widget.loaded and not widget.touched then return true end
    local function wr(v) pcall(function() storage.write("v", v) end) end

    wr(string.format("%d;%d;%d", widget.test, widget.chars, widget.values))
    if widget.test == 2 then
        local pos = 1
        for _, len in ipairs(parts(widget.chars, widget.values)) do
            wr(pattern(pos, pos + len - 1))
            pos = pos + len
        end
        wr("E")
    end
    return true
end

-- Test 3: alle 3 s neu messen, je Datei 5 Ladevorgaenge
local function measure(widget)
    for _, name in ipairs({ widget.bmpFile, widget.pngFile }) do
        if name ~= "" then
            local path = BMP_PATH .. "/" .. name
            local bmp, n = nil, 5
            local t0 = os.clock()
            for _ = 1, n do
                local ok, b = pcall(function() return lcd.loadBitmap(path) end)
                bmp = ok and b or nil
            end
            local load = (os.clock() - t0) / n
            local prev = widget.timing[name] or {}
            widget.timing[name] = {
                bmp  = bmp,
                load = load,
                draw = prev.draw,
                size = fileSize(path),
                w    = bmp and call(bmp, "width"),
                h    = bmp and call(bmp, "height"),
            }
        end
    end
end

local function wakeup(widget)
    if widget.test == 3 and os.clock() - widget.lastMeas >= 3 then
        widget.lastMeas = os.clock()
        measure(widget)
        lcd.invalidate()
    elseif widget.test == 1 then
        lcd.invalidate()   -- Schalterwerte live anzeigen
    end
end

local function ms(t)
    if t == nil then return "-" end
    return string.format("%.1f ms", t * 1000)
end

local function paint(widget)
    local w, h = lcd.getWindowSize()
    lcd.color(lcd.RGB(0, 0, 0))
    lcd.drawFilledRectangle(0, 0, w, h)

    -- Test 3 zeichnet die Bilder zuerst (links BMP, rechts PNG) und misst dabei
    if widget.test == 3 then
        local half = w // 2
        for k, name in ipairs({ widget.bmpFile, widget.pngFile }) do
            local m = widget.timing[name]
            if m and m.bmp then
                local n, t0 = 5, os.clock()
                for _ = 1, n do lcd.drawBitmap((k - 1) * half, 0, m.bmp, half, h) end
                m.draw = (os.clock() - t0) / n
            end
        end
    end

    lcd.font(FONT_S)
    local _, th = lcd.getTextSize("A")
    local y = 2
    local function line(txt)
        lcd.color(lcd.RGB(0, 0, 0))
        local tw = lcd.getTextSize(txt)
        lcd.drawFilledRectangle(0, y, tw + 6, th)
        lcd.color(lcd.RGB(255, 255, 255))
        lcd.drawText(3, y, txt)
        y = y + th
    end

    line(string.format("BMP Test - Widget %d x %d", w, h))

    if widget.test == 1 then
        line("Original | Text | Nachbau   (Werte muessen gleich laufen)")
        for i = 1, MAX_SW do
            local sw = widget.sw[i]
            if sw == nil then
                line(string.format("%d: -", i))
            else
                local txt = encodeSwitch(sw)
                local rb  = decodeSwitch(txt)
                line(string.format("%d: %s = %s | %s | %s = %s", i,
                    tostring(call(sw, "name")), fmtVal(call(sw, "value")),
                    txt or "kein category/member",
                    rb and tostring(call(rb, "name")) or "-",
                    rb and fmtVal(call(rb, "value")) or "-"))
                line(string.format("   cat=%s mem=%s opt=%s", tostring(call(sw, "category")),
                    tostring(call(sw, "member")), tostring(call(sw, "options"))))
            end
        end
    elseif widget.test == 2 then
        line(string.format("Einstellung: %d Zeichen in %d Werten", widget.chars, widget.values))
        local r = widget.result
        if r == nil then
            line("Noch kein Ergebnis - Konfig. schliessen, Neustart")
        else
            line(string.format("Beim Start gelesen (Test mit %d Zeichen / %d Werten):", r.chars, r.values))
            line(string.format("  Werte  %d / %d", r.gotValues, r.values))
            line(string.format("  Zeichen %d / %d", r.gotChars, r.chars))
            line("  Inhalt " .. (r.intact and "vollstaendig" or "FEHLT/FALSCH"))
            line("  Endmarke " .. (r.endMark and "da" or "FEHLT"))
        end
    else
        for _, name in ipairs({ widget.bmpFile, widget.pngFile }) do
            if name ~= "" then
                local m = widget.timing[name]
                if m == nil then
                    line(name .. ": misst ...")
                elseif m.bmp == nil then
                    line(name .. ": NICHT LADBAR")
                else
                    line(string.format("%s: %sx%s px, %s Byte", name, tostring(m.w), tostring(m.h),
                        tostring(m.size or "?")))
                    line(string.format("   laden %s   zeichnen %s", ms(m.load), ms(m.draw)))
                end
            end
        end
        if widget.bmpFile == "" and widget.pngFile == "" then
            line("Bilder in der Konfiguration waehlen")
        end
    end
end

local function init()
    system.registerWidget({
        key       = "BmpTest",
        name      = "BMP Test",
        create    = create,
        configure = configure,
        paint     = paint,
        wakeup    = wakeup,
        read      = read,
        write     = write,
        title     = false,
    })
end

return { init = init }
