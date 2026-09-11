# Move Raid Manager

Super lightweight addon that moves, autohides and re-stratas the default raid manager (the little panel at the top left of the screen), on every version of the game. Type `/moverm` in chat to open the configuration window.

## Commands

- `/moverm` — open the configuration window
- `/moverm reset` — restore every setting to the game's defaults

Any other input opens the window as well. The raid frames themselves are never moved, faded or re-strataed by it — only the manager is.

## The config window

- **move manager** — turn on move mode, then drag the manager itself up and down; a green box marks its exact spot (even where it would sit while hidden), with the manager overlaid on top. The expand/collapse toggle stays clickable while moving — and can itself be dragged to move. Closing the window leaves move mode.
- **Y** — move the manager vertically, with a box for exact values (or drag it in move mode)
- **hide when collapsed** — fade the manager out while it is collapsed; hovering it brings it back
- **Strata** — change the manager's strata; it starts preselected on the game's own value

## Compatibility

Works on Modern, Classic Era, Seasonal, Hardcore, TBC, Wrath, Cataclysm and Mists.

## Links

- [Changelog](CHANGELOG.md)
