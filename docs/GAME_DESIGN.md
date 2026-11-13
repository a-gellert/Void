# VOID CLASH — Game Design & Content

> Living document. Update it whenever content, balance or controls change.
> Technical architecture lives in `PROJECT_DOCS.md`.

## 1. Pitch

Casual 3D arcade space combat for the browser (Poki / CrazyGames / Yandex Games). Team dogfights,
objectives and boss raids in short 2–4 minute sorties, inspired by session space shooters. Original
setting, ships, names and art; generated low-poly assets.

**Core loop:** sortie (2–4 min) → stars + credits + parts + XP → upgrade ship / buy hull / swap modules →
next mission. Contracts give a side goal across all modes.

**Setting:** you are a rookie pilot of the Frontier Guard. The Rust Syndicate pirates raid the Kepler
outskirts; behind them stands the Void Armada with its dreadnoughts. Four sectors lead to the Void Core.

## 2. Controls

| Action | Mouse + keyboard | Touch | Gamepad |
|---|---|---|---|
| Steer | Mouse-aim: move the mouse, the ship turns to the reticle (click captures the cursor) | Floating stick, left half | Left stick |
| Fire | Hold LMB (auto-fire on lock, toggle in settings) | Hold FIRE (auto-fire on lock) | RT |
| Guided missile | RMB / F / R (needs a lock) | MSL | Y / RB |
| Boost (energy) | Hold Shift or W | Hold BOOST | LT |
| Brake (tighter turns) | Hold S | — | LB |
| Strafe | A / D | — | — |
| Evade roll | Space (breaks missile locks) | EVADE | A |
| Modules | Q / E or 1 / 2 | M1 / M2 | X / B |
| Scoreboard / pause | Tab / Esc, P | — / II | Back / Start |

Flight model:
- **Mouse-aim:** the reticle marks a world-space aim direction. Mouse movement rotates it
  (0.003 rad/px × sensitivity); the ship turns towards it on its own (angular speed ∝ remaining angle,
  capped at 0.8 × hull turn rate, smoothed by agility), so releasing the mouse means "fly straight there".
  The camera sits behind the ship along the aim. A small ring shows where the nose points right now.
  Aim is leashed to 70° from the nose and pitch-limited to ~58°; near the arena shell it follows the nose back.
  The cursor is captured (pointer lock) on the first click; losing the capture (Esc) pauses the game.
  Without capture, the cursor at a screen edge keeps turning (1.7 rad/s).
- **Stick / gamepad:** deflection rotates the aim at up to 2.3 rad/s (expo curve).
- **Aim assist:** while the player is not steering and a locked target sits within 7° of the aim, the aim
  drifts towards its lead point (1.6 /s). Auto-horizon, no manual roll.
- **Throttle:** cruise speed by default; boost ×1.65–1.8 drains energy (30/s, regen 22/s after 0.8 s);
  brake ×0.5 speed but ×1.35 turn rate; boosting turns ×0.8.
- **Evade:** 0.5 s burst (×2.3 speed) with a barrel roll, 5 s cooldown, drops every missile lock.
- **Aim:** whatever sits inside the reticle circle is soft-locked; shots lead the locked target.
  Without a lock, shots converge on the point under the reticle.
- **Asteroid bumps:** hitting an obstacle hard (> 22 m/s into the surface) costs ~2.5–5 % hull and speed.

Settings: sound, auto-fire, steering sensitivity (0.6–1.5×), invert Y, language (EN / RU / PT / TR).

## 3. Ships

Global durability multiplier ×1.5 (hull + shield) for every combat hull. Upgrades: 4 nodes (hull,
weapon, shield, engine) T1→T5; +15 % hull/shield/damage, +6 % speed, +5 % turn, +10 % energy per tier.
Costs per tier: 150 / 350 / 700 / 1250 credits and 0 / 2 / 5 / 9 parts.

| Hull | Role | Unlock | Price | Hull / Shield (base) | Weapon | Missiles | Modules |
|---|---|---|---|---|---|---|---|
| Wasp | Interceptor | Lv 1 | free | 90 / 60 | plasma 11×7.5/s, 175 m | 2 | Warp, EMP, Cloak |
| Falcon | Fighter | Lv 2 | 400 | 135 / 100 | kinetic 18×5.4/s, 205 m | 3 | Overdrive, Swarm, Nano |
| Bastion | Frigate | Lv 4 | 900 | 220 / 200 | railgun 62×1.4/s, 300 m | 2 | Dome, Repair, Pulse |
| Phantom | Interceptor | Lv 6 | 1800 | 85 / 70 | plasma 16×6.4/s, 185 m | 2 | Warp, EMP, Cloak |
| Raptor | Fighter | Lv 8 | 2600 | 165 / 115 | kinetic 23×4.8/s, 215 m | 4 | Overdrive, Swarm, Nano |
| Aegis | Frigate | Lv 10 | 3600 | 250 / 260 | railgun 82×1.25/s, 330 m | 3 | Dome, Repair, Pulse |

