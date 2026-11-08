# ZeroUI

A menu library for **Matcha** (the external Roblox LuaVM). Everything is drawn with Matcha's `Drawing` API, so it works without `Instance.new`.

- Sidebar with sections and tabs, collapsible cards, two-column layout
- Toggles, sliders, dropdowns (searchable, multi-select), color pickers, textboxes, keybinds, buttons, labels
- Hub-wide search, themes (11 presets plus your own), font / opacity / outline settings
- Saves every setting to a file, named configs, autoload
- Typing in the menu does not reach the game (see [Input capture](#input-capture))
- No dependencies, one file

> Current version: **1.0.11**. The library publishes itself as the global `_G.main`.

---

## Loading it

Matcha drops the return value of a `loadstring` chunk, so the library puts itself in `_G.main`. Load it, then read the global:

```lua
local LIB_URL = "https://raw.githubusercontent.com/onlywraith/zero-inspired/refs/heads/main/main.lua"

local function usable(t) return type(t) == "table" and not t._dead and type(t.CreateWindow) == "function" end

local Library = rawget(_G, "main")
if not usable(Library) then
    _G.main = nil                                   -- drop a stale or half-loaded copy
    local src
    for _ = 1, 3 do                                 -- retry in case the request hiccups
        local ok, res = pcall(function() return game:HttpGet(LIB_URL) end)
        if ok and type(res) == "string" and #res > 1000 then src = res break end
    end
    if not src then warn("could not download the UI library") return end

    local ok, err = pcall(function() local f = loadstring(src); f() end)
    if not ok then warn("UI library failed to load: " .. tostring(err)) end
    Library = rawget(_G, "main")
    if not usable(Library) then return end
end
```

Replace the URL with the raw link to `main.lua` in your repo.

If `_G.main` already holds a live copy of the same version, it is reused. Running a different version replaces the old one.

---

## Quick start

```lua
local win = Library:CreateWindow({
    title    = "my hub",
    subtitle = "v1.0",
    size     = { 822, 640 },
    toggleKey = "RSHIFT",                -- opens / closes the menu
    config   = "my_hub.json",            -- every setting is saved here
    folder   = "UI/my_hub",              -- named configs live here
})

local tab  = win:AddTab("combat", "main")          -- tab name, sidebar section
local card = tab:AddGroup("aim", 1)                -- card title, column (1 or 2)

local aim = card:AddToggle({ text = "enable aim", flag = "aim_on", default = false })
local fov = card:AddSlider({ text = "fov", flag = "aim_fov", min = 10, max = 360, default = 90, suffix = "°" })

card:AddButton({ text = "say hello", callback = function() Library:Notify("hello") end })

win:AddSettingsTab()                             -- themes, configs, menu key, watermark ...

-- read values anywhere with :Get()
print(aim:Get(), fov:Get())
```

A complete, working example with an ESP is in [`example_esp.lua`](example_esp.lua).

---

## Window

```lua
local win = Library:CreateWindow(options)
```

| Option | Type | Default | Description |
|---|---|---|---|
| `title` | string | `"zero hub"` | Big title in the top-left of the sidebar |
| `subtitle` | string | `""` | Small text under the title |
| `id` | string | title | Unique name. Creating a window with an existing id replaces the old one |
| `size` | `{w, h}` | `{822, 640}` | Window size in pixels |
| `columns` | number (1-3) | `2` | Number of card columns |
| `toggleKey` | string | `"RSHIFT"` | Key that shows / hides the menu |
| `config` | string | none | File that every setting is saved to after each change |
| `folder` | string | none | Folder for named configs (and saved themes) |
| `autoload` | boolean | `true` | Load the saved settings when the window is created |
| `visible` | boolean | `true` | Start shown or hidden |
| `x`, `y` | number | centered | Window position |
| `user` | boolean | `true` | Show the player name and avatar at the bottom of the sidebar. `false` hides both |
| `avatar` | boolean | `true` | `false` skips downloading the avatar |
| `captureInput` | boolean or function | `true` | See [Input capture](#input-capture) |
| `onUnload` | function | none | Called when the window is destroyed |

### Window methods

| Method | Description |
|---|---|
| `win:AddSection(name)` | Add a sidebar section header |
| `win:AddTab(name, section)` | Add a tab. Returns a tab |
| `win:AddSettingsTab(name?, section?)` | Add the built-in settings tab (default name `settings`, section `hub`) |
| `win:SelectTab(tabOrName)` | Switch to a tab |
| `win:Show()` / `win:Hide()` / `win:Toggle()` | Show or hide the menu |
| `win:IsVisible()` | Whether the menu is open |
| `win:SetTitle(title, subtitle?)` | Change the title text |
| `win:GetValue(flag)` / `win:SetValue(flag, value, silent?)` | Read or set a control by its `flag` |
| `win:Refresh()` | Force a re-layout |
| `win:SaveSettings()` / `win:LoadSettings()` | Write or read the file given as `config` |
| `win:SaveConfig(name)` / `win:LoadConfig(name)` / `win:DeleteConfig(name)` | Named configs in `folder` |
| `win:ListConfigs()` | List of saved config names |
| `win:SetAutoload(name)` / `win:GetAutoload()` | Config that loads on start |
| `win:ListThemes()` / `win:SaveTheme(name)` / `win:ApplyTheme(name)` / `win:DeleteTheme(name)` | Your own saved themes |
| `win:ResetAll()` | Put every control back to its default |
| `win:Destroy()` | Remove this window |

---

## Tabs and cards

```lua
local tab = win:AddTab("combat", "main")
local left  = tab:AddGroup("aim", 1)      -- column 1
local right = tab:AddGroup("visuals", 2)  -- column 2
```

- `tab:AddGroup(title, column, { collapsed = true })`, `tab:AddLeftGroup(title)`, `tab:AddRightGroup(title)`
- Cards can be collapsed by clicking the header. `group:SetCollapsed(bool)`, `group:Toggle()`, `group:SetTitle(text)`
- Tabs with the same `section` name are grouped under one sidebar header.

---

## Controls

Every control takes one table of options and returns a handle. Options shared by all controls:

| Option | Description |
|---|---|
| `text` | Label |
| `flag` | Unique name. Controls with a flag are saved and loaded with the config |
| `default` | Starting value |
| `callback` | `function(value, handle)` called when the value changes |
| `tooltip` / `desc` | Small description text under the control |
| `badge` | A small tag next to the label: `"!"`, `"?"` or `"p"` show as `[!]`, `[?]`, `[p]`. Or give your own text, e.g. `{ text = "[new]" }` |
| `depends` | Disable (and optionally hide) the control unless a condition holds. A handle, `{ handle, value }`, or a function returning a boolean |
| `hideDisabled` | With `depends`: hide the control instead of greying it out |
| `save` | `false` keeps the control out of config files |

```lua
local t = card:AddToggle({ text = "esp", flag = "esp", default = true })
card:AddSlider({ text = "distance", flag = "dist", min = 0, max = 500, depends = t, hideDisabled = true })
```

### Toggle
```lua
local h = card:AddToggle({ text = "name", flag = "x", default = false })
h:AddKeybind({ flag = "x_key", default = "F4", mode = "toggle" })   -- small key box on the same row
h:AddColor({ flag = "x_col", default = { 255, 0, 0 } })            -- small color swatch on the same row
```

### Slider
| Option | Default | |
|---|---|---|
| `min`, `max` | 0, 100 | Range |
| `step` | 1 | Increment (use `0.1` for decimals) |
| `suffix` | `""` | Text after the number, e.g. `" studs"` |

Click the number at the top right of a slider to type an exact value.

### Dropdown
| Option | Description |
|---|---|
| `values` | Array of strings |
| `multi` | `true` for multi-select. `:Get()` then returns a table of selected values |
| `allowNone` | Allow no selection |

Lists with more than 6 entries get a search box. `handle:SetValues({...})` replaces the list.

### Color
```lua
local c = card:AddColor({ text = "color", flag = "col", default = { 255, 100, 0 } })   -- also accepts "#ff6400"
c:Get()        -- Color3
c:GetRGB()     -- r, g, b
c:GetHex()     -- "#FF6400"
```

### Textbox
| Option | Description |
|---|---|
| `placeholder` | Grey text when empty |
| `numeric` | Only accept numbers |
| `maxLength` | Character limit |
| `live` | Fire the callback on every keystroke instead of on Enter |

### Keybind
```lua
local k = card:AddKeybind({ text = "menu key", flag = "key", default = "F4", mode = "toggle",
    callback = function(state) print("bind is", state) end })
```
| Option | Description |
|---|---|
| `default` | Key name: `"F4"`, `"E"`, `"MB2"` ... |
| `mode` | `"toggle"` (default), `"hold"` or `"always"`. Right-click the key box to cycle modes |
| `notify` | Show a toast when the bind changes |
| `list` | `false` hides it from the keybind list |
| `onClick` | Called every time the key is pressed |

`k:GetKey()`, `k:GetState()`, `k:SetMode(mode)`.

### Button
```lua
card:AddButton({ text = "reset", confirm = true, callback = function() ... end })
```
`confirm = true` asks to click twice. `handle:SetText(text)` changes the label.

### Label and divider
```lua
local l = card:AddLabel({ text = "some info\nsecond line", dim = true })
l:SetText("new text")      -- the label grows or shrinks to fit
card:AddDivider()
```
Text is word-wrapped, and `\n` starts a new line.

### Handle methods
| Method | Description |
|---|---|
| `:Get()` | Current value |
| `:Set(value, silent?)` | Change the value. `silent = true` skips the callback |
| `:OnChanged(fn)` | Add another listener |
| `:Reset()` | Back to `default` |
| `:SetText(text)` | Change the label |
| `:SetVisible(bool)` / `:SetEnabled(bool)` | Hide or grey out |

---

## Library functions

```lua
Library:Notify("saved")                                                   -- toast
Library:Notify({ title = "esp", text = "enabled", duration = 4 })
Library:SetWatermark("my hub | v1")
Library:SetWatermarkVisible(true)
Library:SetKeybindList(true)               -- on-screen list of active binds
Library:SetTheme("deep sea")               -- see themes below
Library:SetThemeColor("accent", { 255, 80, 120 })
Library:SetFont("Monospace", 13)           -- Library:FontNames() lists what is available
Library:SetOpacity(0.9)
Library:SetTextOutline(true)
Library:OnUnload(function() ... end)       -- clean up your own drawings here
Library:Unload()                           -- remove the whole UI
```

Themes: `zero pink`, `monochrome`, `graphite`, `deep sea`, `rose noir`, `terminal`, `ultraviolet`, `obsidian`, `nordic`, `sakura`, `amber`. Theme roles you can change with `SetThemeColor`: `accent`, `background`, `group` (cards), `topbar` (sidebar), `border`, `text`.

---

## Settings tab

`win:AddSettingsTab()` adds a ready-made tab with:

- theme presets and your own saved themes
- theme colors, font, font size, opacity, text outline
- menu key, watermark, keybind list
- config save / load / delete / autoload
- cursor offset sliders (use them if clicks land slightly off the pointer)
- unload button

---

## Input capture

While the menu is in use the game should not see your key presses. ZeroUI calls `setrobloxinput(false)` while:

- you type in a textbox, a dropdown search or a slider value
- a keybind is waiting for a key
- you drag something
- the pointer is over the menu

Game input comes back as soon as none of these apply, and when the UI unloads. It only changes input when that state flips, and never touches it until it needs to block.

If your script sends its own inputs and needs them to keep working, pass `captureInput` when you create the window:

```lua
captureInput = function() return not State.running end   -- false = leave the game's input alone
```

A function is called whenever the library checks; returning `false` turns blocking off at that moment. A plain `true` / `false` also works.

---

## Notes for Matcha

- Drawings are not part of the game tree. Remove your own with `:Remove()`, ideally from `Library:OnUnload(...)`, so re-running the script does not leave copies on screen.
- Property writes on instances do not replicate in Matcha. That is a Matcha limit, not something the library works around.
- Save files must end in `.json`, `.txt`, `.lua`, `.luau`, `.cfg`, `.dat` or `.ini` (Matcha's file API limit). The library uses `.json`.

---

## Files

| File | |
|---|---|
| `main.lua` | The library |
| `example_esp.lua` | Working example: a configurable ESP with boxes, names, distance, tracers and extra targets |
