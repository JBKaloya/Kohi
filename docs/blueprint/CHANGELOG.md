# Blueprint changelog

## 2026-11-11 · `3894307` · sync 3

Brew feedback of 11 November, on the working tree at that SHA (not committed yet). Only the brew journey is patched.

- **J6** Kit is no longer a step. It is prefilled from the recipe or this card's last brew, and the Kit line on How much? opens the Equipment sheet. Frames: `brew-kit` (now a sheet), `brew-dial`, `brew-dial-no-grinder`.
- **J6** How much? shows the Kit line, the Advance chips (Auto by default, Tap, Cues), Before you pour, and "Already brewed? Log it".
- **J6** "Start a brew" is drawn, with the new "Log a brew made elsewhere" choice. Which recipe? gets "New recipe" in Mine.
- **J6** It's done: Kit and grind can be corrected for this brew only, and "Save as recipe" sits under the summary with "Keep these steps for next time". A saved brew opens read-only behind "Edit this brew".
- **J6** A brew without a coffee: "Skip, add the coffee later" on the coffee picker, then the "Add the coffee" sheet.
- **+** `brew-start` (25:51), `brew-after-saved` (25:128), `link-coffee` (25:226). The `coffee-picker` frame gets the Skip line.
- Prototype J6 now runs Detail → Start → Which recipe? → How much? → Pour → It's done. The old `J6 kit` frame (6:978) is reused as `J6 start`.
- Parcours J6 note and the Cover stamp updated.
- Not patched (drift since `c975c28`): tastings, the 2-column grid, the card split into Coffee and Brews, ScanIntentSheet, and the 4:5 grid crop. DEBUG-only surfaces stay off the canvas.
- The named Figma version still has to be saved by hand: the plugin API does not allow it.

## 2026-10-26 · `c975c28` · sync 2

Journey change on the working tree at that SHA (the brew controls are not in the commit yet).

- **J6** Dial no longer has a Brew button. The footer reads "Swipe up to brew". "Log without timer" still skips Pour. Frames: `brew-dial`, `brew-dial-no-grinder`, prototype `J6 dial`.
- **J6** Pour narration is "Tap to narrate" (tap to start, tap the disc to keep). Frames: `guided-brew`, prototype `J6 pour`.
- Parcours J6 note and the Cover stamp updated. No new screens, no new node ids.

## 2026-09-19 · `03c448a` · sync 1

First file. As-shipped map of the current binary.

- **+** Cover, tokens (Palette), sitemap, 11 journeys
- **+** ~36 iPhone mid-fi frames (First coffee, Archive, Brew, Recipes, Profile)
- **+** Chrome components (Nav, Tabs, FAB scan/cup, Chip, Row, Card object)
- **+** Present flows J2 and J6 on page 09 Prototype
- Inter stands in for SF / Angusta
- PRD §5 ignored (Setup is Profile, not a Recipes label)