Damage types: plasma ×1.25 vs shield / ×0.8 vs hull; kinetic & missiles ×0.85 / ×1.25; railgun ×0.9 / ×1.2.
Shields regenerate 25 %/s after 3 s without damage (ion storm modifier halves it).

Enemy-only: **pirate drone** (38 hull, weak plasma), **kamikaze drone** (rams, 55 blast damage, 14 m),
**freighter** (escort VIP, 1300 hull + 500 shield), **aces** (VIPER/Phantom, WARDEN/Aegis, MAULER/Raptor,
HEX/Wasp — ×2.5–3.5 hull, no respawn), **dreadnought** (3 generators → 4 turrets → reactor, Mk I–III).

## 4. Modules (2 of 3 per hull, assigned in Hangar → Modules)

| Module | Role | Unlock | CD | Effect |
|---|---|---|---|---|
| Warp | Interceptor | Lv 1 | 8 s | 45 m jump forward, 0.45 s invulnerable, breaks missile locks |
| EMP | Interceptor | Lv 1 | 12 s | 34 m: strips enemy shields, blocks regen 3.5 s, 12 dmg |
| Cloak | Interceptor | Lv 5 | 16 s | 5 s unlockable; first shot +60 %; breaks on fire / missile |
| Overdrive | Fighter | Lv 1 | 11 s | +50 % fire rate for 5 s |
| Swarm | Fighter | Lv 1 | 10 s | 6 mini-missiles at up to 3 targets (15 dmg each) |
| Nano | Fighter | Lv 5 | 15 s | heal 45 % hull over 5 s |
| Dome | Frigate | Lv 1 | 13 s | −80 % damage taken for 3.5 s |
| Repair | Frigate | Lv 1 | 14 s | heal 35 % hull to self and the weakest ally in 45 m |
| Pulse | Frigate | Lv 7 | 16 s | 55 m: allies +60 % shield, enemies 30 dmg + knockback |

Universal: guided missile (40 dmg, recharge 8 s per charge, needs lock), evade, boost.

## 5. Modes

| Mode | Win | Lose | Notes |
|---|---|---|---|
| Training (tutorial) | 5 steps done | timer | steer gates → boost gates → shoot dummies → missile → live drones |
| Drone Sweep | destroy N drones | timer | max M alive, allies help |
| Gate Run | all gates in order | timer | gates refill 35 energy; optional harassing drones |
| Team Battle | team reaches kill target | enemy reaches it / timer (tie = win) | pilots respawn |
| Domination | 100 points | enemy 100 / timer | 3 beacons, 0.5 pt/s per held beacon, capture 16 %/s per pilot |
| Survival | clear all waves | station destroyed | waves: 3+2n drones, kamikazes from wave 2, pilots from wave 3; skirmish = endless (5+ waves = win) |
| Escort | freighter reaches the end | freighter destroyed / timer | waves every 22–26 s near the route |
| Ace Hunt | all aces down | timer | aces never respawn, escorts do |
| Dreadnought Raid | reactor destroyed | timer | dome until generators die; telegraphed salvos; Mk II/III add drones |

Pickups on every layout: **repair** (+40 % hull) and **charge** (shield, energy, cooldowns, missiles), 16–18 s respawn.

## 6. Campaign (4 sectors × 6 missions = 24 missions, 72 stars)

Sector unlock: previous sector finale cleared **and** 10 / 24 / 38 total stars for sectors 2 / 3 / 4.
Missions unlock in order. Star 1 = win; stars 2–3 from the mission rules.

