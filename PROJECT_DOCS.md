# Void Clash 3D — Project Documentation & Agent Guide

> **ОБЯЗАТЕЛЬНО ДЛЯ ВСЕХ АГЕНТОВ:** Прочитайте этот файл перед любым изменением в проекте и обновляйте его при добавлении новых модулей, изменении контрактов, ассетов или правил сборки.

---

## 1. Обзор проекта
- **Название:** Void Clash 3D (Star Conflict Lite)
- **Движок:** Defold 1.14.0 (3D Pipeline, Lua)
- **Платформы:** WebGL / HTML5 (Poki, CrazyGames, Яндекс Игры) — Desktop и Mobile Web
- **Целевой размер бандла:** ≤ 5–8 МБ (сжатый WASM)
- **Целевой FPS:** 60 FPS на мобильных браузерах и Chromebook

---

## 2. Жесткие правила разработки (System Rules)

1. **Zero Physics (никакого Box2D / Bullet 3D):**
   - ЗАПРЕЩЕНО добавлять компонент `collisionobject` на любые `.go` или `.collection`.
   - В `main/game.appmanifest` физика (`physics`, `Bullet*`, `box2d*`) вырезана из WASM-бандла (при этом `gamesys_model` сохранен для 3D-мешей `.gltf`).
   - Все коллизии (астероиды, снаряды, ракеты, маяки, ЭМИ, ремонт, босс) считаются в чистом Lua через квадрат расстояния:
     `dx*dx + dy*dy + dz*dz < (r1 + r2)^2`.
2. **UI и локализация:**
   - Весь интерфейс строится через библиотеку **Druid** (`druid.*`).
   - Все текстовые строки хранятся исключительно в `modules/i18n.lua` (`en`, `pt`, `ru`, `tr`).
   - Используется шрифт `assets/fonts/main.font` (`Nunito-Black.ttf`, Distance Field) с поддержкой латиницы, кириллицы (`ru`), португальской (`pt`) и турецкой (`tr`: `ÇĞİÖŞÜçğıöşü`) диакритики.
3. **Poki SDK:**
   - Все вызовы идут через безопасную обертку `modules/poki.lua`.
   - `poki.gameplay_start()` — при первом движении/клике игрока в матче.
   - `poki.gameplay_stop()` — при завершении боя или выходе в Ангар.
   - Межстраничная реклама (`commercial_break`) — строго между матчами, не чаще 1 раза в 150 секунд, с обязательной паузой звука.
   - Rewarded Ads: `test_drive` (+1 тир перед боем), `double_loot` (2x кредиты), `random_skin` (случайный скин/шлейф в Ангаре).
4. **Object Pooling (ноль аллокаций в бою):**
   - Пулы создаются при загрузке в `modules/pool_manager.lua`: 8 кораблей, 120 лазерных импульсов, 24 ракеты, 40 VFX-вспышек/взрывов.
   - Во время боя `factory.create` и `go.delete` не вызываются.
5. **Изоляция логики и минимум `msg.post`:**
   - Игровая симуляция (полет, бой, ИИ, матч, камера) работает в чистых Lua-модулях (`modules/`) с прямыми вызовами функций.
   - `.script`-компоненты на сущностях — тонкая визуальная обвязка (трансформ, крен, hit-flash `tint`, шлейф).

---

## 3. Структура проекта

