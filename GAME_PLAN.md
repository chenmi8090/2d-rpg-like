# Skybound Trails Prototype

An original single-player 2D action RPG prototype inspired by classic side-scrolling adventures.

## Current milestone

- Explicit idle, walk, sprint, jump, fall, crouch, and attack states
- Grounded light and heavy attacks with directional hitboxes and slow attack movement
- Hold-to-repeat attack cadence: fast low-damage light attack and slow high-damage heavy attack
- Configurable grounded enemy definitions for patrol, persistent in-map pursuit, reactions, and melee timing
- Two enemy species using the same controller: a patrol grunt and a slower armored heavy guard
- Configurable enemy drop rules with physical, attracting star-fragment pickups
- Runtime star-fragment count that persists through player death and updates the fixed HUD
- Configurable field, spawn-block, and spawn-slot definitions with manager-owned monster lifecycle tracking
- Ten-slot farming field with staggered grunt/heavy respawns across ground and upper platforms
- OneWay-aware enemy patrol with locked-target edge descent and continued ground pursuit
- Lightweight platform-graph routing with committed monster jumps to pursue players upward
- Shared feet-coordinate navigation keeps same-surface attacks and player-platform routing consistent across different actor origins
- Any player-owned melee or projectile hit immediately acquires monster hatred; after hit stun the monster enters normal horizontal/platform pursuit
- Locked enemies choose platform chains and left/right transitions by minimum estimated physical distance to the player, then preserve committed jump/drop direction
- Original four-attribute player progression with derived health, attack, defense, critical stats, equipment-ready modifiers, and an `E`-toggled character panel
- Fixed seven-slot equipment loadout: weapon, head, body, legs, gloves, shoes, and ring
- Traveler profession with profession-gated weapon types and one aggregated equipment modifier source
- Repeatable enemy experience rewards, multi-level growth, and fixed level/EXP HUD feedback
- Player health, hit stun, invulnerability, death, automatic respawn, and fixed health UI
- All player-facing interface text and display names use Simplified Chinese; stable internal IDs remain language-neutral
- The `E` character panel shows final attributes and seven equipment slots; hovering a slot reveals that item’s exact bonuses
- Fixed equipment drops auto-attract into a counted `I` backpack with hover comparison, click-to-equip, replacement return, and profession restriction feedback
- Sword J/K attacks use profile-driven physical melee strikes; staff J/K attacks use profile-driven magical projectiles

## Controls

- Move: `A` / `D`
- Sprint: double-tap and hold `A` / `D`
- Context movement: `W` is reserved for ladders, ropes, and map entrances
- Crouch: hold `S`
- Drop through an upper platform: hold `S` and press `Space`
- Jump: `Space` (while grounded)
- Light attack: hold `J` for fast repeated low-damage punches
- Heavy attack: hold `K` for slower repeated high-damage punches
- Attributes: press `E` to open or close the character attribute panel
- Backpack: press `I` to open or close the equipment backpack
- Close windows: press `Esc` to close all open interface panels without quitting
- Restart: `R`
- Quit: `Esc`

## Next milestone

Add interactive equipment acquisition and inventory around the fixed seven-slot loadout. Weapon-dependent basic attacks/skills, equipment instances and drops, random affixes, reinforcement, durability, save data, combat feedback, map transitions, moving-platform/ladders/ropes navigation, de-aggro/home recovery, and final artwork remain later milestones.
