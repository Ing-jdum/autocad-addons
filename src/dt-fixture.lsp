;;; ===========================================================================
;;; DT-FIXTURE.LSP  --  Place blocks by area centre, or spaced along a span.
;;;
;;; Commands:  DT-FIXCEN    centre one block in a picked area  (FIXCEN, FXC)
;;;            DT-FIXDIV    space N blocks along a line/curve  (FIXDIV, FXD)
;;;            DT-SETBLOCK  choose the block to place          (SB)
;;;
;;; ---------------------------------------------------------------------------
;;; THE CURRENT BLOCK
;;;
;;; Which block gets placed is session state, not a code constant. It starts as
;;; *dt:fx:block* from config and is changed with DT-SETBLOCK, or with the
;;; Block option offered inside DT-FIXCEN and DT-FIXDIV -- so switching from a
;;; 2x4 troffer to a downlight is two keystrokes, not a config edit.
;;;
;;; The fastest way to set it is to pick an existing one in the drawing:
;;; DT-SETBLOCK reads the effective name off whatever block reference you
;;; select, so it works on dynamic blocks too.
;;;
;;; ---------------------------------------------------------------------------
;;; SPACING
;;;
;;; Attributes are inserted with their default values (ATTREQ = 0); populate
;;; them later with EATTEDIT, BATTMAN, or DT-SETGROUP.
;;;
;;; Scale is forced to 1:1 after insertion to defeat INSUNITS auto-scaling.
;;;
;;; Config: *dt:fx:block*, *dt:fx:layer*, *dt:fx:layer-color*,
;;;         *dt:fx:spacing*, *dt:fx:align*
;;; ===========================================================================

;;; --- Current block ---------------------------------------------------------

(defun fx:block ()
  ;; Session state, seeded from config on first use. Reloading dt-config.lsp
  ;; will not clear a choice made with DT-SETBLOCK; that is deliberate, the
  ;; drafter's pick outranks the startup default.
  (if (null *dt:fx:current*) (setq *dt:fx:current* *dt:fx:block*))
  *dt:fx:current*
)

(defun fx:pad (s n / out)
  (setq out "")
  (repeat (max 1 (- n (strlen s))) (setq out (strcat out " ")))
  out
)

(defun fx:list-blocks (cur / i)
  ;; The office's palette from *dt:blocks*, numbered. Listing them is the
  ;; point: nobody should have to remember block names, and picking an existing
  ;; instance is no help in a drawing that has none yet.
  (if *dt:blocks*
    (progn
      (princ "\n  Configured blocks:")
      (setq i 1)
      (foreach b *dt:blocks*
        (princ (strcat "\n   " (itoa i) ". " (car b) (fx:pad (car b) 14)
                       (cadr b)
                       (if (= (strcase (car b)) (strcase cur)) "   <- current" "")))
        (setq i (1+ i))))
    (princ "\n  No blocks registered yet -- measure one with DT-SETPORT."))
  (princ)
)

(defun fx:pick-block (cur / opt obj)
  (setq opt (entsel "\nSelect a block in the drawing: "))
  (cond
    ((null opt) cur)
    ((progn (setq obj (vlax-ename->vla-object (car opt)))
            (= "AcDbBlockReference" (vla-get-ObjectName obj)))
     (vla-get-EffectiveName obj))
    (t (princ "\nThat is not a block reference.") cur))
)

(defun fx:type-block (cur / name)
  (setq name (getstring (strcat "\nBlock name <" cur ">: ")))
  (if (= name "") cur name)
)

(defun fx:ask-block (cur / ans)
  ;; Choose by number from the configured list, or fall back to picking one in
  ;; the drawing or typing a name. Returns the chosen name, or CUR unchanged.
  (fx:list-blocks cur)
  (initget "Pick Name")
  (setq ans (getint (strcat "\nBlock number, or [Pick/Name] <keep " cur ">: ")))
  (cond
    ((null ans)     cur)                  ; Enter keeps what is current
    ((= ans "Pick") (fx:pick-block cur))
    ((= ans "Name") (fx:type-block cur))
    ((and (> ans 0) (<= ans (length *dt:blocks*)))
     (car (nth (1- ans) *dt:blocks*)))
    (t (princ "\nNo such number.") cur))
)

