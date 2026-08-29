;;; ---------------------------------------------------------------------------
;;; FIXCEN  -  Inserts a block at the center of a user-defined rectangular area.
;;;
;;; The rectangle is only a picking aid: GETCORNER rubber-bands it on screen,
;;; but no geometry is ever created, so nothing needs cleaning up afterward.
;;;
;;; Attributes are inserted with their default values (ATTREQ = 0); populate
;;; them later with EATTEDIT, BATTMAN, or a separate routine.
;;;
;;; Scale is forced to 1:1 after insertion to defeat INSUNITS auto-scaling.
;;;
;;; Usage:  Command: FIXCEN   -> pick two opposite corners, block lands in middle.
;;;                             Repeats until the user presses Enter or Esc.
;;; ---------------------------------------------------------------------------

(defun c:FIXCEN ( / error blk-name p1 p3 center
                    old-cmdecho old-attreq old-attdia old-osmode)

  (defun error (msg)
    (fixcen:restore-vars)
    (if (and msg (not (wcmatch (strcase msg) "BREAK,*CANCEL,EXIT")))
      (princ (strcat "\nError: " msg))
    )
    (princ)
  )

  ;; --- Configuration -------------------------------------------------------
  (setq blk-name "L24")   ; <- your block name here

  ;; --- Validation ----------------------------------------------------------
  (if (not (tblsearch "BLOCK" blk-name))
    (progn
      (princ (strcat "\nBlock \"" blk-name "\" is not defined in this drawing."))
      (exit)
    )
  )

  ;; --- Save state we are about to change -----------------------------------
  (setq old-cmdecho (getvar "CMDECHO")
        old-attreq  (getvar "ATTREQ")
        old-attdia  (getvar "ATTDIA")
        old-osmode  (getvar "OSMODE"))

  (setvar "CMDECHO" 0)
  (setvar "ATTREQ"  0)   ; use attribute defaults, do not prompt
  (setvar "ATTDIA"  0)   ; no attribute dialog

  ;; --- Main loop -----------------------------------------------------------
  (while (setq p1 (getpoint "\nFirst corner of area (Enter to finish): "))
    (if (setq p3 (getcorner p1 "\nOpposite corner: "))
      (progn
        (setq center (fixcen:midpoint p1 p3))
        ;; "_non" forces the literal point through, ignoring running OSNAPs.
        (command "_.-INSERT" blk-name "_non" center 1.0 1.0 0.0)
        (fixcen:force-unit-scale (entlast))
      )
    )
  )

  (fixcen:restore-vars)
  (princ)
)

;;; Midpoint of the diagonal defined by two opposite corners.
;;; Z is taken from the first point so the block lands on the same plane.
(defun fixcen:midpoint (pa pb)
  (list (/ (+ (car  pa) (car  pb)) 2.0)
        (/ (+ (cadr pa) (cadr pb)) 2.0)
        (caddr pa))
)

;;; Overrides the X/Y/Z scale factors of a block reference to exactly 1.0.
;;;
;;; Necessary because AutoCAD applies an automatic unit-conversion factor at
;;; insertion time whenever the block definition's units differ from the
;;; drawing's INSUNITS.  That factor is baked in before our own scale
;;; arguments are applied, so the only reliable fix is to rewrite the scale
;;; on the resulting entity.
(defun fixcen:force-unit-scale (ent / edata)
  (if (and ent (setq edata (entget ent))
           (= "INSERT" (cdr (assoc 0 edata))))
    (entmod
      (subst '(43 . 1.0) (assoc 43 edata)
        (subst '(42 . 1.0) (assoc 42 edata)
          (subst '(41 . 1.0) (assoc 41 edata) edata))))
  )
)

;;; Restores every system variable touched by c:FIXCEN.
;;; Guards against nil so it is safe to call from error before setup runs.
(defun fixcen:restore-vars ()
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (if old-attreq  (setvar "ATTREQ"  old-attreq))
  (if old-attdia  (setvar "ATTDIA"  old-attdia))
  (if old-osmode  (setvar "OSMODE"  old-osmode))
)

(princ "\nFIXCEN loaded. Type FIXCEN to place fixtures.")
(princ)