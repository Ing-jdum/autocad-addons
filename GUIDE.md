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
| `DT-TAG` | `TG` | Place counter tags, building `COUNT_TAG` if the drawing has none |
| `DT-SETGROUP` | `SG` | Tag blocks as a counting group |
| `DT-RENUMBER` | `RNB` | Renumber every group now |
| `DT-SETPREFIX` | `SPX` | Set one group's number prefix |
| `DT-SETROW` | `SR` | Set how far apart one row of tags is |
| `DT-SETORDER` | `SO` | Number by plan order, or by the order you inserted |
| `DT-SETLETTERS` | `LTR` | Count one group A, B, C instead of 1, 2, 3 |
| `DT-SETPAD` | `PAD` | Set one group's digits: `1`, `01` or `001` |
| `DT-SWITCH` | `SWL` | Tag switch legs, repeating the letter as you click |
| `DT-SWNEXT` | `SWN` | Place one switch tag at the next letter, then get out |
| `DT-SETSKIP` | `SKP` | Stop `RNB` renumbering one group |
| `DT-FIXDIM` | `FDM` | Dimension a row of fixtures, wall to wall |
| `DT-FIXDIMH` | `FDMH` | Same, measured across the sheet |
| `DT-FIXDIMV` | `FDMV` | Same, measured up the sheet |
| `DT-COUNTS` | — | Count how many of each group |
| `DT-SETCIRCUIT` | `SC` | Tag devices with a circuit label |
| `DT-RENCIRCUIT` | — | Rename circuits, one or from a CSV |
| `DT-LOAD` | `LD` | Load per circuit, to CSV |
| `DT-SHEETS` | `SHT` | Number the layout tabs in tab order |
| `DT-PREFIX` | `PFX` | Put text in front of picked texts / mleaders |
| `DT-NOLW` | `NOLWPLOT` | Plot every layout without lineweights |

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
and no doubling back, on **whatever layer is current** — set your wiring layer
before you run it, the same as drawing the runs by hand.

```
Command: WTREE
Select device blocks to wire:                <- window round them, Enter
14 runs drawn on layer E-ALUM-CTO.
```

It works out the shortest sensible set of connections for you — you don't pick
pairs. Connect 20 fixtures by selecting all 20 at once.

---

## Dimensioning a row — `FDM`

For the technician mounting the fixtures: how far from the wall the first one
goes, and how far apart the rest are. One command, four picks:

```
Command: FDM
Select the fixtures to dimension:              <- window the row, Enter
Point on the wall to measure from <first fixture>:   <- click the end wall
Point on the wall to finish at <last fixture>:       <- click the far wall
Dimension line location [Chain/Baseline] <Chain>:    <- click where the dims go
5 dimension(s): 1.20, 2.40, 2.40, 2.40, 1.20
```

The figures are printed so you can catch a wrong one here instead of on site.

### Which way it measures — `FDMH` and `FDMV`

`FDM` works the direction out from how the fixtures are lined up, so a column of
lights gets dimensioned down its own length. When you want the *other*
direction — the distance from the side wall across to that column — use the
command that says so:

| | |
|---|---|
| `FDM` | whichever way the fixtures run |
| `FDMH` | across the sheet, left to right |
| `FDMV` | up the sheet, bottom to top |

All three are the same command; `H` and `V` just answer the question up front.
You can also type `H` or `V` at the dimension line prompt to change your mind
without restarting, and the prompt shows which way it is set:

```
Dimension line location [Chain/Baseline/Horizontal/Vertical] <chain, vertical>:
```

Fixtures that land on the same point *along the direction being measured* are
dimensioned once, not over and over — so `FDMH` on a column of four lights gives
one distance to the wall, not four dimensions of 3 mm. `*dt:dm:merge-tol*` in
config sets how close counts as the same point (`0.05` for a drawing in metres).

**The wall prompts take a point, not the wall.** Snap anywhere on the wall face
— any point on a wall square to the run gives the same distance. Press Enter to
skip either one: skip both and you get fixture-to-fixture only, which is the
other half of what this is for.

**It does not care that your fixtures are slightly out of line.** Every point is
projected onto the run's axis first, so the dimension line comes out straight
and each number is the true spacing along the run. That is the part worth
trusting it for — by hand, two lights 3 mm apart in Y give you a slanted
dimension and a number nobody wants.

**`B` at the last prompt** measures everything from the first wall instead,
stacked — `1.20`, `3.60`, `6.00` — rather than gap by gap. Same spacings either
way, different drawing.

Dimensions use your current dimension style and land on the current layer, the
same as if you had drawn them by hand.

> A run more than a couple of degrees off square is dimensioned **aligned**, so
> a diagonal wing measures its true length. The command says so when it happens.

---

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

### Place the tags -- `TG`

On a drawing made from the office template, `COUNT_TAG` is already there and you
insert it the usual way. On a drawing that started without it, `TG` builds it
for you rather than sending you into an old file to copy one:

```
Command: TG
Created block "COUNT_TAG" in this drawing.
Tag insertion point <Enter to finish>:      <- click, click, click, Enter
Name the batch with SG.
```