```text
├── PROJECT_DOCS.md              # Этот документ (обновлять при любых изменениях)
├── game.project                 # Конфиг Defold, зависимости (Poki, Druid, Event), HTML5
├── main/
│   ├── game.appmanifest         # Вырезание физики, рекордера, профайлера для веса <= 5-8 МБ
│   ├── main.collection          # Главная сцена: камера, контроллер, фабрики пулов, GUI
│   └── main.script              # Точка входа: цикл симуляции, переход Бой <-> Ангар
├── render/
│   ├── space.render             # Конфиг рендера
│   └── space.render_script      # 3D-перспектива (динамический FOV) + 2D GUI + world_to_screen
├── assets/
│   ├── fonts/                   # Nunito-Black.ttf + main.font (en, pt, ru, tr)
│   ├── textures/palette_256.png # Единая палитра 256x256 (включая скины и emissive)
│   ├── materials/
│   │   ├── space_palette.material
│   │   ├── space_palette.vp / .fp  # UV-сдвиг скинов, emissive, tint hit-flash
│   │   └── space_unlit.material / .vp / .fp
│   ├── models/                  # Low-poly .gltf: корабли, обвесы T2-T5, астероиды, маяки, дредноут
│   ├── atlases/ui.atlas         # Иконки UI, прицел, маркеры, виртуальный стик
│   └── sfx/                     # Легковесные .wav звуки (лазер, рельса, ракета, взрыв, щит, UI)
├── data/
│   ├── ships_db.lua             # Классы, ТТХ, T1-T5 апгрейды, 24 скина, 12 шлейфов
│   ├── modules_db.lua           # Форсаж + 6 активных модулей
│   ├── arenas_db.lua            # 3D-арены (TDM, Domination, Dreadnought Raid)
│   └── bots_db.lua              # Ники, флаги, 3 архетипа ИИ
├── modules/
│   ├── math3d.lua               # Векторные и кватернионные хелперы без лишних аллокаций
│   ├── pool_manager.lua         # Пулы кораблей, снарядов, ракет и VFX
│   ├── flight_physics.lua       # 3D-полет, автогоризонт, крен, облет сфер астероидов
│   ├── combat_manager.lua       # Soft Lock-On, стрельба, урон щит/корпус, 6 модулей
│   ├── ai_controller.lua        # ИИ 3 архетипов + логика турелей/генераторов Дредноута
│   ├── camera_rig.lua           # Следящая 3D-камера, FOV 65->78, Screen Shake, проекция
│   ├── match_controller.lua     # Первые 15с, TDM 4v4, 3D Domination, Дредноут (каждый 5-й бой)
│   ├── progress.lua             # sys.save / sys.load (кредиты, детали, T1-T5, скины, цикл босса)
│   ├── i18n.lua                 # Локализация (en, pt, ru, tr)
│   ├── audio.lua                # SFX менеджер с паузой под рекламу
│   └── poki.lua                 # Обертка Poki SDK (gameplay_start/stop, ads)
├── entities/                    # .go + тонкие .script для визуала пулов и окружения
├── gui/                         # hud_combat.gui / hangar.gui (Druid)
└── tools/                       # Node.js генераторы palette_256.png, .gltf моделей, .wav SFX и ui.png
```

---

## 4. Контракты модулей и системные параметры

### Палитра и шейдер `space_palette`
- `palette_256.png` имеет размер `256x256` (16x16 ячеек по 16x16 px).
- Константа фрагментного шейдера `skin_offset` (`vec4(u_offset, v_offset, emissive_boost, 0.0)`):
  - Для базовых элементов (астероиды, маяки, обвесы, сопла) передается `u_offset = 0`.
  - Для корпуса корабля игрока/бота передается `u_offset`, сдвигающий UV в нужную строку/столбец палитры из 24 раскрасок.
- Константа `tint` (`vec4(r, g, b, flash)`): при `flash > 0` меш смешивается с белым цветом на 1–2 кадра (Hit Flash).

### Баланс и формулы
- **Урон:** `base_damage * (1 + 0.15 * (tier - 1)) * type_multiplier`
  - `plasma`: 1.25 по щиту / 0.80 по корпусу
  - `kinetic`, `railgun`, `missile`: 0.85 по щиту / 1.25 по корпусу
- **Щит:** восстанавливается через 3.0 сек после последнего полученного урона.
- **Цикл матчей:** каждые 4 обычных боя (TDM / Domination) чередуются с 5-м боем — **Охота на Дредноут**.

---

## 5. Журнал изменений (Changelog)
- **2026-11-12 (Этапы 0–6):**
  - Инициализация `PROJECT_DOCS.md`, `main/game.appmanifest` (физика Box2D/Bullet3D вырезана, `gamesys_model` + `gamesys_rig` + `rig` сохранены), `game.project` (`Poki SDK`, `defold-event`, `druid 1.3.0`), `input/game.input_binding`.
  - Генератор `tools/gen_assets.js`: `assets/fonts/main.font` (`en`, `pt`, `ru`, `tr`), `assets/textures/palette_256.png`, 21 low-poly `.gltf` модель (включая `star_dome.gltf` и обвесы T2–T5), 10 `.wav` SFX и `assets/atlases/ui.atlas`.
  - 3D-рендер `render/space.render_script` + материалы `space_palette.material` (сдвиг UV для 24 скинов + `tint` Hit Flash) и `space_emissive.material`.
  - Базы `data/` (`ships_db`, `modules_db`, `arenas_db`, `bots_db`) и чистые Lua-модули (`math3d`, `pool_manager`, `flight_physics`, `combat_manager`, `ai_controller`, `camera_rig`, `match_controller`, `progress`, `i18n`, `audio`, `poki`).
  - Интерфейс Druid (`gui/hud_combat.gui`, `gui/hangar.gui`, `gui/ui_helper.lua`) и точка входа `main/main.collection` / `main/main.script`.
  - Проверена сборка `bob --platform=wasm-web --archive build bundle`: `VoidClash3D.wasm` ~1.98 МБ, `game0.arcd` ~403 КБ.
