---
description: How to generate and integrate new visual assets using the Visual Asset Creator agent.
---

# Workflow: Create Visual Assets

Follow these steps to generate high-quality, theme-consistent icons for modules or resources.

## Steps

1. **Describe the Item**
   Identify the item name, type (Weapon, Shield, etc.), and rarity. 
   *(Example: "Titan's Wrath", Zone 9 Unique Weapon)*

2. **Invoke Visual Agent**
   Call the `Visual Asset Creator` agent or use the `visual-asset-creator` skill to construct a theme-compliant prompt.

3. **Generate Image**
   Use the `generate_image` tool. Ensure the negative prompt is set to exclude photorealism and UI elements.

4. **Iterate (Manual Review)**
   Review the generated image. If the colors don't match the rarity (e.g., a Unique item is missing Magenta glows), adjust the prompt and regenerate.

5. **Finalize and Save**
   Once approved, move the file from the artifacts directory to the project's assets folder:
   - Weapons: `assets/weapons/`
   - Shields/Armor: `assets/shields/`
   - Resources: `assets/raws/`

6. **Update Metadata**
   Ensure any relevant JSON in `assets/elements.json` or `prompts/` is updated to include the new asset's filename.

---
// turbo
// Use this command to see existing assets for style reference
`ls assets/**/*`
