# Grind check — research (brief #5 §9)

**Status**: research only. 1.0 ships `GrindPreview` able to accept a measured distribution; nothing else from this section is in the binary.

## What 1.0 already does

`GrindPreview` is driven by the G1 µm bands (`RecipeRules.microns(for:)`: espresso 180–380, V60 400–700, French press 690–1300). A 1 mm hairline sits on the pile so the drawing has a scale. The optional `measured: [Double]?` argument is unused.

The rail is seven notches. A click column is bound both ways. `GrindSetting.position` (1…7) survives a grinder with no range. Helpers write `position` and `value`, never `raw`.

## Phase B — drop in a measured distribution

When a grind check exists (sieve stack, laser, or a photo pipeline), pass diameters in µm into `GrindPreview.measured`. Call sites of the preview do not change. Do not rewrite `FilterModel.flowClass` or the G1 bands from that sample.

## Phase C — still open

Whether the check is a photo of the bed, a Kruve stack, or an out-of-app lab file is undecided. The preview is the only 1.0 hook. Keep the decision here rather than in the brew flow.
