;;; ===========================================================================
;;; DT-CONFIG.LSP  --  Office settings.
;;;
;;; THIS is the file you edit. Nothing in src/ should ever need changing to
;;; adjust a block name, a layer, a colour or a distance.
;;;
;;; Values are read at command time, not captured at load time, so after an
;;; edit you can just reload this one file:
;;;
;;;     Command: (load "dt-config.lsp")
;;;
;;; and the next command picks up the change. No AutoCAD restart.
;;; ===========================================================================

(setq

;;; --- Fixtures (DT-FIXCEN, DT-FIXDIV) ---------------------------------------

  ;; Which of them is current when AutoCAD starts. DT-SETBLOCK (or the Block
  ;; option inside DT-FIXCEN and DT-FIXDIV) changes it for the session.
  *dt:fx:block*        "L24"

  ;; Layer the block is placed on. nil = use whatever layer is current.
  ;; If the layer does not exist it is created with the colour below.
  *dt:fx:layer*        nil
  *dt:fx:layer-color*  2

  ;; How DT-FIXDIV spaces N blocks along a span. Flip it per-command with the
  ;; Mode keyword; this is just the default.
  ;;   'divide    interior division points, what the native DIVIDE gives:
  ;;              3 blocks land at 1/4, 2/4, 3/4 of the span
  ;;   'segment   each block centred in its own 1/N bay:
  ;;              3 blocks land at 1/6, 3/6, 5/6 -- equal share of the room
  *dt:fx:spacing*      'divide

  ;; Rotate each block to follow the direction of the span in DT-FIXDIV?
  ;; Safe to turn on: DT-WTREE measures attachment points from each block's own
  ;; rotation, so a rotated symbol keeps its wiring stubs in the right place.
  *dt:fx:align*        nil

;;; --- Wiring runs (DT-WTREE) ------------------------------------------------

  ;; Layer the arcs are drawn on. nil = whatever layer is current, the same as
  ;; *dt:fx:layer*. Name one instead and it is created if missing, in the
  ;; colour below -- which is also the only thing that colour is for.
  *dt:wt:layer*        nil
  *dt:wt:color*        4           ; ACI colour for that layer

  ;; Included angle of each run, in degrees. Larger = more bowed.
  *dt:wt:arc-angle*    90.0

  ;; Tolerance for treating two points as coincident.
  *dt:wt:fuzz*         1e-8

;;; --- The block registry (DT-SETBLOCK, DT-WTREE) ----------------------------

  ;; ---------------------------------------------------------------------
  ;; THE BLOCK REGISTRY -- one record per symbol the office uses
  ;;
  ;;   (block-name  description  attachment points)
  ;;
  ;; Set a symbol up ONCE and it is done everywhere: it appears in
  ;; DT-SETBLOCK's menu by number, and DT-WTREE knows where its wires meet it.
  ;; Switching between symbols never needs reconfiguring.
  ;;
  ;; Attachment points are (x y) in BLOCK coordinates -- what you would read in
  ;; the block editor, insertion point at the origin, before rotation and
  ;; scale. A point, not a distance and a direction, so a connection that sits
  ;; off the centre line (the outlet's bars) is describable at all. At draw
  ;; time each point goes through the block reference's own transform, so
  ;; rotated, scaled and mirrored inserts all come out right.
  ;;
  ;; DON'T TYPE THE NUMBERS, AND DON'T ADD SYMBOLS HERE BY HAND. DT-SETPORT
  ;; measures a symbol in the drawing, registers it if it is new, and saves
  ;; everything to dt-blocks.lsp, which loads after this file and overrides it.
  ;; DT-PORTS lists what is stored. Delete dt-blocks.lsp to come back to these.
  ;;
  ;; A symbol with no attachment points still works: DT-WTREE falls back to four
  ;; cardinal points off its bounding box, turned with the block.
  ;; ---------------------------------------------------------------------
  *dt:blocks*
    '(;; Carried over from the measurements in the old dt-profiles.lsp. The
      ;; three L24 stubs recorded there were exact cardinals at a uniform
      ;; 0.10645, so they convert faithfully; the fourth is filled in by
      ;; symmetry. Re-run DT-SETPORT if it looks off.
      ("L24" "2x4 light fixture"
             ((0.10645 0.0) (0.0 0.10645) (-0.10645 0.0) (0.0 -0.10645)))

      ;; MEASURE THIS ONE -- the value below is a guess.
      ;; The old file recorded three points at 81, 90 and 98 degrees sharing a
      ;; single averaged distance of 0.179764. That spread is the signature of
      ;; points sitting OFF the centre line: the old format could only store one
      ;; distance for all of them, so each point's real distance was averaged
      ;; away and cannot be recovered. Run DT-SETPORT on this symbol.
      ("TOMACORRIENTE 120V" "outlet 120V" ((0.0 0.179764))))

;;; --- Load takeoff (DT-LOAD) ------------------------------------------------

  ;; Attributes each device block carries. Give them sensible defaults in the
  ;; block so the common case is zero typing: a 120 V general purpose outlet
  ;; should already say what it is and what it draws the moment it is inserted.
  ;;
  ;; A block counts as a device if it has the power attribute at all. Anything
  ;; else in the selection is ignored, so windowing round a circuit and catching
  ;; text or tags is harmless.
  ;;
  ;; Write POTENCIA as a plain number. Spaces and thousands separators are
  ;; stripped, so 1500 and "1,500" both read as 1500; a decimal must use a
  ;; period, "180.5".
  *dt:ld:desc-tag*     "DESCRIPCION"
  *dt:ld:power-tag*    "POTENCIA"
  *dt:ld:volt-tag*     "VOLTAJE"

  ;; Holds the circuit label. Make it INVISIBLE in the block -- you do not want
  ;; "cocina" printed on the plan, but Properties and EATTEDIT still show it so
  ;; it stays inspectable and fixable by hand.
  *dt:ld:circuit-tag*  "CIRCUITO"

  ;; Holds the panel label -- "TD-A", "TABLERO 1". Also INVISIBLE.
  ;;
  ;; Circuit numbers only mean anything within a panel: circuit 1 of TD-A and
  ;; circuit 1 of TD-B are different circuits that happen to share a number, and
  ;; totalling them together would be wrong. A device with no TABLERO attribute
  ;; is not an error -- it falls into an unnamed panel, so drawings whose blocks
  ;; predate this attribute still total correctly as a single panel.
  *dt:ld:panel-tag*    "TABLERO"

  ;; Where the CSV goes. nil = beside the drawing.
  ;;
  ;; DT-LOAD writes one file per panel, <drawing>-<panel>-load.csv, plus a
  ;; combined <drawing>-load-all.csv carrying a Panel column. Set this to a
  ;; path to override the base name; the panel suffixes are still added.
  *dt:ld:file*         nil

;;; --- Sheet numbering (DT-SHEETS) -------------------------------------------

  ;; Prefix used for the very first DT-SHEETS prompt of a session. After that
  ;; the command offers whatever you last typed, so this is only a seed.
  *dt:sh:prefix*       "EL-"

  ;; Zero-padded width of the sheet number: 2 = 01, 3 = 001.
  *dt:sh:pad*          2

;;; --- Dimensioning fixtures (DT-FIXDIM) -------------------------------------

  ;; How far off horizontal or vertical a run may be, in degrees, and still be
  ;; dimensioned as if it were square to the drawing. Fixtures placed by eye are
  ;; never exactly in line; snapping keeps the dimension line clean and costs
  ;; well under a millimetre per metre at two degrees. Set it to 0.0 to measure
  ;; exactly what is drawn, however crooked.
  *dt:dm:square-tol*   2.0

  ;; Fixtures closer together than this ALONG the direction being measured are
  ;; treated as one point. It is what makes Horizontal on a column of fixtures
  ;; give one distance to the wall instead of a stack of 3 mm dimensions.
  ;; In drawing units: 0.05 suits a drawing in metres, 50 one in millimetres.
  *dt:dm:merge-tol*    0.05

;;; --- Numbering (DT-SETGROUP, DT-RENUMBER, DT-COUNTS) -----------------------

  ;; ---------------------------------------------------------------------
  ;; WHAT GETS COUNTED
  ;;
  ;; One block does all the counting. It carries two attributes: GROUP, which
  ;; the drafter types ("C", "P", "TUG"), and NUMBER, which is filled in
  ;; automatically. Each distinct GROUP value gets its own 1..N sequence.
  ;;
  ;; To count a new kind of thing: type a new GROUP value on the block. There
  ;; is nothing to add here, and nothing to change in the code.
  ;;
  ;; For visually different symbols per group, make COUNT_TAG a dynamic block
  ;; with visibility states -- the routine resolves the effective block name,
  ;; so the anonymous names dynamic blocks take on are handled.
  ;; ---------------------------------------------------------------------
  *dt:lbl:block*       "COUNT_TAG"
  *dt:lbl:group-tag*   "GROUP"
  *dt:lbl:number-tag*  "NUMBER"

  ;; How a number is formatted: (prefix suffix start pad)
  ;; pad is the zero-padded width: 0 = none, 2 = 01, 3 = 001
  ;; %G anywhere in prefix or suffix expands to the group value, so
  ;;   '("" "" 1 2)     ->  01, 02, 03           NUMBER holds just the number
  ;;   '("%G-" "" 1 2)  ->  C-01, C-02, P-01     NUMBER holds the full tag
  *dt:lbl:format*      '("" "" 1 2)

  ;; Per-group prefixes are NOT set here. They are drafter-facing, so they live
  ;; in dt-labels.lsp, written by DT-SETPREFIX. This file stays hand-edited
  ;; only. The prefix above is the shared default every unlisted group uses.

  ;; Block DT-SWITCH places. A clone of COUNT_TAG, made the first time the
  ;; command runs, so switch-leg tags look identical to counter tags but carry
  ;; a different name -- which is the whole reason DT-RENUMBER never sees them
  ;; and their repeated labels survive. Point it at an office block of your own
  ;; and nothing is cloned.
  *dt:sw:block*        "SWITCH_TAG"

  ;; Groups that count in letters instead of numbers: A, B, ... Z, AA, AB,
  ;; the way spreadsheet columns run. Every group not listed counts 1, 2, 3.
  ;; Prefix, suffix and start still apply; pad does not -- A is never 0A.
  ;;
  ;; The starting list only. DT-SETLETTERS switches a group from inside AutoCAD
  ;; and records it in dt-labels.lsp, which loads after this file and wins.
  *dt:lbl:letter-groups*  '()

  ;; Numbering order.
  ;;   'reading   top-to-bottom, then left-to-right   (how a plan is read)
  ;;   'columns   left-to-right, then bottom-to-top
  ;;   'database  the order the tags were inserted     (first placed is 01)
  ;;
  ;; The starting value only. DT-SETORDER switches it from inside AutoCAD and
  ;; records it in dt-labels.lsp, which loads after this file and wins.
  *dt:lbl:order*       'reading

  ;; Row banding for 'reading: tags whose Y differs by less than this are
  ;; treated as the same row and numbered left-to-right across it.
  ;;
  ;; This is the starting value only. DT-SETROW sets it from inside AutoCAD and
  ;; records it in dt-labels.lsp, which loads after this file and wins.
  ;;
  ;; 0.0 means an exact Y comparison, which sounds strict but is not useful: two
  ;; tags a thousandth of a unit apart become separate rows, so anything copied
  ;; as part of a selection stops reading left-to-right. Run DT-SETROW and pick
  ;; two tags that belong to the same row.
  *dt:lbl:row-tol*     0.0

  ;; Text height for the COUNT_TAG that DT-TAG builds when the drawing has
  ;; none. It draws the number and nothing else -- no circle, no frame.
  ;; nil means match this drawing: TEXTSIZE, or DIMTXT if the current text
  ;; style has a fixed height. Set a number only to override that.
  ;; A COUNT_TAG that already exists -- one that came in with the office
  ;; template -- is never touched, so this only applies to a drawing that
  ;; starts without one.
  *dt:lbl:tag-height*  nil

;;; --- Panels (DT-PANELS, DT-SETPANEL) ---------------------------------------

  ;; ---------------------------------------------------------------------
  ;; WHAT GETS FILLED
  ;;
  ;; A block is a panel if it carries the name attribute. Nothing keys on the
  ;; block name, so a switchboard symbol, a panelboard symbol and a meter
  ;; module symbol all fill from the same schedule.
  ;;
  ;; Give the panel block these two attributes at minimum:
  ;;
  ;;   PANEL   the tag, e.g. LC.PS.001   -- typed by the drafter
  ;;   KVA     the connected load        -- filled by DT-SETPANEL
  ;;
  ;; Any further attribute fills too, as long as the CSV has a column whose
  ;; header matches its tag. VOLTAJE, MAIN and KAIC all work with no change
  ;; here: add the column, get the column.
  ;; ---------------------------------------------------------------------
  *dt:pn:name-tag*     "PANEL"

  ;; Only used for the running total DT-PANELS prints. A value it cannot read
  ;; as a number is still written to the drawing untouched.
  *dt:pn:kva-tag*      "KVA"

  ;; Where the CSV goes. nil = beside the drawing, named <drawing>-panels.csv
  *dt:pn:file*         nil

)

(princ)
