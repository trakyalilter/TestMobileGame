---
name: visual-asset-creator
description: Generates sci-fi pixel art icons for modules and resources adhering to the game's theme.
---

# Visual Asset Creator

This skill enables the generation of game assets (modules, resources, ships) that match the *Horizon Idle* aesthetic.

## Aesthetic Guidelines

### Theme: Dark Sci-Fi Pixel Art
- **Style**: High-quality pixel art (not simplistic, but structured).
- **Resolution**: 256x256 (intended for downscaling/interpolation).
- **Background**: Transparent (or consistent dark `#05080c`).
- **Lighting**: Cinematic, directional light from top-left, cyan/blue highlights.

### Rarity Color Palettes
When generating modules, the dominant glow/accent color must match the rarity:
- **Uncommon**: Vibrant Green (`#33cc33`)
- **Rare**: Electric Blue (`#3388ff`)
- **Legendary**: Radiant Gold (`#ffaa33`)
- **Unique**: Neon Magenta (`#e633cc`)

## Usage Instructions

### 1. Identify Target
Determine if you are creating a **Weapon**, **Shield**, **Armor**, **Utility**, or **Resource**.

### 2. Select Template
Use the following base prompt template:

> **Prompt Template**:
> "Pixel art icon of a sci-fi {ITEM_TYPE} called '{NAME}' for a 2D space game. {SPECIFIC_DETAIL}. Made of {MATERIAL}. Dominant glow color is {RARITY_COLOR}. Dark metallic base, visible circuitry and modular parts. Top-down or slight 45-degree angle. Transparent background."

### 3. Generate Image
Call `generate_image` with the constructed prompt.

### 4. Negative Prompt
Always include: "realistic gun, human hands, photorealism, blurry, text, watermark, UI frame, messy pixels".