Keep clicking to drop a run of tags; Enter ends it. The whole run is one `U`.
It never asks you to type anything into the tag -- `SG` fills `GROUP` and `RNB`
fills `NUMBER`. A fresh tag reads `01` so you can see it on the plan; that is
a placeholder, and every tag shows it until `RNB` puts the real sequence in. If the drawing already has a `COUNT_TAG`, `TG` uses that one
untouched, whatever it looks like.

It draws the number and nothing else -- no circle, no frame. Height matches the
drawing's own `TEXTSIZE`, so it comes out the size your other text is. Set
`*dt:lbl:tag-height*` in [dt-config.lsp](dt-config.lsp) only if you want to
override that. If you want a bubble around the number, draw the tag you want
once and put it in the office template -- `TG` never overrides an existing one.

`GROUP` is invisible on the tag, since it is data rather than annotation. Turn
`ATTDISP` On if you want to see which tag is in which group.

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

### Prefixes -- `SPX`

By default `NUMBER` holds just the number: `01`, `02`. To put something in front
of it for one group, run `DT-SETPREFIX` (`SPX`). It shows what is set now, then
asks:

```
Command: SPX
  Group                       Prefix
  --------------------------- ---------------
  C                           (shared)
  TUG                         (shared)

GROUP to set a prefix for: TUG
Prefix for TUG <Enter to clear>: T-
TUG -> T-, 41 number(s) updated.
```

`TUG` now numbers `T-01`, `T-02`. Every group still shown as `(shared)` carries
on exactly as before. Run `SPX` again on the same group to change it, or press
Enter at the prefix prompt to put it back to shared.

You do not have to edit any file. `SPX` writes `dt-labels.lsp` itself, so the
setting survives closing AutoCAD and travels with the toolkit.

`%G` in a prefix stands for the group name, so a prefix of `%G-` on group `C`
gives `C-01`. To do that for *every* group at once rather than one at a time,
that one is still the shared default in [dt-config.lsp](dt-config.lsp) --
`*dt:lbl:format*` `'("%G-" "" 1 2)`. Ask and it can become a command too.

### Renumber — `RNB`

After moving, copying or deleting tags, run `RNB` to put the numbers back in
order. Numbering runs the way you read a plan: top to bottom, left to right.

```
Command: RNB
41 attribute(s) renumbered.
```

### If the numbering order looks wrong — `SR`

`RNB` numbers the way you read a plan: rows top to bottom, left to right across
each row. To do that it has to decide which tags are on the *same row*, and out
of the box it demands they sit at **exactly** the same height. Nothing in a real
drawing does.

The symptom is specific: tags you placed one at a time number correctly, but
tags that arrived as part of a `COPY` of several objects come out shuffled. They
look level on screen and are a fraction of a unit apart in Y, which is enough.

Fix it once, with `DT-SETROW` (`SR`):

```
Command: SR
Row tolerance is 0.000 drawing units.
Tags closer than this in Y count as one row and number left to right.
New tolerance, or pick two points <keep>:      <- pick two tags in the same row
Row tolerance 143.000, 68 number(s) updated.
```

You can type a number instead of picking, but picking is easier: click two tags
that belong to the same row and AutoCAD works out the distance. Anything from
"a bit more than the wobble in a row" to "less than the gap between rows" works;
half your fixture spacing is a good answer.

Like `SPX`, it writes `dt-labels.lsp` itself. Set it once per office standard,
not once per drawing.

### Leaving a group alone — `SKP`

Numbered something by hand and want it to stay exactly as typed? `SKP` turns
`RNB` off for that group only:

```
Command: SKP
  Group                       RNB
  --------------------------- -------
  C.PN.                       renumbers
  TRF                         renumbers
GROUP to change: TRF
RNB should [Renumber/Skip] TRF <keep>: S
RNB skips TRF, 0 number(s) updated.
```

Every other group keeps renumbering. `RNB` tells you afterwards which groups it
walked past, so a group that stopped renumbering never looks like a bug:

```
Command: RNB
64 attribute(s) renumbered.
1 group(s) set to skip: TRF
```

Turn it back on with `SKP` and `R` — the group renumbers from `01` again on the
spot, so anything typed by hand is gone. That is the one irreversible move here.

`SWL` tags don't need this: they are a different block and `RNB` never sees them
at all.

### Switch legs — `SWL`

Lights on one switch all carry the same letter, so this one does **not**
renumber. You click, it stamps, and clicking again stamps the same label:

```
Command: SWL
GROUP for these tags: SW-COCINA
Tag point [Next/Back] <A>:        <- click, click, click   all three read A
Tag point [Next/Back] <A>: N      <- now B
Tag point [Next/Back] <B>:        <- click, click          both read B
Tag point [Next/Back] <B>:        <- Enter ends it
5 tag(s) placed in SW-COCINA, last one reads B.
```

Repeating is the default and advancing is the keystroke, because that is the
way round a switch leg works. `B` steps back if you overshoot.

`N` only moves on once the current label is on the drawing — press it twice by
accident and the second one is refused, so you cannot leave an empty letter in
the middle of a run.

