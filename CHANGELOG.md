# Move Raid Manager Changelog

## v2.3.1
- Fixed CurseForge packaging: the Forever interface rides its own setup file again instead of sharing the Mainline one (the packager rejects mixed game types in a single `-Mainline.toc`). Nothing changes in game.

## v2.3.0
- The "hide when collapsed" checkbox is now a Hide picker: `never` keeps the manager fully visible (the default), `when cursor away` fades it out while it is collapsed and the cursor is elsewhere (hovering brings it back), `always` hides it at all times, even on hover. Your existing fade choice carries over automatically.
- The strata picker now shows digits 2–9, lowest to highest, so every entry fits the dropdown.
- Each row has a little info icon beside it — hover it for a tooltip explaining that row.
- The window now sizes its dropdowns from their entries and centers every row, so all the controls line up.
- Move mode works outside groups now (the drag surface no longer depends on the hidden toggle strip), and a yellow box below the green one previews the taller leader/assist version — a fixed preview derived from Blizzard's own panel layout, shown immediately even solo on a fresh install, draggable like the rest.
- The download now ships one setup file per game family (Classic, Mainline and Forever) instead of one per expansion — nothing changes in game.

## v2.2.0
- The manager now works in World of Warcraft: Forever (beta).

## v2.1.0
- Everything now works while fighting: moving the manager, typing coordinates, toggling autohide, changing strata and moving the config window all apply instantly mid-combat and in Mythic+ / rated PvP, with no errors.
- Fixed: hovering the collapsed expand button reveals the manager again (only the window body woke it before).
- Fixed: the autohide now kicks in right after a UI reload mid-fight, like it always used to.

## v2.0.0
- Rewritten as a single implementation shared by every game version, with the raid manager's own behavior on each version learned directly from that version's UI code.
- New: `/moverm` now opens a configuration window with a Y-coordinate box, a "hide when collapsed" checkbox and a strata picker. `/moverm reset` restores every setting to the game's defaults, including the config window's own position (the window stays open, move mode stays on); any other input opens the window.
- New: a "move manager" button in the config window turns on move mode — drag the manager itself up and down, with a green box marking its exact spot. The expand/collapse toggle stays clickable while moving, and dragging from the toggle itself moves too. The box follows expand/collapse and roster rebuilds.
- Changed: out of the box the raid manager now keeps the game's own strata; previously every login forced it to the LOW strata even if you never touched the setting. The strata picker simply starts on the game's own value.
- Fixed: changing the strata no longer affects the raid frames when they are anchored to the raid manager; the strata now moves only the raid manager itself.
- Fixed: the custom position no longer uses an override of the game's own placement calls, so expanding and collapsing the raid manager in combat can't get it stuck.
- Combat-safe rewrite: configuration changes made while fighting (or in Mythic+ / rated PvP) no longer risk errors — they are remembered quietly and applied when the fight ends. The raid manager also keeps working after a UI reload mid-fight.
- Fixed: after `/moverm reset` the Y box could show `0.0000` instead of the game's `-140`.
- The custom vertical position now survives expanding and collapsing the raid manager more robustly, on every version of the game.
- The collapsed toggle arrows now use the same show/hide calls the game itself uses.
- Existing settings carry over automatically: your saved position, fade and strata choices keep working exactly as before.
