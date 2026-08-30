# Drafting Add-ins

AutoLISP tooling for an engineering office. The goal is a small, reliable
set of commands that take the repetitive parts of electrical plan production —
placing fixtures, numbering circuits and panels, drawing wiring runs — and turn
them into one keystroke each, without surprising the drafter or leaving the
drawing in a state they have to clean up.

This document is both the **overview** and the **house rules**. Anything added to
this folder is expected to follow the conventions in §6.

---

## 1. Setup

```
Command: APPLOAD  ->  Contents...  ->  Add...  ->  dt-load.lsp  ->  Close
```

That is the whole installation. [dt-load.lsp](dt-load.lsp) is the only file
in the Startup Suite; it finds its own folder and loads everything else in order.

If the folder is ever moved, update `*dt:fallback-root*` at the top of
[dt-load.lsp](dt-load.lsp) — that one line is the only path in the codebase.

> [legacy/](legacy/) holds the three original routines this was built from.
> Nothing loads them, and they can be deleted — just keep them out of the
> Startup Suite, since one of them redefines the native `COPY` command.

## 2. Commands

| Command | Aliases | What it does |
|---|---|---|
| `DT-FIXCEN` | `FIXCEN`, `FXC` | Pick two opposite corners of a room or bay; the current block lands at the exact centre. Repeats until Enter. |
| `DT-FIXDIV` | `FIXDIV`, `FXD` | Pick a line/arc/polyline (or two points) and a quantity; spaces that many blocks along it. Replaces draw-line + `DIVIDE` + place. |
| `DT-SETBLOCK` | `SB` | Choose which block those two place — by picking an existing one in the drawing, or by name. |
| `DT-WTREE` | `WTREE`, `WTR` | Select device blocks; draws loop-free wiring runs between them as bulged arcs. Builds a Euclidean minimum spanning tree (Prim's, O(n²)), then attaches each run to that symbol's own connection points. |
| `DT-SETPORT` | `SP` | Measure a symbol in the drawing — pick where wires meet it — and save that permanently. |
| `DT-PORTS` | — | List every measured symbol and its attachment points. |
| `DT-RENUMBER` | `RNB` | Renumber every group's `NUMBER` attribute once, in plan reading order. |
| `DT-SETGROUP` | `SG` | Select blocks, type a group name; tags them all and renumbers. |
| `DT-COUNTS` | — | Report how many of each group are in the drawing. |
| `DT-SETCIRCUIT` | `SC` | Writes a circuit label into each selected device's `CIRCUITO` attribute. |
| `DT-RENCIRCUIT` | — | Renames a circuit across the drawing, one at a time or from an `old,new` CSV. |
| `DT-LOAD` | `LD` | Totals connected load per circuit and writes a CSV. |
| `DT-SHEETS` | `SHT` | Renames the layout tabs to `<prefix><number>` in tab order, keeping any descriptive text. |

Together these cover one workflow: **place fixtures → number the circuits and
panels → wire them**. Everything we add should slot into a workflow that
concrete, not be a loose utility.

### Layout

```
addons/
  dt-load.lsp          <- the only thing in the Startup Suite
  dt-config.lsp        <- office settings; this is the file you edit
  dt-blocks.lsp        <- written by DT-SETPORT; never edit by hand
  src/
    dt-core.lsp        <- shared: sysvar save/restore, undo marks, layers
    dt-fixture.lsp     <- DT-FIXCEN
    dt-wiretree.lsp    <- DT-WTREE
    dt-label.lsp       <- DT-SETGROUP, DT-RENUMBER, DT-COUNTS
    dt-sheet.lsp       <- DT-SHEETS
    dt-load-takeoff.lsp<- DT-SETCIRCUIT, DT-RENCIRCUIT, DT-LOAD
  legacy/                 <- the pre-restructure originals, kept for reference
```

---

## 3. Placing blocks

### The current block is session state, not a constant

`*dt:fx:block*` in config is only the **starting** value. Which block
`DT-FIXCEN` and `DT-FIXDIV` place is remembered for the session and changed two
ways:

- `DT-SETBLOCK` (`SB`) — lists the block registry `*dt:blocks*` by number, so the drafter picks
  `2` rather than recalling a block name, and it works in an empty drawing.
  `P` at that prompt points at an existing instance instead (reading its
  effective name, so dynamic blocks resolve correctly); `N` types a name.
- The `Block` option inside `DT-FIXCEN` and `DT-FIXDIV`, so you can switch
  without leaving the command.

Reloading `dt-config.lsp` will not override a choice made with `DT-SETBLOCK` —
the drafter's pick outranks the startup default for the rest of the session.

### DT-FIXDIV spacing

Pick a line, arc or polyline (or `P` for two points), give a quantity, and the
blocks are placed along it. **Two spacing rules, because both get used and they
land in different places:**

| Mode | 3 blocks land at | When you want it |
|---|---|---|
| `divide` | `1/4`, `2/4`, `3/4` | Matches the native `DIVIDE` command's interior points — the workflow this command replaces. |
| `segment` | `1/6`, `3/6`, `5/6` | Each block centred in its own equal bay. What you want when the span is a room and every fixture should light an equal share. |

`*dt:fx:spacing*` sets the default; the `Mode` keyword at the quantity prompt
flips it for one command without touching config.

Because it walks the real curve, an arc or a curved polyline works the same as
a straight line — useful for a corridor that bends.

`*dt:fx:align*` rotates each block to follow the span direction. Safe to turn
on — `DT-WTREE` measures attachment points from each block's own rotation, so a
rotated symbol keeps its wiring stubs in the right place.

---

## 4. Wiring

`DT-WTREE` connects selected blocks with loop-free arcs — a minimum spanning
tree, so N blocks give exactly N-1 runs and nothing doubles back.

### Every symbol connects differently

Where a run meets a block is one field of its registry record in `*dt:blocks*`, not one
rule for the whole drawing:

```lisp
;;  block   port-distance   angles (degrees, from the BLOCK'S OWN rotation)
("L24"      0.376           (0.0 90.0 180.0 270.0))   ; fixture: four stubs
("TC"       0.376           (0.0))                    ; outlet: one, along the bars
```

Two properties make a rotatable symbol work:

- **Angles are relative to the block's rotation, not to world east.** Rotate an
  outlet 90° and its connection point follows. A fixture rotated 45° carries all
  four stubs around with it.
- **Port distance is multiplied by the block reference's scale**, so one profile
  covers the symbol inserted at any size.

`nil` for the distance measures half the bounding box instead — fine for a plain
symmetric symbol, but any attribute or text in the block inflates the box, so an
explicit number is safer.

### Measuring a symbol instead of typing numbers

You should never have to work out these numbers by hand. `DT-SETPORT` reads them
off the drawing:

```
Command: DT-SETPORT
Select the symbol to measure:            <- pick any instance of it
Attachment point (Enter when done):      <- pick each stub tip, OSNAP endpoint
Attachment point (Enter when done):
Attachment point (Enter when done):
Attachment point (Enter when done):
  1: 0 deg, 0.3760
  2: 90 deg, 0.3760
  3: 180 deg, 0.3760
  4: 270 deg, 0.3760
L24: 4 attachment point(s), distance 0.3760
Saved to dt-blocks.lsp -- it will load automatically.
```

Each pick yields an angle *and* a distance at once. Both are stored relative to
the block — its rotation is divided out of the angle, its scale out of the
distance — so measuring an instance that happens to be rotated or scaled still
produces a correct, reusable profile.

For the outlet you pick one point; for the fixture, four. `DT-PORTS` lists
what is currently stored.

**It persists.** `DT-SETPORT` writes `dt-blocks.lsp`, which
the loader reads *after* `dt-config.lsp`, so measurements override the shipped
defaults and survive restarts. Two consequences worth knowing:

- That file is **generated** — don't hand-edit it; run `DT-SETPORT` again.
- Once it exists, editing the profile list in `dt-config.lsp` has no effect,
  because the generated file wins. Delete `dt-blocks.lsp` to fall back to the
  config defaults.

The hand-written config is never rewritten by code and the generated file is
never hand-edited, so the two cannot clobber each other.

### Sharing an attachment point is normal

A one-port outlet in the middle of a chain has a wire in and a wire out, both
meeting it at the same place. `DT-WTREE` counts those and reports them:

```
14 runs drawn on layer E-WIRE. 3 run(s) share an attachment point.
```

That is information, not a warning. It only means something is wrong if the
count surprises you — for instance if a *fixture* is sharing, which needs five
or more runs meeting at one symbol.

---

## 5. Counting things

**You never edit code or config to count a new kind of thing.**

One block, `COUNT_TAG`, carries two attributes:

| Tag | Who fills it | Example |
|---|---|---|
| `GROUP` | the drafter | `C`, `P`, `TUG` |
| `NUMBER` | the routine, automatically | `01`, `02`, `03` |

Every distinct `GROUP` value gets its own independent `1..N` sequence. Counting
outlets as well as circuits and panels means typing `TUG` into a block's `GROUP`
attribute — nothing else. Three different things, one block definition.

`DT-SETGROUP` is the fast path: select the blocks, type the group name once, and
they are tagged and renumbered in a single step.

`DT-COUNTS` prints the tally per group:

```
  Group                       Count
  --------------------------- -----
  C                              24
  P                               3
  TUG                            41
  --------------------------- -----
  3 group(s)                     68
```

That report is also the typo detector. Group values are upper-cased, so `tug`
and `TUG` are the same group — but `TGU` is a new group with a count of 1, and
this is where you see it.

Blocks whose `GROUP` is blank are **skipped, not guessed at**, and both
`DT-RENUMBER` and `DT-COUNTS` say how many they skipped.

### Number format

`*dt:lbl:format*` is `(prefix suffix start pad)`, and `%G` in either string
expands to the group value:

```lisp
'("" "" 1 2)        ; ->  01, 02, 03           NUMBER holds just the number
'("%G-" "" 1 2)     ; ->  C-01, C-02, P-01     NUMBER holds the full tag
```

Which you want depends on whether the block displays `GROUP` as visible text
next to `NUMBER`, or whether `NUMBER` alone is the visible label.

### Making the block

`COUNT_TAG` does not exist yet. Draw it once and add it to the office template,
the same way `L24` and `TOMACORRIENTE 120V` already are.

**What the code requires** — get these wrong and nothing works:

| | |
|---|---|
| Block name | `COUNT_TAG`, matching `*dt:lbl:block*` |
| Attribute 1 | tag `GROUP` |
| Attribute 2 | tag `NUMBER` |
| Attribute mode | **not Constant** — see below |

Both must be real attribute definitions (`ATTDEF`) inside the block. A
**Constant** attribute is baked into the definition rather than stored per
insert, so it is not writable and the routine cannot number it — the tag will
simply be skipped. Invisible, Preset and Verify modes are all fine.

**The one design decision: is `GROUP` visible?** Two setups both work, and they
change what you put in `*dt:lbl:format*`:

| Setup | On the drawing | `*dt:lbl:format*` |
|---|---|---|
| `GROUP` **visible**, `NUMBER` visible | two pieces of text, `C` and `01` | `'("" "" 1 2)` — `NUMBER` holds just the number |
| `GROUP` **invisible**, `NUMBER` visible | one piece of text, `C-01` | `'("%G-" "" 1 2)` — `%G` expands to the group |

The second is usually tidier: the drafter still types the group, but the tag
reads as a single label. `GROUP` is then a hidden key rather than drawn text.

**Practical settings** — none of these are enforced, but they save trouble:

- **Put the insertion point at the centre of the symbol.** Numbering sorts by
  insertion point (top-to-bottom, then left-to-right), so a consistent, sensible
  origin is what makes the order match what a person reads.
- Justify the attributes **Middle Center** so the number sits centred as it
  grows from `1` to `24`.
- Give `NUMBER` a default like `00` — an untagged tag then looks obviously
  unfinished rather than blank.
- Leave `GROUP`'s default empty, or preset it to whatever you place most. Blank
  is safe: those tags are skipped and reported, never mis-counted.
- Make it **annotative** if the office uses annotative scaling; the routine
  neither knows nor cares.
- Lock the attribute positions in the block editor so they cannot drift.

If different groups need to *look* different, make `COUNT_TAG` a dynamic block
with visibility states rather than several block definitions. The routine
resolves each reference's effective name, so the anonymous names (`*U12`) that
dynamic blocks take on are handled correctly.

---

## 6. Design Standards

These are the rules. They exist because AutoLISP runs *inside* the user's
session — a badly behaved routine doesn't crash its own process, it leaves the
drafter with OSNAP off, a broken undo stack, or a drawing full of entities on
the wrong layer.

### 6.1 A command is a transaction

Every `c:` command must be all-or-nothing from the drafter's point of view:
one `U` undoes the whole thing, and nothing about their session changes.

```lisp
(defun c:DT-FOO ( / *error* saved doc )

  (defun *error* (msg)
    (dt:restore-vars saved)      ; nil-safe, so it works before setup ran
    (dt:undo-end doc)            ; always close what you opened
    (dt:report-error msg))       ; quiet on Esc, loud on real faults
  ...)
```

Non-negotiables:

- **The handler must be named `*error*`, not `error`.** AutoLISP calls nothing
  else. Localize it in the argument list so it is torn down when the command
  exits. (The original `centrar_luminaria.lsp` defined `error`, so the handler
  never ran and system variables survived an Esc unrestored.)
- **Save and restore every system variable you touch** — via `dt:save-vars`
  / `dt:restore-vars` — on all exit paths, including Esc.
- **Wrap drawing changes in an undo mark** — `dt:undo-begin` /
  `dt:undo-end`. If the command can bail out midway, the error handler
  closes the mark.
- **Save only what you actually change.** Restoring a variable you never touched
  is noise that hides the ones that matter.

### 6.2 Never shadow a native AutoCAD command

Redefining a native command breaks scripts, menu macros, and any drafter's
muscle memory for the standard behavior — and it is invisible until something
misbehaves.

- Use our own command names, always. `DT-` prefix, with a short alias.
- If a native command genuinely must be wrapped, do it explicitly with
  `undefine` / `redefine` and document it loudly at the top of the file.
- Reactor-driven behavior is the better answer: react to the copy, don't
  replace the copy command.

### 6.3 Namespacing and naming

| Thing | Convention | Example |
|---|---|---|
| Shared helpers | `dt:verb-noun` | `dt:ensure-layer` |
| Module-private helpers | `module:verb-noun` | `wt:draw-edge`, `lbl:sort` |
| Config globals | `*dt:module:name*` | `*dt:wt:layer*` |
| Commands | `DT-NAME` plus a short alias | `DT-WTREE` / `WTR` |
| Files | `dt-<module>.lsp`, lowercase, no spaces | `dt-wiretree.lsp` |

Every symbol a file defines at top level is global to the AutoCAD session. Two
routines that both define `midpoint` will silently overwrite each other. The
prefix is what prevents that.

Identifiers, filenames and comments are English. Command-line prompts can be
Spanish if the office prefers — that is a separate decision from the code.

### 6.4 Local variables, always

Declare every variable after the `/` in the argument list. An undeclared `setq`
inside a function creates a **global** that persists for the whole AutoCAD
session and will collide with the next routine.

Pass state as arguments rather than reading the caller's locals through dynamic
scoping. (`fixcen:restore-vars` used to read `old-cmdecho` out of its caller,
which meant it could only ever be called from that one command.)

The one deliberate exception is `lbl:current`, which carries the running command
name from one reactor callback to the next and therefore cannot be localized.

### 6.5 Validate before you draw

Check preconditions and fail with a clear message *before* creating geometry or
modifying any variable. `dt:require-block` and `dt:ensure-layer` return
values you branch on, rather than calling `(exit)` — expected outcomes should
use ordinary control flow, not the error handler.

Create layers if missing; never assume the drafter's template has them.

### 6.6 Report what happened

End every command with a one-line summary, and surface degraded results rather
than failing silently:

```
14 runs drawn on layer E-WIRE. 2 run(s) share a stub: more than four runs meet at a fixture.
```

### 6.7 Comments

AutoLISP has no docstrings. A bare string after the argument list — as in
`(defun foo () "Renumber all blocks" ...)` — is just an expression that gets
evaluated and thrown away. Use `;;;` for a file or function header, `;;` for a
block, `;` for a trailing note.

Comment the **why**, not the what. The best comments in this codebase are the
ones explaining that the INSUNITS auto-scale factor is baked in before our own
scale arguments apply, that an MST vertex can carry six edges against four
stubs, and that `vl-sort` silently discards elements its comparator calls equal.
That is the standard to hold.

### 6.8 Loading must have no side effects

Loading a file should define functions and print one load message. Nothing more.
This is why numbering is on demand: an earlier version installed a reactor
that renumbered as you drew, and it was removed. A live reactor is a standing
cost in every drawing for something `DT-RENUMBER` does when asked.

---

## 7. Configuration

**A drafter must never edit code to change a value.** Every tunable — block
names, layer names, colours, attribute tags, prefixes, arc angles, stub
distances — lives in [dt-config.lsp](dt-config.lsp), commented, with units
stated.

Config is read **at command time**, not captured at load time, so after an edit:

```lisp
Command: (load "dt-config.lsp")
```

and the next command picks up the change. No AutoCAD restart.

Two settings are worth a deliberate decision before the office uses this in
anger:

- **`*dt:wt:port-dist*`** (currently `0.376`) — distance from a fixture's
  insertion point to a stub tip. Set to `nil` to measure per block from the
  bounding box instead; that fallback breaks on blocks carrying attributes or
  text, which inflate the box, so an explicit number is safer.
- **`*dt:lbl:row-tol*`** (currently `0.0`) — row banding for reading-order
  numbering. At `0.0` two fixtures are only "the same row" if their Y matches
  exactly. Set it to roughly half a fixture spacing in your drawing units for
  the numbering to run across rows the way a person reads the plan.

---

## 8. Open items

**Verification status:** the code is checked for balanced parentheses, for every
namespaced call resolving to a definition, and for every config key being both
defined and used. None of it has been run inside AutoCAD yet — that is the next
step, and this list is the order to work through.

1. **Test in AutoCAD.** In order: load, `DT-SETBLOCK`, `DT-FIXCEN`, `DT-FIXDIV`,
   `DT-SETPORT` on both symbols, `DT-WTREE`, `DT-RENUMBER`, then
   Check that Esc mid-command leaves OSNAP and the undo stack intact, and that
   one `U` undoes one command.
2. **Measure the real symbols** with `DT-SETPORT` (§4). The `L24` and `TC`
   numbers shipped in config are placeholders — `TC` in particular is a copy of
   the fixture's distance and is almost certainly wrong for the `O=` bars.
3. **Set `*dt:lbl:row-tol*`** to a real value for the office's typical plan
   scale (§7), then confirm the numbering reads the way an engineer expects.
4. **Add `COUNT_TAG` to the office template**, alongside `L24` and `TC`. Jobs
   always start from a template that already carries the block definitions, so
   that is where a new symbol needs to land — the tools assume their blocks are
   already defined and just report if one is not.
5. **`*dt:fallback-root*` is machine-specific.** Fine for one workstation;
   put the folder on the support path (OPTIONS > Files) before rolling out
   more widely, and the fallback stops mattering.
6. **Non-uniformly scaled blocks.** `DT-WTREE` scales a profile's port distance
   by the block's X scale factor only. A block stretched in X but not Y will
   put its attachment points slightly off. Rotation and uniform scale are
   handled correctly.
7. **Put this folder in git.** Version belongs in history, not in filenames, and
   [legacy/](legacy/) can then be deleted rather than kept as a manual backup.

---

## 9. Adding a new command — checklist

- [ ] `c:DT-NAME` function with everything localized after `/`
- [ ] `*error*` handler that restores sysvars and closes the undo mark
- [ ] `dt:undo-begin` / `dt:undo-end` around drawing changes
- [ ] Preconditions validated before anything is created
- [ ] Zero hard-coded block names, layers, colours or distances — all in config
- [ ] Config read at command time, not at load time
- [ ] `dt:` or `module:` prefix on every function and global
- [ ] Layers created if missing, never assumed
- [ ] One-line result summary; degraded cases reported, not swallowed
- [ ] No side effects at load time
- [ ] Header comment: what it does, the command name, how to use it
- [ ] Added to the loader's file list and to the table in §2
