--[[
	SMASH ARENA — how this place is put together

	Play: press Play in Studio. You start in FREE PLAY with a training dummy. Pick a fighter (M),
	set CPUs / level / stocks in the top-right panel and hit START MATCH.

	Controls (keyboard):  A/D move · Space jump · W/S aim · S in air = fast fall · S on a platform = drop
	  J / left click = attack (neutral, tilts, aerials by direction) · L = smash attack (hold to charge)
	  K / right click = special (neutral / side / up / down) · Q or Shift = shield (+A/D roll, +S spot dodge,
	  in the air = air dodge) · T = taunt · M = fighter select · H = hide controls
	Gamepad: stick move · X/Y jump · A attack · B special · right stick smash · bumpers/triggers shield

	Where things live
	  ReplicatedStorage.Smash.Config      tuning: gravity, blast zones, knockback, shields, match rules
	  ReplicatedStorage.Smash.Fighters    the roster: stats, colors, cosmetic parts, special move names
	  ReplicatedStorage.Smash.Moves       every attack's timing, hitboxes, damage, angles, knockback
	  ReplicatedStorage.Smash.Poses       procedural attack animations (no animation assets needed)
	  ReplicatedStorage.Smash.Controller  movement physics shared by players and CPUs
	  ServerScriptService.SmashServer     match flow + Combat (hits, KOs), Bots (CPU AI), Looks (outfits)
	  StarterPlayerScripts.SmashClient    input, camera, HUD, menus, effects, animation
	  Workspace.SmashStage                the arena. "Main" is the stage, "Platforms" are pass-through,
	                                      "Spawns" are start positions. Blast zones follow Main's size.
	  ServerStorage.Legacy                your original scripts and stage, kept (disabled) for reference

	Adding a fighter: copy an entry in Fighters.List, give it a new Key, then add its specials to
	Specials.<Key> in Moves (or leave them out to reuse the default specials of Blaze).
]]
return nil
