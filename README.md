# Smash Arena (Roblox)

A Super Smash Bros.-style platform fighter for Roblox, with five custom fighters, CPU opponents, stocks, and percent-based knockback.

Open **`place/RobloxSmashGames_Smash.rbxl`** in Roblox Studio and press **Play**.

## What's in the game

- **Damage % instead of HP.** Every hit raises your percent, and the higher it is, the farther you fly. You're KO'd when you go past a blast zone. The knockback uses the Smash formula: damage, base knockback, knockback growth, and the victim's weight.
- **Hitlag, launch smoke, and screen shake.** Strong hits freeze both fighters for a few frames, the victim shakes, and the camera rumbles.
- **Stocks and matches.** The flow is READY? → 3, 2, 1, GO! → GAME! → a results screen, then back to free play.
- **Real platform-fighter movement:**
  - double and multi-jumps, with short hops when you tap jump
  - fast fall
  - air drift and momentum
  - pass-through platforms (jump up through them, press S to drop)
  - ledge grabs with ledge jump, climb, and getup attack
  - directional influence (DI) while you're launched
- **Defense:**
  - shield that shrinks as it takes hits, and breaks into a stun
  - perfect-shield parry
  - roll, spot dodge, and directional air dodge
- **Every attack type:**
  - 3-hit jab
  - tilts (side, up, down)
  - chargeable smash attacks
  - five aerials, including a spiking down-air
  - four unique specials per fighter
- **Grabs and throws.**
  - Grabs go through shields, so you get Smash's attack / shield / grab rock-paper-scissors.
  - While holding someone, attack pummels them, and a direction throws them forward, back, up or down. Back throw is the KO throw, and down throw sets up combos.
  - If you're grabbed, mash any button to break out sooner. The more damage you have, the longer you're held.
- **Crouching.** Hold down to crouch. It makes you shorter, so some high attacks miss you.
- **Procedural animation.** No animation assets are needed:
  - each fighter has their own run (Frost does a ninja run, Titan stomps, Nova glides), idle fighting stance, double-jump style, taunt and victory pose
  - movement: turnarounds, skidding to a stop, jump takeoff, rising, falling, fast-fall dive, landing squash, crouch, and teetering and flailing at the edge of the stage
  - ledges: hanging with swaying legs, and a real climb up onto the stage
  - getting hit: flinches that react to which side the hit came from, tumbling, being knocked flat and getting back up, and a dizzy wobble after a shield break
  - idle fidgets, heads that look toward the nearest opponent, and a bobbing pose on the revival platform
  - grab, pummel, four throws, being held, and being pushed away when a grab ends
  - on the results screen, the winner does their victory pose and everyone else claps
  - on the character select screen, each fighter holds their stance and taunts when you pick them
  - every pose blends smoothly into the next
- **Dash attack.** Attacking out of a full run does a sliding kick instead of stopping dead.
- **CPU opponents.** Three difficulty levels, plus a training dummy in free play. CPUs approach, attack, shield, dodge, grab and throw, mash out of grabs, edge-guard, and recover with jumps and up-specials.
- **2.5D camera.** It frames every fighter and zooms as they spread out.
- **Smash-style HUD.** Damage cards change color with percent, and stock icons show remaining lives.
- **Character select screen.** Each fighter spins in a 3D preview, with stat bars and a list of their specials.

## Fighters

| Fighter | Style | Specials (Neutral / Side / Up / Down) |
|---|---|---|
| **Blaze** – The Blazing Brawler | All-rounder, fire | Fireball / Flame Dash / Rising Phoenix / Magma Slam |
| **Frost** – The Ice Ninja | Fast, light, triple jump | Ice Shuriken / Blink Strike / Frost Warp / Glacier Counter |
| **Titan** – The Iron Colossus | Heavy, armored smashes | Titan Punch (charge) / Iron Charge / Rocket Uppercut / Earthquake |
| **Volt** – The Lightning Racer | Fastest runner, combos | Thunder Orb / Lightning Dash / Thunder Zip / Thunderbolt |
| **Nova** – The Cosmic Mage | Floaty zoner, 5 jumps | Star Bolt (charge) / Gravity Well / Warp Star / Reflect Nova |

