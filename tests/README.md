# QustahShindo tests

Runs the hub, its raw files and the UI lib without the game, inside a mock Roblox environment, and checks their logic.

```
tests/run.sh                          # hub (map, menu, nofiles) + real UI lib
tests/run.sh path/QustahShindo.lua    # a given hub file
BENCH=tests/bench.lua tests/run.sh    # ESP timing with 29 players instead of the tests
STRIPE_IMAGE=1 BENCH=... tests/run.sh # the same with getcustomasset (Stripes as one picture)
```

Requirements: `python3` and `texlua` (ships with TeX Live and includes Lua 5.3). The other repos are expected next to
this one: `../jewvjs-s-savhas-sh-sahsvsjebebs-wneve` (the hub) and `../79650/gwanjkcdsjawbdnjascdas-ui-lib` or
`../gwanjkcdsjawbdnjascdas-ui-lib` (the UI lib); `HUB_SRC` / `LIB_SRC` point elsewhere. The raw files the hub downloads
(`rellauto`, `shindo/esp.lua`, `shindo/teleports.lua`) are served from this repo instead of HttpGet.

## Files

| File | Purpose |
|---|---|
| `run.sh` | Converts the hub, the raw files and the lib (Luau → Lua 5.3) and runs every scenario |
| `transpile.py` | Converts Luau extensions such as `x += 1` to Lua 5.3 (strings and comments are left untouched) |
| `luaparse.py` | Syntax check plus a list of undefined globals |
| `mock.lua` | Roblox imitation: Instance, Vector3, CFrame, Color3 (HSV), camera, signals, virtual clock, Drawing, executor functions |
| `fake_lib.lua` | Fake Qustah UI lib for the hub tests: draws nothing, records tabs / cards / elements; driven with `SetFlag` and `Press` |
| `run.lua` | The hub tests. `map` runs on a map, `menu` in the main menu (Inf Spin), `nofiles` with the raw files unreachable |
| `lib_run.lua` | The real UI lib in the mock: Window:Value, ColorChoice, gradient dots, ServerList, SkyPreview, LocationList, WhileVisible, the ESP preview capsules and Stripes |
| `bench.lua` | ESP timing and object count with 29 players (`BENCH=`) |
| `dump_ui.lua` | With `UI_DUMP=path`, writes the hub's UI structure as JSON (used for preview images) |

## Coverage

- **Lists:** every tab has all the expected features and none of the removed ones; slider ranges and defaults are correct.
- **FOV + ESP (Drawing or GUI rendering):** the FOV circle follows the mouse, also with ESP on, with no `TextBounds` on Drawing and with a broken character (a single ESP error used to freeze the FOV).
- **Silent aim:** Raycast and Mouse.Hit are redirected to the target (with a cloneref-style executor). Safe origin leaves other rays alone, prediction strength is computed correctly and nothing changes outside the FOV.
- **Farm:**
  - Legacy and Jutsu attack positions (Jutsu: fixed Height 0 / Distance 10; Legacy: 7 or 10 studs depending on the style).
  - The loop survives a mob being removed and stuck missions are cancelled.
  - Mentor punch and Daily M1 do not switch each other off; Claim all missions; Auto rank.
- **Boss farm:**
  - Waits 1000 studs above the giver until the mission ends and the next boss is ready.
  - The safe floor is 85x85, cloned from the map's ground and you stand exactly on top of it.
  - Specific / Random, multi-select and the "Bosses on map" counter.
- **Kill aura:** hits only the current target, removes `antiexploit` and works from either toggle.
- **Movement:** Always run, FOV slider (kept during fly jutsu), Wider dash and Puppet boost.
- **Server:** the list the hub hands to the lib hides your own and full servers; Join goes to the right server; Re-execute after teleport queues the raw link.
- **Inf Spin:**
  - No spins and no save while Wanted or Slots is empty.
  - Stops and saves once the wanted result arrives.
  - Selections are written to a file.
- **Unload:** remote traffic stops, and Drawings and the platform are removed.
- **Raw files unreachable (`nofiles`):** the hub still opens; the errors are reported, the user is notified, the ESP page shows a notice, its settings still exist and the Locations card is left out.
- **Real UI lib (`lib_run.lua`):** headless flags are saved like elements; colour dots and picker stay in step; several-colour dots are gradients; the server list draws rows and joins; the ESP preview capsules keep their own colours (theme-bound frames hid the style switch and the selection ring); Stripes use one tiled picture with getcustomasset and frames without it.

## Adding a test

In `run.lua`: `test("name", function() ... check("condition", ok, detail) end)`. Helpers:

- **Flags and buttons:** `W:SetFlag("flag", value)` changes a flag, `L.find("Title", "Button"):Press()` presses a button.
- **Time:** `mock.frame()` advances one frame, `mock.advance(seconds)` advances a duration (loops and `task.wait` run).
- **Sent traffic:** `mock.remotesSince(t0, "startevent")` lists remotes fired since then. `mock.drawingsOf("Circle", true)` lists visible drawings.
- **World:** `mock.player(name, pos)`, `mock.character(...)`, `mock.part(...)`, `mock.value(...)`, `mock.folder(...)`.
- **Game calls:** `mock.gameNamecall(workspace, "Raycast", ...)` behaves like the game's own Raycast (goes through the hook).
- **Faulty executor imitation:** `mock.drawingMode = "noTextBounds" | "noTriangle" | "none"`.
