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

Untested: `DT-TAG` (new, below), `DT-FIXCEN`, `DT-FIXDIV`, `DT-SETBLOCK` —
the placement side — and
`DT-SHEETS`. The layout-name parsing in `DT-SHEETS` is verified against ten
cases, but its COM side (`vla-get-TabOrder`, `vla-put-Name`, the two-pass
rename) has only been reasoned about. Try it on a copy of a drawing first.
`DT-NOLW` is also untested in AutoCAD.

Also untested in AutoCAD: **`DT-PANELS` and `DT-SETPANEL`** (`dt-panel.lsp`,
added for the La Colonial one-line). Statically verified only — parens balance,
every top-level form closes on itself, no undefined `dt:`/`pn:` call, and the
three config globals it reads are declared. The CSV split and the header/row
zip were transliterated to Python and run against eight cases including quoted
commas, doubled quotes, empty cells and short rows. None of that proves the COM
side (`vla-put-textstring` over the write plan). Run it on a copy first.

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

## Latest change: DT-TAG builds COUNT_TAG

`COUNT_TAG` used to have to come from the office template or an old drawing.
`DT-TAG` (`TG`) now builds it when the drawing has none: `lbl:make-block` in
[dt-label.lsp](src/dt-label.lsp) entmakes a BLOCK/ATTDEF/ATTDEF/ENDBLK
run — layer `0` so the insert's layer governs, `NUMBER` centred and visible,
`GROUP` invisible, both **preset** (flag 8) so insertion never prompts for
either. `NUMBER` defaults to the padded start number from `*dt:lbl:format*`,
so a fresh tag reads `01` instead of inserting blank.

No circle and no frame: the first version drew a bubble and it was unwanted.
Height is `*dt:lbl:tag-height*`, nil meaning the drawing's own `TEXTSIZE`
(`DIMTXT` when the text style has a fixed height), which removed the last
hardcoded drawing-units guess from this module.

`lbl:ensure-block` takes the same contract as `dt:ensure-layer`: build if
missing, never touch what is there. An existing `COUNT_TAG` wins whatever it
looks like, so the template stays the source of truth. It is called from
`lbl:collect`, the one place `DT-TAG`, `SG`, `RNB` and `DT-COUNTS` all route
through.

**Statically verified only** — parens balance across all nine files, every
namespaced call resolves, `*dt:lbl:tag-height*` is defined in config and read
in code. The entmake DXF for the ATTDEFs (72/74 justification needing group 11,
flag 70 = 8 preset and 9 invisible+preset, BLOCK flag 70 = 2) has been reasoned
about, not run. **Try `TG` in AutoCAD on a scratch drawing first** and check the
tag looks right before trusting it on a job.

## Per-group prefixes, set from AutoCAD

`*dt:lbl:format*` stays the shared `(prefix suffix start pad)` in
[dt-config.lsp](dt-config.lsp), with `%G` expanding to the group.
`*dt:lbl:prefix-overrides*` is an alist letting one group diverge:
`(("TUG" . "T-"))` makes `TUG` number as `T-01` while every unlisted group is
untouched.

**It is set by `DT-SETPREFIX` (`SPX`), not by hand.** The first cut of this put
the alist in `dt-config.lsp`, which broke the rule at the bottom of this file --
hand-written config is never rewritten by code. Per-group prefixes are a
drafter-facing setting, so they follow the `dt-blocks.lsp` pattern instead:

- `lbl:save-prefixes` writes **`dt-labels.lsp`**, a generated file, whole,
  with the same "DO NOT EDIT / delete it to go back to the config defaults"
  header `dt:save-blocks` uses.
- `dt-load.lsp` loads it with `dt:load-optional` after `dt-config.lsp`, so what
  the drafter recorded wins over the default.
- `src/dt-label.lsp` binds `*dt:lbl:prefix-overrides*` to `nil` at load time, so
  the variable is always bound whether or not the generated file exists.

`lbl:prefix-entry` does the lookup and `lbl:prefix-for` wraps it with the
fallback; the result still passes through `lbl:expand`, so `%G` works inside an
override. The lookup uses `vl-some` rather than `assoc` on purpose: `lbl:collect`
upper-cases every `GROUP` it reads, so a plain `assoc` would miss a key recorded
in lower case and silently fall back.

`lbl:prefix-ok` refuses a prefix containing `"` or `\`, because the string is
written into a file that is `load`ed at startup -- either character would break
the load and take every command down, not just the prefix. It uses
`vl-string-search` rather than `wcmatch`, since a prefix is exactly where
someone types a `*` or `?` and `wcmatch` would read those as pattern syntax.

Suffix has no per-group override, and the shared prefix is still config-only.
Neither has been asked for.

## Fixed: RNB reading order

Reported from the field: tags copied one at a time number fine, tags copied as
part of a multi-object `COPY` come out shuffled. Two separate faults, both in
the ordering, both reproduced before touching anything.

**1. `*dt:lbl:row-tol*` shipped at `0.0`.** That is an exact Y comparison, so
two tags a thousandth of a unit apart are different rows and reading order
collapses into a pure Y sort. A four-tag row drifting 3 mm over 1500 mm
numbered `C A D B`. This was already on this list as a loose end; it turned out
to be a live bug, not a nicety.

**2. Raising the tolerance alone would not have fixed it.** Above zero, "same
row?" is not transitive, and where the X order disagrees with the Y order the
old comparator *cycles*: A before C, C before B, B before A. Three tags fed to
`vl-sort` in six input orders produced three different numberings. The old
comment claimed this only moved a band boundary. It did not -- it made the
result depend on what the sort happened to compare.

`lbl:band` now assigns a row number in one pass over Y before any sorting, and
`lbl:sort` orders on (row, X, original index) -- three total orders read in
turn, so the comparator cannot cycle and no two records ever compare equal.
`lbl:less` became `lbl:less-columns`, since only `'columns` still uses it.

`DT-SETROW` (`SR`) sets the tolerance with `getdist`, which takes a typed
number *or two picked points* -- so the answer can be shown rather than known,
and nobody has to work out the drawing units. It writes `dt-labels.lsp`
alongside the prefixes, through the renamed `lbl:save-labels`.

### What legacy actually did

`legacy/AutoLabelAttributesV1-4.lsp` was cited as ordering correctly, and it
does -- because **it does no geometric sorting at all**. It walks the selection
set backwards (`(ssname sel (setq idx (1- idx)))` from `sslength` down) and
numbers in that order. Nothing about position enters into it, which is exactly
why copying never disturbed it.

So legacy is closest to `*dt:lbl:order*` `'database`, not to `'reading`. Note
the direction differs: legacy walks the selection **backwards**, `'database`
here walks it forwards. If the office wants the legacy sequence exactly,
`'database` needs reversing and that has not been done -- nobody has confirmed
which way round is wanted.

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
- **The CSV helpers are written twice.** `dt-panel.lsp` carries `pn:split-csv`
  and `pn:csv-cell`, which are the same code as `ld:split-csv` and
  `ld:csv-cell` in `dt-load-takeoff.lsp`. They belong in `dt-core.lsp` as
  `dt:`-prefixed functions, the way the block registry helpers were promoted.
  Not done yet because `dt-load-takeoff.lsp` is verified working in AutoCAD and
  this was not the moment to edit it. Do it the next time that file is open.
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
