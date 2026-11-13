# Void Clash

Casual 3D arcade space combat for the web, built with Defold 1.14 for Poki / CrazyGames / Yandex Games.

- 24-mission campaign in 4 sectors (team battles, beacon domination, survival, escort, gate runs, ace hunts,
  dreadnought raids), quick skirmish battles, pilot levels, contracts.
- 6 ships in 3 roles, 4 upgrade nodes, 9 role modules, guided missiles, cosmetics.
- Mouse + keyboard, touch (multi-touch stick + buttons) and gamepad. EN / RU / PT / TR.

Docs:
- `docs/GAME_DESIGN.md` — controls, ships, modules, modes, campaign, economy.
- `PROJECT_DOCS.md` — architecture, module contracts, build and test.

Build: see `PROJECT_DOCS.md` §5. Assets are generated with `node tools/gen_assets.js`.

Poki: the project uses the Poki SDK extension; lock the SDK version in `game.project` before release
([releases](https://github.com/defold/extension-poki-sdk/releases)).
