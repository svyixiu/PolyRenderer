# PolyRenderer

**Poly's Rendering Layer for Roblox.** Live viewport copies of any instance, locked to your camera and drawn over the world.

It clones what you give it into a full-screen `ViewportFrame` whose camera tracks the world camera exactly, so each copy sits precisely where its source sits on screen — and, because a ViewportFrame draws on top of the 3D scene, it stays visible through walls.

The renderer **only renders**. Hiding the source, tinting it, highlighting it: yours to do.

---

## Install

**Studio / Rojo** — drop [`ViewportRender.luau`](ViewportRender.luau) in as a `ModuleScript` (for example `ReplicatedStorage.ViewportRender`):

```lua
local PolyRenderer = require(game:GetService("ReplicatedStorage").ViewportRender)
```

**Executor:**

```lua
local PolyRenderer = loadstring(game:HttpGet("https://raw.githubusercontent.com/svyixiu/PolyRenderer/main/ViewportRender.luau"))()
```

Client-side only. Nothing it does touches the server.

---

## Quick start

```lua
local Ws = PolyRenderer.new()

local WsBased = Ws:Add(workspace.SomeModel)   -- returns the copy in the viewport
print(WsBased:GetFullName())                  -- ...PolyRenderer.Render.Copy_SomeModel

Ws:Edit(WsBased).Fps = 10                     -- refresh that copy 10x a second
Ws:Remove(WsBased)                            -- or Ws:Remove(workspace.SomeModel)
Ws:Destroy()
```

---

## API

### `PolyRenderer.new()`

Returns a renderer handle. Creates one `ScreenGui` + `ViewportFrame`; make as many as you like.

### `Ws:Add(source [, options]) → copy | nil`

Starts rendering `source` (a `BasePart`, a `Model`, anything with parts under it). Returns **the copy inside the viewport**, so you can hold onto it and hand it back to `Edit` or `Remove`.

Returns `nil` if `source` isn't an `Instance`, is already added, or couldn't be cloned.

`options` is a table of entry properties:

```lua
local ref = Ws:Add(rig, { Fps = 5, MirrorTransparency = false, MyOwnFlag = true })
```

### `Ws:Edit(obj [, options]) → entry | nil`

Takes **either the source or the copy** and returns that entry's property handle. With a table, applies it first and returns the handle. `nil` if the object isn't being rendered.

```lua
Ws:Edit(rig).Fps = 0
Ws:Edit(ref).Fps = 0            -- same entry
Ws:Edit(rig, { Fps = 30 })
print(Ws:Edit(rig).Source, Ws:Edit(rig).Clone)
```

### `Ws:Remove(obj) → boolean`

Stops rendering. Takes the source or the copy. `false` if it wasn't being rendered.

### `Ws:RemoveAll() → boolean`

Stops rendering everything. `false` if nothing was.

### `Ws:Destroy()`

Tears down the GUI, the loops and every entry. Safe to call twice; calls afterwards return `nil`/`false`.

---

## Properties

### Renderer — `Ws.*`

| Property | Default | Meaning |
|---|---|---|
| `Fps` | `0` | Refreshes per second for the renderer: the camera, the lighting, and every entry that hasn't set its own. `0` = every frame. |
| `AutoRebuild` | `true` | Re-clone an entry when its hierarchy changes (tool equipped, accessory added). |
| `SyncLighting` | `false` | Drive `Ambient` / `LightColor` / `LightDirection` from `Lighting`. |
| `AllowArchiving` | `true` | May the renderer flip `Archivable` on to clone a source that has it off. With it off, non-archivable sources are refused instead. |

Anything else falls through to the `ViewportFrame`, then to custom properties:

```lua
Ws.Ambient = Color3.fromRGB(255, 255, 255)   -- ViewportFrame property
Ws.Visible = false                            -- ViewportFrame property
print(Ws.AbsoluteSize)
Ws.MyState = { anything = true }              -- kept as a custom property
```

Escape hatches: `Ws.ViewportFrame`, `Ws.ScreenGui`, `Ws.Camera`.

### Entry — `Ws:Edit(x).*`

| Property | Default | Meaning |
|---|---|---|
| `Fps` | `nil` | This entry's refresh rate. `nil` inherits `Ws.Fps`, `0` = every frame. |
| `MirrorTransparency` | `true` | Keep the copy's `Transparency` in step with the source. Turn it off to set your own. |
| `Source` | — | The original. Read only. |
| `Clone` | — | The copy in the viewport. Read only. |

