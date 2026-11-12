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
- **2026-11-12 (Этап 0):** Инициализация структуры, создание `PROJECT_DOCS.md`, `main/game.appmanifest`, настройка зависимостей `Druid` + `defold-event` + `Poki SDK` в `game.project`, настройка `input/game.input_binding` и мультиязычного шрифта `Nunito-Black`.
