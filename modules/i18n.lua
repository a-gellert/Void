local M = {}

M.LANGUAGES = { "en", "pt", "ru", "tr" }

local STRINGS = {
    en = {
        game_title = "VOID CLASH 3D",
        hint_first_15 = "AIM AT ENEMY TO LOCK & AUTO-FIRE • SHIFT TO DASH",
        hint_dreadnought = "DESTROY 3 SHIELD GENERATORS, THEN TURRETS & REACTOR!",
        mode_tdm = "TEAM DEATHMATCH 4v4",
        mode_dom = "3D DOMINATION",
        mode_boss = "DREADNOUGHT RAID",
        victory = "VICTORY",
        defeat = "DEFEAT",
        credits = "CREDITS",
        parts = "PARTS",
        double_loot = "2X LOOT (AD)",
        next_battle = "NEXT BATTLE",
        hangar = "HANGAR",
        battle = "BATTLE",
        test_drive = "TEST DRIVE +1 TIER (AD)",
        test_drive_active = "PROTOTYPE +1 TIER READY!",
        random_skin = "RANDOM SKIN / TRAIL (AD)",
        respawn_in = "RESPAWN",
        locked = "LOCK",
        shield = "SHIELD",
        hull = "HULL",
        weapon = "WEAPON",
        engine = "ENGINE",
        tier = "TIER",
        upgrade = "UPGRADE",
        max_lv = "MAX",
        skins = "HULL SKINS",
        trails = "ENGINE TRAILS",
        dash = "DASH",
        language = "LANG",
        sound = "SOUND",
        on = "ON",
        off = "OFF",
        boss_gen = "GENERATORS",
        boss_turret = "TURRETS",
        boss_reactor = "REACTOR CORE",
        class_interceptor = "INTERCEPTOR",
        class_fighter = "FIGHTER",
        class_frigate = "FRIGATE",
        role_interceptor = "High speed • Plasma • Flanker",
        role_fighter = "Balanced • Kinetic • Dogfighter",
        role_frigate = "Heavy tank • Railgun • Support",
        mod_microwarp = "WARP",
        mod_emp = "EMP",
        mod_micromissiles = "MISSILES",
        mod_overdrive = "OVERDRIVE",
        mod_energydome = "DOME",
        mod_repairdrone = "REPAIR",
        kills = "KILLS",
        you = "YOU",
    },
    pt = {
        game_title = "VOID CLASH 3D",
        hint_first_15 = "MIRE NO INIMIGO PARA TRAVAR E ATIRAR • SHIFT PARA IMPULSO",
        hint_dreadnought = "DESTRUA 3 GERADORES DE ESCUDO, TORRES E O REATOR!",
        mode_tdm = "MATA-MATA 4v4",
        mode_dom = "DOMINAÇÃO 3D",
        mode_boss = "ATAQUE AO DREADNOUGHT",
        victory = "VITÓRIA",
        defeat = "DERROTA",
        credits = "CRÉDITOS",
        parts = "PEÇAS",
        double_loot = "DOBRAR LOOT (AD)",
        next_battle = "PRÓXIMA BATALHA",
        hangar = "HANGAR",
        battle = "BATALHA",
        test_drive = "TESTAR +1 NÍVEL (AD)",
        test_drive_active = "PROTÓTIPO +1 NÍVEL ATIVO!",
        random_skin = "SKIN / RASTRO ALEATÓRIO (AD)",
        respawn_in = "RENASCER",
        locked = "TRAVA",
        shield = "ESCUDO",
        hull = "CASCO",
        weapon = "ARMA",
        engine = "MOTOR",
        tier = "NÍVEL",
        upgrade = "MELHORAR",
        max_lv = "MÁX",
        skins = "PINTURAS",
        trails = "RASTROS",
        dash = "IMPULSO",
        language = "IDIOMA",
        sound = "SOM",
        on = "LIG",
        off = "DESL",
        boss_gen = "GERADORES",
        boss_turret = "TORRES",
        boss_reactor = "REATOR",
        class_interceptor = "INTERCEPTOR",
        class_fighter = "CAÇA",
        class_frigate = "FRAGATA",
        role_interceptor = "Alta veloc. • Plasma • Flanco",
        role_fighter = "Equilibrado • Cinética • Combate",
        role_frigate = "Tanque • Canhão Rail • Suporte",
        mod_microwarp = "WARP",
        mod_emp = "EMP",
        mod_micromissiles = "MÍSSEIS",
        mod_overdrive = "TURBO",
        mod_energydome = "CÚPULA",
        mod_repairdrone = "REPARO",
        kills = "ABATES",
        you = "VOCÊ",
    },
    ru = {
        game_title = "VOID CLASH 3D",
        hint_first_15 = "НАВЕДИ ПРИЦЕЛ НА ВРАГА ДЛЯ АВТООГНЯ • SHIFT — ФОРСАЖ",
        hint_dreadnought = "СНЕСИ 3 ГЕНЕРАТОРА ЩИТА, ТУРЕЛИ И РЕАКТОР!",
        mode_tdm = "КОМАНДНЫЙ БОЙ 4v4",
        mode_dom = "ЗАХВАТ МАЯКОВ 3D",
        mode_boss = "ОХОТА НА ДРЕДНОУТ",
        victory = "ПОБЕДА",
        defeat = "ПОРАЖЕНИЕ",
        credits = "КРЕДИТЫ",
        parts = "ДЕТАЛИ",
        double_loot = "2X ДОБЫЧА (РЕКЛ.)",
        next_battle = "НОВЫЙ БОЙ",
        hangar = "АНГАР",
        battle = "В БОЙ",
        test_drive = "ТЕСТ-ДРАЙВ +1 ТИР (РЕКЛ.)",
        test_drive_active = "ПРОТОТИП +1 ТИР ГОТОВ!",
        random_skin = "СЛУЧАЙНЫЙ СКИН (РЕКЛ.)",
        respawn_in = "РЕСПАВН",
        locked = "ЗАХВАТ",
        shield = "ЩИТ",
        hull = "КОРПУС",
        weapon = "ОРУЖИЕ",
        engine = "ДВИГАТЕЛЬ",
        tier = "ТИР",
        upgrade = "УЛУЧШИТЬ",
        max_lv = "МАКС",
        skins = "РАСКРАСКИ",
        trails = "ШЛЕЙФЫ",
        dash = "ФОРСАЖ",
        language = "ЯЗЫК",
        sound = "ЗВУК",
        on = "ВКЛ",
        off = "ВЫКЛ",
        boss_gen = "ГЕНЕРАТОРЫ",
        boss_turret = "ТУРЕЛИ",
        boss_reactor = "РЕАКТОР",
        class_interceptor = "ПЕРЕХВАТЧИК",
        class_fighter = "ШТУРМОВИК",
        class_frigate = "ФРЕГАТ",
        role_interceptor = "Сверхбыстрый • Плазма • Фланги",
        role_fighter = "Универсал • Кинетика • Догфайт",
        role_frigate = "Танк • Рельсотрон • Поддержка",
        mod_microwarp = "ВАРП",
        mod_emp = "ЭМИ",
        mod_micromissiles = "РАКЕТЫ",
        mod_overdrive = "ФОРСАЖ+",
        mod_energydome = "КУПОЛ",
        mod_repairdrone = "РЕМОНТ",
        kills = "ФРАГИ",
        you = "ВЫ",
    },
    tr = {
        game_title = "VOID CLASH 3D",
        hint_first_15 = "KİLİTLEME VE OTOMATİK ATEŞ İÇİN NİŞAN AL • SHIFT HIZLANMA",
        hint_dreadnought = "3 KALKAN JENERATÖRÜNÜ, TARETLERİ VE REAKTÖRÜ YOK ET!",
        mode_tdm = "TAKIM SAVAŞI 4v4",
        mode_dom = "3D İŞARET FENERİ",
        mode_boss = "DREADNOUGHT BASKINI",
        victory = "ZAFER",
        defeat = "YENİLGİ",
        credits = "KREDİ",
        parts = "PARÇA",
        double_loot = "2X ÖDÜL (REKLAM)",
        next_battle = "SONRAKİ SAVAŞ",
        hangar = "HANGAR",
        battle = "SAVAŞ",
        test_drive = "TEST SÜRÜŞÜ +1 SEVİYE",
        test_drive_active = "PROTOTİP +1 SEVİYE HAZIR!",
        random_skin = "RASTGELE KAPLAMA (REKLAM)",
        respawn_in = "DOĞUŞ",
        locked = "KİLİT",
        shield = "KALKAN",
        hull = "GÖVDE",
        weapon = "SİLAH",
        engine = "MOTOR",
        tier = "SEVİYE",
        upgrade = "GELİŞTİR",
        max_lv = "MAKS",
        skins = "KAPLAMALAR",
        trails = "İZ RENKLERİ",
        dash = "DEPAR",
        language = "DİL",
        sound = "SES",
        on = "AÇIK",
        off = "KAPALI",
        boss_gen = "JENERATÖR",
        boss_turret = "TARETLER",
        boss_reactor = "REAKTÖR",
        class_interceptor = "ÖNLEYİCİ",
        class_fighter = "SAVAŞÇI",
        class_frigate = "FIRKATEYN",
        role_interceptor = "Yüksek Hız • Plazma • Akıncı",
        role_fighter = "Dengeli • Kinetik • İt Dalaşı",
        role_frigate = "Ağır Tank • Raylı Top • Destek",
        mod_microwarp = "SIÇRAMA",
        mod_emp = "EMP",
        mod_micromissiles = "FÜZELER",
        mod_overdrive = "AŞIRI YÜK",
        mod_energydome = "KUBBE",
        mod_repairdrone = "ONARIM",
        kills = "SKOR",
        you = "SEN",
    },
}

local current_lang = "en"

function M.detect_default()
    local info = sys.get_sys_info()
    local lang = string.lower(string.sub(info.language or "en", 1, 2))
    if STRINGS[lang] then
        current_lang = lang
    else
        current_lang = "en"
    end
    return current_lang
end

function M.set_language(lang)
    if STRINGS[lang] then
        current_lang = lang
    end
end

function M.get_language()
    return current_lang
end

function M.cycle_language()
    for i, l in ipairs(M.LANGUAGES) do
        if l == current_lang then
            local nxt = M.LANGUAGES[(i % #M.LANGUAGES) + 1]
            current_lang = nxt
            return nxt
        end
    end
    current_lang = "en"
    return "en"
end

function M.t(key)
    local dict = STRINGS[current_lang] or STRINGS.en
    return dict[key] or STRINGS.en[key] or key
end

return M