Anything else falls through to the copy instance, then to custom properties:

```lua
Ws:Edit(ref).Name = "MyCopy"       -- renames the copy
Ws:Edit(ref).Tag = "enemy"         -- custom property
```

---

## Examples

### Render your own character while the real one is hidden

```lua
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

local Ws = PolyRenderer.new()
Ws.SyncLighting = true

local hidden = {}

local function attach(char)
    char:WaitForChild("HumanoidRootPart", 10)
    -- wait for the avatar to finish loading, or the clone is taken before the
    -- clothing and accessories exist
    local t0 = os.clock()
    while not player.HasAppearanceLoaded and os.clock() - t0 < 5 do task.wait() end
    task.wait(0.1)

    Ws:Add(char)

    table.clear(hidden)
    for _, d in char:GetDescendants() do
        if d:IsA("BasePart") or d:IsA("Decal") then
            table.insert(hidden, d)
        end
    end
end

-- LocalTransparencyModifier is client-only, so other players still see you
-- normally, but the camera scripts reset it constantly — reassert every frame
RunService.RenderStepped:Connect(function()
    for _, d in hidden do
        if d.Parent then d.LocalTransparencyModifier = 1 end
    end
end)

if player.Character then task.spawn(attach, player.Character) end
player.CharacterAdded:Connect(attach)
```

### Render a set of objects, some cheaper than others

```lua
local Ws = PolyRenderer.new()

for _, obj in workspace.Targets:GetChildren() do
    Ws:Add(obj, { Fps = 15 })          -- 15x a second is plenty for distant things
end

Ws:Add(workspace.Boss)                  -- inherits Ws.Fps: every frame
```

### Budget the whole overlay

```lua
Ws.Fps = 10    -- camera, lighting and every inheriting entry step 10x a second
Ws.Fps = 0     -- back to every frame
```

---

## Behaviour worth knowing

**`Fps` gates the camera too.** At a low `Ws.Fps` the whole picture steps: copies slide off their sources while you turn, then snap back on each refresh. A per-entry `Fps` only changes how often *that copy* is re-posed — it can refresh faster than the camera, but the rendered result still steps at `Ws.Fps`, because where a copy lands on screen depends on the camera. Low `Fps` is a budget or stylistic choice, not something to leave on when the overlay has to sit exactly on its sources.

**Copies draw through walls.** A ViewportFrame always renders on top of the 3D scene; it has no depth relationship with the world. If you want occlusion you have to test for it yourself (a raycast from the camera to the source, toggling `Ws.Visible` or the copy's transparency).

**A viewport has no sky, fog, shadows or post-processing.** Copies won't self-shadow and won't pick up atmosphere, so in a heavily-graded place expect to tune `Ws.Ambient` and `Ws.LightColor` (or `SyncLighting`) to match.

**Clothing needs the whole model.** `Shirt`, `Pants` and `BodyColors` live on the character model, not on its parts, and won't render without a `Humanoid` — so add the character model itself, not individual limbs.

**Entries clean themselves up.** When a source is destroyed its entry and copy go with it. A respawned character is a new `Model`, so add the new one.

**`Archivable` is handled.** `Clone()` returns `nil` for a non-archivable instance and *silently drops* non-archivable descendants, so the renderer flips the flag on for the duration of the clone and puts it back exactly as it was. Set `Ws.AllowArchiving = false` if you'd rather it never touched the flag.

**Environment.** Outside Studio the `ScreenGui` goes to `gethui()` if the executor provides one, then `CoreGui`, then `PlayerGui`; in Studio it's always `PlayerGui`. Service handles pass through `cloneref()` where it exists. Note that `cloneref` returns *another reference to the same instance*, not a copy — duplication is always `Clone()`.

---

## Measured

From a test rig of unanchored physics parts, a yaw spinner, an orbiter, a three-axis tumbler and a multi-part model, all driven from the server:

| | result |
|---|---|
| Copy vs source, moving and animating | **0.000000 studs** over 228 rendered frames |
| Viewport camera vs world camera | **0.000000 studs** over 213 rendered frames |
| Physics parts under live simulation | **0.000000 studs** over 551 rendered frames |
| `Fps = 20` | camera 19.5/s, position 19.5/s, rotation 19.5/s |
| `Fps = 5` | camera 5.0/s, position 5.0/s, rotation 5.0/s |

---

## License

MIT — see [LICENSE](LICENSE). Fork it, ship it, sell it; keep the copyright notice.

Copyright (c) 2026 [@svyixiu](https://github.com/svyixiu)
