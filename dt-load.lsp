;;; ===========================================================================
;;; DT-LOAD.LSP  --  The only file that goes in the Startup Suite.
;;;
;;; Setup on a new machine:
;;;   Command: APPLOAD  ->  Contents...  ->  Add...  ->  pick this file  -> Close
;;;
;;; Loads core, then config, then every module, in that order. Prints one
;;; summary line naming the commands that are now available.
;;;
;;; Nothing here touches the drawing. Loading defines functions and says so.
;;; ===========================================================================

(vl-load-com)

;;; --- Where are we? ---------------------------------------------------------
;;; APPLOAD does not put a file's own folder on the support path, so findfile
;;; only works once the folder has been added under OPTIONS > Files. The
;;; fallback below covers the normal case where it has not.
;;;
;;; If the office moves this folder, this is the one line to update.

(setq *dt:fallback-root*
  "C:\\Users\\promi\\OneDrive\\Documentos\\john\\FERZA\\addons\\")

(defun dt:root ( / f)
  (cond
    ((setq f (findfile "dt-load.lsp"))
     (strcat (vl-filename-directory f) "\\"))
    ((findfile (strcat *dt:fallback-root* "dt-load.lsp"))
     *dt:fallback-root*)
    (t nil))
)

;;; --- Load one file, reporting failure by name ------------------------------

(defun dt:load-file (root rel / path)
  (setq path (strcat root rel))
  (cond
    ((not (findfile path))
     (princ (strcat "\n  MISSING: " rel))
     nil)
    ((vl-catch-all-error-p
       (vl-catch-all-apply 'load (list path)))
     (princ (strcat "\n  FAILED:  " rel))
     nil)
    (t t))
)

(defun dt:load-optional (root rel / path)
  ;; For generated files that may legitimately not exist yet. Absent is fine;
  ;; present but broken is not.
  (cond
    ((not (setq path (findfile (strcat root rel)))) t)
    ((vl-catch-all-error-p (vl-catch-all-apply 'load (list path)))
     (princ (strcat "\n  FAILED:  " rel))
     nil)
    (t t))
)

;;; --- Go --------------------------------------------------------------------

(defun dt:load-all ( / root ok)
  (if (not (setq root (dt:root)))
    (progn
      (princ "\nDrafting tools: cannot locate the addons folder.")
      (princ "\n  Fix *dt:fallback-root* in dt-load.lsp, or add the")
      (princ "\n  folder under OPTIONS > Files > Support File Search Path.")
      nil)
    (progn
      ;; Published so DT-SETPORT knows where to write dt-blocks.lsp.
      (setq *dt:root* root
            ok        t)
      ;; Order matters: core defines the helpers the modules call, config
      ;; defines the globals they read.
      (foreach rel '("src\\dt-core.lsp"
                     "dt-config.lsp"
                     "src\\dt-fixture.lsp"
                     "src\\dt-wiretree.lsp"
                     "src\\dt-label.lsp"
                     "src\\dt-dim.lsp"
                     "src\\dt-sheet.lsp"
                     "src\\dt-text.lsp"
                     "src\\dt-load-takeoff.lsp"
                     "src\\dt-panel.lsp")
        (if (not (dt:load-file root rel)) (setq ok nil)))

      ;; The block registry as measured by DT-SETPORT. Loaded after config so
      ;; what the office recorded wins over the defaults in dt-config.lsp.
      (if (not (dt:load-optional root "dt-blocks.lsp")) (setq ok nil))

      ;; Per-group prefixes as set by DT-SETPREFIX. Same rule: loaded
      ;; after config so what the drafter recorded wins over the default.
      (if (not (dt:load-optional root "dt-labels.lsp")) (setq ok nil))

      (if ok
        (progn
          (princ "\nDrafting tools loaded.")
          (princ "\n  DT-FIXCEN   (FIXCEN, FXC)  place block at centre of picked area")
          (princ "\n  DT-FIXDIV   (FIXDIV, FXD)  space N blocks along a line or curve")
          (princ "\n  DT-SETBLOCK (SB)           choose the block those two place")
          (princ "\n  DT-WTREE    (WTREE, WTR)   wire selected devices, loop-free")
          (princ "\n  DT-SETPORT  (SP)           measure where wires meet a symbol")
          (princ "\n  DT-PORTS                   list the measured symbols")
          (princ "\n  DT-TAG      (TG)           place counter tags, building COUNT_TAG")
          (princ "\n  DT-SETGROUP (SG)           tag picked blocks as one count group")
          (princ "\n  DT-RENUMBER (RNB)          renumber every group now")
        (princ "\n  DT-SETPREFIX (SPX)        set one group's number prefix")
        (princ "\n  DT-SETROW   (SR)           set how far apart one row of tags is")
        (princ "\n  DT-SETORDER (SO)           number by plan order or by insert order")
        (princ "\n  DT-SETLETTERS (LTR)        count one group in A, B, C or in 1, 2, 3")
        (princ "\n  DT-SETPAD   (PAD)          digits one group pads to: 1, 01, 001")
        (princ "\n  DT-SWITCH   (SWL)          click-by-click tags, label repeats")
        (princ "\n  DT-SWNEXT   (SWN)          one switch tag at the next letter")
        (princ "\n  DT-SETSKIP  (SKP)          turn RNB off for one group")
          (princ "\n  DT-FIXDIM   (FDM)          dimension a row of fixtures, wall to wall")
          (princ "\n  DT-FIXDIMH  (FDMH)         same, measured across the sheet")
          (princ "\n  DT-FIXDIMV  (FDMV)         same, measured up the sheet")
          (princ "\n  DT-COUNTS                  how many of each group in the drawing")
          (princ "\n  DT-SHEETS   (SHT)          number the layout tabs in tab order")
          (princ "\n  DT-NOLW     (NOLWPLOT)     plot every layout without lineweights")
          (princ "\n  DT-PREFIX   (PFX)          put text in front of picked text/mleaders")
          (princ "\n  DT-SETCIRCUIT (SC)         tag devices with panel + circuit")
          (princ "\n  DT-RENCIRCUIT              rename circuits, one or from a CSV")
          (princ "\n  DT-RENPANEL                rename a panel everywhere")
          (princ "\n  DT-FIXATTS                 add missing attributes to a block")
          (princ "\n  DT-LOAD     (LD)           load per panel and circuit, to CSV")
          (princ "\n  DT-PANELS   (PNL)          list panels, write the CSV template")
          (princ "\n  DT-SETPANEL (SPN)          fill panel kVA from that CSV"))
        (princ "\nDrafting tools: loaded with errors -- see above."))
      ok))
)

(dt:load-all)
(princ)
