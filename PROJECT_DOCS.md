# Void Clash — Project Documentation & Agent Guide

> **ОБЯЗАТЕЛЬНО ДЛЯ ВСЕХ АГЕНТОВ:** прочитайте этот файл и `docs/GAME_DESIGN.md` перед изменениями.
> Обновляйте оба при добавлении модулей, контента, изменении контрактов, ассетов или правил сборки.

---

## 1. Обзор
- **Название:** Void Clash (казуальный 3D космический экшен с командными боями, кампанией и боссами)
- **Движок:** Defold 1.14.0 (3D, Lua), `game.project` → `title = Void Clash 3D`
- **Платформы:** HTML5 (Poki, CrazyGames, Яндекс Игры), desktop + mobile web
- **Бандл:** ≤ 5–8 МБ; цель 60 FPS
- **Геймдизайн, контент, баланс:** `docs/GAME_DESIGN.md`

## 2. Жёсткие правила
1. **Без физического движка.** Никаких `collisionobject`. Коллизии — чистый Lua: сферы, торы, отрезок-сфера
   для снарядов (`combat_manager.find_hit`, без туннелирования на 500 м/с).
2. **Пулы, без `factory.create` в бою.** `modules/pool_manager.lua`: 20 кораблей, 160 лазеров, 40 ракет,
   56 VFX, 28 астероидов, 3 маяка, 9 частей дредноута, 32 пылинки, 3 бонуса, 16 колец.
3. **UI — Druid + код.** GUI-ноды строятся в `*.gui_script` через `gui/ui_helper.lua`. Боевые кнопки
   (мультитач) — собственный `gui.pick_node`, Druid только для оверлеев/меню.
4. **Строки — только `data/lang/*.lua`** (`en` — фолбэк, `ru`, `pt`, `tr`). Шрифт содержит ASCII, кириллицу,
   PT/TR диакритику и `° × • → —`. Других символов (★ … « » ✓) не использовать — звёзды и замки рисуются спрайтами.
5. **Poki SDK — через `modules/poki.lua`.** `gameplay_start` при первом вводе в бою, `gameplay_stop` на паузе/в конце.
   Межстраничная реклама между матчами не чаще 140 с, звук глушится. Rewarded: 2× награда, тест-драйв, случайный скин.
6. **Симуляция — в Lua-модулях**, `main/main.script` тикает `match_controller.update(dt)` и очищает одноразовые
   флаги ввода. Скрипты сущностей не используются.
7. **Генерация ассетов детерминирована** (`tools/gen_assets.js`, сидированный `Math.random`).

## 3. Структура

```text
├── PROJECT_DOCS.md / docs/GAME_DESIGN.md / README.md
├── game.project                     # Defold-конфиг, зависимости (Poki SDK, defold-event, Druid 1.3.0)
├── input/game.input_binding         # мышь, WASD/стрелки, Shift, Space, Q/E/1/2, F/R/ПКМ, Tab, Esc/P, тач, геймпад
├── main/
│   ├── main.collection              # controller, factories, star_dome, audio, hud, hangar
│   ├── main.script                  # поток игры: ангар ↔ бой, retry/next, превью корабля
│   ├── factories.go / audio.go      # фабрики пулов (+ring) / 24 звука
│   └── game.appmanifest             # вырезание физики/профайлеров из WASM
├── render/space.render_script       # 3D-проход, emissive-проход, GUI; сообщения set_space_camera, clear_color
├── assets/                          # сгенерировано tools/gen_assets.js (модели, палитра, SFX, UI-атлас, шрифт)
├── data/
│   ├── ships_db.lua                 # 6 корпусов игрока + дрон/камикадзе/грузовик, апгрейды, скины, DURABILITY
│   ├── modules_db.lua               # DASH, AFTERBURNER, BRAKE, MISSILE, 9 модулей, ROLE_DEFAULTS
│   ├── arenas_db.lua                # раскладки rift/belt/nebula/wreck, кольца, маршрут эскорта, волны, THEMES
│   ├── campaign_db.lua              # 4 сектора × 6 миссий, правила звёзд, награды, пресеты SKIRMISH
│   ├── progression_db.lua           # уровни пилота, награды за уровень, шаблоны контрактов, награды схватки
│   ├── bots_db.lua                  # имена, асы, архетипы, skill(difficulty)
│   └── lang/{en,ru,pt,tr}.lua       # строки
├── modules/
│   ├── match_controller.lua         # ядро матча: спавн, респавн, ввод игрока, события HUD, финиш, награды
│   ├── modes/*.lua                  # tdm, domination, survival, escort, race, hunt, ace, boss, tutorial
│   ├── flight_physics.lua           # rate-управление игрока, ИИ-руление, тяга/энергия/тормоз/стрейф, бочка, препятствия
│   ├── combat_manager.lua           # оружие, ракеты, модули, урон, лок-он, камикадзе, коллизии снарядов
│   ├── ai_controller.lua            # pilot / drone / kamikaze / dummy
│   ├── camera_rig.lua               # чейз-камера, камера смерти, орбита ангара, aim point, world_to_screen
│   ├── input_state.lua              # общее состояние ввода (оси, удержания, одноразовые нажатия, устройство)
│   ├── progress.lua                 # сейв v2 + миграция v1, ангар, кампания, контракты, настройки
│   ├── pool_manager.lua, math3d.lua, audio.lua, poki.lua, i18n.lua
├── gui/
│   ├── hud_combat.gui(_script)      # HUD, весь боевой ввод, пауза, результаты
│   ├── hangar.gui(_script)          # меню: HUB / CAMPAIGN / SKIRMISH / HANGAR / SETTINGS
│   └── ui_helper.lua                # box/text/para/button/bar, палитра UI
├── entities/                        # .go с моделями для пулов (ship: 5 мешей + обвесы T2–T5 + trail + dome; ring)
└── tools/gen_assets.js              # node tools/gen_assets.js — пересоздаёт все ассеты
```

