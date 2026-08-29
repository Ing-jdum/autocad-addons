# Drafting Tools — User Guide

A set of AutoCAD commands for electrical plans: place fixtures, space them along
a run, wire them together, and number them. This guide is for using them. If you
maintain the code, read [README.md](README.md) instead.

---

## Install (once per machine)

1. In AutoCAD, type `APPLOAD` and press Enter.
2. Click **Contents…** (under "Startup Suite", bottom right).
3. Click **Add…**, browse to this folder, pick **`dt-load.lsp`**, click Open.
4. Click **Close**, then **Close** again.
5. Restart AutoCAD.

You should see this in the command line when a drawing opens:

```
Drafting tools loaded.
  DT-FIXCEN   (FIXCEN, FXC)  place block at centre of picked area
  DT-FIXDIV   (FIXDIV, FXD)  space N blocks along a line or curve
  ...
```

If you don't, jump to [Troubleshooting](#troubleshooting).

### The blocks

The tools place and read these blocks. They come from your office template, so
in a normal job they are already there:

| Block | What it is |
|---|---|
| `L24` | The light fixture — circle with stubs at N/E/S/W |
| `TC` | The outlet — the `O=` symbol |
| `COUNT_TAG` | The numbering tag, with two attributes: `GROUP` and `NUMBER` |

Names are set in `dt-config.lsp`, so they can be changed to match your standard.

If a command says a block "is not defined in this drawing", that drawing didn't
come from the template — insert one copy of the block from another drawing and
carry on.

---

## Command reference

Every command has a short alias. Use whichever you like.

| Type this | Or this | What it does |
|---|---|---|
| `DT-FIXCEN` | `FIXCEN` `FXC` | Centre a block in an area you pick |
| `DT-FIXDIV` | `FIXDIV` `FXD` | Space N blocks along a line |
| `DT-SETBLOCK` | `SB` | Choose which block those two place |
| `DT-WTREE` | `WTREE` `WTR` | Wire the selected blocks together |
| `DT-SETPORT` | `SP` | Teach the tools where wires meet a symbol |
| `DT-PORTS` | — | Show what `DT-SETPORT` has learned |
| `DT-SETGROUP` | `SG` | Tag blocks as a counting group |
| `DT-RENUMBER` | `RNB` | Renumber every group now |
| `DT-COUNTS` | — | Count how many of each group |
| `DT-AUTOLABELON` | — | Renumber automatically as you draw |
| `DT-AUTOLABELOFF` | — | Stop doing that |

---

## Placing fixtures

### Centre one in a room — `FIXCEN`

Pick two opposite corners of the room. The block lands dead centre. It keeps
asking, so you can do a whole floor without restarting.

```
Command: FIXCEN
First corner of area or [Block=L24] (Enter to finish):    <- pick a corner
Opposite corner:                                          <- pick the opposite
First corner of area or [Block=L24] (Enter to finish):    <- next room
Opposite corner:
First corner of area or [Block=L24] (Enter to finish):    <- press Enter
2 L24 blocks placed.
```

The rectangle you drag is only a guide — no line is drawn, nothing to erase.

Turn on **endpoint** and **intersection** osnaps so you can snap to the actual
wall corners.

> **Undo:** one `U` undoes everything you placed in that run of the command, not
> one block at a time.

### Space several along a run — `FIXDIV`

This replaces the old routine of drawing a line, running `DIVIDE`, then placing
blocks on the points.

```
Command: FIXDIV
Select line, arc or polyline or [Points]:    <- pick an existing line
Number of blocks or [Mode=divide]: 3
3 L24 block(s) placed, on interior division points.
```

No line to work with? Type `P` and pick two points instead:

```
Command: FIXDIV
Select line, arc or polyline or [Points]: P
Start point:                                 <- pick
End point:                                   <- pick
Number of blocks or [Mode=divide]: 3
```

Arcs and curved polylines work too — the blocks follow the curve.

#### The two spacing modes — this matters

"Three fixtures evenly over a distance" means two different things, and you want
different ones on different jobs:

```
divide     |----o----o----o----|      3 blocks at 1/4, 2/4, 3/4
segment    |--o-----o-----o--|        3 blocks at 1/6, 3/6, 5/6
```

- **`divide`** puts them on the interior division points — the same result the
  native `DIVIDE` command gives you.
- **`segment`** splits the span into 3 equal bays and centres one block in each.
  **This is usually what you want for lighting**, where each fixture should
  light an equal share of the room.

Type `M` at the quantity prompt to switch between them. The prompt always shows
which one you're in: `[Mode=divide]` or `[Mode=segment]`.

### Changing which block gets placed — `SB`

You never edit a file to do this. `SB` lists the office's blocks by number:

