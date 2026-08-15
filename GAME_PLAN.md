# Skybound Trails Prototype

An original single-player 2D side-scrolling action RPG prototype.

The project is developed as a playable vertical slice: establish stable gameplay and data boundaries first, then expand professions, skills, enemies, regions, progression content, presentation, and final artwork. Stable internal IDs remain language-neutral, while player-facing text uses Simplified Chinese.

## Core loop

Create a character -> choose a permanent profession -> explore connected maps -> fight repeatable encounters -> gain experience, materials, and equipment -> improve the character -> continue from saved world progress.

The current game remains an endless combat and farming prototype. Clearing all visible enemies does not complete a map, portals do not require clearing enemies, and there is no dungeon, boss, region-clear, or victory flow yet.

## Current playable milestone

### Character profiles and persistence

- Three fixed local character slots with create, continue, and typed-name deletion flows.
- Permanent profession binding with Traveler and staff-focused Star Seeker starting options.
- Character-isolated level, EXP, materials, equipment, backpack, skill progress, and world location.
- Versioned per-character JSON saves with temporary writes, last-known-good backups, corrupt-save recovery, migration, and future-version rejection.
- Safe return to the character list with autosave, combat countdown interruption, and challenge-lock support.
- Continue location and checkpoint respawn location are stored and applied independently.

### Movement and platforming - Issue #2

- Explicit idle, walk, sprint, jump, fall, crouch, attack, skill, hit, and death-related states.
- Responsive start, stop, reversal, and double-tap-and-hold sprint behavior.
- Variable jump height, coyote time, jump buffering, controlled air movement, and stable landing recovery.
- Crouching and one-way-platform drop-through without accidental jumps or repeated platform drops.
- Movement input is cleared across UI use, focus changes, hits, death, respawn, reset, save application, and scene changes.

### Ground combat and enemy readability - Issues #3-#7

- Grounded light and heavy attacks with distinct startup, active, recovery, repeat cadence, movement commitment, and directional snapshots.
- Sword attacks use profile-driven physical melee hitboxes; staff attacks use profile-driven magical projectiles.
- Enemy attacks use configurable startup, active, recovery, and cooldown phases; hitboxes are active only during the real damage window.
- Patrol grunts and heavy guards have visibly different telegraph timing and procedural attack motion without explicit attack-range boxes.
- Accepted hits produce bounded visual impact and hurt feedback; misses and rejected hits do not produce false hit feedback.
- Shared hit metadata and reaction rules distinguish normal and heavy reactions using post-mitigation damage, critical state, movement context, and knockback protection.
- Attack interruption, hitboxes, delayed effects, visual poses, invulnerability, death, respawn, and reset states are cleaned safely.

### Air and platform combat - Issue #9

- Existing sword and staff light/heavy attacks can be used while jumping or falling.
- A single airborne basic-attack allowance is shared by light and heavy attacks for each departure from the ground.
- Gravity, vertical speed, bounded air control, landing, and platform-edge behavior continue during attacks.
- Starting an attack on the ground and leaving a ledge, or landing during an airborne attack, does not restart phases, duplicate hitboxes, projectiles, or damage.

### Progression, loot, and equipment - Issues #10-#11

- Original four-attribute progression with derived health, physical/magical attack, defense, critical stats, and equipment-ready modifiers.
- Repeatable enemy experience rewards, multi-level growth, material drops, and fixed HUD feedback.
- Seven equipment slots: weapon, head, body, legs, gloves, shoes, and ring.
- Enemy-specific equipment drop rates and a small quality model: common, uncommon, and rare.
- Equipment instances preserve stable instance IDs, quality, and bounded rolled attributes; higher-quality drops are better on average without bypassing profession restrictions.
- Physical equipment pickups are visually identifiable, auto-attract, enter the current character's backpack once, expire safely, and are cleared on map exit.
- Keyboard-first backpack navigation, scrolling, selection persistence, item comparison, equip, unequip, deterministic sorting, and confirmed discard.
- Replaced or unequipped items return as the same equipment instance; save/load preserves inventory decisions and prevents cross-character contamination.