## 4. Контракты модулей

### Матч (`match_controller`)
- `M.start(cfg)` — cfg из `M.campaign_config(mission_id)` или `M.skirmish_config(preset_id)`:
  `{ kind, mission_id?, preset_id?, mode, layout, theme, difficulty, bot_tier, allies, enemies, params, time_limit, modifiers }`.
- `M.update(dt)`, `M.set_paused(bool)`, `M.stop_match()`, `M.get_state()`, `M.finish(won)`.
- Режим (`modules/modes/<mode>.lua`) реализует `setup(match, api)`, `update(match, api, dt)` и опционально
  `on_kill`, `on_structure_killed`, `on_timeout → won`, `on_finish`.
- `api`: `spawn_ship(opts)`, `spawn_player()`, `spawn_pilots(team, n, opts)`, `spawn_drone(kind, pos, team)`,
  `build_environment(opts)` (`keepout`, `keep_r`, `no_hollow`, `no_station`, `no_pickups`, `extra_obstacles`),
  `add_structure(s)`, `spawn_point`, `free_slots`, `skill(team)`, `banner`, `hint`, `set_objective`, `track`, `finish`.
- Состояние для HUD: `score[1..2]`, `score_kind` (`kills|percent|waves|none`), `objective {key,a,b,pct}`,
  `boss_bar {key,pct}`, `protect {entity,key}`, `waypoints[1]`, `banner`, `hint`, `feed[5]`, `dmg_numbers[12]`,
  `hit_marker_*`, `kill_banner_timer`, `hurt_timer`, `missile_warning`, `stats`, `result`.
- Сущности: корабли (`match.ships`, поле `ai` = player/pilot/drone/kamikaze/dummy/freighter) и структуры
  (`match.structures`: части босса, станция; `is_structure`, `targetable`, `shielded`).

### Бой (`combat_manager`)
- `reset(ctx)` с колбэками `on_hit(target, attacker, dealt, is_kill)`, `on_kill`, `on_structure_killed`, `on_module`, `on_missile_kill`.
- `fire_primary(ship, target?, aim_point?)`, `fire_missile(ship, target)`, `activate_dash(ship, sign)`,
  `activate_module(ship, slot, ships, structures)`, `detonate(ship, ...)`, `apply_damage(...)`, `acquire_player_lock(...)`.
- Урон: `damage × (1 + 0.15·(tier−1)) × dmg_mult × type_mult`; щит восстанавливается 25 %/с через 3 с.

### Ввод
- HUD пишет `modules/input_state.lua`: `steer_x/y`, `strafe`, `fire`, `boost`, `brake`, одноразовые `dash/missile/mod1/mod2`,
  `device` (`mouse|touch|gamepad` — переключает подсказки и раскладку кнопок).
- Мышь — mouse-aim: дельты мыши копятся в `aim_dx/aim_dy` (рад), `match_controller.update_aim` вращает мировой
  вектор `player.aim_dir` (поводок 70° от носа, ассист по лок-цели), `flight_physics.update_player_aim` доворачивает
  корабль, `camera_rig.update_battle(ship, aim_dir)` ставит камеру по прицелу. Захват курсора —
  `window.set_mouse_lock` из `html5.set_interaction_listener` (только в жесте пользователя); потеря захвата = пауза;
  без захвата — дельты по позиции + поворот у края экрана. Стик/геймпад пишут `steer_x/y` (скорость вращения прицела). Тач: `touch_multi` с назначением пальцев
  (стик слева, удержание FIRE/BOOST, нажатия EVADE/MSL/M1/M2). Событие `touch` игнорируется при тач-устройстве.

