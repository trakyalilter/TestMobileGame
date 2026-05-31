class_name CoachMarks
extends RefCounted

# First-visit onboarding cards, shown once per page (tracked in
# GameState.game_settings["coach_seen"]). Each step's `anchor` is resolved by
# the target page's get_coach_anchor(key); a missing/offscreen anchor falls
# back to a centered card so the message is never lost.
#
# Phase 1: gathering, research, mission.
# Phase 2: processing, shipyard, designer, combat, infrastructure, inventory,
#          bounty, quest, warp, atlas.

const STEPS := {
	"gathering": [
		{
			"anchor": "first_action",
			"title": "Gathering Operations",
			"body": "Pick an action to start gathering resources. It runs automatically on a timer — and keeps producing even while the game is closed.",
		},
		{
			"anchor": "xp_bar",
			"title": "Skill Progression",
			"body": "Every action grants skill XP. Leveling this skill unlocks higher-tier resources and faster actions.",
		},
	],
	"research": [
		{
			"anchor": "tabs",
			"title": "Research Tree",
			"body": "Research unlocks new gathering actions, processing recipes, ships, and combat zones. Switch categories with these tabs.",
		},
		{
			"anchor": "first_node",
			"title": "Unlocking Tech",
			"body": "Each node costs Liras and sometimes items. Gold = ready to unlock, green = already owned. A glowing tab marks the tech your current mission needs.",
		},
	],
	"mission": [
		{
			"anchor": "first_mission",
			"title": "Your Objective",
			"body": "This is your current mission. Follow it — these objectives guide you through the whole early game, one step at a time.",
		},
		{
			"anchor": "claim",
			"title": "Claiming Rewards",
			"body": "When an objective is complete, claim it here to collect Liras and XP and unlock the next mission.",
		},
	],
	"processing": [
		{
			"anchor": "first_recipe",
			"title": "Processing",
			"body": "Refine raw materials into useful goods. Recipes are grouped by category and need their inputs in your inventory.",
		},
		{
			"anchor": "xp_bar",
			"title": "Processing Skill",
			"body": "Processing is its own skill. Leveling it unlocks alloys, electronics, munitions, and more advanced recipes.",
		},
	],
	"shipyard": [
		{
			"anchor": "first_item",
			"title": "Shipyard",
			"body": "Build ship hulls and modules here from refined materials. Bigger hulls have more module slots and hull points.",
		},
		{
			"anchor": "stats",
			"title": "Active Ship",
			"body": "This shows your current ship's combat stats. After building modules, equip them in the Designer.",
		},
	],
	"designer": [
		{
			"anchor": "schematic",
			"title": "Ship Designer",
			"body": "Drag modules from your armory onto these ship slots to equip weapons, shields, armor and engines.",
		},
		{
			"anchor": "power",
			"title": "Batteries & Power",
			"body": "Hulls supply NO power. Every weapon, shield, armor, engine and sensor DRAWS energy — and only BATTERY modules supply it. Fill your battery slots: if total draw exceeds battery supply, the ship can't engage at all. As you move to bigger hulls, craft higher-tier batteries to keep everything running.",
		},
		{
			"anchor": "schematic",
			"title": "Matrix Cores",
			"body": "In your armory's MATRIX CORES rack: 'Matrix Synthesis' rolls a random core; fuse 3 of one kind into the next tier (Cracked → Stable → Pristine) for a bigger bonus. Crimson = attack, Cobalt = shield/evasion, Topaz = power, Amethyst = defense/hull.",
		},
		{
			"anchor": "schematic",
			"title": "Matrix Sockets",
			"body": "Modules with ◆ slots accept Matrix Cores. Drag a core from your armory onto an equipped, socketed module — the bonus is global no matter which module holds it. Higher tiers are stronger.",
		},
	],
	"combat": [
		{
			"anchor": "zones",
			"title": "Combat Sectors",
			"body": "Pick a sector to patrol. Higher sectors mean tougher enemies but better loot and materials.",
		},
		{
			"anchor": "enemies",
			"title": "Engaging Targets",
			"body": "Select an enemy to start the fight. Combat runs on its own — defeat foes for module drops and resources.",
		},
		{
			"anchor": "enemies",
			"title": "Weapon Damage Types",
			"body": "KINETIC: big hull damage but armor stops it. ENERGY: shreds shields, weak on bare hull. EXPLOSIVE: ignores most armor — a safe all-rounder. CRYO: unlocked by Warping — the ONLY damage that breaches Warp-Hardened hulls (Sector 11+). Enemies resist or are weak to a type, so swap weapons to match the target.",
		},
		{
			"anchor": "consumables",
			"title": "Repair Kits in Combat",
			"body": "These HULL and SHLD buttons spend an equipped repair kit to patch up mid-fight (short shared cooldown). They are manual — tap them when you're getting low; nothing auto-heals.",
		},
	],
	"infrastructure": [
		{
			"anchor": "first_building",
			"title": "Infrastructure",
			"body": "Buildings auto-produce resources in the background — always running, even while you're away or doing other tasks.",
		},
		{
			"anchor": "energy",
			"title": "Power Balance",
			"body": "Production consumes power. Keep this net energy balance positive or buildings throttle down.",
		},
	],
	"inventory": [
		{
			"anchor": "grid",
			"title": "Inventory",
			"body": "All your materials live here. Slots are limited — some gathering actions stop when storage is full.",
		},
		{
			"anchor": "storage",
			"title": "Expanding Storage",
			"body": "Spend Liras here to add more inventory slots as your operation grows.",
		},
	],
	"bounty": [
		{
			"anchor": "available",
			"title": "Bounty Board",
			"body": "Optional timed contracts for bonus Liras. Accept one to add it to your active list.",
		},
		{
			"anchor": "active",
			"title": "Active Contracts",
			"body": "Accepted contracts track here. Complete the objective before the timer runs out to claim the reward.",
		},
	],
	"quest": [
		{
			"anchor": "grid",
			"title": "Quests",
			"body": "Repeatable side goals that progress automatically as you play. A steady extra income stream.",
		},
		{
			"anchor": "claim_all",
			"title": "Claiming Quests",
			"body": "Finished quests stack up — claim them all here for their combined rewards.",
		},
	],
	"warp": [
		{
			"anchor": "gain",
			"title": "Warp Core",
			"body": "Warping resets your run but grants Exotic Matter: permanent multipliers that make every future run dramatically faster.",
		},
		{
			"anchor": "warp_btn",
			"title": "When to Warp",
			"body": "Warp once you have shards to gain. Every 5 warps raises your Warp Tier, doubling the bonus scale.",
		},
		{
			"anchor": "tree",
			"title": "Warp Mastery Tree",
			"body": "Spend Exotic Matter Shards here on permanent upgrades. The Engineering branch opens on your first Warp, Combat on your second — each Warp reveals more. Your first Warp also grants Cryo weapons: the key to breaching Sector 11.",
		},
	],
	"atlas": [
		{
			"anchor": "list",
			"title": "Atlas",
			"body": "An encyclopedia of every material and enemy in the game. Use it whenever you're unsure where something comes from.",
		},
		{
			"anchor": "details",
			"title": "Sources & Uses",
			"body": "Select an entry to see exactly where it drops and everything that consumes it.",
		},
	],
}

static func get_steps(page_name: String) -> Array:
	return STEPS.get(page_name, [])
