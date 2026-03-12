const enemy_db = {};
const modules = {};
const hulls = {};

// v80.1 Safety Caps
const MAX_ATK_SPEED_MULT = 3.0;
const MAX_EVASION = 75;
const MAX_CRIT_CHANCE = 0.50;
const DEF_K_CONSTANT = 100.0;

function build_zone(zone) {
    const mult = Math.pow(2.2, zone - 1);
    
    enemy_db[`z${zone}_reg`] = {
        hp: Math.floor(200 * mult),
        atk: Math.floor(12 * mult),
        def: Math.floor(3 * mult),
        max_shield: Math.floor(50 * mult),
        atk_interval: 2.5
    };
    
    // REDUCED BOSS MULTIPLIERS to make them beatable by same-zone legendaries
    // HP 8x -> 6x
    // ATK 3x -> 2.5x
    // DEF 4x -> 3x
    enemy_db[`z${zone}_boss`] = {
        hp: Math.floor(200 * mult) * 6,
        atk: Math.floor(12 * mult) * 2.5,
        def: Math.floor(3 * mult) * 3,
        max_shield: Math.floor(50 * mult) * 4,
        atk_interval: 2.5
    };
    
    hulls[zone] = {
        hp: Math.floor(80 * mult),
        slots: Math.min(6 + (zone * 2), 26)
    };
    
    modules[`z${zone}_common`] = {
        atk: Math.floor(9 * mult),
        atk_interval: 2.0,
        def: Math.floor(5 * mult),
        hp: Math.floor(20 * mult),
        max_shield: Math.floor(40 * mult)
    };
    
    modules[`z${zone}_unique`] = {
        atk: Math.floor(9 * mult * 1.8),
        atk_interval: 2.0,
        def: Math.floor(5 * mult * 1.8),
        hp: Math.floor(20 * mult * 1.8),
        max_shield: Math.floor(40 * mult * 1.8)
    };
}

function run_sim(player_zone, is_unique, enemy_zone, is_boss, rarity_mult = 1.25) {
    const p_hull = hulls[player_zone];
    const p_mod = is_unique ? modules[`z${player_zone}_unique`] : modules[`z${player_zone}_common`];
    const e_target = is_boss ? enemy_db[`z${enemy_zone}_boss`] : enemy_db[`z${enemy_zone}_reg`];
    
    const num_wep = Math.floor(p_hull.slots / 3.0);
    const num_shd = Math.floor(p_hull.slots / 3.0);
    const num_arm = Math.floor(p_hull.slots / 3.0);
    
    const set_dmg = is_unique ? 1.15 : 1.00;
    const set_def = is_unique ? 500 : 0;

    const p_atk = (p_mod.atk * num_wep * rarity_mult) * set_dmg;
    const p_def = (p_mod.def * num_arm * rarity_mult) + set_def;
    const p_hp = p_hull.hp + (p_mod.hp * num_arm * rarity_mult);
    const p_shield = (p_mod.max_shield * num_shd * rarity_mult);
    
    const edmg_red = p_def / (p_def + DEF_K_CONSTANT);
    const p_ehp = (p_hp / (1.0 - edmg_red)) + p_shield;
    
    const e_dps = e_target.atk / e_target.atk_interval;
    const ttk_player = e_dps > 0 ? p_ehp / e_dps : 99999;
    
    const pdmg_red = e_target.def / (e_target.def + DEF_K_CONSTANT);
    const e_ehp = (e_target.hp / (1.0 - pdmg_red)) + e_target.max_shield;
    
    const p_dps = p_atk / p_mod.atk_interval;
    const ttk_enemy = p_dps > 0 ? e_ehp / p_dps : 99999;
    
    const gear_lbl = `Z${player_zone} ${is_unique ? "Unique" : (rarity_mult === 1.20 ? "Legendary" : "Common")}`;
    const e_lbl = `Z${enemy_zone} ${is_boss ? "Boss" : "Regular"}`;
    
    console.log(`\n--- ${gear_lbl} vs ${e_lbl} ---`);
    console.log(`Player: ${p_dps.toFixed(0)} DPS | ${p_ehp.toFixed(0)} EHP [Time To Die: ${ttk_player.toFixed(1)}s]`);
    console.log(`Enemy : ${e_dps.toFixed(0)} DPS | ${e_ehp.toFixed(0)} EHP [Time To Die: ${ttk_enemy.toFixed(1)}s]`);
    
    if (ttk_player > ttk_enemy) {
        console.log(`RESULT: Player WINS comfortably (Survives by ${(ttk_player - ttk_enemy).toFixed(1)}s)`);
    } else {
        console.log(`RESULT: Player LOSES (Dies ${(ttk_enemy - ttk_player).toFixed(1)}s before enemy)`);
    }
}

for (let i = 1; i <= 11; i++) {
    build_zone(i);
}

run_sim(4, true, 5, true); // Z4 Unique vs Z5 Boss (Expect Loss)
run_sim(5, false, 5, true, 1.20); // Z5 Legendary vs Z5 Boss (Expect Win)
