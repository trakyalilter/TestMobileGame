/**
 * Progression Pacing Simulation v1.1
 * Fixed mission logic and expanded tech tree.
 */

// --- DATA: MISSIONS (Corrected structure) ---
const MISSIONS = [
    { id: "m001", type: "gather", item: "Dirt", qty: 350 },
    { id: "m002", type: "research", tech: "basic_engineering" },
    { id: "m002b", type: "research", tech: "applied_physics" },
    { id: "m003", type: "research", tech: "fluid_dynamics" },
    { id: "m004", type: "gather", item: "Water", qty: 350 },
    { id: "m005", type: "gather_multi", items: { Si: 100, Fe: 80 } },
    { id: "m007", type: "craft", module: "z1_engine" },
    { id: "m008", type: "research", tech: "materials_science" },
    { id: "m009", type: "gather", item: "Wood", qty: 100 },
    { id: "m010", type: "research", tech: "combustion" },
    { id: "m011", type: "gather", item: "C", qty: 50 },
    { id: "m012", type: "gather", item: "Spodumene", qty: 100 },
    { id: "m013", type: "gather", item: "Li", qty: 50 },
    { id: "m013b", type: "gather", item: "Malachite", qty: 100 },
    { id: "m013c", type: "gather", item: "Cu", qty: 50 },
    { id: "m020", type: "research", tech: "power_systems" },
    { id: "m021", type: "gather", item: "BatteryT1", qty: 5 },
    { id: "m022", type: "craft", module: "z1_battery" },
    { id: "m014", type: "research", tech: "kinetics_101" },
    { id: "m015", type: "craft", module: "z1_kinetic" },
    { id: "m016", type: "gather", item: "SlugT1", qty: 100 },
    { id: "m023", type: "research", tech: "energy_shields" },
    { id: "m024", type: "craft", module: "z1_shield" },
    { id: "m016b", type: "loadout_check" },
    { id: "m017", type: "defeat", enemy: "z1_drone", qty: 1 },
    { id: "m018", type: "research", tech: "industrial_logistics" },
    { id: "m018b", type: "research", tech: "automated_logistics" },
    { id: "m019", type: "gather", item: "Circuit", qty: 10 },
    { id: "m025", type: "research", tech: "smelting" },
    { id: "m025b", type: "gather", item: "Steel", qty: 50 },
    { id: "m026", type: "research", tech: "shipwright_1" },
    { id: "m026b", type: "construct", hull: "frigate_hull" },
    { id: "m026c", type: "drop_rarity", rarity: 2 },
    { id: "m026d", type: "loadout_rarity", rarity: 2 },
    { id: "m026e", type: "defeat", enemy: "z1_boss", qty: 1 },
    { id: "m027", type: "research", tech: "zone_2_access" },
    { id: "m028", type: "gather", item: "Sn", qty: 100 },
    { id: "m029", type: "craft", module: "z2_armor" },
    { id: "m029b", type: "gather", item: "AdvCircuit", qty: 10 },
    { id: "m030", type: "research", tech: "shipwright_2" },
    { id: "m030b", type: "build", building: "fabricator" },
    { id: "m030c", type: "construct", hull: "destroyer_hull" },
    { id: "m031", type: "research", tech: "sector_alpha_decryption" },
    { id: "m032", type: "defeat", enemy: "z5_frigate", qty: 3 },
    { id: "m032b", type: "research", tech: "deep_space_nav" },
    { id: "m032d", type: "gather", item: "VoidArtifact", qty: 5 },
    { id: "m032c", type: "construct", hull: "battlecruiser_hull" },
    { id: "m033", type: "defeat", enemy: "z6_guardian", qty: 5 },
    { id: "m033b", type: "research", tech: "radiation_shielding" },
    { id: "m033c", type: "construct", hull: "dreadnought_hull" },
    { id: "m034", type: "defeat", enemy: "z6_boss", qty: 3 },
];