The tags are a **separate block**, `SWITCH_TAG` — a copy of `COUNT_TAG` made
automatically the first time you run `SWL`, so it looks identical on the plan.
That is what keeps `RNB` away from them: it only ever touches `COUNT_TAG`, so
your repeated letters cannot be renumbered into `01, 02, 03` by someone running
`RNB` later. They don't show up in `DT-COUNTS` either — they aren't a count.

Run `SWL` again on the same `GROUP` and it picks up at the last letter you used,
so a leg that carries into the next room continues rather than restarting at
`A`. `SPX`, `PAD` and `LTR` apply to these groups the same as any other.

#### One tag at a time — `SWN`

Don't want a command holding the drawing hostage? `SWN` places **one** tag at
the next letter and ends. Then `COPY` it along the leg, nudge the text, do
whatever — and type `SWN` again when you want the next letter:

```
Command: SWN
Point for B or [Group]:        <- click
B placed in SW-COCINA. COPY it for the rest of the leg.
```

No group prompt after the first tag of the session — it uses the last group you
tagged. `G` changes it.

**New tags are copies of the last one**, so whatever you set on that tag —
scale, rotation, layer, colour — every tag after it follows. Get the first one
in the drawing looking right and you never adjust another. (Only the very first
tag is inserted fresh from the block definition.)

It works out the next letter by **reading the drawing**, not by remembering. So
it is still right after you copy tags, undo, delete one, close the drawing and
come back tomorrow, or place a few with `SWL` in between. Copies keep the letter
they were copied from, which is exactly what a leg is.

#### After changing `SPX`, `PAD` or `LTR` — restamp

The labels are stamped as you place them, so tags already on the sheet keep the
old format when you change one of those settings. `R` at the first prompt
rewrites them:

```
Command: SWL
GROUP for these tags, or R to restamp: R
GROUP to restamp: SW-COCINA
12 tag(s) restamped in SW-COCINA, 4 leg(s): A through D.
```

Legs stay intact — every tag that shared a label still shares it. The only thing
that changes beyond formatting is that skipped labels close up: a run that
jumped `A` to `C` comes back `A`, `B`.

> A group cannot be called `R`, since that is the keyword.

### `01` or `1` — `PAD`

Per group, so eight panels can read `1` to `8` while the fixtures on the same
sheet read `001` to `240`:

```
Command: PAD
  Group                       Digits   Example
  --------------------------- -------- -------
  C.PN.                       2        C.PN.01
  PL-                         2        PL-01
GROUP to change: PL-
Digits for PL- (1 = 1, 2 = 01, 3 = 001) <keep>: 3
PL- -> PL-001, 240 number(s) updated.
```

`1` means no padding at all. The Example column is the group's *first* tag as it
will actually read, prefix included — quicker to judge than a digit count.

A group you never touch with `PAD` uses the shared width, the `2` in
`*dt:lbl:format*`. Setting a group back to that width is how you undo one.
Letters ignore padding: `A` is never `0A`, and `PAD` says so if you try.

### Letters instead of numbers — `LTR`

Some things are lettered, not numbered — transformers, feeders, details. `LTR`
switches one group over and leaves every other group alone:

```
Command: LTR
  Group                       Counts in
  --------------------------- ---------
  C                           numbers
  TRF                         numbers
GROUP to change: TRF
TRF counts in [Numbers/Letters] <keep>: L
TRF counts in letters, 6 number(s) updated.
```

`TRF` now reads `A, B, C` and keeps going `Z, AA, AB` past twenty-six. The
prefix still applies, so a group with prefix `TRF-` gives `TRF-A`, `TRF-B`. Zero
padding does not: `A` is never `0A`. Switch it back with `LTR` and `N`.

It writes `dt-labels.lsp`, so it holds for the next drawing too.

### Numbering by plan or by the order you placed them — `SO`

Reading order is right most of the time and wrong some of the time: a run you
walked in the order the circuit actually runs, or tags whose position on the
sheet says nothing about their sequence, want the order **you** put them down
in. `DT-SETORDER` (`SO`) switches between the two:

```
Command: SO
Numbering order is reading.
Order [Reading/Columns/Database] <keep>: D
Numbering order database, 68 number(s) updated.
```

| | |
|---|---|
| `Reading` | rows top to bottom, left to right across each row — how a plan is read |
| `Columns` | left to right, then bottom to top |
| `Database` | the order the tags were inserted — first placed is `01` |

`Database` is insert order, so it ignores where the tags sit entirely: place
them in the sequence you want numbered and run `RNB`. First placed is `01`.
Moving a tag afterwards does not change its number.

What *does* change it is anything that makes AutoCAD create the entity again —
`COPY`, cut and paste, `WBLOCK` and back in. A copied tag is a new tag as far as
the drawing is concerned, so it lands at the end of the run no matter where you
put it. So does deleting one and placing a replacement.

It writes `dt-labels.lsp` like `SR` and `SPX` do, so the setting survives the
drawing. Switch it back with `SO` and `R` — nothing is lost either way, since
`RNB` recomputes every number from scratch each time it runs.

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
