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
    
    // Zone 1
    if (zone === 1) {
        hulls[1] = { hp: 120, slots: 8 }; // Corvette
        modules[`z1_common`] = { atk: 9, atk_interval: 2.0, def: 5, hp: 20, max_shield: 40 };
        modules[`z1_unique`] = { atk: 18, atk_interval: 2.0, def: 9, hp: 36, max_shield: 72 };
    }
    // Zone 2
    else if (zone === 2) {
        hulls[2] = { hp: 200, slots: 10 }; // Frigate
        enemy_db[`z2_boss`] = {
            hp: 2880, atk: 66, def: 21, max_shield: 264, atk_interval: 3.5
        };
        modules[`z2_common`] = { atk: 18, atk_interval: 2.0, def: 11, hp: 44, max_shield: 88 };
        modules[`z2_unique`] = { atk: 32, atk_interval: 2.0, def: 20, hp: 79, max_shield: 158 };
    }
}

function run_sim(player_zone, is_unique, enemy_zone, is_boss, rarity_mult = 1.25, hull_tier) {
    const p_hull = hulls[hull_tier];
    const p_mod = is_unique ? modules[`z${player_zone}_unique`] : modules[`z${player_zone}_common`];
    const e_target = enemy_db[`z${enemy_zone}_boss`];
    
    // 8 slots for Corvette, 10 for Frigate. Let's assume an offensive setup: 50% Weapons, 25% Shield, 25% Armor
    const num_wep = Math.ceil(p_hull.slots * 0.5);
    const num_shd = Math.floor(p_hull.slots * 0.25);
    const num_arm = Math.floor(p_hull.slots * 0.25);
    
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
    
    console.log(`\n--- ${gear_lbl} on Tier ${hull_tier} Hull vs ${e_lbl} ---`);
    console.log(`Player: ${p_dps.toFixed(0)} DPS | ${p_ehp.toFixed(0)} EHP ${is_unique ? '(Set DEF Bonus active!)' : ''} [Time To Die: ${ttk_player.toFixed(1)}s]`);
    console.log(`Enemy : ${e_dps.toFixed(0)} DPS | ${e_ehp.toFixed(0)} EHP [Time To Die: ${ttk_enemy.toFixed(1)}s]`);
    
    if (ttk_player > ttk_enemy) {
        console.log(`RESULT: Player WINS comfortably (Survives by ${(ttk_player - ttk_enemy).toFixed(1)}s)`);
    } else {
        console.log(`RESULT: Player LOSES (Dies ${(ttk_enemy - ttk_player).toFixed(1)}s before enemy)`);
    }
}

build_zone(1);
build_zone(2);

// Let's test what happens if the player takes their Z1 uniques and puts them on the Z1 Corvette
run_sim(1, true, 2, true, 1.25, 1);

// Let's test what happens if the player takes their Z1 uniques and puts them on the Z2 Frigate (more slots, more HP)
run_sim(1, true, 2, true, 1.25, 2);
