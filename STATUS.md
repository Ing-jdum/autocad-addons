# Where we left off — 2026-08-29

Working notes for picking this back up. [README.md](README.md) is the technical
reference, [GUIDE.md](GUIDE.md) is the drafter-facing manual. This file is just
the handoff.

## State of the code

All six files parse (balanced parens), every namespaced call resolves to a
definition, and every config key is both defined and used.

**Confirmed working in AutoCAD:**

- The tools load.
- `DT-SETPORT` measures correctly, including the outlet — which is what the
  block-coordinate rewrite was for. `dt-blocks.lsp` records its two bars as
  `(0.033948 0.224486)` and `(-0.033089 0.224693)`: symmetric about the centre
  line, same height. That is the offset-from-centre geometry the old radial
  model could not hold.
- `DT-WTREE` wires outlets correctly, **including mirrored ones** — the negative
  scale factor path through `wt:to-world`, and the specific case the old radial
  model got wrong.

- `COUNT_TAG` exists and is in use; group tagging and numbering work.

**The wiring module is fully verified.** That was the project's largest
technical risk and it is now closed.

Untested: `DT-FIXCEN`, `DT-FIXDIV`, `DT-SETBLOCK` — the placement side — and
`DT-SHEETS`. The layout-name parsing in `DT-SHEETS` is verified against ten
cases, but its COM side (`vla-get-TabOrder`, `vla-put-Name`, the two-pass
rename) has only been reasoned about. Try it on a copy of a drawing first.
`DT-NOLW` is also untested in AutoCAD.

```
dt-load.lsp        Startup Suite entry point; sets *dt:root*
dt-config.lsp      everything you edit by hand
dt-blocks.lsp      GENERATED block registry (does not exist until first run)
src/dt-core.lsp    sysvar save/restore, undo marks, layers, validation
src/dt-fixture.lsp DT-FIXCEN, DT-FIXDIV, DT-SETBLOCK
src/dt-wiretree.lsp DT-WTREE, DT-SETPORT, DT-PORTS
src/dt-label.lsp   DT-SETGROUP, DT-RENUMBER, DT-COUNTS
src/dt-sheet.lsp   DT-SHEETS, DT-NOLW
src/dt-load-takeoff.lsp  DT-SETCIRCUIT, DT-RENCIRCUIT, DT-LOAD
legacy/            the three original routines; nothing loads them
```

## Latest change: one block registry

`*dt:blocks*` in [dt-core.lsp](src/dt-core.lsp) is now the single per-symbol
record, shared by every module:

```lisp
(block-name  description  ((x y) (x y) ...))
```

It replaces the old split, where the menu list lived in config (hand-edited) and
the attachment points lived in a generated file. A symbol is now **one thing to
set up**: `DT-SETPORT` measures it, asks for a description if it has never been
seen, registers it, and it appears in `DT-SETBLOCK`'s menu from then on. No
config editing to add a symbol, ever.

- Generated file renamed `dt-profiles.lsp` → **`dt-blocks.lsp`**.
- `*dt:fx:blocks*` and `*dt:wt:profiles*` are **gone**, merged into `*dt:blocks*`.
- Registry helpers (`dt:block-entry`, `dt:block-ports`, `dt:put-block`,
  `dt:save-blocks`) moved into core, since both modules use them.
- `dt:polar-pt` deleted — the earlier rewrite was its only caller.

## The change before that

**Rewrote how wiring attachment points are stored**, because `DT-SETPORT` worked
on the light fixture but not on the outlet.

The cause: attachment was stored as a **distance + angle** and rebuilt with
`dt:polar-pt`, reading only DXF group 41 (X scale). That breaks outlets two ways
the fixture hides:

- A **mirrored** insert (an outlet on a facing wall) has group 41 = −1. The
  distance went negative and the attachment point landed 180° opposite.
  Mirroring a symmetric four-stub fixture is invisible.
- The outlet's bars sit **off the centre line**, so its connection point is not
  on a ray from the insertion point. A radial model cannot express that; a
  coordinate can.

Now stored as **points in block coordinates** — what you'd read in the block
editor with the insertion point at the origin — and put through the block
reference's real transform at draw time:

```
world = insertion + R(rotation) . S(x-scale, y-scale) . point
```

`wt:to-world` / `wt:to-block` in [src/dt-wiretree.lsp](src/dt-wiretree.lsp) are
exact inverses, which is what lets `DT-SETPORT` measure a rotated/scaled/mirrored
instance and still record a profile true for every other instance.

This also closed the old "non-uniform scale" open item, and removed the angle
rounding and the distance averaging — both existed only to prop up the radial
model.

### Config format changed with it

Attachment points are now `(x y)` in block coordinates:

```lisp
("L24" ((0.376 0.0) (0.0 0.376) (-0.376 0.0) (0.0 -0.376)))
("TC"  ((0.376 0.0)))
```

`*dt:wt:default-profile*` is **gone** — an unmeasured block now falls back to
four cardinal points off its bounding box, turned with the block.

> **If `dt-profiles.lsp` exists from an earlier run, delete it.** It holds the
> old format and is no longer read — the file is `dt-blocks.lsp` now.

## Do this first when we resume

1. **Placement**: `DT-SETBLOCK` (the numbered menu), then `DT-FIXCEN`, then
   `DT-FIXDIV` — both spacing modes, and the arc/polyline path.
2. Check Esc mid-command leaves OSNAP and the undo stack intact, and that one
   `U` undoes one whole command.

## Known loose ends

- **`*dt:lbl:row-tol*` is `0.0`**, which means exact-Y matching and no useful
  row banding. Wants roughly half a fixture spacing in drawing units.
- **`*dt:fallback-root*` in [dt-load.lsp](dt-load.lsp)** is a hardcoded path to
  this machine. Putting the folder on the support path (OPTIONS > Files) makes
  it irrelevant.
- **`L24` has never actually been re-measured.** Its points in `dt-blocks.lsp`
  came from `dt-config.lsp`, which I migrated from the old file: three exact
  cardinals at 0.10645 with the fourth inferred by symmetry. Worth one
  `DT-SETPORT` pass to confirm the inferred stub is real.
- **Not in git.** Once it is, [legacy/](legacy/) can go.

## Offered but not built

- **`DT-HELP`** — reprint the command list on demand. The load banner scrolls
  away, which is how `DT-SETBLOCK` got missed. ~15 lines.
- **Persisting the current block** across sessions. Now cheap: the writer
  (`dt:save-blocks`) already lives in core, so this is a field on the registry
  or one more line in the generated file. Not done because starting each
  session on the office default may well be the better behaviour — decide
  before building.

## Decisions worth not relitigating

- No backward compatibility anywhere — nothing has shipped, simplicity wins.
- Nothing carries the company name; namespace is `dt:`, commands are `DT-`.
- Blocks come from the office template. Routines assume their blocks exist and
  report if one does not; no block-library loading.
- Hand-written config is never rewritten by code; generated files are never
  hand-edited. That is why `dt-blocks.lsp` is separate from `dt-config.lsp`.
