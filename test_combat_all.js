const enemy_db = {};
const modules = {};
const hulls = {};

const DEF_K_CONSTANT = 100.0;

const TRINITY_SET_BONUSES = {
    1: { atk_speed_pct: 15, hp_regen_flat: 5 }, 
    2: { def_pct: 10, reflect_pct: 5 }, 
    3: { crit_chance: 12, atk_pct: 8 }, 
    4: { shield_regen_pct: 10, accuracy_flat: 50 }, 
    5: { missile_dmg_pct: 15, enemy_def_reduce_pct: 10 }, 
    6: { all_dmg_pct: 12, evasion_flat: 5 }, 
    7: { def_flat: 300, energy_dmg_pct: 10 }, 
    8: { shield_hp_pct: 20, crit_chance: 8 }, 
    9: { all_dmg_pct: 15, def_flat: 500 }, 
    10: { all_dmg_pct: 20, hp_regen_flat: 1000 } 
};

function build_all() {
    for (let zone = 1; zone <= 10; zone++) {
        const mult = Math.pow(2.2, zone - 1);
        
        hulls[zone] = {
            hp: Math.floor(80 * mult),
            slots: 6 + (2 * zone)
        };
        
        const c_atk = Math.floor(10 * mult); 
        const c_def = Math.floor(5 * mult);
        const c_hp = Math.floor(20 * mult);
        const c_shield = Math.floor(40 * mult);
        const c_sregen = Math.ceil(c_shield * 0.05); 
        
        modules[`z${zone}_common`] = {
            atk: c_atk, atk_interval: 2.0, def: c_def, hp: c_hp, max_shield: c_shield, shield_regen: c_sregen
        };
        
        const U_MULT = 1.6; 
        
        modules[`z${zone}_unique`] = {
            atk: Math.floor(c_atk * U_MULT),
            atk_interval: 2.0,
            def: Math.floor(c_def * U_MULT),
            hp: Math.floor(c_hp * U_MULT),
            max_shield: Math.floor(c_shield * U_MULT),
            shield_regen: Math.ceil(c_shield * U_MULT * 0.05)
        };
        
        // ABSOLUTE WALL FORMULA
        let hp_mult = 6.0 + (zone - 1) * 6.0; 
        let atk_mult = 4.0 + (zone * 0.5); 
        
        enemy_db[`z${zone}_boss`] = {
            hp: Math.floor(200 * mult * hp_mult),
            atk: Math.floor(12 * mult * atk_mult),
            def: Math.floor(3 * mult * 6.0), 
            max_shield: Math.floor(40 * mult * 3.0),
            atk_interval: 2.5 
        };
    }
}