(defun c:DT-SETBLOCK ( / new)
  (setq new             (fx:ask-block (fx:block))
        *dt:fx:current* new)
  ;; Say so rather than refusing: the drafter may well set the block before
  ;; inserting the first one. DT-FIXCEN checks again and stops if it is missing.
  (princ (strcat "\nCurrent block: " new
                 (if (tblsearch "BLOCK" new) ""
                   "  (not in this drawing yet)")))
  (princ)
)

;;; --- Insertion -------------------------------------------------------------

(defun fx:insert (blk pt rot)
  ;; ROT is in radians, the way every AutoLISP angle function reports one.
  ;; -INSERT reads its rotation argument in the drawing's angular units, so it
  ;; has to be converted; fx:setup pins AUNITS to decimal degrees to make that
  ;; conversion true regardless of how the drawing is set up.
  ;;
  ;; "_non" forces the literal point through, ignoring running OSNAPs.
  (command "_.-INSERT" blk "_non" pt 1.0 1.0 (dt:rad->deg rot))
  (dt:force-unit-scale (entlast))
)

(defun fx:setup ( / saved)
  ;; Shared prologue: the system variables both commands change, saved so the
  ;; caller can hand them straight back to dt:restore-vars.
  ;;
  ;; OSNAP is deliberately left alone -- running snaps are wanted for the picks,
  ;; and the "_non" above protects the computed insertion points.
  (setq saved (dt:save-vars '("CMDECHO" "ATTREQ" "ATTDIA" "AUNITS" "CLAYER")))
  (setvar "CMDECHO" 0)
  (setvar "ATTREQ"  0)          ; use attribute defaults, do not prompt
  (setvar "ATTDIA"  0)          ; no attribute dialog
  (setvar "AUNITS"  0)          ; decimal degrees, so fx:insert's angle is right
  (if *dt:fx:layer*
    (setvar "CLAYER" (dt:ensure-layer *dt:fx:layer* *dt:fx:layer-color*)))
  saved
)

;;; --- DT-FIXCEN -------------------------------------------------------------

(defun c:DT-FIXCEN ( / *error* saved doc blk p1 p3 placed going)

  ;; The handler must be named *error* -- AutoLISP calls nothing else.
  (defun *error* (msg)
    (dt:restore-vars saved)
    (dt:undo-end doc)
    (dt:report-error msg)
  )

  (setq blk (fx:block))

  (if (not (dt:require-block blk))
    (princ)
    (progn
      (setq saved  (fx:setup)
            doc    (dt:undo-begin)     ; one mark, so one U undoes the session
            placed 0
            going  t)

      (while going
        (initget "Block")
        ;; The current block shows as part of the keyword label, not in angle
        ;; brackets: <> means "press Enter for this" everywhere else in AutoCAD,
        ;; and here Enter finishes the command instead.
        (setq p1 (getpoint (strcat "\nFirst corner of area or [Block=" blk
                                   "] (Enter to finish): ")))
        (cond
          ((null p1) (setq going nil))
          ((= p1 "Block")
           (setq blk (fx:ask-block blk) *dt:fx:current* blk))
          ((setq p3 (getcorner p1 "\nOpposite corner: "))
           (fx:insert blk (dt:midpoint p1 p3) 0.0)
           (setq placed (1+ placed)))))

      (setq doc   (dt:undo-end doc)
            saved (dt:restore-vars saved))

      (princ (strcat "\n" (itoa placed) " " blk
                     (if (= placed 1) " block placed." " blocks placed.")))
      (princ)))
)

;;; --- DT-FIXDIV -------------------------------------------------------------
;;; Replaces the draw-a-line / DIVIDE / place-blocks routine with one command.
;;;
;;; Two spacing rules, because both are used and they are not the same:
;;;
;;;   divide    N blocks at 1/(N+1), 2/(N+1) ... -- the interior points the
;;;             native DIVIDE command would give you. 3 blocks land at
;;;             1/4, 2/4, 3/4 of the span.
;;;
;;;   segment   N blocks each centred in its own 1/N bay, at 1/2N, 3/2N ...
;;;             3 blocks land at 1/6, 3/6, 5/6. This is what you want when the
;;;             span is a room and each fixture should light an equal share.

(defun fx:params (n mode / out i)
  ;; Normalised positions along the span, in [0,1], in order.
  (setq out nil i 1)
  (repeat n
    (setq out (cons (if (= mode 'segment)
                      (/ (- i 0.5) (float n))
                      (/ (float i) (+ n 1.0)))
                    out)
          i   (1+ i)))
  (reverse out)
)

(defun fx:point-at (f p1 p2 obj len)
  ;; F is a fraction in [0,1]. With OBJ we walk the real curve, so arcs and
  ;; polylines work; without it we interpolate the picked segment.
  (if obj
    (vlax-curve-getPointAtDist obj (* f len))
    (list (+ (car  p1) (* f (- (car  p2) (car  p1))))
          (+ (cadr p1) (* f (- (cadr p2) (cadr p1))))
          (if (caddr p1) (caddr p1) 0.0)))
)

(defun fx:angle-at (f p1 p2 obj len / d)
  ;; Tangent direction, used only when *dt:fx:align* is on.
  (if obj
    (if (setq d (vlax-curve-getFirstDeriv obj
                  (vlax-curve-getParamAtDist obj (* f len))))
      (angle '(0.0 0.0) d)
      0.0)
    (angle p1 p2))
)

(defun fx:pick-span ( / opt p1 p2 obj)
  ;; Returns (p1 p2 obj length), or nil if the drafter backed out. OBJ is the
  ;; selected curve when there is one, nil for a two-point pick.
  (initget "Points")
  (setq opt (entsel "\nSelect line, arc or polyline or [Points]: "))
  (cond
    ((= opt "Points")
     (if (and (setq p1 (getpoint "\nStart point: "))
              (setq p2 (getpoint p1 "\nEnd point: ")))
       (list p1 p2 nil (distance p1 p2))))
    ((null opt) nil)
    ((vl-catch-all-error-p
       (vl-catch-all-apply 'vlax-curve-getEndParam
                           (list (setq obj (vlax-ename->vla-object (car opt))))))
     (princ "\nThat object cannot be divided.")
     nil)
    (t (list nil nil obj (vlax-curve-getDistAtParam
                           obj (vlax-curve-getEndParam obj)))))
)

(defun c:DT-FIXDIV ( / *error* saved doc blk span p1 p2 obj len qty mode
                       ans placed)

  (defun *error* (msg)
    (dt:restore-vars saved)
    (dt:undo-end doc)
    (dt:report-error msg)
  )

  (setq blk  (fx:block)
        mode *dt:fx:spacing*)

  (cond
    ((not (dt:require-block blk)) (princ))
    ((null (setq span (fx:pick-span))) (princ "\nCancelled."))
    ((<= (setq len (nth 3 span)) 0.0) (princ "\nThat span has no length."))
    (t
     (setq p1 (nth 0 span)
           p2 (nth 1 span)
           obj (nth 2 span))

     ;; Quantity, with the spacing rule available as a keyword so it can be
     ;; flipped per-command without touching config.
     (setq qty nil)
     (while (null qty)
       (initget 6 "Mode")          ; 6 = reject zero and negative
       (setq ans (getint (strcat "\nNumber of blocks or [Mode="
                                 (if (= mode 'segment) "segment" "divide")
                                 "]: ")))
       (cond
         ((= ans "Mode")
          (setq mode (if (= mode 'segment) 'divide 'segment))
          (princ (strcat "\nSpacing: " (if (= mode 'segment)
                                         "centred in equal bays"
                                         "interior division points"))))
         ((null ans) (setq qty 0))  ; Enter = give up
         (t (setq qty ans))))

     (if (< qty 1)
       (princ "\nNothing placed.")
       (progn
         (setq saved  (fx:setup)
               doc    (dt:undo-begin)
               placed 0)
         (foreach f (fx:params qty mode)
           (fx:insert blk
                      (fx:point-at f p1 p2 obj len)
                      (if *dt:fx:align* (fx:angle-at f p1 p2 obj len) 0.0))
           (setq placed (1+ placed)))
         (setq doc   (dt:undo-end doc)
               saved (dt:restore-vars saved))
         (princ (strcat "\n" (itoa placed) " " blk " block(s) placed, "
                        (if (= mode 'segment) "centred in equal bays."
                                              "on interior division points.")))))))
  (princ)
)

;;; --- Aliases ---------------------------------------------------------------
;;; None of these shadow a native AutoCAD command (README 6.2).

(defun c:FIXCEN () (c:DT-FIXCEN))
(defun c:FXC    () (c:DT-FIXCEN))
(defun c:FIXDIV () (c:DT-FIXDIV))
(defun c:FXD    () (c:DT-FIXDIV))
(defun c:SB     () (c:DT-SETBLOCK))

(princ)
