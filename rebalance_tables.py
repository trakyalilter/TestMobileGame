import sys
import re

file_path = "scripts/managers/combat_manager.gd"
with open(file_path, "r", encoding="utf-8") as f:
    code = f.read()

# The definitive re-mapped drop pools that align with crafting progression:
# This ensures Sector Gamma drops what's craftable AT Sector Gamma.

drop_pools = {
    # Luna/Asteroid Basic Enemies
    "dust_mite": '["mining_laser_mk1", "railgun_mk1", "battery_t1", "basic_shield", "basic_thruster", "lidar_array"]',
    "lunar_drone": '["mining_laser_mk1", "railgun_mk1", "battery_t1", "basic_shield", "basic_thruster", "lidar_array"]',
    "scrap_collector": '["mining_laser_mk1", "railgun_mk1", "battery_t1", "basic_shield", "basic_thruster", "lidar_array"]',
    "survey_probe": '["mining_laser_mk1", "railgun_mk1", "battery_t1", "basic_shield", "basic_thruster", "lidar_array"]',
    "claim_jumper": '["mining_laser_mk1", "railgun_mk1", "battery_t1", "basic_shield", "basic_thruster", "lidar_array"]',
    "ore_hauler": '["mining_laser_mk1", "railgun_mk1", "battery_t1", "basic_shield", "basic_thruster", "lidar_array"]',
    "derelict_frigate": '["mining_laser_mk1", "railgun_mk1", "battery_t1", "basic_shield", "basic_thruster", "lidar_array"]',
    "salvage_swarm": '["mining_laser_mk1", "railgun_mk1", "battery_t1", "basic_shield", "basic_thruster", "lidar_array"]',
    "frozen_hulk": '["mining_laser_mk1", "railgun_mk1", "battery_t1", "basic_shield", "basic_thruster", "lidar_array"]',
    "smuggler_cutter": '["mining_laser_mk1", "railgun_mk1", "battery_t1", "basic_shield", "basic_thruster", "lidar_array"]',
    
    # Mars/Titan / Early Midgame (Requires Ti, W, AdvCir)
    "pirate_skiff": '["mining_laser_mk2", "micro_missile_launcher", "heatsink_array", "battery_t2", "thermal_tile", "titanium_armor", "aluminum_hull_patch", "plasma_drive", "stasis_web"]',
    "rock_golem": '["mining_laser_mk2", "micro_missile_launcher", "heatsink_array", "battery_t2", "thermal_tile", "titanium_armor", "aluminum_hull_patch", "plasma_drive", "stasis_web"]',
    "scavenger_mech": '["mining_laser_mk2", "micro_missile_launcher", "heatsink_array", "battery_t2", "thermal_tile", "titanium_armor", "aluminum_hull_patch", "plasma_drive", "stasis_web"]',
    "martian_sentry": '["mining_laser_mk2", "micro_missile_launcher", "heatsink_array", "battery_t2", "thermal_tile", "titanium_armor", "aluminum_hull_patch", "plasma_drive", "stasis_web"]',
    "cryo_drone": '["mining_laser_mk2", "micro_missile_launcher", "heatsink_array", "battery_t2", "thermal_tile", "titanium_armor", "aluminum_hull_patch", "plasma_drive", "stasis_web"]',
    "pirate_gunship": '["mining_laser_mk2", "micro_missile_launcher", "heatsink_array", "battery_t2", "thermal_tile", "titanium_armor", "aluminum_hull_patch", "plasma_drive", "stasis_web"]',
    "titan_overseer": '["missile_launcher_mk2", "cryo_vent", "targeting_matrix", "railgun_mk2", "advanced_shield", "composite_armor", "mg_al_frame", "galvanized_plating", "battery_t3"]',

    # Sector Alpha/Beta (Superalloy, AICore, Co, Ni)
    "xenon_scout": '["railgun_mk3", "mining_laser_mk3", "composite_armor_mk2", "stainless_armor", "cobalt_battery_module"]',
    "alien_probe": '["railgun_mk3", "mining_laser_mk3", "composite_armor_mk2", "stainless_armor", "mg_battery_module"]',
    "alien_frigate": '["railgun_mk3", "mining_laser_mk3", "composite_armor_mk2", "stainless_armor", "superalloy_engine", "ai_targeting_system", "broadside_array"]',
    "xenon_corvette": '["railgun_mk3", "mining_laser_mk3", "composite_armor_mk2", "stainless_armor", "superalloy_engine", "ai_targeting_system", "signal_jammer"]',
    "xenon_mothership": '["railgun_mk3", "mining_laser_mk3", "composite_armor_mk2", "stainless_armor", "superalloy_engine", "ai_targeting_system", "broadside_array"]',
    
    "repair_drone": '["railgun_mk3", "mining_laser_mk3", "composite_armor_mk2", "stainless_armor", "cobalt_battery_module"]',
    "ore_guardian": '["railgun_mk3", "mining_laser_mk3", "composite_armor_mk2", "stainless_armor", "mg_battery_module"]',
    "mining_sentinel": '["railgun_mk3", "mining_laser_mk3", "composite_armor_mk2", "stainless_armor", "superalloy_engine", "ai_targeting_system", "signal_jammer"]',
    "defense_turret": '["railgun_mk3", "mining_laser_mk3", "composite_armor_mk2", "stainless_armor", "superalloy_engine", "ai_targeting_system", "broadside_array"]',
    "colony_overseer": '["railgun_mk3", "mining_laser_mk3", "composite_armor_mk2", "stainless_armor", "superalloy_engine", "ai_targeting_system", "broadside_array"]',

    # Sector Gamma (Pt, Ir, RadIsotope, U, SyntheticCrystal) -> NOW DROPS Iridium Penetrator, Plasma Overcharger, etc
    "irradiated_hulk": '["cryo_laser_mk3", "antimatter_engine", "iridium_armor", "reactive_core_battery"]',
    "plasma_wraith": '["iridium_penetrator", "platinum_laser", "reactive_armor", "plasma_overcharger", "exotic_shield_matrix"]',
    "radiation_beast": '["cryo_laser_mk3", "antimatter_engine", "iridium_armor", "reactive_core_battery", "iridium_penetrator", "platinum_laser", "reactive_armor", "plasma_overcharger", "exotic_shield_matrix"]',
    "nebula_leviathan": '["cryo_laser_mk3", "antimatter_engine", "iridium_armor", "reactive_core_battery", "iridium_penetrator", "platinum_laser", "reactive_armor", "plasma_overcharger", "exotic_shield_matrix"]',
    "gamma_colossus": '["cryo_laser_mk3", "antimatter_engine", "iridium_armor", "reactive_core_battery", "iridium_penetrator", "platinum_laser", "reactive_armor", "plasma_overcharger", "exotic_shield_matrix"]',

    # Sector Delta (VoidCrystal, ExoticMatter, Diamond, Os)
    "shard_swarm": '["quantum_dissipator", "omni_scanner", "torpedo_launcher", "osmium_core_module", "palladium_fuel_cell"]',
    "prism_guardian": '["reflective_sheath", "diamond_edge_railgun", "crystal_lens_laser"]',
    "crystal_golem": '["quantum_dissipator", "omni_scanner", "torpedo_launcher", "osmium_core_module", "palladium_fuel_cell", "reflective_sheath", "diamond_edge_railgun", "crystal_lens_laser"]',
    "energy_wraith": '["quantum_dissipator", "omni_scanner", "torpedo_launcher", "osmium_core_module", "palladium_fuel_cell", "reflective_sheath", "diamond_edge_railgun", "crystal_lens_laser"]',
    "sentinel_prime": '["quantum_dissipator", "omni_scanner", "torpedo_launcher", "osmium_core_module", "palladium_fuel_cell", "reflective_sheath", "diamond_edge_railgun", "crystal_lens_laser"]',

    # Sector Zeta (Void Tech Transition)
    "plague_drone": '["temporal_scrambler", "warp_stabilizer"]',
    "bio_horror": '["void_engine", "chrono_stabilizer"]',
    "rogue_ai_core": '["temporal_scrambler", "warp_stabilizer", "void_engine", "chrono_stabilizer"]',
    "quarantine_warden": '["temporal_scrambler", "warp_stabilizer", "void_engine", "chrono_stabilizer"]',

    # Sector Epsilon (Omega, Primordial, Endgame)
    "void_stalker": '["omega_armor", "primordial_core", "omega_beam", "void_battery_array", "temporal_drive", "primordial_fortification", "omega_singularity", "void_breaker_laser"]',
    "temporal_phantom": '["omega_armor", "primordial_core", "omega_beam", "void_battery_array", "temporal_drive", "primordial_fortification", "omega_singularity", "void_breaker_laser"]',
    "omega_sentinel": '["omega_armor", "primordial_core", "omega_beam", "void_battery_array", "temporal_drive", "primordial_fortification", "omega_singularity", "void_breaker_laser"]',
    "primordial_titan": '["omega_armor", "primordial_core", "omega_beam", "void_battery_array", "temporal_drive", "primordial_fortification", "omega_singularity", "void_breaker_laser"]',
    "void_leviathan": '["omega_armor", "primordial_core", "omega_beam", "void_battery_array", "temporal_drive", "primordial_fortification", "omega_singularity", "void_breaker_laser"]',
}

new_code = code

for enemy_id, new_pool in drop_pools.items():
    # Find the enemy dict
    pattern = r'(\"' + enemy_id + r'\":\s*\{(?:[^{}]*|\{[^{}]*\})*?\"module_drop_pool\":\s*)\[.*?\]'
    
    # We use a regex replacement function to safely replace just the pool list
    def rep(m):
        return m.group(1) + new_pool
        
    new_code, num_subs = re.subn(pattern, rep, new_code, flags=re.DOTALL)
    if num_subs == 0:
        print(f"Failed to find or replace module_drop_pool for {enemy_id}")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(new_code)

print("Done rebalancing module drops.")