- **2026-11-12 (Task 2 — Читаемость боя):**
  - Добавлен `assets/sfx/lock.wav` (`main/audio.go`, `modules/audio.lua`) и проигрывание при смене `locked_target` в `modules/combat_manager.lua`.
  - Добавлен спрайт `assets/ui/hit_marker.png` в `assets/atlases/ui.atlas` (`tools/gen_assets.js`), событие попадания `on_hit_callback` и состояние хит-маркера / `+1 KILL` / 4-строчного килл-фида без аллокаций в `modules/match_controller.lua`.
  - В `gui/hud_combat.gui_script` добавлены хит-маркер на прицеле, всплывающий баннер `+1 KILL`, килл-фид (`Кто → Кого`) и до 7 компактных 2D-маркеров (HP/щит + цвет команды) над видимыми кораблями и уязвимыми частями Дредноута.
  - В `modules/i18n.lua` добавлены ключи `kill_plus`, `dreadnought`, `part_generator`, `part_turret`, `part_reactor` (`en`, `pt`, `ru`, `tr`).
- **2026-11-12 (Task 4 — Босс-рейд Дредноут и тактический ИИ):**
  - В `entities/dreadnought/dreadnought.go` и `modules/pool_manager.lua` добавлен полупрозрачный энергокупол `dome` (`vfx_sphere.gltf` + `space_emissive.material`), активный вокруг Дредноута в Фазе 1 (пока живы генераторы щита) с реакцией на попадания по щиту и эффектом коллапса при переходе в Фазу 2.
  - В `modules/match_controller.lua` и `modules/combat_manager.lua` добавлены телеграфируемые ракетные залпы турелей Дредноута (`fire_turret_salvo`, `has_incoming_missile`), исключена блокировка лазеров сферой отталкивания корпуса (`is_boss_hull`) для надежного попадания по реактору/генераторам.
  - В `gui/hud_combat.gui_script` и `modules/i18n.lua` добавлен пульсирующий баннер предупреждения о ракетном залпе (`missile_warning`) и подсветка кнопки `Dash`.
  - В `modules/ai_controller.lua` добавлено реактивное уклонение ботов (`activate_dash` + боковой маневр) при захвате ракетами, телеграфе залпа босса или плотном обстреле.
- **2026-11-12 (Task 3 — Ощущение 3D-скорости, полый астероид и сферы подбора):**
  - В `assets/materials/space_emissive.material` / `.vp` добавлена вершинная константа `stretch`, а в `modules/pool_manager.lua` (`set_ship_trail_dash`) — растяжение `#trail` и усиление яркости при `dash_timer > 0`.
  - Добавлен пул из 32 частиц 3D-пыли (`entities/dust/dust.go`, `/factories#dust`), оборачивающихся вокруг камеры (`camera_rig.get_pos` / `get_forward`) с растяжением в полосы скорости при форсаже.
  - В `modules/flight_physics.lua` (`torus_closest_offset`), `modules/match_controller.lua`, `modules/combat_manager.lua` и `modules/ai_controller.lua` реализована тороидальная коллизия стенок `hollow_asteroid` со свободным пролетом и стрельбой сквозь центральный тоннель.
  - На аренах (`data/arenas_db.lua`) размещены 2–3 сферы подбора (`entities/pickup/pickup.go`, `/factories#pickup`): `repair` (+40% корпуса) и `charge` (100% щита и сброс КД форсажа/модулей) с респавном 18 с, 2D-маркерами и локализованным уведомлением в `gui/hud_combat.gui_script` (`modules/i18n.lua`).
