# Drawing

A Roblox port of the [sUNC Drawing library](https://docs.sunc.io/Drawing/), rebuilt on plain Roblox instances, so it runs in any normal game with no executor. It adds 3D ESP types (Skeleton, Box3D, Mesh, Highlight), UI decorators (UIStroke, UICorner, UIGradient), and a per-object refresh rate.

Version **1.0.0**.

---

## Contents

1. [Setup](#setup)
2. [Quick start](#quick-start)
3. [The basics](#the-basics)
4. [2D types](#2d-types)
5. [3D types](#3d-types)
6. [UI decorators](#ui-decorators)
7. [Functions](#functions)
8. [How `fps` works](#how-fps-works)
9. [Recipes](#recipes)
10. [Performance and lifecycle](#performance-and-lifecycle)
11. [Limits and gotchas](#limits-and-gotchas)
12. [Credits](#credits)

---

## Setup

1. Put the `Drawing` ModuleScript in **ReplicatedStorage**.
2. Require it from a **LocalScript**. It only works on the client:

```lua
local Drawing = require(game.ReplicatedStorage.Drawing)
```

---

## Quick start

```lua
local Drawing = require(game.ReplicatedStorage.Drawing)

local line = Drawing.new("Line")
line.From = Vector2.new(100, 100)
line.To = Vector2.new(400, 250)
line.Color = Color3.fromRGB(255, 80, 80)
line.Thickness = 2
line.Visible = true          -- every object starts hidden

print(line)                  -- Players.You.PlayerGui.Drawing.Line_1.Line  (the Frame drawing it)

task.wait(3)
line:Destroy()
```

You can also set all the properties in one call:

```lua
local box = Drawing.new("Square", {
	Position = Vector2.new(50, 50),
	Size = Vector2.new(120, 80),
	Thickness = 2,
	Color = Color3.new(0, 1, 0),
	Visible = true,
})
```

---

## The basics

These apply to every drawing type.

| Property | Type | Default | Meaning |
|---|---|---|---|
| `Visible` | boolean | `false` | Whether it's drawn. **Objects start hidden.** |
| `ZIndex` | number | `1` | Draw order. Higher is drawn on top. |
| `Transparency` | number | `0` | **0 = fully visible, 1 = invisible**, like Roblox's `Transparency`. |
| `Color` | Color3 | white | The object's colour. |
| `fps` | number | `0` | How many times a second the object refreshes. `0` means it updates immediately. See [How `fps` works](#how-fps-works). |
| `__OBJECT_EXISTS` | boolean | read-only | `false` once the object is destroyed. |

Methods:

- `obj:Destroy()` removes the object. `obj:Remove()` does the same.
- `print(obj)` / `tostring(obj)` gives the full path of the instance that draws it: the Frame for a one-piece shape, the container for a shape made of many pieces, the `ViewportFrame` for a Mesh, or the `Highlight` for a Highlight.

**Coordinates** are screen pixels, the same space `Camera:WorldToViewportPoint()` and `UserInputService:GetMouseLocation()` use. The top bar inset is already accounted for, so you can pass those results straight in.

**Mistakes give clear errors:**

```lua
line.Thicknes = 2    --> Thicknes is not a valid member of Drawing.Line (did you mean Thickness?)
line.Visible = 1     --> Drawing.Line.Visible expects boolean, got number
```

---

## 2D types

### Line
| Property | Type | Default |
|---|---|---|
| `From` | Vector2 | `(0, 0)` |
| `To` | Vector2 | `(0, 0)` |
| `Thickness` | number | `1` |

### Square (alias `"Box"`)
| Property | Type | Default | Notes |
|---|---|---|---|
| `Position` | Vector2 | `(0, 0)` | Top-left corner. |
| `Size` | Vector2 | `(0, 0)` | Negative sizes work. |
| `Thickness` | number | `1` | Outline width, centred on the edge. |
| `Filled` | boolean | `false` | |

### Circle
| Property | Type | Default | Notes |
|---|---|---|---|
| `Position` | Vector2 | `(0, 0)` | Centre. |
| `Radius` | number | `0` | |
| `NumSides` | number | `0` | `0` or `32`+ gives a perfectly round circle; 3–31 draws a real polygon. |
| `Thickness` | number | `1` | |
| `Filled` | boolean | `false` | |

### Triangle
`PointA`, `PointB`, `PointC` (Vector2), `Thickness` (1), `Filled` (false).

### Quad
`PointA`, `PointB`, `PointC`, `PointD` (Vector2), `Thickness` (1), `Filled` (false).

### Text
| Property | Type | Default | Notes |
|---|---|---|---|
| `Text` | string | `""` | |
| `Size` | number | `13` | Font size in pixels. |
| `Position` | Vector2 | `(0, 0)` | Top-left, or top-centre when `Center` is on. |
| `Center` | boolean | `false` | Centres the text horizontally on `Position`. |
| `Outline` | boolean | `false` | |
| `OutlineColor` | Color3 | black | |
| `Font` | number / Enum.Font / Font | `Drawing.Fonts.UI` | |
| `TextBounds` | Vector2 | read-only | The text's size on screen. Always up to date, even while hidden. |

`Drawing.Fonts`: `UI` (SourceSans), `System` (Arial), `Plex` (Gotham), `Monospace` (RobotoMono).

### Image
| Property | Type | Default | Notes |
|---|---|---|---|
| `Data` | string / number | `""` | An asset id: `"rbxassetid://123"`, `"123"` or `123`. Raw image bytes aren't supported. |
| `Position` | Vector2 | `(0, 0)` | Top-left. |
| `Size` | Vector2 | `(0, 0)` | |
| `Rounding` | number | `0` | Corner radius in pixels. |

---

## 3D types

These follow something in the world. Their **`Adornee`** can be a `Model`, a `BasePart`, or a **`Player`**. A Player adornee automatically follows that player's current character, including after they respawn.

### Highlight
Highlights the adornee with a Roblox `Highlight`, driven by a hidden copy of it. The copy lets the highlight have its own `fps`.

| Property | Type | Default |
|---|---|---|
| `Adornee` | Instance / nil | `nil` |
| `Enabled` (alias `Visible`) | boolean | `false` |
| `DepthMode` | Enum.HighlightDepthMode | `AlwaysOnTop` |
| `FillColor` | Color3 | `(255, 0, 0)` |
| `FillTransparency` | number | `0.5` |
| `OutlineColor` | Color3 | white |
| `OutlineTransparency` | number | `0` |
| `fps` | number | `0` |

A Highlight has no `ZIndex`, `Color` or `Transparency`, and no `Parent`: it places itself.

### Mesh
Draws a full copy of the adornee (clothing and accessories included) in a `ViewportFrame` that lines up exactly with the real thing. The copy is drawn on top of the world, so walls never hide it, and it layers with other drawings by `ZIndex`.

| Property | Type | Default | Notes |
|---|---|---|---|
| `Adornee` | Instance / nil | `nil` | |
| `Color` | Color3 | white | Tint. |
| `Transparency` | number | `0` | |
| `MirrorTransparency` | boolean | `true` | Copies each part's `Transparency` from the real thing. |
| `SyncLighting` | boolean | `false` | Takes lighting from `game.Lighting`. |
| `Ambient` | Color3 | `(200, 200, 200)` | Used when `SyncLighting` is off. |
| `LightColor` | Color3 | white | Used when `SyncLighting` is off. |
| `LightDirection` | Vector3 | `(-1, -1, -1)` | Used when `SyncLighting` is off. |

Also has `Visible`, `ZIndex` and `fps`.

### Skeleton
Draws bones along the adornee's joints, for R15 and R6. Works with both `Motor6D` and the newer `AnimationConstraint` joints.

| Property | Type | Default |
|---|---|---|
| `Adornee` | Model / Player / nil | `nil` |
| `Thickness` | number | `1.5` |

Also has `Visible`, `ZIndex`, `Transparency`, `Color` and `fps`.

### Box3D
Draws the 12 edges of a rotated 3D box around the adornee. With no adornee, it draws the box described by `CFrame` and `Size`.

| Property | Type | Default |
|---|---|---|
| `Adornee` | Instance / nil | `nil` |
| `CFrame` | CFrame | identity |
| `Size` | Vector3 | `(0, 0, 0)` |
| `Thickness` | number | `1.5` |

Also has `Visible`, `ZIndex`, `Transparency`, `Color` and `fps`.

---

## UI decorators

`UIStroke`, `UICorner` and `UIGradient` work like the Roblox instances of the same name. You create one, set its properties, and set its **`Parent`** to a drawing:

```lua
local box = Drawing.new("Square", { Position = Vector2.new(50, 50), Size = Vector2.new(100, 60), Filled = true, Visible = true })

local corner = Drawing.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = box                        -- rounded box

local stroke = Drawing.new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2, Parent = box })
```

| Decorator | Properties (defaults) |
|---|---|
| `UIStroke` | `Color` (black), `Thickness` (1), `Transparency` (0), `LineJoinMode` (Round), `ApplyStrokeMode` (Contextual), `Enabled` (true) |
| `UICorner` | `CornerRadius` (`UDim.new(0, 8)`) |
| `UIGradient` | `Color` (white ColorSequence, or a plain `Color3`), `Transparency` (NumberSequence, or a plain number), `Rotation` (0), `Offset` (0, 0), `Enabled` (true) |

**Where decorators can go:** any 2D drawing, a Skeleton, a Box3D or a Mesh, but not a Highlight. A decorator on a shape made of several pieces goes on **every** piece: a `UIGradient` on a Skeleton colours every bone, and a `UICorner` on a Line rounds its ends.

**A UIGradient recolours only what it's parented to.** Parented to a drawing, it tints that drawing's own fill or text, never its outline strokes. To colour a stroke, put the gradient **inside the stroke**:

```lua
local outline = Drawing.new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, Parent = box })
local gradient = Drawing.new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(80, 255, 140), Color3.fromRGB(40, 140, 255)),
	Rotation = 90,
})
gradient.Parent = outline        -- gradient-coloured outline
```

Engine rules still apply:

- Several `UIStroke`s on one drawing all show.
- Only the **first** `UICorner` and the **first** `UIGradient` on an object count.
- A `UICorner` on a Square or Image sets its own corner. Circles always stay round.
- The **filled** pieces of Triangle, Quad and polygon Circles can't take decorators, because they use their own gradient to cut their shape. You get a one-time warning. Their outlines can take decorators.

Re-parent, unparent (`decorator.Parent = nil`) or change properties at any time. **Destroying a drawing destroys its decorators**, like Roblox children.

---

## Functions

| Function | What it does |
|---|---|
| `Drawing.new(type, props?)` | Creates an object. `props` is an optional table of starting properties. |
| `Drawing.cleardrawcache()` | Destroys every object created by this module. |
| `Drawing.getrenderproperty(obj, name)` | The same as `obj[name]`. |
| `Drawing.setrenderproperty(obj, name, value)` | The same as `obj[name] = value`. |
| `Drawing.isrenderobj(value)` | `true` if `value` is a Drawing object. |
| `Drawing.getstats()` | A health snapshot (below). |
| `Drawing.Fonts` | `{ UI, System, Plex, Monospace }` |
| `Drawing.VERSION` | `"1.0.0"` |

`Drawing.getstats()` returns:

| Field | Meaning |
|---|---|
| `live` | Objects not yet destroyed. |
| `active` | Objects the frame loop is updating right now. |
| `loopRunning` | Whether the library's frame loop is running at all. |
| `cloneBuilds` | Total Highlight/Mesh copies built so far. |
| `enabledHighlights` | Highlights currently on (Roblox shows at most 31). |

Type names for `Drawing.new`: `Line`, `Text`, `Image`, `Circle`, `Square` (or `Box`), `Quad`, `Triangle`, `Highlight`, `Mesh`, `Skeleton`, `Box3D`, `UIStroke`, `UICorner`, `UIGradient`.

---

## How `fps` works

Every object has an `fps` property. `0` (the default) means changes show immediately.

**2D types (Line, Square, Circle, Triangle, Quad, Text, Image):** when `fps` is above 0, every property change waits for the object's next update. Setting `box.fps = 10` makes the box update at most 10 times a second, however often you change it. Use this for a deliberately "low refresh" ESP.

**3D types (Highlight, Mesh, Skeleton, Box3D):** `fps` controls how often the object **samples the adornee** (its pose or box). Your **camera** is always applied every frame. At a low `fps` the ESP trails behind the target in the world, but it never slides around on screen when you turn the camera.

```lua
local ghost = Drawing.new("Mesh", { Adornee = somePlayer, Transparency = 0.4, fps = 5, Visible = true })
-- a see-through copy that follows somePlayer 5 times a second
```

---

## Recipes

### A full ESP on one target

```lua
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Drawing = require(game.ReplicatedStorage.Drawing)

local target = workspace:WaitForChild("TestBot")   -- any character model

-- these follow the target on their own
local skeleton = Drawing.new("Skeleton", { Adornee = target, Color = Color3.new(1, 1, 1), Visible = true })
local box3d = Drawing.new("Box3D", { Adornee = target, Color = Color3.fromRGB(190, 120, 255), Visible = true })
local highlight = Drawing.new("Highlight", { Adornee = target, FillColor = Color3.fromRGB(255, 60, 60), Enabled = true })

-- these are 2D, so you position them each frame
local box = Drawing.new("Square", { Thickness = 2, Color = Color3.fromRGB(80, 255, 140) })
local name = Drawing.new("Text", { Text = Players.LocalPlayer.Name, Size = 16, Center = true, Outline = true })
local tracer = Drawing.new("Line", { Thickness = 2, Color = Color3.fromRGB(90, 210, 255) })

RunService.RenderStepped:Connect(function()
	local camera = workspace.CurrentCamera
	local cf, size = target:GetBoundingBox()
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	local onScreen = true
	for _, x in { -1, 1 } do for _, y in { -1, 1 } do for _, z in { -1, 1 } do
		local p = camera:WorldToViewportPoint(cf:PointToWorldSpace(size / 2 * Vector3.new(x, y, z)))
		if p.Z <= 0 then onScreen = false end
		minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
		minY, maxY = math.min(minY, p.Y), math.max(maxY, p.Y)
	end end end

	box.Visible, name.Visible, tracer.Visible = onScreen, onScreen, onScreen
	if not onScreen then return end
	box.Position = Vector2.new(minX, minY)
	box.Size = Vector2.new(maxX - minX, maxY - minY)
	name.Position = Vector2.new((minX + maxX) / 2, minY - 20)
	local root = camera:WorldToViewportPoint(target.HumanoidRootPart.Position)
	tracer.From = Vector2.new(root.X, root.Y)
	tracer.To = UserInputService:GetMouseLocation()
end)
```

### Highlight every other player (respawns handled)

```lua
local Players = game:GetService("Players")
local Drawing = require(game.ReplicatedStorage.Drawing)

local highlights = {}

local function add(player)
	if player == Players.LocalPlayer then return end
	highlights[player] = Drawing.new("Highlight", { Adornee = player, Enabled = true })
end

Players.PlayerAdded:Connect(add)
Players.PlayerRemoving:Connect(function(player)
	if highlights[player] then highlights[player]:Destroy() end
	highlights[player] = nil
end)
for _, player in Players:GetPlayers() do add(player) end
```

Because the adornee is a **Player**, each highlight follows that player's new character after a respawn, with nothing else to do.

### A gradient outline box

```lua
local box = Drawing.new("Square", { Position = Vector2.new(100, 100), Size = Vector2.new(80, 140), Transparency = 1, Visible = true })
-- Transparency = 1 hides the built-in outline; the stroke below draws the box instead
local outline = Drawing.new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, Parent = box })
Drawing.new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = box })
Drawing.new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(80, 255, 140), Color3.fromRGB(40, 140, 255)),
	Rotation = 90,
	Parent = outline,
})
```

### A gradient skeleton

```lua
local skeleton = Drawing.new("Skeleton", { Adornee = somePlayer, Thickness = 2, Visible = true })
Drawing.new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(255, 170, 60), Color3.fromRGB(255, 80, 160)),
	Parent = skeleton,
})
```

### A 3D box at a fixed spot

```lua
local zone = Drawing.new("Box3D", {
	CFrame = CFrame.new(0, 5, 0),
	Size = Vector3.new(10, 10, 10),
	Color = Color3.fromRGB(255, 220, 70),
	Visible = true,
})
```

### Rounded, gradient tracer

```lua
local tracer = Drawing.new("Line", { Thickness = 3, Color = Color3.new(1, 1, 1), Visible = true })
Drawing.new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = tracer })   -- round ends
Drawing.new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(90, 210, 255), Color3.fromRGB(255, 90, 200)), Parent = tracer })
```

---

## Performance and lifecycle

- **Nothing runs when nothing needs it.** The library has one frame loop, and it only runs while some object needs updating: a pending `fps` change, or a visible Highlight, Mesh, Skeleton or Box3D. It stops on its own when nothing does.
- **Hidden objects cost nothing.** Hiding a Highlight, Mesh or Skeleton stops it and frees its copy or rig, and showing it again rebuilds it.
- **Idle scenes cost nothing.** Poses, the camera and lighting are only written when they actually change.
- **Changes are grouped.** Setting ten properties in one frame redraws the object once.
- **Rebuilds are rate-limited.** If a target keeps gaining or losing parts, its copy is rebuilt at most every 0.25 s.
- **Errors are contained.** An object that errors warns once and never stops the others.
- **Objects repair themselves** if something outside destroys their instances, for example if PlayerGui is cleared or the camera is replaced.
- **Always destroy what you create.** Like sUNC, objects live until `:Destroy()` or `Drawing.cleardrawcache()`. If you drop your reference without destroying the object, it stays on screen and in memory.

Measured on a full ESP scene (box, circle, name, tracer, skeleton, 3D box, random Highlight and Mesh): about **0.3 ms per frame** over a hidden-overlay baseline. Memory and instance counts stay flat over long runs.

---

## Limits and gotchas

- **Client only.** `Drawing.new` errors on the server.
- **31 Highlights.** Roblox renders at most 31 Highlights at once. The library warns once if you go over.
- **Mesh draws over everything.** A Mesh copy isn't hidden by walls; only its `ZIndex` against other drawings matters.
- **Filled shapes and decorators.** Filled Triangle, Quad and polygon pieces don't take decorators (outlines do).
- **Semi-transparent filled triangles and quads** show a faint 1 px line where their inner pieces overlap.
- **Image** takes asset ids only, not raw bytes.
- **Transparency means see-through.** `Transparency` follows sUNC and Roblox: `0` is visible and `1` is invisible. Some older Drawing libraries used it the other way round.

---

## Credits

- API modelled on the [sUNC Drawing documentation](https://docs.sunc.io/Drawing/).
- The Mesh type is adapted from **PolyRenderer** (MIT, [@svyixiu](https://github.com/svyixiu/PolyRenderer)).