### Сейв (`progress`, файл `save_v2`)
`credits, parts, xp, level, owned{}, selected, upgrades{ship}, loadouts{ship}, unlocked_skins/trails, equipped_*,
campaign{stars{}, best_time{}}, contracts[3], stats{}, match_count, skirmish_round, test_drive_active, settings{}`.
Старый `save_v1` мигрирует автоматически (классы → wasp/falcon/bastion, кредиты, детали, скины, настройки).

### Палитра и шейдеры
- `palette_256.png`: строки 0–5 — 24 скина (сдвиг `skin_offset`), строка 8 — механика/дрон/грузовик,
  9 — астероиды/станция, 10 — дредноут, 14–15 — эмиссив.
- `space_palette`: `tint` (rgb > 1 = вспышка попадания; затемнение = маскировка), `skin_offset`.
- `space_emissive`: `tint`, вершинная `stretch` (растяжение шлейфа при форсаже/рывке).

## 5. Сборка и проверка
```bash
# пересоздать ассеты (после правок tools/gen_assets.js)
node tools/gen_assets.js
# сборка HTML5 (bob из пакета редактора; запускать ИМЕННО главный класс Bob, а не -jar — тот стартует редактор)
"C:/Program Files (x86)/Defold/packages/jdk-25.0.4.1+1/bin/java.exe" -cp "C:/Program Files (x86)/Defold/packages/defold-<sha>.jar" \
  com.dynamo.bob.Bob --platform=wasm-web --architectures=wasm-web,wasm_pthread-web --archive --variant=release \
  --bundle-output=dist/html5 resolve build bundle
```
- Нативные расширения собираются на build.defold.com (нужен интернет), движок кешируется в `.internal/cache`.
- E2E: бандл раздаётся локальным HTTP-сервером и открывается в headless Chrome через CDP (скриншоты, консоль,
  ввод мышью/клавиатурой). Ошибки Lua видны в консоли как `ERROR:SCRIPT:`.

## 6. Журнал изменений
- **2026-11-13 — Управление v2:** mouse-aim вместо руления отклонением курсора (корабль больше не крутится, пока курсор
  не в центре), камера по прицелу, маркер носа, pointer lock с авто-паузой, поворот у края экрана без захвата,
  мягкий аим-ассист, мягче удары об астероиды. Старый `flight_physics.update_player` удалён.
- **2026-11-13 — Полная переработка (v2.0):**
  - Геймлуп: хаб-меню (кампания, схватка, ангар, контракты, настройки), уровни пилота 1–30, 24 миссии в 4 секторах
    со звёздами и гейтами, 4 пресета схватки, 3 контракта, экран результатов (звёзды, XP-бар, level-up, 2× за рекламу,
    retry / next / hangar). Первый запуск сразу стартует обучение (правило первых 15 секунд).
  - Управление: rate-руление с экспонентой и инерцией, форсаж на энергии, тормоз (резче поворот), стрейф A/D, рывок-бочка
    со сбросом ракет, управляемые ракеты с зарядами, модули Q/E, автоогонь как настройка, чувствительность и инверсия Y,
    мультитач (стик + удержание огня/форсажа), геймпад. Прицел по лучу через центр экрана.
  - Контент: 9 режимов (`modules/modes/`), 6 корпусов, 9 модулей с выбором 2 из 3, пиратские дроны, камикадзе, грузовик,
    асы, дредноут Mk I–III с волнами дронов; 3 новые раскладки (belt, nebula + обновлённый rift) и 4 темы секторов.
  - HUD: радар, маркеры с HP/щитом, числа урона, виньетка урона и низкого корпуса, кнопки с кулдауном (stencil),
    энергия и ракеты, цель/прогресс, полоса босса/защиты, баннеры (стрики, волны, маяки), таблица счёта (Tab), камера смерти.
  - ИИ: архетипы + сложность 1–10, цели по режиму (маяки, станция, грузовик, части босса), отход к ремонту, стрейф-уклонение,
    ракеты, ситуативные модули, реактивный рывок.
  - Ассеты: модели ring_gate, drone, freighter; спрайты star, radar, vignette, padlock, dot; 10 новых SFX.
    Исправлен `white.png` (был с альфой 0.5 — все полосы HUD выглядели тусклыми). Генерация детерминирована.
  - Баланс: DURABILITY ×1.5, урон ботов 0.42–0.82, захват маяков 16 %/с, 0.5 очка/с за маяк.
  - Локализация вынесена в `data/lang/` (en, ru, pt, tr; 285+ ключей).
- **2026-11-12 (Этапы 0–7, v1):** базовый прототип — 3 класса, TDM/Domination/Dreadnought, пулы, Druid HUD/ангар,
  Poki SDK, пыль скорости, полый астероид, бонусы, детали и крафт, исправление «закручивания» корабля
  (`math3d.rotate_towards`, `clamp_pitch`, мягкая граница арены). Подробности — в истории git.