- **2026-11-12 (Task 5 — Экономика Деталей, числовые ТТХ в Ангаре и звуковой эмбиент):**
  - В `data/ships_db.lua` и `modules/progress.lua` задействованы детали (`parts`): требование деталей (`3 / 6 / 10`) на апгрейдах T3–T5 (`can_upgrade` / `upgrade_node`), а также крафт случайного (`craft_random_cosmetic`, 2 детали) или выбранного (`craft_cosmetic`, 4 детали за скин / 3 за шлейф) элемента кастомизации; в `get_effective_stats` добавлено поле `dps`.
  - В `gui/hangar.gui_script` и `main/main.script` добавлены карточка числовых ТТХ (`Hull`, `Shield`, `DPS`, `Speed`) с отображением прироста следующего апгрейда, отображение стоимости в деталях на кнопках T3–T5, предпросмотр закрытых скинов/шлейфов и кнопки крафта за детали (`modules/i18n.lua`: `dps`, `speed`, `craft_random`, `craft_selected`, `select_locked`, `all_unlocked`).
  - В `tools/gen_assets.js`, `main/audio.go`, `modules/audio.lua`, `main/main.script` и `modules/match_controller.lua` добавлены зацикленный космический эмбиент (`ambient.wav`) и звуки завершения боя (`victory.wav`, `defeat.wav`) с поддержкой `set_ad_paused` (`sound.pause` + `master` gain) и удален дубликат `lock` в `main/audio.go`.
- **2026-11-12 (Task 6 — E2E WASM-бандл и проверка в браузере):**
  - `game.project`: добавлен `[model] max_count = 1024` (лимит по умолчанию `128` переполнялся пулами снарядов/VFX/астероидов).
  - Симуляция `match_controller.update(...)` перенесена из `.gui_script` в `main/main.script` (`match_controller.get_input_state()`), а переходы из `gui/hud_combat.gui_script` (`btn_pause_hangar`, `btn_next`) маршрутизируются через `msg.post("/controller#main", ...)` без прямых вызовов `go.*` из `.gui_script`.
  - В `gui/hud_combat.gui_script` и `gui/hangar.gui_script` переключение `self.root` переведено с `gui.set_visible` на `gui.set_enabled` (каскадное скрытие и отключение ввода дочерних нод Ангара/HUD).
  - В `modules/camera_rig.lua` и `render/space.render_script` пользовательское сообщение проекции переименовано в `"set_space_camera"` (избежание системной валидации `id` встроенного `"set_view_projection"` в Defold 1.14).
  - Финальный HTML5 WASM-бандл (`dist/html5/Void Clash 3D`): **5.24 МБ** raw / **2.42 МБ** gzip (цель ≤ 5–8 МБ выполнена с запасом); E2E-прогон в headless Edge (Combat → Pause → Hangar → Battle) завершился с `0` ошибками Lua/JS/404 и подтверждённым рендером 3D и 2D GUI.
- **2026-11-12 (Task 7 — Исправление самопроизвольного вращения/пикирования корабля при нейтральном курсоре):**
  - `modules/camera_rig.lua`: `get_aim_ray` теперь наводит корабль на **мировую точку под курсором** (луч из камеры, затем направление от корабля к этой точке), а не копирует направление взгляда следящей камеры. Камера расположена выше и позади корабля, поэтому её вектор взгляда всегда занижен на ~4–5°; при курсоре ровно в центре это давало постоянную цель «носом вниз», корабль непрерывно закладывал пике/петлю и вращался вместо полёта прямо. Сигнатура: `camera_rig.get_aim_ray(ship_pos, ship_forward, steer_x, steer_y)`, вызов обновлён в `modules/match_controller.lua`.
  - `modules/math3d.lua`: добавлены `clamp_pitch()` (ограничение тангажа с сохранением курса и единичной длины) и `rotate_towards()` (поворот по кратчайшей дуге, аналог slerp). Прежний вариант `clamp(y) + normalize`, а затем и покомпонентный `lerp` + `normalize` не ограничивали угол: вблизи полюса нормализация «выталкивала» `y` обратно выше лимита, корабль проходил через вертикаль, базис авто-горизонта вырождался и модель резко переворачивалась/крутилась вокруг оси. `rotate_towards()` используется в `flight_physics.update_ship()` вместо покомпонентного lerp, а `clamp_pitch()` применяется и к цели, и к результату поворота (после репульсии/границы).
  - `modules/flight_physics.lua`: граница арены сделана действительно мягкой. В зоне от `0.90 * ARENA_RADIUS` до радиуса нос плавно доворачивается внутрь (сила растёт по мере приближения), плюс остаётся жёсткий клампинг позиции как страховка. Раньше после первого исправления нос просто скользил по касательной к сфере: корабль с нейтральным курсором упирался в невидимую стенку и начинал бесконечно кружить вдоль неё — это выглядело как периодическое «закручивание».
  - Пересобран HTML5-бандл `dist/html5/Void Clash 3D` (bob `--platform=wasm-web --archive`), чтобы браузерная версия содержала исправления.
