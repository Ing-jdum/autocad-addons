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
| `DT-SETCIRCUIT` | `SC` | Tag devices with a circuit label |
| `DT-RENCIRCUIT` | — | Rename circuits, one or from a CSV |
| `DT-LOAD` | `LD` | Load per circuit, to CSV |
| `DT-SHEETS` | `SHT` | Number the layout tabs in tab order |

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

---

## Circuits and load — `SC`, `LD`

Tag devices into circuits, then export what each one draws. The order matters:
**circuit numbers come last**, because you balance the loads to decide them.

```
1. SC             group devices under any label -- "cocina", "A", "1"
2. LD             export every circuit to one CSV
3. balance in Excel
4. DT-RENCIRCUIT  apply the final numbers back to the drawing
```

### Tag a circuit — `SC`

First time in a drawing there is nothing to pick from, so it just asks:

```
Command: SC
Select the devices in one circuit:            <- select, Enter
  No circuits tagged yet -- this will be the first.
Circuit label: cocina
7 device(s) set to circuit cocina.
```

After that it lists what exists, so you pick a number instead of retyping —
which is what stops `cocina` and `Cocina` becoming two different circuits:

```
Command: SC
Select the devices in one circuit:            <- select, Enter
  Circuits in this drawing:
   1. cocina                  7 device(s)
   2. habitaciones1          12 device(s)
Circuit number, or [New/Clear] <cocina>: N
New circuit label: sala
9 device(s) set to circuit sala.
```

`N` makes a new circuit. `C` clears the label off the selection.

The label lives in each device's `CIRCUITO` attribute, which is invisible — it
doesn't print, but Properties and `EATTEDIT` still show it if you need to fix
one by hand.

### Export the load — `LD`

Select everything. Rows come out grouped by circuit:

```
Command: LD
Select the devices to total (all of them, normally):    <- select all, Enter

  Circuito 1
  Descripcion                        V      VA   Cant     Total
  ---------------------------------- ---- ----- ------ ---------
  TOMACORRIENTE 120V                  120   150      3       450
  ---------------------------------- ---- ----- ------ ---------
                                                     3       450

  Circuito 2
  ...

  Total connected load: 1500 VA

Written to C:\...\LEYENDA-EJEMPLO-VIVIENDAS-load.csv
```

and the CSV pastes straight into Excel:

```
Circuit,Description,Voltage,VA each,Qty,Total VA
"1","TOMACORRIENTE 120V","120",150,3,450
"2","TOMACORRIENTE 120V","",150,3,450
"3","SALIDA CENITAL","",60,10,600
```

**Rows split by what a device *is*, not which block it is.** The same
`TOMACORRIENTE 120V` used as a general outlet and as a fridge gives two rows,
because the description and VA differ. That's the point — counting the block
alone would merge loads that have nothing to do with each other.

Devices you haven't tagged yet land in a `(sin circuito)` row, which doubles as
your "what did I miss" check.

> A blank `VOLTAJE` just shows as empty — it doesn't affect anything, since the
> totals add VA. A blank `POTENCIA` is different: those devices are **left out
> of the totals** and reported, because counting them as zero would understate
> the circuit.

### Apply the final numbers — `DT-RENCIRCUIT`

Once you've balanced and decided `cocina` is really circuit 3, hand the mapping
back as a CSV — the same file you did the balancing in:

```
old,new
cocina,3
habitaciones1,1
sala,2
```

```
Command: DT-RENCIRCUIT
  Circuits in this drawing:
   1. cocina                  7 device(s)
   2. habitaciones1          12 device(s)
   3. sala                    9 device(s)
Rename which number, or [File]? F
                                              <- pick the CSV
28 device(s) renumbered from 3 of 3 mapping(s).
```

The header row is optional. Anything in the file that isn't in the drawing is
listed so you can see it was skipped.

Renaming two circuits onto the same label merges them, which is a normal result
of balancing. Doing it one at a time (pick a number instead of `F`) asks first,
since that one is easy to do by accident.

---

## Numbering the sheets — `SHT`

Renames the layout tabs to `EL-01`, `EL-02`, … **left to right along the tabs**.
Reorder the tabs, run it again, and the set renumbers to match.

```
Command: SHT
Sheet prefix <EL->:              <- press Enter, or type a different one
4 layout(s) numbered EL-01 to EL-04.
```

The prefix is whatever you want — `EL-`, `ME-`, `CI-`. It offers the one you
used last, so on the second sheet set of the day it's just `SHT` then Enter.

**Your descriptions are kept.** Only the number in front is rewritten:

```
  tab order            becomes
  EL-03 LIGHTING  ->   EL-01 LIGHTING
  PLANTA          ->   EL-02 PLANTA
  EL-01 DETAILS   ->   EL-03 DETAILS
  Layout1         ->   EL-04
```

A tab that was never numbered — `PLANTA` — keeps its whole name and just gains
a number in front. The **Model** tab is never touched.

> A name like `PLANO 2 DE 5` is treated as *unnumbered* and kept whole, so it
> becomes `EL-01 PLANO 2 DE 5`. That's deliberate: a space is not accepted as
> the separator before a number, otherwise it would read `PLANO` as the prefix,
> `2` as the number, and throw away everything but `DE 5`.

If a rename fails partway for any reason, all the tabs go back to their original
names rather than being left half renamed.

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
9.  SC          tag each circuit's devices
10. LD          export the load per circuit
11. DT-RENCIRCUIT   apply the balanced numbers back from Excel
12. SHT         number the layout tabs once the sheets are laid out
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