| # | Mission | Mode | Layout | Diff | Bot tier | Stars 2 / 3 |
|---|---|---|---|---|---|---|
| 1-1 | First Flight | tutorial | rift | 1 | 1 | ≤200 s / no deaths |
| 1-2 | Drone Sweep | hunt 12 | rift | 1 | 1 | ≤1 death / ≤150 s |
| 1-3 | Belt Run | race 12 | belt | 1 | 1 | ≤80 s / ≤64 s |
| 1-4 | First Blood | TDM 3v3 →10 | rift | 2 | 1 | 4+ kills / ≤1 death |
| 1-5 | Hold the Line | survival 3 | rift | 2 | 1 | station 50 % / 80 % |
| 1-6 | The Viper | ace ×1 | belt | 3 | 2 | ≤140 s / ≤1 death |
| 2-1 | Rift Control | domination 4v4 | rift | 3 | 2 | 5+ kills / ≤2 deaths |
| 2-2 | Cargo Run | escort | rift | 3 | 2 | freighter 50 % / 80 % |
| 2-3 | Ion Slalom | race 12 + drones | nebula | 3 | 2 | ≤90 s / ≤74 s |
| 2-4 | Siege of Ion Station | survival 5 | nebula | 4 | 2 | station 40 % / ≤1 death |
| 2-5 | Belt Brawl | TDM 4v4 →12 | belt | 4 | 2 | 5+ kills / ≤1 death |
| 2-6 | Leviathan | boss Mk I | wreck | 4 | 2 | ≤140 s / ≤1 death |
| 3-1 | Storm Convoy | escort, ion storm | nebula | 5 | 3 | freighter 45 % / 75 % |
| 3-2 | Twin Fangs | ace ×2 | nebula | 5 | 3 | ≤170 s / ≤1 death |
| 3-3 | Crimson Hold | domination 5v5 | belt | 6 | 3 | 6+ kills / ≤2 deaths |
| 3-4 | Last Bastion | survival 6, ion storm | rift | 6 | 3 | station 40 % / 70 % |
| 3-5 | Red Line | race 16 + drones | rift | 6 | 3 | ≤108 s / ≤92 s |
| 3-6 | Dreadnought Mk II | boss Mk II | wreck | 6 | 3 | ≤160 s / ≤1 death |
| 4-1 | Void Vanguard | TDM 5v5 →15 | nebula | 7 | 4 | 6+ kills / ≤2 deaths |
| 4-2 | Lifeline | escort + kamikazes | belt | 7 | 4 | freighter 40 % / 70 % |
| 4-3 | Core Defense | survival 7 | nebula | 8 | 4 | station 35 % / ≤2 deaths |
| 4-4 | Eclipse | domination 5v5, weak shields | rift | 8 | 4 | 6+ kills / ≤2 deaths |
| 4-5 | Ace Gauntlet | ace ×3 | belt | 9 | 5 | ≤220 s / ≤2 deaths |
| 4-6 | Void Leviathan | boss Mk III | wreck | 9 | 5 | ≤190 s / ≤2 deaths |

Themes per sector (clear colour, star tint, dust): Kepler (teal), Ion (blue), Crimson (red), Void (violet).

**Skirmish** (quick battles, scale with pilot level): Team Battle (Lv 1), Domination (Lv 2),
Endless Survival (Lv 3), Dreadnought (Lv 5, Mk grows every 8 levels). Layouts rotate.

## 7. Progression & economy

- **Pilot level 1–30.** XP to next level = 200 + 100 × level. Level-up reward: 100 × level credits + 1–2 parts.
- **Mission reward:** credits 120 + 35 × diff, parts 1 + diff/3, XP 100 + 25 × diff; +10 cr / +8 XP per kill,
  +50 cr per new star; first clear doubles credits and adds 1 part. Loss: 35 % credits, 40 % XP.
- **Skirmish reward:** win 150 cr / 2 parts / 120 XP, loss 70 / 1 / 60, +15 cr +10 XP per kill, +25 cr per survived wave.
- **Contracts:** 3 active, re-rolled on claim (kills, wins, missile kills, stars, beacons, drones, gates, damage, modules).
- **Cosmetics:** 24 hull paints, 12 engine trails; craft random (2 parts) or chosen (paint 4, trail 3).
- **Ads (Poki):** 2× reward after a match, +1 tier test drive, random cosmetic; interstitial between matches ≥140 s apart.
- **Bots:** difficulty 1–10 sets aim error, fire cone, reaction, damage ×0.42–0.82, hull ×0.85–1.2, missiles (≥3),
  retreat to repairs (≥4); bot ship tier comes from the mission.

## 8. Playtime estimate (why 1+ hour)

- Campaign: 24 missions × ~3 min average + ~25 % retries ≈ **85–95 min** for a first clear.
- Three-starring all missions roughly doubles that; star gates (10 / 24 / 38) push some replays.
- Hangar: 6 hulls × 16 upgrade steps (≈ 9 800 credits + 64 parts per hull) — far beyond the campaign income,
  so skirmish and contracts stay useful after the story.

## 9. Changelog (design)

- **2026-11-13 — controls v2:** mouse-aim instead of cursor-offset rate steering (the old scheme kept the
  ship spinning while the cursor was off-centre); camera follows the aim; nose marker; pointer lock with
  auto-pause; edge push without capture; aim assist; softer asteroid bumps.
- **2026-11-13 — full rework:** campaign (24 missions), 9 modes, 6 hulls, 9 modules, pilot levels, contracts,
  new flight model (rate control, throttle/energy, brake, strafe, evade roll), guided missiles, radar, damage
  numbers, scoreboard, results with stars, 4 languages.