// --- DATA: TECH TREE ---
const TECH_TREE = {
    "basic_engineering": { cost: 125, materials: {} },
    "applied_physics": { cost: 625, materials: {}, parent: "basic_engineering" },
    "materials_science": { cost: 625, materials: {}, parent: "basic_engineering" },
    "industrial_logistics": { cost: 625, materials: {}, parent: "basic_engineering" },
    "fluid_dynamics": { cost: 125, materials: {}, parent: "applied_physics" },
    "combustion": { cost: 125, materials: {}, parent: "materials_science" },
    "smelting": { cost: 3750, materials: { Res1: 20, Circuit: 10 }, parent: "combustion" },
    "shipwright_1": { cost: 50000, materials: { Steel: 40, Res1: 40, Circuit: 20 }, parent: "power_systems" },
    "shipwright_2": { cost: 1000000, materials: { Res2: 50 }, parent: "shipwright_1" },
    "adv_materials": { cost: 5000, materials: { Res2: 10 }, parent: "smelting" },
    "energy_shields": { cost: 1250, materials: {}, parent: "applied_physics" },
    "automation": { cost: 12500, materials: { Res2: 50, Circuit: 40 }, parent: "adv_materials" },
    "power_systems": { cost: 300, materials: {}, parent: "kinetics_101" },
    "kinetics_101": { cost: 50, materials: {}, parent: "applied_physics" },
    "automated_logistics": { cost: 3000, materials: { Cu: 50, Fe: 100, Res1: 50 }, parent: "industrial_logistics" },
    "zone_2_access": { cost: 30000, materials: { Z1_Core: 1, Fe: 400, Cu: 200 } },
    "zone_3_access": { cost: 75000, materials: { Z2_Core: 1, Steel: 200, Ti: 100 } },
    "zone_4_access": { cost: 187500, materials: { Z3_Core: 2, Ti: 400, Circuit: 100 } },
    "zone_5_access": { cost: 468750, materials: { Z4_Core: 2, AdvCircuit: 200, Superalloy: 50 } },
    "warp_drive": { cost: 12500, materials: { NavData: 100, Ti: 400, Res3: 20 }, parent: "shipwright_2" },
    "sector_alpha_decryption": { cost: 50000, materials: { NavData: 30, Res1: 100 }, parent: "zone_5_access" },
    "deep_space_nav": { cost: 100000, materials: { NavData: 50, Ti: 300, Res3: 20 }, parent: "warp_drive" },
    "radiation_shielding": { cost: 250000, materials: { Co: 100, Al: 200, Superalloy: 50, AdvCircuit: 30 }, parent: "deep_space_nav" },
};

// --- DATA: RECIPES ---
const RECIPES = {
    "Steel": { input: { Fe: 5, C: 2 }, output: 5, duration: 5 },
    "Li": { input: { Spodumene: 2 }, output: 1, duration: 5 },
    "Cu": { input: { Malachite: 2, C: 1 }, output: 1, duration: 5 },
    "Sn": { input: { Cassiterite: 3, C: 1 }, output: 2, duration: 6 },
    "Si": { input: { Quartz: 2, C: 1 }, output: 1, duration: 6 },
    "C": { input: { Wood: 5 }, output: 10, duration: 4 },
    "Circuit": { input: { Cu: 3, Si: 4 }, output: 2, duration: 6 },
    "Semiconductor": { input: { Si: 2, Germanium: 1 }, output: 1, duration: 10 },
    "AdvCircuit": { input: { Semiconductor: 1, Au: 1 }, output: 1, duration: 15 },
    "SlugT1": { input: { Fe: 1 }, output: 20, duration: 5 },
    "BatteryT1": { input: { Li: 5, Fe: 2 }, output: 1, duration: 10 },
    "Res2": { input: { Res1: 100, Circuit: 10 }, output: 1, duration: 8 },
    "Res3": { input: { Res2: 5, AdvCircuit: 2, NavData: 5 }, output: 1, duration: 60 },
};

// --- DATA: GATHERING ---
const GATHERING = {
    "Dirt": 1.5, 
    "Water": 1.5,
    "Wood": 1.0,
    "Spodumene": 0.4,
    "Malachite": 0.6,
    "Cassiterite": 0.3,
    "Quartz": 0.25,
    "Germanium": 0.05,
    "Au": 0.05,
    "Ti": 0.2,
    "Co": 0.1,
    "Al": 0.2,
    "Superalloy": 0.05,
};

