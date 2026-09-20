# Move Raid Manager

Super lightweight addon that moves (vertically), autohides and re-stratas the default raid manager (the little panel at the top left of the screen), on every version of the game. Type `/moverm` in chat to open the configuration window.

## Commands

- `/moverm` — toggle the configuration window open/closed
- `/moverm reset` — restore every setting to the game's defaults (the window stays open, move mode stays on)

Any other input toggles it too (opens it when closed). The raid frames themselves are never moved, faded or re-strataed by it — only the manager is.

## The config window

- **move manager** — turn on move mode, then drag the manager itself up and down; a green box marks its exact spot (even where it would sit while hidden), with the manager overlaid on top. A yellow box below it previews the taller leader/assist version (a fixed preview derived from Blizzard's own panel layout, so it shows immediately -- even solo on a fresh install). The expand/collapse toggle stays clickable while moving — and can itself be dragged to move. Closing the window leaves move mode.
- **Y** — move the manager vertically, with a box for exact values (or drag it in move mode)
- **Hide** — `never` keeps the manager fully visible, `when cursor away` fades it out while it is collapsed and the cursor is elsewhere (hovering brings it back), `always` hides it at all times, even on hover; `never` is the default
- **Strata** — change the manager's strata, shown as 2–9; it starts preselected on the game's own value
- **info icons** — hovering the little icon beside each row explains that row

## Compatibility

- World of Warcraft: Forever (1.60.1)
- World of Warcraft: Midnight (12.1.0)
- World of Warcraft: Mists of Pandaria (5.5.4)
- World of Warcraft: Cataclysm (4.4.0)
- World of Warcraft: Wrath of the Lich King (3.4.3)
- World of Warcraft: The Burning Crusade (2.5.6)
- World of Warcraft: Classic Era (1.15.9)

## Links

- [Changelog](CHANGELOG.md)