```
Command: SB
  Configured blocks:
   1. L24           2x4 light fixture   <- current
   2. TC            outlet / tomacorriente
Block number, or [Pick/Name] <keep L24>: 2
Current block: TC
```

Now `FIXCEN` and `FIXDIV` place `TC` until you change it again or close AutoCAD.
Press Enter instead of a number to keep what you have.

Two other ways at that same prompt:

- **`P`** — point at a block already in the drawing and use that one. Handy for
  a symbol that isn't in the list.
- **`N`** — type a block name.

You can also switch **without leaving** `FIXCEN` or `FIXDIV` — type `B` at the
first prompt and you get the same menu.

> **Adding a block to the list** needs no file editing at all. Run `SP`
> (`DT-SETPORT`) on the new symbol: it asks for a short description, records
> where its wires attach, and from then on it is in this menu. See
> [Setting up a new symbol](#first-time-with-a-new-symbol--sp).

---

## Wiring — `WTREE`

Select the blocks you want connected. It draws arcs between them with no loops
and no doubling back, on layer `E-WIRE` (created automatically).

```
Command: WTREE
Select device blocks to wire:                <- window round them, Enter
14 runs drawn on layer E-WIRE.
```

It works out the shortest sensible set of connections for you — you don't pick
pairs. Connect 20 fixtures by selecting all 20 at once.

### Setting up a new symbol — `SP`

This is the whole setup for a symbol, and you do it once, ever. `SP` records
**where** a wire should attach — and if the symbol is new, it registers it, so
it also turns up in `SB`'s menu afterwards. No file editing at any point.

```
Command: SP
Select the symbol to measure:                <- pick one L24
Measuring L24. Pick each point where a wire should meet it.
Attachment point (Enter when done):          <- pick the E stub tip
  1: block x 0.3760, y 0.0000
Attachment point (Enter when done):          <- pick the N stub tip
  2: block x 0.0000, y 0.3760
Attachment point (Enter when done):          <- pick the W stub tip
  3: block x -0.3760, y 0.0000
Attachment point (Enter when done):          <- pick the S stub tip
  4: block x 0.0000, y -0.3760
Attachment point (Enter when done):          <- press Enter
L24: 4 attachment point(s) recorded.
Saved to dt-blocks.lsp -- it will load automatically.
```

A symbol it has never seen is registered on the spot:

```
Command: SP
Select the symbol to measure:                <- pick the new downlight
...
SPOT is new.
Short description for the menu: recessed downlight
SPOT: 2 attachment point(s) recorded.
Saved to dt-blocks.lsp -- it will load automatically.
```

**Use endpoint osnap** so you land exactly on the attachment points.

For the fixture you pick four points. For the outlet, **pick one** — the end of
the `O=` bars — because an outlet has a single connection point.

It's saved to disk, per symbol. Setting up a second symbol never disturbs the
first, so switching between them costs nothing. `DT-PORTS` shows what's stored:

```
Command: DT-PORTS
  Block         Description             Attachment points (x y)
  ------------- ----------------------- -----------------------
  L24           2x4 light fixture       (0.376000 0.000000) (0.000000 0.376000) ...
  TC            outlet / tomacorriente  (0.376000 0.052000)
  SPOT          recessed downlight      not measured -- bounding box

  Anything not listed falls back to its bounding box.
  Measure or add one with DT-SETPORT.
```

Those numbers are **block coordinates** — where the point sits inside the block
itself, measured from its insertion point. That's why it doesn't matter which
instance you measured: rotated, scaled or mirrored, the recorded values are the
same, and every other copy of that symbol gets wired correctly.

### Rotated symbols just work

Outlets get rotated to sit against whatever wall they're on. The attachment
point rotates with the symbol, so wiring stays correct at any angle. You measure
the symbol once, in any orientation, and every rotated copy is handled.

### "3 run(s) share an attachment point"

Normal, not an error. An outlet in the middle of a chain has a wire coming in
and a wire going out, both meeting it at its single connection point.

It's only worth a look if the number surprises you — a *fixture* sharing means
five or more wires converged on one symbol, which is usually a sign the layout
needs a second circuit.

---

## Numbering and counting

### What this is for

On a plan you place little numbered tags next to things — circuit 1, 2, 3;
panel 1, 2, 3; outlet 1, 2, 3. Numbering them by hand is slow, and renumbering
after you add one in the middle is worse.

These commands do the numbering. You place the tags and say *what* each batch
is; the numbers fill themselves in and stay in order.

### One block does all the counting

You do **not** need a different tag block for circuits, panels and outlets.
There is one, `COUNT_TAG`, with two attributes:

| Attribute | Who fills it | Example |
|---|---|---|
| `GROUP` | **You** — what kind of thing this tag is counting | `C`, `P`, `TUG` |
| `NUMBER` | Filled in automatically | `01`, `02`, `03` |

**Each `GROUP` value counts separately, from 1.** That is the whole idea:

```
   (O=) [TUG-01]      outlets tagged GROUP = TUG   ->  01, 02, 03 ...
   (O=) [TUG-02]
    O   [C-01]        lights  tagged GROUP = C     ->  01, 02, 03 ...
    O   [C-02]                                          its own sequence
```

The group name is just a label you choose — `C`, `P`, `TUG`, `TAB`, whatever
your office writes on the drawing. Counting a new kind of thing means typing a
new group name. Nothing to configure, no new block.

### Tag a batch — `SG`

Place your tags, then tell a batch what it is:

```
Command: SG
Select blocks to tag as one group:           <- select the 24 outlet tags, Enter
GROUP value: TUG
24 block(s) set to GROUP = TUG, 24 number(s) updated.
```

That did two things at once: set `GROUP` to `TUG` on all 24 tags, and filled in
their `NUMBER` — `01` through `24`, in plan reading order. Do it again with the
light tags and `C`, and those get their own `01`, `02`, `03`.

### Renumber — `RNB`

After moving, copying or deleting tags, run `RNB` to put the numbers back in
order. Numbering runs the way you read a plan: top to bottom, left to right.

```
Command: RNB
41 attribute(s) renumbered.
```

### Count — `DT-COUNTS`

```
Command: DT-COUNTS
  Group                       Count
  --------------------------- -----
  C                              24
  P                               3
  TUG                            41
  --------------------------- -----
  3 group(s)                     68
```

Good for filling in a schedule. **Also your typo check** — `tug` and `TUG` are
treated as the same group, but `TGU` shows up as its own group with a count of
1. That's how you spot it.

### Automatic renumbering — `DT-AUTOLABELON`

Turns on live renumbering: copy a tag and everything renumbers itself. Off by
default because it's working constantly in the background.

`DT-AUTOLABELOFF` stops it. It's per drawing, and off again next time you open
AutoCAD.

---

## A typical job

```
1.  SB          pick the fixture block
2.  FIXCEN      centre one in each room
3.  FIXDIV      3 down the corridor, Mode=segment
4.  SB          pick the outlet block
5.  FIXCEN      place the outlets
6.  WTREE       select a circuit's worth, wire it
7.  SG          tag the circuit tags as group C
8.  DT-COUNTS   check the totals for the schedule
```

---

## Troubleshooting

**Nothing happens when I type the command / "Unknown command"**
The tools didn't load. Check `APPLOAD` → Contents… and confirm `dt-load.lsp` is
listed in the Startup Suite. Then restart AutoCAD.

**"Drafting tools: cannot locate the addons folder."**
The folder was moved or renamed. Whoever maintains the tools needs to update one
line in `dt-load.lsp`, or add the folder under **Options → Files → Support File
Search Path**.

**`Block "L24" is not defined in this drawing.`**
That block isn't in this drawing yet. Insert it once from your block library or
template, or use `SB` to pick a different block that is present.

**"Need at least two distinct blocks."** (`WTREE`)
You selected one block, or several stacked exactly on top of each other. Select
at least two in different places.

**"That is not a block reference."** (`SB` or `SP`)
You clicked a line, text or hatch. Click on the symbol itself.

**"That object cannot be divided."** (`FIXDIV`)
You picked something with no length — text, a block, a hatch. Pick a line, arc
or polyline, or type `P` to use two points.

**"N block(s) have no GROUP value and were skipped."**
Some tags have an empty `GROUP`. Select them and run `SG` to tag them.

**The wires attach in the wrong place**
That symbol hasn't been measured, or was measured wrong. Run `SP` on it again —
use endpoint osnap, and pick the tips where wires should actually meet.

**"Cannot save: load the tools through dt-load.lsp first."** (`SP`)
Someone loaded a file by hand instead of through the Startup Suite. Restart
AutoCAD.

**Everything undoes at once**
That's deliberate. Each command is a single undo step, so one `U` reverses the
whole command rather than one block at a time.

---

## Where the settings live

Two files, and you only ever open the first one:

- **`dt-config.lsp`** — block names, layers, colours, arc angle, numbering
  format and order. Commented throughout. After editing, either restart AutoCAD
  or type `(load "dt-config.lsp")` to pick up the change.
- **`dt-blocks.lsp`** — the block registry, written by `DT-SETPORT`: each
  symbol's name, description and attachment points. **Don't edit this by hand**;
  run `SP` again instead. Delete it to go back to the defaults in `dt-config.lsp`.
