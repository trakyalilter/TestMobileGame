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
	# v113 (NG+): milestone coach, fired on the first Z10-boss kill (not a page
	# visit). Anchors to the Warp Core nav button; steers the player to prestige.
	# v128: fired on the player's FIRST combat loss (a game event, not a page visit) —
	# warns that losing degrades/destroys equipped modules, which can strand the ship.
	# Anchor "" → centered card (it's a concept, not a single button).
	"combat_loss": [
		{
			"anchor": "",
			"title": "Systems Damaged",
			"body": "Losing a fight is costly: every equipped module takes durability damage, and some can be DESTROYED outright — including your battery, which can leave your ship unable to power its weapons at all. Repair your hull, re-equip anything you lost, and don't out-reach your gear — match your loadout to the sector before you engage.",
		},
	],
	"warp_milestone": [
		{
			"anchor": "warp_nav",
			"title": "The Threshold Awaits",
			"body": "Sector 10 cleared! The frontier beyond is Warp-Hardened - conventional weapons barely scratch it. Open the Warp Core (here) and execute a reset: it permanently unlocks Cryogenic armaments (the only thing that pierces these hulls) and reveals Sector 11. Your research and Warp Mastery carry over, and every run gets faster.",
		},
	],
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
			"body": "Modules draw power; only battery modules supply it. Keep batteries equipped — if draw exceeds supply, your ship can't engage at all.",
		},
		{
			"anchor": "schematic",
			"title": "Matrix Cores",
			"body": "Matrix Cores are equippable bonus chips. Use Matrix Synthesis to roll one, then fuse 3 of a kind into a stronger tier.",
		},
		{
			"anchor": "schematic",
			"title": "Matrix Sockets",
			"body": "Modules with ◆ slots hold Matrix Cores. Drag a core onto a socketed, equipped module — the bonus applies globally, so placement doesn't matter.",
		},
		{
			"anchor": "schematic",
			"title": "Set Bonuses",
			"body": "Some modules belong to a SET (named on the module). Equip 3 pieces of the SAME set at once to unlock its set bonus — a large combat multiplier on top of the modules' own stats. Completing a set is one of the strongest build upgrades in the game; the Sector bosses drop the unique set pieces.",
		},
	],
	"combat": [
		{
			"anchor": "zones",
			"title": "Combat Sectors",
			"body": "This is the Sector Chart — pick a system to patrol. Deeper sectors mean tougher enemies but better loot and materials; cleared sectors glow, and the frontier waits ahead.",
		},
		{
			"anchor": "enemies",
			"title": "Engaging Targets",
			"body": "Click a sector to drop in, then pick a hostile cluster or its boss on the map. Combat runs on its own — defeat foes for module drops and resources.",
		},
		{
			"anchor": "enemies",
			"title": "Weapon Damage Types",
			"body": "Once you pick a target, this panel shows what it RESISTS and is WEAK TO. Match your equipped weapons to the weakness for far faster kills.",
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
			"body": "All your materials live here, and cargo is slot-limited — when it's full, newly gathered materials are lost. Expand storage below or clear out what you don't need.",
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
	"fleet": [
		{
			"anchor": "build",
			"title": "Battle Fleet",
			"body": "Forge your material surplus into warships. Capacity grows with every Warp, and build costs are glut basics (Water/Dirt/Steel) — this is the sink for your overflowing stockpiles.",
		},
		{
			"anchor": "power",
			"title": "Combat Support",
			"body": "Each fleet ship adds +25% of your ship's damage in combat, up to +100% with a full fleet. The roster persists across Warps — it's prestige progression that fights beside you.",
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