function run_sim(p_zone, is_unique, e_zone, hull_tier, has_affixes = false, infinite_consumables = false) {
    const p_hull = hulls[hull_tier];
    const p_base_mod = is_unique ? modules[`z${p_zone}_unique`] : modules[`z${p_zone}_common`];
    const e_target = enemy_db[`z${e_zone}_boss`];
    
    const num_wep = Math.ceil(p_hull.slots * 0.5);
    const num_shd = Math.floor(p_hull.slots * 0.25);
    const num_arm = Math.floor(p_hull.slots * 0.25);
    
    const rarity_stat_mult = is_unique ? 1.25 : 1.0;
    
    let max_hp = p_hull.hp + (p_base_mod.hp * num_arm * rarity_stat_mult);
    let max_shield = (p_base_mod.max_shield * num_shd * rarity_stat_mult);
    let shield_regen = (p_base_mod.shield_regen * num_shd * rarity_stat_mult);
    let defense = (p_base_mod.def * num_arm * rarity_stat_mult);
    let hp_regen = 0;
    
    let atk_val = (p_base_mod.atk * num_wep * rarity_stat_mult);
    let atk_speed_mult = 1.0;
    let dmg_mult = 1.0;
    let enemy_def_mult = 1.0;

    if (is_unique) {
        const bonus = TRINITY_SET_BONUSES[p_zone];
        if (bonus.atk_speed_pct) atk_speed_mult += (bonus.atk_speed_pct / 100);
        if (bonus.hp_regen_flat) hp_regen += bonus.hp_regen_flat;
        if (bonus.def_pct) defense *= (1.0 + bonus.def_pct / 100);
        if (bonus.atk_pct) dmg_mult += (bonus.atk_pct / 100);
        if (bonus.all_dmg_pct) dmg_mult += (bonus.all_dmg_pct / 100);
        if (bonus.energy_dmg_pct) dmg_mult += (bonus.energy_dmg_pct / 100);
        if (bonus.missile_dmg_pct) dmg_mult += (bonus.missile_dmg_pct / 100);
        if (bonus.enemy_def_reduce_pct) enemy_def_mult -= (bonus.enemy_def_reduce_pct / 100);
        if (bonus.def_flat) defense += bonus.def_flat;
        if (bonus.shield_hp_pct) max_shield *= (1.0 + bonus.shield_hp_pct / 100);
        if (bonus.shield_regen_pct) shield_regen *= (1.0 + bonus.shield_regen_pct / 100);
    }
    
    if (has_affixes) {
        dmg_mult += 0.50; 
        max_shield *= 1.50;
        defense += (10 * p_zone * num_arm);
    }

    const player_dps = (atk_val * dmg_mult) / (p_base_mod.atk_interval / atk_speed_mult);
    const boss_raw_dps = e_target.atk / e_target.atk_interval;
    const player_dmg_red = defense / (defense + DEF_K_CONSTANT);
    const boss_eff_dps = boss_raw_dps * (1.0 - player_dmg_red);
    
    const boss_hp = e_target.hp;
    const boss_shield = e_target.max_shield;
    const boss_def = e_target.def * enemy_def_mult;
    const boss_dmg_red = boss_def / (boss_def + DEF_K_CONSTANT);
    const boss_ehp = (boss_hp / (1.0 - boss_dmg_red)) + boss_shield;

    let p_curr_hp = max_hp;
    let p_curr_shd = max_shield;
    let e_curr_ehp = boss_ehp;
    let time = 0;
    
    let consumable_cooldown = 0;
    const H_HEAL = 0.50; // AdvMaintenanceKit
    const S_HEAL = 0.50; // ZeroPoint
    
    while (time < 600) { 
        time += 1;
        
        // Consumables logic
        if (infinite_consumables && consumable_cooldown <= 0) {
            if (p_curr_shd < max_shield * 0.8) {
                p_curr_shd = Math.min(max_shield, p_curr_shd + max_shield * S_HEAL);
                consumable_cooldown = 1.5;
            } else if (p_curr_hp < max_hp * 0.8) {
                p_curr_hp = Math.min(max_hp, p_curr_hp + max_hp * H_HEAL);
                consumable_cooldown = 1.5;
            }
        }
        if (consumable_cooldown > 0) consumable_cooldown -= 1;

        let dmg_to_p = boss_eff_dps;
        let absorbed = Math.min(p_curr_shd, dmg_to_p);
        p_curr_shd -= absorbed;
        let bleed = dmg_to_p - absorbed;
        p_curr_hp -= bleed;
        
        e_curr_ehp -= player_dps;
        
        if (p_curr_hp <= 0) break;
        if (e_curr_ehp <= 0) break;
        
        p_curr_shd = Math.min(max_shield, p_curr_shd + shield_regen);
        p_curr_hp = Math.min(max_hp, p_curr_hp + hp_regen);
    }

    const won = e_curr_ehp <= 0;
    const result = won ? "WIN " : "LOSE";
    
    return [
        p_zone, e_zone, result,
        time.toFixed(0) + "s", 
        player_dps.toFixed(0),
        boss_eff_dps.toFixed(0),
        e_curr_ehp <= 0 ? "0" : e_curr_ehp.toFixed(0)
    ];
}

build_all();

console.log("=== PERFORMANCE TEST: Z(N) UNIQUE vs Z(N+1) BOSS ===");
console.log("| Case                  | RES  | TIME  | Player DPS | Boss DPS | Boss End EHP |");
for (let n = 1; n < 10; n++) {
    let [pz, ez, res, t, pd, ed, be] = run_sim(n, true, n + 1, n + 1, false, false);
    let label = `Z${n} U vs Z${n+1} B`.padEnd(21, ' ');
    console.log(`| ${label} | ${res} | ${t.padStart(5, ' ')} | ${pd.padStart(10, ' ')} | ${ed.padStart(8, ' ')} | ${be.padStart(12, ' ')} |`);
}

console.log("\n=== CONSUMABLE TEST: Z1 UNIQUE vs Z2 BOSS (INFINITE ITEMS) ===");
let [pz2, ez2, res2, t2, pd2, ed2, be2] = run_sim(1, true, 2, 1, true, true);
let label2 = `Z1 U+GA vs Z2 B`.padEnd(21, ' ');
console.log(`| ${label2} | ${res2} | ${t2.padStart(5, ' ')} | ${pd2.padStart(10, ' ')} | ${ed2.padStart(8, ' ')} | ${be2.padStart(12, ' ')} |`);

console.log("\n=== CONSUMABLE TEST: Z1 UNIQUE vs Z3 BOSS (INFINITE ITEMS) ===");
let [pz3, ez3, res3, t3, pd3, ed3, be3] = run_sim(1, true, 3, 1, true, true);
let label3 = `Z1 U+GA vs Z3 B`.padEnd(21, ' ');
console.log(`| ${label3} | ${res3} | ${t3.padStart(5, ' ')} | ${pd3.padStart(10, ' ')} | ${ed3.padStart(8, ' ')} | ${be3.padStart(12, ' ')} |`);
