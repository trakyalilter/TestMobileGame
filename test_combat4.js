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
        modules[`z1_common`] = { atk: 9, atk_interval: 2.0, def: 5, hp: 20, max_shield: 40, set_bonus_atk_speed: 0, set_bonus_hp_regen: 0 };
        // NERF: hp_regen dropped from 20 to 5
        modules[`z1_unique`] = { atk: 18, atk_interval: 2.0, def: 9, hp: 36, max_shield: 72, set_bonus_atk_speed: 1.15, set_bonus_hp_regen: 5 };
    }
    // Zone 2
    else if (zone === 2) {
        hulls[2] = { hp: 200, slots: 10 }; // Frigate
        enemy_db[`z2_boss`] = {
            // NOTE: The previous plan raised HP to 4000. Let's see if 4000 is needed with the regen nerf.
            // I'll test it at 4000.
            hp: 4000, atk: 66, def: 21, max_shield: 264, atk_interval: 3.5
        };
        modules[`z2_common`] = { atk: 18, atk_interval: 2.0, def: 11, hp: 44, max_shield: 88, set_bonus_def_mult: 1.0, set_bonus_reflect: 0 };
        modules[`z2_unique`] = { atk: 32, atk_interval: 2.0, def: 20, hp: 79, max_shield: 158, set_bonus_def_mult: 1.10, set_bonus_reflect: 0.05 };
    }
}

function run_sim(player_zone, is_unique, enemy_zone, is_boss, rarity_mult = 1.25, hull_tier, has_affixes = false) {
    const p_hull = hulls[hull_tier];
    const p_mod = is_unique ? modules[`z${player_zone}_unique`] : modules[`z${player_zone}_common`];
    const e_target = enemy_db[`z${enemy_zone}_boss`];
    
    // 8 slots for Corvette, 10 for Frigate. Let's assume an offensive setup: 50% Weapons, 25% Shield, 25% Armor
    const num_wep = Math.ceil(p_hull.slots * 0.5);
    const num_shd = Math.floor(p_hull.slots * 0.25);
    const num_arm = Math.floor(p_hull.slots * 0.25);
    
    // Affixes: Let's assume on average, 3 affixes per Unique item.
    // If we have 10 slots * 3 affixes = 30 affixes.
    // Let's assume 10 goes to ATK, 10 goes to DEF/HP, 10 goes to Shields
    // Assuming mid-rolls (like +5% ATK per affix, or +10 flat DEF)
    const affix_atk_mult = has_affixes ? 1.50 : 1.0; 
    const affix_def_flat = has_affixes ? (10 * player_zone * num_arm) : 0;
    const affix_shield_mult = has_affixes ? 1.50 : 1.0; 

    // Set Bonuses (If Unique, assume full set is active)
    let p_atk_interval = p_mod.atk_interval;
    let p_hp_regen = 0;
    let p_def_mult = 1.0;
    
    if (is_unique) {
        if (player_zone === 1) { // Architect's Regalia
            p_atk_interval = p_mod.atk_interval / p_mod.set_bonus_atk_speed;
            p_hp_regen = p_mod.set_bonus_hp_regen;
        } else if (player_zone === 2) { // Monolith's Bedrock
            p_def_mult = p_mod.set_bonus_def_mult;
        }
    }

    const p_atk = (p_mod.atk * num_wep * rarity_mult) * affix_atk_mult;
    let p_def = ((p_mod.def * num_arm * rarity_mult) + affix_def_flat) * p_def_mult;
    const p_hp = p_hull.hp + (p_mod.hp * num_arm * rarity_mult);
    const p_shield = (p_mod.max_shield * num_shd * rarity_mult) * affix_shield_mult;
    
    const edmg_red = p_def / (p_def + DEF_K_CONSTANT);
    const e_dps = e_target.atk / e_target.atk_interval;
    const e_actual_dps = Math.max(1, e_dps * (1.0 - edmg_red));
    
    // EHP math with actual damage reduction and HP regen factored in over time
    // Roughly EHP = (HP + Shield) / DPS ... but if we regen 5 HP/sec, actual incoming DPS is lower!
    const effective_incoming_dps = Math.max(0.1, e_actual_dps - p_hp_regen); 
    const ttk_player = (p_hp + p_shield) / effective_incoming_dps;

    const pdmg_red = e_target.def / (e_target.def + DEF_K_CONSTANT);
    const e_ehp = (e_target.hp / (1.0 - pdmg_red)) + e_target.max_shield;
    
    const p_dps = p_atk / p_atk_interval;
    const ttk_enemy = p_dps > 0 ? e_ehp / p_dps : 99999;
    
    const gear_lbl = `Z${player_zone} ${is_unique ? "Unique" : (rarity_mult === 1.20 ? "Legendary" : "Common")}`;
    const e_lbl = `Z${enemy_zone} ${is_boss ? "Boss" : "Regular"}`;
    
    console.log(`\n--- ${gear_lbl} on Tier ${hull_tier} Hull vs ${e_lbl} ---`);
    console.log(`Player: ${p_dps.toFixed(0)} DPS | ${p_hp.toFixed(0)} HP | ${p_shield.toFixed(0)} Shield | ${p_def.toFixed(0)} DEF | ${p_hp_regen} Regen/s`);
    if (has_affixes) console.log(` >> (Affixes Active)`);
    if (is_unique) console.log(` >> (Set Bonuses Active)`);
    console.log(`Enemy : ${e_dps.toFixed(0)} Raw DPS -> ${effective_incoming_dps.toFixed(0)} Effective DPS | ${e_ehp.toFixed(0)} EHP`);
    
    console.log(`Time To Die (Player): ${ttk_player.toFixed(1)}s`);
    console.log(`Time To Die (Enemy) : ${ttk_enemy.toFixed(1)}s`);

    if (ttk_player > ttk_enemy) {
        console.log(`RESULT: Player WINS comfortably (Survives by ${(ttk_player - ttk_enemy).toFixed(1)}s)`);
    } else {
        console.log(`RESULT: Player LOSES (Dies ${(ttk_enemy - ttk_player).toFixed(1)}s before enemy)`);
    }
}

build_zone(1);
build_zone(2);

// Standard Z1 Unique on Corvette (No random affixes)
run_sim(1, true, 2, true, 1.25, 1, false);

// Standard Z1 Unique on Frigate (No random affixes)
run_sim(1, true, 2, true, 1.25, 2, false);

// Z1 Unique on Frigate WITH good Affixes (+50% ATK, +50% Shield, +Flat DEF)
run_sim(1, true, 2, true, 1.25, 2, true);