Each fighter's look is built entirely from parts: body colors, proportions, hair, helmets, capes, weapons, and elemental auras. No catalog assets are needed.

## Controls

These are the defaults. Every one of them can be changed in the game (see **Remapping** below).

| Action | Keyboard | Gamepad |
|---|---|---|
| Move | A / D | Left stick (+ D-pad) |
| Jump (tap for short hop) | Space | X / Y |
| Aim up / down | W / S | Left stick |
| Fast fall (in air) / drop through platform | S | Stick down |
| Attack (neutral, tilts, aerials by direction) | J or left click | A |
| Smash attack (hold to charge) | L | Right stick flick |
| Special (+ direction) | K or right click | B |
| Shield / roll (+A/D) / spot dodge (+S) / air dodge | Q or Shift | Triggers (LT / RT) |
| Grab (or shield + attack), then a direction to throw, attack to pummel | E | Bumpers (LB / RB) |
| Crouch | S (hold) | Stick down (hold) |
| Taunt | T | D-pad up |
| Fighter select (in the lobby) | M | View / Select |
| Controls menu | C | View / Select during a match, or Y on the fighter select screen |
| Hide controls card | H | |

The fighter select screen works with a controller. Use the D-pad or stick to pick a fighter, **A** to lock in, **X** to lock in and start the match, **Y** to open Controls, and **B** to go back.

On mobile, an on-screen stick and buttons appear.

### Remapping

Open the **Controls** menu (the **CONTROLS** button in the lobby panel, **C** on the keyboard, or the controller's **View** button) to change any control.

- There are separate **Controller** and **Keyboard & Mouse** tabs. Switch between them with **LB / RB** or by clicking.
- Pick a button and press **A** (or click it), then press the new button. Each action can have up to 4 buttons.
- A button can only do one thing. If you give it to a new action, it's taken off the old one, and the menu tells you.
- **X** (or right-click) removes a button. **Y** (press twice) resets that tab to the defaults.
- It also has toggles for **Right stick = Smash** and **Tap Jump** (Up also jumps).
- The controls card on the left of the screen always shows your current buttons, for whichever device you're using.

Changes apply instantly. They're saved to your Roblox account through a DataStore, so they come back next time you play. In Studio, saving only works if the place is published and **Game Settings → Security → Enable Studio Access to API Services** is on. Without that, your remaps still work until you stop playing.

## Project layout

```
place/RobloxSmashGames_Smash.rbxl   the finished place (open this)
place/RobloxSmashGames.rbxl         the original prototype the build starts from
src/                                all game code, Rojo-style
  ReplicatedStorage/Smash/          Config, Fighters, Moves, Poses, Controller (shared)
  ServerScriptService/SmashServer/  match flow + Combat, Bots (CPU AI), Looks (outfits)
  StarterPlayer/StarterPlayerScripts/SmashClient/  Input, CameraRig, Animator, Effects, Hud, Menu
tools/                              C# tool that reads/writes .rbxl and injects src/ into the place
default.project.json                Rojo project, if you'd rather sync with Rojo
```

In the place itself:

- `Workspace.SmashStage` is the arena. `Main` is the stage, `Platforms` are the soft platforms, and `Spawns` are the start positions. Blast zones follow `Main`'s size, so you can resize or move the stage in Studio.
- `ServerStorage.Legacy` keeps the original scripts and stage, disabled, for reference.

## Tuning

Everything that affects game feel is in `src/ReplicatedStorage/Smash/Config.lua`: gravity, blast zones, knockback scale, hitstun, hitlag, shield numbers, and match rules. Each fighter's stats are in `Fighters.lua`, and every attack's timing and hitboxes are in `Moves.lua`. Set `Config.ShowHitboxes = true` to see hitboxes while testing.

## Rebuilding the place from source

The tool compiles with the C# compiler that ships with Windows, so nothing needs to be installed:

```powershell
cd tools
./build.ps1
```

This does the following:

1. Compiles `rbx.exe`.
2. Lint-checks every `.lua` file for syntax errors and misspelled or undefined variables.
3. Rebuilds `place/RobloxSmashGames_Smash.rbxl` from the original place plus `src/`.
