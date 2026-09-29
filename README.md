# Far Flight

[Русская версия](README_RU.md)

[![Far Flight / Airmail — an aircraft over a remote airfield](assets/title_screen.png)](https://delorum.github.io/FarFlight/)

### [▶ Play in your browser](https://delorum.github.io/FarFlight/)

A game and a minimalist instrument-flight simulator.

You are an airmail pilot. Between remote airfields, mail aviation keeps people connected: parcels, letters, and news from afar must reach their destinations. Take jobs, load the aircraft, and plan profitable routes with multiple deliveries.

The sky here is almost never clear. A solid cloud layer begins only one hundred metres above the ground. Beyond it, you fly by instruments: heading, altitude, speed, radio beacon signals, and your own marks on the map. Your aircraft position disappears after departure, so you must determine it yourself.

Account for the wind, avoid mountains and thunderstorms, and plan your landings and stops. Fuel, food, hotels, and repairs are not available everywhere. The pilot needs food and rest, while the aircraft gradually wears out. There is no final money target: fly, deliver mail, improve your routes, and beat your own records.

## Contents

- [Quick start](#quick-start)
- [World and starting a game](#world-and-starting-a-game)
- [Controls](#controls)
  - [Aircraft](#aircraft)
  - [Map and weather radar](#map-and-weather-radar)
  - [Cabin and airport](#cabin-and-airport)
  - [Time and pause](#time-and-pause)
- [Flight model and instruments](#flight-model-and-instruments)
  - [Altitude, speed, and economy](#altitude-speed-and-economy)
  - [Electrical power, engine, and gliding](#electrical-power-engine-and-gliding)
  - [Radio altimeter](#radio-altimeter)
  - [Airframe wear](#airframe-wear)
- [Navigation](#navigation)
  - [Navigation map](#navigation-map)
  - [Flight calculator](#flight-calculator)
  - [Radio beacons](#radio-beacons)
  - [ILS and landing](#ils-and-landing)
- [Weather](#weather)
  - [Wind](#wind)
  - [Thunderstorms and weather report](#thunderstorms-and-weather-report)
  - [Weather radar](#weather-radar)
- [Airports and economy](#airports-and-economy)
  - [Services and prices](#services-and-prices)
  - [Mail](#mail)
  - [Cargo and refuelling](#cargo-and-refuelling)
  - [Hunger and energy](#hunger-and-energy)
  - [Departure preparation](#departure-preparation)
- [Landing, records, and the end of a flight](#landing-records-and-the-end-of-a-flight)
- [Saves](#saves)
- [Running and development](#running-and-development)
  - [Versioning](#versioning)
  - [Local launch](#local-launch)
  - [Web and GitHub Pages](#web-and-github-pages)
  - [Architecture](#architecture)
- [Credits](#credits)

## Quick start

The first departure is already paid for and prepared. Press `P` to turn on electrical power, `M` to start the engine, and `W` to increase the throttle. At approximately 70 km/h, pull the yoke back with the down arrow.

For level cruise, use roughly 87% throttle and 200 km/h as a starting point. The exact setting depends on altitude and wind. Before later departures, visit flight service, pay for preparation, and choose a runway direction.

## World and starting a game

The 200×200 km map is procedurally generated. Each of its four 100×100 km regions contains two airfields and four en-route radio beacons. Any two airfields are separated by at least 45 km.

Before a new game, you may enter a positive `seed` from 1 to 2147483647 or leave the field blank. The same seed reproduces the terrain, airfields, beacons, services, and weather sequence. You can share it with another player to compare records in the same world. The seed appears on the Continue button in both the title and pause menus.

The title screen offers continuation or results for the saved run, a new game, Landing Practice, About, Language, Credits, and Quit. About links to this complete guide. The Language screen switches the entire interface between Russian and English and saves that choice independently of the current game.

Landing Practice creates a fresh random world and airfield for every attempt. The aircraft starts on a six-kilometre final at 234 m, 150 km/h, 70% throttle, with electrical power and engine on, 40 litres of fuel, random wind, no thunderstorms, and the large ILS open. The mode can be restarted or left for the title screen and never reads, creates, or replaces the main campaign save.

## Controls

### Aircraft

- `W` / `S` — increase / decrease throttle;
- `P` — turn instrument power on or off;
- `M` — start or stop the engine;
- up/down arrows — pitch control: up/forward to descend, down/back to climb;
- left/right arrows — immediately deflect the yoke and turn;
- `Shift` + left/right arrow — adjust heading by 0.1°; holding changes it at 0.1° per second without deflecting the yoke;
- `Shift` + up/down arrow — move the yoke forward/back by a precise 0.1°;
- mouse over the throttle or yoke — direct control;
- `X` — leave for the cabin or return to the cockpit from anywhere in the cabin.

The yoke automatically centres laterally. Its longitudinal position remains where you leave it.
The small arrow to the right of the attitude indicator shows the resulting nose direction; the number below it shows the yoke's longitudinal deflection in degrees.

### Map and weather radar

- wheel over the map — zoom;
- LMB drag — pan the map;
- two short LMB clicks — draw a measurement line;
- drag an endpoint — change a line; lines sharing that endpoint move together;
- RMB — cancel an unfinished line or delete the nearest completed one;
- wheel over a radio receiver — change frequency by 1 kHz, or 10 kHz with `Shift`;
- `B` or click the weather radar — switch between the map and large radar;
- `I` or click the small ILS display — switch between the map and large ILS;
- wheel over the large radar — choose a 30, 20, 10, or 5 km range;
- click the aircraft on the large radar — draw the single 30 km current-ground-track line;
- RMB over the radar track line — delete it;
- track button — show or hide the completed flight track.

### Cabin and airport

- arrows or LMB — walk or move instantly in a side scene;
- `Enter` or click an active object — interact;
- `X` — return to the pilot seat;
- wheel down in the cabin — open the zoomed-out side view; three scales are available;
- wheel up, `Enter`, or `Esc` in the zoomed-out view — return to the cabin;
- leave a building with its button or `Enter`; `Esc` opens the pause menu.

Clicking the door, seat, table, or chair performs the interaction immediately. Merely walking past an object does not activate it.

### Time and pause

- `Shift+Z` — cycle through 1×, 2×, 4×, 8×, and 16×;
- `Z` — immediately return to 1×;
- `Space` — pause or resume the simulation in any scene;
- `Esc` — open the pause menu.

Aircraft or character control after acceleration returns time to 1×. Using the map and its lines does not. Rotation caused by a newly encountered storm resets acceleration immediately.

## Flight model and instruments

The panel contains airspeed and ground speed, barometric and radio altitude, vertical speed, compass, attitude indicator, clock, fuel gauge, two radio receivers, ILS, and weather radar. The clock begins on day 1 at 00:00:00 and uses the same time as the flight log.

The altimeter is marked every 50 and 100 m, the airspeed indicator every 25 and 50 km/h, and the vertical-speed indicator every 1 and 5 m/s. The compass retains N/E/S/W. Exact readings appear below the instruments.

### Altitude, speed, and economy

Fuel consumption falls to an optimum near 425 m and then rises again. Above 450 m the engine rapidly loses excess power, climb becomes negligible near 600 m, and the model's absolute ceiling is 700 m. High ridges must be bypassed through valleys and passes.

The cyan bands on the airspeed indicator and altimeter show ranges that achieve at least 95% of the maximum calculated range for the current direction and wind. An economical speed is selected separately at each altitude. When the radio altimeter can see the ground, a red mark on the altimeter shows its absolute elevation, while the cyan recommendation only considers levels at least 50 m above that mark. Recommendations are hidden on the ground and recalculated no more than once per real second.

Range is calculated from ground speed. The counter under the clock starts from zero at actual liftoff and accumulates the distance travelled over the ground while airborne; a touch-and-go keeps the current count. The fuel gauge shows the saving or penalty relative to sea-level consumption.

### Electrical power, engine, and gliding

Electrical power can be enabled without the engine and consumes no fuel. Turning power off also stops the engine; turning it back on starts only the instruments. Starting the engine requires both electrical power and departure clearance.

Without power, the mechanical airspeed, altitude, vertical-speed indicators, and clock continue to work. Electrical instruments and weather radar go dark.

In calm air with a neutral yoke, the unpowered aircraft glides at roughly 100 km/h and descends at about 3.6 m/s. Pulling too hard consumes speed and may cause a stall; pushing forward allows recovery. Gliding blends in smoothly below 10% throttle.

### Radio altimeter

The first large line below the dial shows barometric altitude: `… m`. The second line shows `RA … m • GND … m`: radio altitude and the absolute elevation directly below the aircraft. `GND` corresponds to the red mark on the scale. A red band after the mark shows the first 100 m above the current terrain; below that height the entire second line turns red, and above it the line is cyan.

The radio altimeter works with power on up to and including 750 m. Outside its range or without power, dashes replace both `RA` and `GND`. It shows terrain only directly below the aircraft, not ahead.

### Airframe wear

The airframe begins with 100 condition points and slowly wears during flight. Above safe speed, wear grows quadratically; inside a storm it increases toward the core. Reaching zero condition destroys the aircraft.

The panel shows integrity and wear per game minute. Side scenes use a compact indicator. Repairs are available in dedicated hangars.

## Navigation

### Navigation map

Before movement begins, the map shows the aircraft at its departure airfield. After departure its position is hidden. The completed track is also hidden in flight; after a flight ends, it can be shown or hidden while the final-position symbol remains visible.

A measurement line shows distance, time, direct and reciprocal courses, and maximum terrain elevation. A short line places its label horizontally nearby; hovering displays the same information in the lower-left corner. Points snap only to beacons and endpoints of existing lines, not to the middle of a segment.

### Flight calculator

The map contains a collapsible, draggable calculator with four tabs. Values accept either a decimal point or comma without requiring `Enter`, and the mouse wheel also changes them.

It relates distance, time, airspeed and vertical speed, initial and final altitude, ground track, heading, and wind. Distance is the fixed anchor of a tab: it changes only when edited manually or when its linked line changes. Other parameters recalculate one another. An impossible calculation turns red without erasing the route.

Current buttons insert aircraft data. Updating Altitude 1 inserts the wind at that altitude, after which it can be edited manually. The calculation assumes a constant regime and ignores storm gusts.

Link to Line binds a tab to a segment. Moving endpoints updates the calculation, while changing distance or direction moves the endpoint. The active linked line is red and other linked lines are orange. Reverse turns the direction by 180°.

### Radio beacons

En-route NDBs have a 30 km range; approach beacons have a 15 km range. NDBs are generated in low, open terrain. Terrain at least 250 m high between the aircraft and antenna may block the signal; the instrument distinguishes being out of range from terrain masking. This is a simplified model of medium-wave propagation in mountains.

### ILS and landing

ILS uses receiver 1. Tune an approach beacon: the instrument activates within 15 km, inside the forward sector, and with a suitable aircraft heading. The vertical needle shows localizer deviation and the horizontal needle shows deviation from the 3.3° glideslope. Green indicates capture within tolerance.

The small ILS also shows course error, distance, and predicted touchdown distance. Press `I` or click it to open the large display. In its single square window, runway perspective is calculated from the real 2 km × 50 m dimensions, current altitude, signed distance to the threshold, and a fixed field of view. It therefore remains appropriately small on a distant final and moves backwards out of the window at touchdown. Centreline dashes have fixed positions on the runway: they move in perspective as the aircraft advances and pass behind it. The larger coloured cross shows the aircraft's localizer and glideslope position, just like the moving cross on the small ILS. Its short arrow indicates the current ground-track trend; a compact cyan cross separately shows nose direction relative to runway heading and the glideslope-aligned viewing direction. When either cross exceeds the horizontal display range, it becomes an outward-pointing edge arrow labelled with the aircraft's lateral distance from the runway axis in metres or the nose's heading difference in degrees; the arrows remain distinct if both reach the same side. The diamond shows where the aircraft will reach the ground if throttle and longitudinal yoke remain unchanged and the lateral yoke is released. Twice per real second, an isolated aircraft copy is simulated with changing speed and vertical speed, fuel burn, and altitude-dependent wind; thunderstorms are currently excluded. The diamond and numerical forecast disappear after touchdown or whenever the unchanged-control trajectory predicts no contact. Precise readings are placed directly beside the window. The two large displays are mutually exclusive: opening large ILS closes the weather radar and vice versa.

Both ILS readouts place the touchdown forecast on one line: `TD` is the distance from the threshold, and `LAT` is the lateral offset from the runway centreline. The small ILS also groups its other readings into compact rows.

At the two most detailed map scales, dashed lines show the capture sector: side boundaries begin at the far runway end and the outer arc lies 15 km from the beacon. Each airfield has approach markers with distance and required altitude. Both ILS sizes show the current descent angle calculated from vertical speed and ground speed along the runway; the 3.3° target is exceeded in yellow and substantially exceeded in red. A shallower angle is neutral rather than presented as a correct approach.

As a throttle reference, join the runway extension 6 km from the far beacon at about 230 m and 100 km/h, set neutral pitch and 30% throttle. Reduce to 10% about 2.05 km from the beacon. The stable segment runs at 90–92 km/h on a roughly 3° glide path.

## Weather

### Wind

Wind is defined at 0, 250, 500, and 700 m and interpolated between them. It affects ground speed, drift, range, and economical regimes. New weather is generated after a completed landing; a touch-and-go does not change it.

### Thunderstorms and weather report

Thunderstorms may appear over airfields and approaches. They move, cause turbulence, and accelerate wear.

The map shows a static storm snapshot: pale yellow, orange, and red areas mirror the weather radar, while the contour records the position at report time. Its age is displayed at the upper left. Hovering shows the storm's approximate direction and speed.

Update Weather Report at flight service records current storm positions for free without changing the physical weather. A button to the left of ILS toggles this overlay. The sequence of weather cycles depends on the seed and number of completed landings.

### Weather radar

The large radar is centred on the aircraft and has 30, 20, 10, and 5 km ranges. Storm imagery updates once per second and rotates smoothly with heading; a hidden or paused radar does not update. Hovering shows storm motion, direction, and speed.

Clicking the aircraft draws a single 30 km line from its current position along its current ground track, including wind drift. It remains fixed to the ground and does not transfer to the map. A second line cannot be created until the first is deleted with RMB. If both endpoints move farther than 30 km from the aircraft, the line is removed automatically.

To the right of the scope, compact indications show lateral deviation `⊥` from the line and ground-track difference `ΔC`. An arrow indicates whether the aircraft or its current track is to the right or left; green means nearly exact alignment, yellow a small error, and red a significant one.

## Airports and economy

### Services and prices

Every airfield has a post office and flight service. Fuel, a cafe, a hotel, and repairs are each available at only three airfields; no more than two airfields have no optional services.

For every service, one airfield is 30% below the base price, one uses the base price, and one is 30% above it.

| Service | Base price |
| --- | ---: |
| Fuel | 2 coins/L |
| Empty fuel can | 15 coins |
| Takeaway food | 20 coins |
| Cafe meal | twice the local takeaway price |
| 20 hotel minutes | 10 coins |
| Repair | 3 coins per point |
| Departure preparation | 12 coins |

Starting money is 160 coins. After visiting at least two buildings of one type, the map shows the known price ranking: `(+)` is cheapest, followed by `(++)` and `(+++)`. Inside buildings, the same ranking is written as `(cheap)` and `(expensive)` for two known prices, with `(average)` added when all three are known. Unvisited prices remain hidden.

### Mail

The post office offers three parcels for different airfields and refreshes them after a landing at another airfield. Job distance follows the shortest passable route under the 700 m ceiling with 150 m terrain clearance.

Payment grows slightly faster than distance and accounts for a destination's lack of services: no optional services add 35%, one adds 20%, and two add 10%. Actual flown distance does not increase the reward. There are no deadlines, so several parcels can be taken on a multi-stop route.

### Cargo and refuelling

Parcels, food, and 20-litre fuel cans must be carried into the aircraft. The cabin has six cargo slots: clicking an empty slot stores an item, while clicking an occupied one retrieves it. A carried item can be stored or discarded.

The fuel station sells the can and fuel separately. Sliders use 0.1 L increments. In the technical bay, fuel can be transferred to the tank; the last partial increment fills it exactly. Enter the bay with the down arrow near the cockpit ladder or by clicking the refuelling device.

### Hunger and energy

Hunger and energy each have six segments and fall once per game hour. Reaching zero ends the game.

Food restores one hunger segment. At a cafe, it can be bought as takeaway at the regular local price or eaten immediately for twice that amount; eating there does not occupy your hands or a cargo slot. Takeaway food can only be eaten at the aircraft table: pick it up, sit down with a click or `Enter`, then press `Enter` or Eat. Sitting down alone does not consume it.

In the bed, every 20 uninterrupted minutes restores one energy segment, but only up to two. A hotel restores it up to six in paid 20-minute periods. You may stay there even at full energy to advance time.

### Departure preparation

The first departure is prepared for free. After a completed landing and full stop, clearance is revoked: pay for preparation and select a runway direction. Selecting the already paid runway again is free; changing direction charges again.

Entering the cabin on the ground stops the engine but does not cancel preparation before takeoff. Manually stopping and restarting it also retains clearance. The engine cannot start without preparation, and the reason appears in red.

## Landing, records, and the end of a flight

Touchdown does not complete a flight. Until the aircraft stops, you may add power and perform a touch-and-go; weather and clearance remain unchanged.

Flight service keeps flight records. The main log shows the newest flights first, with airfields, actual distance, duration, start time, and end time. Repeated routes have a fastest-to-slowest record list.

Flight continues while you walk through the cabin. A warning appears at a high angle of attack or during a stall. After a crash, the map opens with the cause, distance, time, and track. The slot is replaced by a completed-run save: its history, seed, and route remain viewable, but the flight cannot continue.

## Saves

The desktop slot is stored at `user://flight_save.dat`. Save and Quit writes it before closing the game. On failure, the game remains open and the previous slot is preserved. Starting a new game does not delete the old slot until a successful save.

Landing Practice is deliberately temporary: it has no save command, does not autosave after a crash, and leaves the main slot untouched.

The world, weather and report, aircraft and pilot, economy, mail, cargo, instruments, map, map and radar lines, calculator tabs, active flight, track, log, scene, and character are saved. A corrupted or incompatible file is not loaded.

In the browser, the slot is stored in `localStorage` under `farflight.save.v5`. It belongs to that browser and site address, does not synchronise with the desktop version, and may disappear after clearing data or using a private session. Closing the tab does not save the game by itself.

## Running and development

The game is built with Godot 4.7.

### Versioning

The current version is stored in `application/config/version` in `project.godot` and appears in the lower-right corner of the title and pause menus. The format is `0.MINOR.PATCH`: the first number remains zero until a stable release, the second increases for significant changes, and the third for small changes and fixes. Every commit must increase one of them; increasing `MINOR` resets `PATCH` to zero.

When a debug build is launched from a working tree with uncommitted changes, `-dev` is appended automatically. Exported builds always display the version recorded in the project.

### Local launch

Open `project.godot` in Godot 4.7 and run the project (`F5`). The main screen is `scenes/game_shell.tscn`; running `scenes/main.tscn` with `F6` skips the menu and is intended for development and tests.

### Web and GitHub Pages

The `Web` preset uses Compatibility/WebGL 2 without threads or a service worker. Godot 4.7 and export templates are required for a local build:

```sh
mkdir -p build/web
godot --headless --editor --path . --import
godot --headless --path . --export-release Web build/web/index.html
python3 -m http.server 8000 --directory build/web
```

Open `http://localhost:8000`, not `index.html` through `file://`.

On pushes to `main` and manual runs, `.github/workflows/web-pages.yml` runs tests, builds the Web version, and publishes GitHub Pages. Pull requests are built without publication. The downloadable artifact is named `FarFlight-Web`.

References: [Godot Web export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html), [GitHub Pages with Actions](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).

### Architecture

- `FlightWorld` owns the seed, terrain, airfields, corridors, weather, and beacons;
- `FlightModel` stores aircraft state and dynamics independently from the interface;
- `FlightPlanSolver` performs pure route calculations;
- `EconomyModel` stores money, needs, services, mail, and cargo;
- `main.gd` coordinates models and scenes; `cockpit_input.gd` handles flight controls;
- session mode rules and landing practice setup live in `session_mode.gd` and `landing_practice.gd`;
- `ils_display_state.gd` supplies the same guidance and forecast readouts to both ILS sizes;
- the map, instrument panel, and side scenes live in separate modules;
- `aircraft_art.gd` draws the aircraft externally and in cutaway view.

More detail is available in [ARCHITECTURE.md](ARCHITECTURE.md).

Rendering is limited to 60 FPS with VSync. The map is cached and redrawn after generation, resize, zoom, pan, or line changes. Instruments update separately. The terrain profile refreshes ten times per second and weather radar once per second.

Title artwork: `assets/title_screen.png`; original prompt: `assets/title_screen_prompt.md`.

## Credits

[github.com/delorum](https://github.com/delorum)
