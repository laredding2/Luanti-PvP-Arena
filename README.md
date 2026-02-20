# PvP Arena Mod for Minetest

A (soon-to-be) PvP arena mod with team-based combat, guns, scoreboards, and match management.

## Features (that I hope to have done soon)

- **Team-based PvP** — Red vs Blue with auto-assignment
- **6 Weapons** — Pistol, Assault Rifle, Shotgun, Sniper Rifle, Rocket Launcher, Frag Grenade
- **HUD Scoreboard** — Live scores, timer, personal K/D stats, team indicator
- **Raycast Guns** — Hitscan shooting with bullet trails and impact particles
- **Area-of-Effect** — Rocket Launcher and Grenades deal splash damage
- **ADS / Zoom** — Right-click to aim down sights (Pistol, Rifle, Sniper)
- **Arena Barriers** — Players are pushed back if they leave the arena zone
- **Match System** — Configurable time limit, score limit, respawn delay
- **Persistent Config** — Arena boundaries and spawns saved across restarts
- **Kill Feed** — Broadcasts kills in chat with team colors

## Installation

1. Copy the `pvp_arena` folder into your Minetest `mods/` directory
2. Enable the mod in your world settings
3. Requires the `default` mod (included with Minetest Game)

## Quick Setup

```
/arena_set pos1        -- Stand at one corner, set boundary
/arena_set pos2        -- Stand at opposite corner, set boundary
/arena_set redspawn    -- Stand where red team spawns
/arena_set bluespawn   -- Stand where blue team spawns
/arena_start           -- Start the match!
```

## Commands

| Command | Privilege | Description |
|---------|-----------|-------------|
| `/arena_set <pos1\|pos2\|redspawn\|bluespawn>` | server | Set arena boundaries and spawns at your position |
| `/arena_start` | server | Start a match (auto-assigns teams) |
| `/arena_stop` | server | Force-end current match |
| `/arena_config <key> <value>` | server | Change settings (see below) |
| `/arena_scores` | none | View current match scores |
| `/arena_give <weapon>` | server | Give yourself a weapon for testing |

## Config Options (`/arena_config`)

| Key | Default | Description |
|-----|---------|-------------|
| `duration` | 300 | Match time limit in seconds |
| `maxscore` | 25 | Kills needed to win |
| `hp` | 20 | Starting/max HP per player |
| `friendlyfire` | false | Allow team damage (`true`/`false`) |

## Weapons

| Weapon | Damage | Range | Fire Rate | Special |
|--------|--------|-------|-----------|---------|
| Pistol | 3 | 40 | Fast | ADS zoom |
| Assault Rifle | 4×3 | 60 | 3-burst | ADS zoom, burst fire |
| Shotgun | 2×8 | 15 | Slow | 8 pellets, high spread |
| Sniper Rifle | 14 | 100 | Very slow | High zoom ADS |
| Rocket Launcher | 10 | 50 | Very slow | AoE radius 4 |
| Frag Grenade | 8 | Thrown | 3s fuse | AoE radius 5, 3 per spawn |

## Customizing Textures

Replace the placeholder PNGs in `textures/` with your own 16×16 pixel art:
- `pvp_arena_pistol.png`, `pvp_arena_rifle.png`, `pvp_arena_shotgun.png`
- `pvp_arena_sniper.png`, `pvp_arena_rocket.png`, `pvp_arena_grenade.png`
- `pvp_arena_bullet_trail.png`, `pvp_arena_impact.png`, `pvp_arena_explosion.png`

## Tips

- The default loadout is: Assault Rifle + Pistol + 3 Grenades
- Players auto-respawn at their team spawn after a 3-second delay
- Nametag colors change to match team colors during a match
- The arena zone is defined as a 3D box between pos1 and pos2