### Profession active skills - Issue #12

- Data-driven skill definitions with stable IDs, profession/weapon requirements, category, level bounds, prerequisite metadata, delivery type, phase timings, cooldown, strength, and ground/air conditions.
- Shared definitions, per-character learned skill progress, and active shortcut slots are separate data concepts.
- Unlearned or level-zero active skills cannot be cast; passive definitions do not occupy active slots.
- Each current profession has two default learned active skills using melee, projectile, ground-only, air-capable, and controlled-knockback behavior.
- Skills use startup, active, recovery, and independent cooldown phases and reuse the existing hitbox, projectile, damage, critical, metadata, and reaction pipelines.
- Skill input, effects, projectiles, and cooldown state are handled safely across UI isolation, hit interruption, death, respawn, reset, save application, character changes, and scene exit.
- Profession skills can define a single same-profession prerequisite and required rank; advanced skills cannot be learned or leave their prerequisite below the required rank.
- The current mouse-driven skill panel groups base active, advanced active, and independent passive skills and shows prerequisite status with safe rank increase/decrease controls.
- A full graphical branching skill tree, respec economy, and mouse-driven shortcut editing are not implemented.

### World maps and encounters - Issues #13-#14

- Data-driven region, map, entry, portal, and checkpoint definitions.
- A combat test map and three field-passage maps connected through a branching, bidirectional portal graph.
- Runtime map switching preserves entry position, facing, camera bounds, portal debounce, continue location, and checkpoint recovery rules.
- Save schema v5 stores `world_location` and migrates older character saves safely.
- Each combat map owns an explicit encounter definition; maps may also explicitly contain no enemies.
- Field maps differ through enemy species, composition, count, and spawn placement while sharing one respawn timing rule.
- Encounter managers own enemy lifecycle and infinite respawn without introducing a clear-map or victory state.
- Map changes remove old enemies, hatred, pursuit, attack state, pending respawns, skill/projectile state, and uncollected material/equipment drops.
- Returning to a map creates exactly one clean copy of its configured encounter; rapid repeated travel does not duplicate enemies, respawns, drops, or rewards.

## Controls

- Move: `Left Arrow` / `Right Arrow`
- Sprint: double-tap and hold `Left Arrow` / `Right Arrow`
- Context interaction and map entrances: `Up Arrow`
- Crouch: hold `Down Arrow`
- Drop through a one-way platform: hold `Down Arrow` and press `Space`
- Jump: `Space`
- Light attack: `Z`
- Heavy attack: `X`
- Active skill slots: `1` / `2`
- Profession skills: `K` (mouse-controlled rank `+` / `-` buttons)
- Character status: `E`
- Equipment backpack: `I`
- Close open interface panels: `Esc`
- Manual reset: `R`

Combat and movement inputs are isolated while interface panels are open. The current acceptance scope is keyboard-only; controller support and rebinding are later work.

## Issue delivery status

