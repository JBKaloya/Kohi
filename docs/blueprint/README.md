# Kohi Figma blueprint

Mid-fi map of the iOS app as shipped: sitemap, 11 journeys, iPhone frames (393×852), clickable proto for scan and brew.

**File:** [Kohi Blueprint](https://www.figma.com/design/kjMp5JEMr5xmZXlC3QYNEv)

| | |
| --- | --- |
| File key | `kjMp5JEMr5xmZXlC3QYNEv` |
| Last sync | 2026-09-19 · git `03c448a` · sync 1 |
| Source of truth | Swift + [fonctionnalites.md](../fonctionnalites.md), not PRD §5 |

## Present

Open page **09 Prototype**. Two flows:

1. **J2 Scan a card** — empty archive → camera → review → New card → grid → setup
2. **J6 Log a brew** — card detail → Scope → Kit → Dial → Pour → After

Tap the 393×852 frame to advance. Pages 04–08 hold the inventory screens (nested in boards). 09 is a top-level clone so Figma can `NAVIGATE`.

## Resync

In Cursor: *mets à jour le blueprint* / *resync Figma*. The agent loads [`.cursor/skills/kohi-figma-blueprint/`](../../.cursor/skills/kohi-figma-blueprint/SKILL.md), diffs code against `inventory.yaml`, and patches only what moved.

Needs the official Figma MCP in a Desktop session. Without it, the agent writes a drift note in `CHANGELOG.md` only.
