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

  ;; Layer the arcs are created on, made automatically if missing.
  *dt:wt:layer*        "E-WIRE"
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

  ;; Where the CSV goes. nil = beside the drawing, named <drawing>-load.csv
  *dt:ld:file*         nil

;;; --- Sheet numbering (DT-SHEETS) -------------------------------------------

  ;; Prefix used for the very first DT-SHEETS prompt of a session. After that
  ;; the command offers whatever you last typed, so this is only a seed.
  *dt:sh:prefix*       "EL-"

  ;; Zero-padded width of the sheet number: 2 = 01, 3 = 001.
  *dt:sh:pad*          2

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

  ;; Numbering order.
  ;;   'reading   top-to-bottom, then left-to-right   (how a plan is read)
  ;;   'columns   left-to-right, then bottom-to-top
  ;;   'database  order the blocks were created in
  *dt:lbl:order*       'reading

  ;; Row banding for 'reading: fixtures whose Y differs by less than this are
  ;; treated as the same row and numbered left-to-right across it. Set to 0 for
  ;; an exact Y comparison. Use the drawing units of your plan.
  *dt:lbl:row-tol*     0.0

)

(princ)