| Issue | Status | Delivered scope |
| --- | --- | --- |
| #2 | Complete | Movement, sprint, variable jump, coyote time, jump buffer, air control, crouch, and one-way platforms |
| #3 | Complete | Ground light/heavy attack cadence, phases, sword/staff delivery, interruption, and feedback baseline |
| #4 | Complete | Enemy attack telegraphs and authoritative startup/active/recovery phases |
| #5 | Complete | Accepted-hit, enemy-hurt, and player-hurt visual feedback with bounded impact response |
| #6 | Complete | Normal/heavy hit classification, shared metadata, controlled knockback, and protection rules |
| #7 | Complete | Procedural enemy attack motion synchronized with attack phases |
| #8 | Deferred | Combat audio is intentionally not part of the current implementation plan |
| #9 | Complete | Airborne and platform-edge basic attacks with one attack per airborne cycle |
| #10 | Complete | Repeatable equipment drops, qualities, rolled instances, pickups, cleanup, and farming stability |
| #11 | Complete | Keyboard-first equipment inventory, comparison, equip/unequip, sorting, discard, and persistence |
| #12 | Complete | Data-driven profession active-skill definitions, casting, cooldowns, ownership boundaries, and two temporary slots |
| #13 | Complete | World-map definitions, branching bidirectional travel, checkpoints, continue positions, and save migration |
| #14 | Complete | Per-map encounters, unified respawn timing, map isolation, drop cleanup, and repeatable farming |
| #15 | Complete | Advanced-skill prerequisites, protected rank reduction, legacy-save refunds, and clearer skill hierarchy |

## Compatibility rules for future work

- Preserve permanent profession binding and per-character isolation.
- Preserve stable internal IDs and Simplified Chinese player-facing text.
- Preserve keyboard-complete gameplay; controller support must not replace keyboard access.
- Preserve existing movement, one-way-platform, attack, hit-reaction, death, respawn, inventory, skill, save, and map-transition behavior.
- Continue reusing the shared hitbox, projectile, hit metadata, reaction, equipment-instance, skill-definition, world-definition, and encounter pipelines.
- Continue location and checkpoint respawn location must remain independent.
- Enemies remain infinitely repeatable unless a future dungeon or challenge explicitly defines a separate completion rule.
- Ordinary enemies do not show explicit attack-range boxes, player damage does not add a circular aura, and global hit stop is not introduced by default.
- New save data must be versioned, migrated safely, and tested without writing to real player saves.
- Temporary UI must remain clear and usable, but final art and complex presentation wait until gameplay systems stabilize.

## Next milestone: learnable skill trees and profession growth

Issue #12 deliberately established the data boundaries required by a real skill tree but defaulted the first active skills to learned. The next milestone should convert that foundation into player-controlled progression without rewriting the generic casting state machine.

Planned scope:

- Define how skill points are earned and stored per character.
- Add learnable active and passive skills with level costs and prerequisite validation.
- Apply per-level skill values without mutating shared skill resources.
- Add profession-specific branches while preserving permanent profession binding.
- Build a keyboard-first skill-tree interface for inspecting, learning, and upgrading skills.
- Add explicit shortcut-slot assignment separate from skill ownership.
- Define a safe respec rule that cannot change profession or corrupt learned-skill dependencies.
- Persist skill points, learned levels, and shortcut assignments with migration and character isolation.
- Extend automated coverage and run the full Issue #1-#14 regression suite.

## Remaining vertical-slice backlog

These items remain later milestones unless promoted into a reviewed Issue:

- Complete profession stat growth, resource types, resistances, and broader equipment restrictions.
- Add consumables and complete material/other-item inventory behavior.
- Add a safe town, NPCs, dialogue, shops, currency, quests, and quest tracking.
- Add new normal enemies, an elite enemy, a dungeon, a regional boss, and explicit challenge completion rules.
- Add regional drops and enough content to form one complete playable region.
- Add moving platforms, ladders, ropes, and other traversal types currently reserved by the controls.
- Expand equipment with a larger affix system, reinforcement, durability, crafting, sets, or storage only after their individual scopes are defined.
- Add settings, input rebinding, controller support, accessibility options, and onboarding.
- Revisit combat audio only if Issue #8 is explicitly restored to the plan.
- Add background music, environment audio, final animation, final artwork, and presentation polish after the gameplay slice stabilizes.

## Milestone completion rule

Each new feature should have a reviewed Issue describing the user problem, scope, non-goals, acceptance criteria, and test strategy. Implementation begins from the latest `test` branch, receives feature-specific automated coverage, runs existing regression tests, and is manually validated before the Issue is closed and this plan is updated.
