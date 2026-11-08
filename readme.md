# ZeroUI

ZeroUI is a UI library built for Matcha's LuaVM. It uses Matcha's `Drawing` API to render the interface without relying on Roblox instances.

## Features

- Sidebar navigation with tabs and sections
- Collapsible groups with multi-column layouts
- Toggles, sliders, dropdowns, color pickers, textboxes, keybinds, buttons, and labels
- Searchable dropdowns with multi-select support
- Built-in themes and custom theme support
- Config saving, loading, and autoload
- Custom fonts, opacity, and text outlines
- Built-in settings tab
- Input capture while interacting with the menu
- No external dependencies

**Current version:** `1.0.11`

## Installation

Load the library using its raw GitHub URL.

```lua
local LIB_URL = "https://raw.githubusercontent.com/onlywraith/zero-inspired/refs/heads/main/main.lua"

local src = game:HttpGet(LIB_URL)
loadstring(src)()

local Library = _G.main

if not Library or type(Library.CreateWindow) ~= "function" then
    warn("Failed to load ZeroUI")
    return
end
```

ZeroUI is exposed through `_G.main` after loading.

## Quick Start

```lua
local win = Library:CreateWindow({
    title = "My Hub",
    subtitle = "v1.0",
    size = {822, 640},
    toggleKey = "RSHIFT",
    config = "my_hub.json",
    folder = "UI/my_hub"
})

local tab = win:AddTab("Combat", "Main")
local group = tab:AddGroup("Aimbot", 1)

local aim = group:AddToggle({
    text = "Enable Aimbot",
    flag = "aim_enabled",
    default = false
})

local fov = group:AddSlider({
    text = "Field of View",
    flag = "aim_fov",
    min = 10,
    max = 360,
    default = 90,
    suffix = "°"
})

group:AddButton({
    text = "Test Notification",
    callback = function()
        Library:Notify("Hello!")
    end
})

win:AddSettingsTab()

print(aim:Get())
print(fov:Get())
```

## Windows

Create a window using `Library:CreateWindow(options)`.

| Option | Description | Default |
|---|---|---|
| `title` | Window title | `"zero hub"` |
| `subtitle` | Subtitle | `""` |
| `id` | Unique window identifier | Title |
| `size` | Window dimensions | `{822, 640}` |
| `columns` | Number of group columns (1–3) | `2` |
| `toggleKey` | Menu toggle key | `"RSHIFT"` |
| `config` | Settings file | None |
| `folder` | Config and theme folder | None |
| `autoload` | Load saved settings on startup | `true` |
| `visible` | Initial visibility | `true` |
| `x`, `y` | Window position | Centered |
| `user` | Show player information | `true` |
| `avatar` | Load player avatar | `true` |
| `captureInput` | Control game input capture | `true` |
| `onUnload` | Unload callback | None |

### Window Methods

| Method | Description |
|---|---|
| `win:AddSection(name)` | Add a sidebar section |
| `win:AddTab(name, section)` | Create a tab |
| `win:AddSettingsTab(name?, section?)` | Add the settings tab |
| `win:SelectTab(tabOrName)` | Select a tab |
| `win:Show()` | Show the window |
| `win:Hide()` | Hide the window |
| `win:Toggle()` | Toggle visibility |
| `win:IsVisible()` | Check visibility |
| `win:SetTitle(title, subtitle?)` | Update window title |
| `win:GetValue(flag)` | Get a control value |
| `win:SetValue(flag, value, silent?)` | Set a control value |
| `win:Refresh()` | Refresh layout |
| `win:SaveSettings()` | Save settings |
| `win:LoadSettings()` | Load settings |
| `win:SaveConfig(name)` | Save a named config |
| `win:LoadConfig(name)` | Load a named config |
| `win:DeleteConfig(name)` | Delete a config |
| `win:ListConfigs()` | List saved configs |
| `win:SetAutoload(name)` | Set startup config |
| `win:GetAutoload()` | Get startup config |
| `win:ListThemes()` | List saved themes |
| `win:SaveTheme(name)` | Save current theme |
| `win:ApplyTheme(name)` | Apply a theme |
| `win:DeleteTheme(name)` | Delete a saved theme |
| `win:ResetAll()` | Reset all controls |
| `win:Destroy()` | Remove the window |

## Tabs and Groups

Tabs can be organized into sidebar sections and contain multiple groups.

```lua
local tab = win:AddTab("Combat", "Main")

local left = tab:AddGroup("Aimbot", 1)
local right = tab:AddGroup("Visuals", 2)
```

Groups support collapsing and title changes.

```lua
group:SetCollapsed(true)
group:Toggle()
group:SetTitle("New Title")
```

You can also use:

```lua
tab:AddLeftGroup("Aimbot")
tab:AddRightGroup("Visuals")
```

## Controls

All controls use an options table and return a handle.

### Shared Options

| Option | Description |
|---|---|
| `text` | Control label |
| `flag` | Unique identifier used for saving and retrieving values |
| `default` | Initial value |
| `callback` | Function called when the value changes |
| `tooltip` / `desc` | Additional description |
| `badge` | Small label displayed beside the control |
| `depends` | Condition controlling whether the control is enabled |
| `hideDisabled` | Hide disabled controls |
| `save` | Set to `false` to exclude the control from configs |

### Toggle