// --- SIMULATION ENGINE ---
function run_pacing_sim(persona = "active") {
    let state = {
        credits: 0,
        resources: { Dirt: 0, Water: 0, Wood: 0, Spodumene: 0, Malachite: 0, Cassiterite: 0, Quartz: 0, Fe: 0, Si: 0, C: 0, Li: 0, Cu: 0, Sn: 0, Steel: 0, Circuit: 0, AdvCircuit: 0, Res1: 0, Res2: 0, Res3: 0, NavData: 0, VoidArtifact: 0, SlugT1: 0, BatteryT1: 0, Z1_Core: 0, Z2_Core: 0, Z3_Core: 0, Z4_Core: 0, Ti: 0, Au: 0, Germanium: 0, Co: 0, Al: 0, Superalloy: 0 },
        unlocked_techs: new Set(),
        active_mission_idx: 0,
        total_time: 0,
        log: []
    };

    const add_time = (s, reason) => {
        state.total_time += s;
        // Basic income during time spent
        if (persona === "active") {
            state.credits += s * 10; // Active players sell surplus
        } else {
            state.credits += s * 2;
        }
    };

    while (state.active_mission_idx < MISSIONS.length) {
        let m = MISSIONS[state.active_mission_idx];
        let start_time = state.total_time;

        if (m.type === "research") {
            let tech = TECH_TREE[m.tech];
            if (!tech) {
                console.error(`MISSING TECH: ${m.tech}`);
                break;
            }
            // Materials
            for (let [item, qty] of Object.entries(tech.materials)) {
                let time = simulate_get_resource(state, item, qty, persona);
                add_time(time, `Gathering ${item} for ${m.tech}`);
                state.resources[item] -= qty;
            }
            // Credits
            let needed_cr = tech.cost - state.credits;
            if (needed_cr > 0) {
                add_time(needed_cr / (persona === "active" ? 100 : 10), "Farming credits"); // Adjusted late game credit income
                state.credits -= tech.cost;
            } else {
                state.credits -= tech.cost;
            }
            state.unlocked_techs.add(m.tech);
            add_time(10, "Researching...");
        } 
        else if (m.type === "gather") {
            let time = simulate_get_resource(state, m.item, m.qty, persona);
            add_time(time, `Mission: ${m.id}`);
            state.resources[m.item] -= m.qty;
        }
        else if (m.type === "gather_multi") {
            for (let [item, qty] of Object.entries(m.items)) {
                let time = simulate_get_resource(state, item, qty, persona);
                add_time(time, `Mission: ${m.id}`);
                state.resources[item] -= qty;
            }
        }
        else if (m.type === "defeat") {
            let time = m.enemy.includes("boss") ? 300 : 60 * m.qty;
            add_time(time, `Combat: ${m.id}`);
            if (m.enemy === "z1_boss") state.resources.Z1_Core = 1;

            // General loot during combat - v1.2: ZONE SCALING LOOT
            let current_zone = m.enemy.startsWith("z1") ? 1 : m.enemy.startsWith("z2") ? 2 : m.enemy.startsWith("z3") ? 3 : 5;
            state.resources.Res1 += 50 * m.qty;
            state.resources.NavData += 10 * m.qty;
            if (current_zone >= 3) {
                state.resources.Res2 += 5 * m.qty; // Direct Res2 drops start in Z3!
            }
        }
        else if (m.type === "craft" || m.type === "construct") {
            add_time(120, `Crafting/Building ${m.id}`);
        }
        else if (m.type.includes("rarity") || m.type.includes("check")) {
            add_time(300, `Wait for drop/equip ${m.id}`);
        }

        state.log.push({ id: m.id, duration: state.total_time - start_time, total: state.total_time });
        state.active_mission_idx++;
    }

    return state;
}

function simulate_get_resource(state, item, qty, persona) {
    if ((state.resources[item] || 0) >= qty) return 0;
    let needed = qty - (state.resources[item] || 0);

    if (GATHERING[item]) {
        let time = needed / GATHERING[item];
        state.resources[item] += needed;
        return time;
    }

    if (RECIPES[item]) {
        let recipe = RECIPES[item];
        let total_time = 0;
        let loops = Math.ceil(needed / recipe.output);
        for (let i = 0; i < loops; i++) {
            for (let [inp, iqty] of Object.entries(recipe.input)) {
                total_time += simulate_get_resource(state, inp, iqty, persona);
                state.resources[inp] -= iqty;
            }
            total_time += recipe.duration;
            state.resources[item] += recipe.output;
        }
        return total_time;
    }

    // Combat-only items
    // v1.2 logic: if they have zone_3_access, they can farm Res2 at a high rate.
    // Otherwise, they must CRAFT it (which handled by RECIPES block above).
    const COMBAT_ITEMS = { 
        Res1: 0.5, 
        NavData: 0.1, 
        VoidArtifact: 0.05, 
        Res2: state.unlocked_techs.has("shipwright_2") ? 0.2 : 0, // Gated direct farming!
        Res3: state.unlocked_techs.has("zone_6_access") ? 0.1 : 0, 
        Z1_Core: 0 
    };
    if (COMBAT_ITEMS[item] !== undefined) {
        let rate = COMBAT_ITEMS[item];
        if (rate === 0) return 0; 
        let time = needed / rate;
        state.resources[item] += needed;
        return time;
    }

    return 0;
}

console.log("=== PROGRESSION PACING SIMULATION v1.1 ===");
let active = run_pacing_sim("active");
active.log.forEach(l => {
    let t = l.total;
    let time_str = `${Math.floor(t / 3600)}h ${Math.floor((t % 3600) / 60)}m ${Math.floor(t % 60)}s`;
    console.log(`| ${l.id.padEnd(5)} | +${Math.floor(l.duration).toString().padStart(6)}s | Total: ${time_str.padStart(12)} |`);
});
console.log(`\nTOTAL TIME (Active): ${(active.total_time / 3600).toFixed(2)} hours`);
