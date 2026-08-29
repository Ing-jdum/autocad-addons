;;; ===========================================================================
;;; DT-CORE.LSP  --  Shared services for every DT command.
;;;
;;; Loaded first by dt-load.lsp. Defines no commands and touches nothing in
;;; the drawing; it only provides the plumbing that README.md section 6 requires
;;; every command to use: system-variable save/restore, undo marks, layer
;;; creation, and precondition checks.
;;;
;;; Naming: everything here is prefixed dt: and is fair game for any module.
;;; Module-private helpers belong in the module file under its own prefix.
;;; ===========================================================================

(vl-load-com)

;;; --- Document --------------------------------------------------------------

(defun dt:doc ()
  (vla-get-ActiveDocument (vlax-get-acad-object))
)

;;; --- System variables ------------------------------------------------------
;;; Save returns an alist we hand back to restore. Passing the state explicitly
;;; means these helpers do not depend on the caller's locals (README 6.4).

(defun dt:save-vars (names)
  ;; NAMES is a list of system-variable name strings.
  (mapcar '(lambda (n) (cons n (getvar n))) names)
)

(defun dt:restore-vars (saved)
  ;; Safe to call with nil, so the error handler can run before setup finished.
  ;; Note 0 is truthy in AutoLISP, so this only skips genuinely unread vars.
  (foreach pair saved
    (if (cdr pair) (setvar (car pair) (cdr pair))))
  nil
)

;;; --- Undo marks ------------------------------------------------------------
;;; One mark per command, so the drafter's single U undoes the whole thing.
;;; dt:undo-end is idempotent-safe against nil, which is what lets the error
;;; handler close a mark that may or may not have been opened.

(defun dt:undo-begin ( / doc)
  (setq doc (dt:doc))
  (vla-StartUndoMark doc)
  doc
)

(defun dt:undo-end (doc)
  (if doc (vla-EndUndoMark doc))
  nil
)

;;; --- Error reporting -------------------------------------------------------
;;; Each command defines its own localized *error* (it has to, to see its own
;;; state) and calls this for the message half. Esc and normal exits stay quiet.

(defun dt:report-error (msg)
  (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*EXIT*,*QUIT*")))
    (princ (strcat "\nDT error: " msg)))
  (princ)
)

;;; --- Preconditions ---------------------------------------------------------
;;; These return T/nil rather than calling (exit), so callers use ordinary
;;; control flow and never rely on the error handler for expected outcomes.

(defun dt:require-block (name)
  (cond
    ((or (null name) (= name ""))
     (princ "\nNo block name configured. Check dt-config.lsp.")
     nil)
    ((tblsearch "BLOCK" name) t)
    (t
     (princ (strcat "\nBlock \"" name "\" is not defined in this drawing."))
     nil))
)

(defun dt:ensure-layer (name color)
  ;; Creates the layer if missing. Never assume the template has it.
  ;; A nil NAME means "use whatever layer is current" and is not an error.
  (if (and name (/= name "") (not (tblsearch "LAYER" name)))
    (entmake
      (list '(0 . "LAYER")
            '(100 . "AcDbSymbolTableRecord")
            '(100 . "AcDbLayerTableRecord")
            (cons 2 name)
            (cons 62 color)
            '(70 . 0))))
  name
)

;;; --- Geometry --------------------------------------------------------------

(defun dt:2d (p) (list (car p) (cadr p)))

(defun dt:deg->rad (d) (/ (* pi d) 180.0))

(defun dt:rad->deg (r) (/ (* 180.0 r) pi))

(defun dt:midpoint (pa pb)
  ;; Midpoint of the diagonal between two opposite corners. Z comes from the
  ;; first point so the result lands on the same plane as the pick.
  (list (/ (+ (car  pa) (car  pb)) 2.0)
        (/ (+ (cadr pa) (cadr pb)) 2.0)
        (if (caddr pa) (caddr pa) 0.0))
)

;;; --- Block references ------------------------------------------------------

(defun dt:force-unit-scale (ent / edata)
  ;; Overrides the X/Y/Z scale factors of a block reference to exactly 1.0.
  ;;
  ;; Necessary because AutoCAD applies an automatic unit-conversion factor at
  ;; insertion time whenever the block definition's units differ from the
  ;; drawing's INSUNITS. That factor is baked in before our own scale arguments
  ;; are applied, so the only reliable fix is to rewrite the scale on the
  ;; resulting entity.
  (if (and ent
           (setq edata (entget ent))
           (= "INSERT" (cdr (assoc 0 edata))))
    (entmod
      (subst '(43 . 1.0) (assoc 43 edata)
        (subst '(42 . 1.0) (assoc 42 edata)
          (subst '(41 . 1.0) (assoc 41 edata) edata)))))
)

;;; --- The block registry ----------------------------------------------------
;;; One record per symbol the office uses, shared by every module:
;;;
;;;     (block-name  description  ((x y) (x y) ...))
;;;
;;; The points are wiring attachment points in BLOCK coordinates, or nil if the
;;; symbol has never been measured. Keeping name, description and geometry in
;;; one record is what makes a symbol a single thing to set up: DT-SETPORT
;;; registers it and measures it in one go, and it appears in DT-SETBLOCK's menu
;;; from then on, with no config edit at any point.
;;;
;;; *dt:blocks* is seeded from dt-config.lsp and overridden by dt-blocks.lsp,
;;; which is generated. Hand-written config is never rewritten by code; the
;;; generated file is never hand-edited.

(defun dt:block-entry (name)
  (assoc (strcase name)
         (mapcar '(lambda (b) (cons (strcase (car b)) (cdr b))) *dt:blocks*))
)

(defun dt:block-desc (name / e)
  (if (setq e (dt:block-entry name)) (cadr e) "")
)

(defun dt:block-ports (name / e)
  (if (setq e (dt:block-entry name)) (caddr e))
)

(defun dt:put-block (name desc pts)
  ;; Replace or append, never reorder the rest: DT-SETBLOCK numbers the menu off
  ;; this list, and menu numbers that shuffle under the drafter are hostile.
  (setq *dt:blocks*
    (append
      (vl-remove-if '(lambda (b) (= (strcase (car b)) (strcase name))) *dt:blocks*)
      (list (list (strcase name) desc pts))))
)

(defun dt:pts->str (pts / out)
  (setq out "")
  (foreach p pts
    (setq out (strcat out (if (= out "") "" " ")
                      "(" (rtos (car p) 2 6) " " (rtos (cadr p) 2 6) ")")))
  out
)

(defun dt:save-blocks ( / path f)
  (cond
    ((null *dt:root*)
     (princ "\nCannot save: load the tools through dt-load.lsp first.")
     nil)
    ((null (setq f (open (setq path (strcat *dt:root* "dt-blocks.lsp")) "w")))
     (princ (strcat "\nCannot write " path " -- is it read-only?"))
     nil)
    (t
     (write-line ";;; ======================================================" f)
     (write-line ";;; DT-BLOCKS.LSP  --  GENERATED FILE, DO NOT EDIT." f)
     (write-line ";;;" f)
     (write-line ";;; Written by DT-SETPORT. Loaded after dt-config.lsp, so" f)
     (write-line ";;; what is recorded here overrides the defaults there." f)
     (write-line ";;;" f)
     (write-line ";;;   (block-name  description  attachment points)" f)
     (write-line ";;;" f)
     (write-line ";;; Points are (x y) in BLOCK coordinates: the insertion" f)
     (write-line ";;; point is the origin, before rotation and scale." f)
     (write-line ";;;" f)
     (write-line ";;; To change one, run DT-SETPORT again. To go back to the" f)
     (write-line ";;; config defaults, delete this file." f)
     (write-line ";;; ======================================================" f)
     (write-line "" f)
     (write-line "(setq *dt:blocks*" f)
     (write-line "  '(" f)
     (foreach b *dt:blocks*
       (write-line (strcat "    (\"" (car b) "\" \"" (cadr b) "\" ("
                           (dt:pts->str (caddr b)) "))")
                   f))
     (write-line "   )" f)
     (write-line ")" f)
     (write-line "" f)
     (write-line "(princ)" f)
     (close f)
     t))
)

(defun dt:space-filter ()
  ;; ssget filter pair restricting a selection to the space the drafter is
  ;; actually looking at: the current layout tab, or model space.
  (if (= 1 (getvar 'cvport))
    (cons 410 (getvar 'ctab))
    '(410 . "Model"))
)

(princ)