```lua
local toggle = group:AddToggle({
    text = "Enable ESP",
    flag = "esp",
    default = false
})
```

Toggles can have a keybind or color picker attached.

```lua
toggle:AddKeybind({
    flag = "esp_key",
    default = "F4",
    mode = "toggle"
})

toggle:AddColor({
    flag = "esp_color",
    default = {255, 0, 0}
})
```

### Slider

```lua
group:AddSlider({
    text = "Distance",
    flag = "distance",
    min = 0,
    max = 500,
    step = 1,
    default = 100,
    suffix = " studs"
})
```

Click the displayed value to enter a specific number.

### Dropdown

```lua
group:AddDropdown({
    text = "Target",
    flag = "target",
    values = {"Player", "NPC", "Both"},
    default = "Player",
    multi = false
})
```

Additional options:

| Option | Description |
|---|---|
| `values` | Available entries |
| `multi` | Enable multiple selections |
| `allowNone` | Allow no selection |

Dropdowns with more than six entries include a search field.

Use `handle:SetValues({...})` to update the available entries.

### Color Picker

```lua
local color = group:AddColor({
    text = "ESP Color",
    flag = "esp_color",
    default = {255, 100, 0}
})
```

Hex colors are also supported.

```lua
color:Get()
color:GetRGB()
color:GetHex()
```

`Get()` returns a Color3 value.

### Textbox

```lua
group:AddTextbox({
    text = "Username",
    flag = "username",
    placeholder = "Enter username",
    maxLength = 20,
    numeric = false,
    live = false
})
```

| Option | Description |
|---|---|
| `placeholder` | Placeholder text |
| `numeric` | Restrict input to numbers |
| `maxLength` | Maximum character count |
| `live` | Update callback on each keystroke |

### Keybind

```lua
group:AddKeybind({
    text = "Menu Key",
    flag = "menu_key",
    default = "F4",
    mode = "toggle",
    callback = function(state)
        print(state)
    end
})
```

Supported modes:

- `toggle`
- `hold`
- `always`

Right-click the keybind to change its mode.

Additional options include `notify`, `list`, and `onClick`.

Keybind methods:

```lua
key:GetKey()
key:GetState()
key:SetMode("hold")
```

### Button

```lua
group:AddButton({
    text = "Reset",
    confirm = true,
    callback = function()
        print("Reset")
    end
})
```

Set `confirm = true` to require two clicks.

Use `handle:SetText(text)` to change the button label.

### Label and Divider

```lua
local label = group:AddLabel({
    text = "Information",
    dim = true
})

label:SetText("Updated information")

group:AddDivider()
```

Labels support multiple lines and automatically adjust their height.

## Control Methods

All control handles support the following methods:

| Method | Description |
|---|---|
| `:Get()` | Get current value |
| `:Set(value, silent?)` | Change value |
| `:OnChanged(fn)` | Add a change listener |
| `:Reset()` | Restore default value |
| `:SetText(text)` | Change label |
| `:SetVisible(bool)` | Show or hide control |
| `:SetEnabled(bool)` | Enable or disable control |

## Library Methods

```lua
Library:Notify("Settings saved")

Library:Notify({
    title = "ESP",
    text = "Enabled",
    duration = 4
})

Library:SetWatermark("My Hub | v1")
Library:SetWatermarkVisible(true)

Library:SetKeybindList(true)

Library:SetTheme("deep sea")
Library:SetThemeColor("accent", {255, 80, 120})

Library:SetFont("Monospace", 13)
Library:SetOpacity(0.9)
Library:SetTextOutline(true)

Library:OnUnload(function()
    -- Cleanup
end)

Library:Unload()
```

## Themes

ZeroUI includes the following themes:

- Zero Pink
- Monochrome
- Graphite
- Deep Sea
- Rose Noir
- Terminal
- Ultraviolet
- Obsidian
- Nordic
- Sakura
- Amber

Theme colors can be customized using `SetThemeColor()`.

Available color properties:

- `accent`
- `background`
- `group`
- `topbar`
- `border`
- `text`

## Settings Tab

`win:AddSettingsTab()` adds a built-in settings page.

It includes:

- Theme selection and customization
- Font and font size
- Opacity and text outline
- Menu key configuration
- Watermark settings
- Keybind list
- Config management
- Autoload configuration
- Cursor offset adjustments
- Unload option

## Input Capture

ZeroUI prevents menu interactions from being passed to the game while the menu is active.

Input capture applies when:

- Typing in textboxes
- Searching dropdowns
- Editing slider values
- Selecting keybinds
- Dragging interface elements
- Hovering over the menu

Game input is restored when the interaction ends or the UI unloads.

To customize input capture, pass `captureInput` when creating the window.

```lua
captureInput = function()
    return not State.running
end
```

Returning `false` disables input blocking.

You can also pass a regular boolean instead of a function.

## Matcha Compatibility

A few Matcha-specific limitations are worth noting:

- Drawings are separate from the Roblox instance tree.
- Custom drawings should be removed during cleanup to prevent duplicates.
- Instance property changes do not replicate through Matcha.
- Supported file extensions are `.json`, `.txt`, `.lua`, `.luau`, `.cfg`, `.dat`, and `.ini`.

ZeroUI uses `.json` for its configuration files.

## Repository

| File | Description |
|---|---|
| `main.lua` | ZeroUI library |
| `example_esp.lua` | Example ESP implementation |

