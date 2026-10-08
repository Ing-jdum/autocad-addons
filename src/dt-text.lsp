;;; ===========================================================================
;;; DT-TEXT.LSP  --  Bulk edits to TEXT and MTEXT.
;;;
;;; Commands:  DT-PREFIX   put the same string in front of every picked text
;;;                        or multileader
;;;                        (alias: PFX)
;;;
;;; The prefix is taken exactly as typed, spaces included, so "C-" and "C- "
;;; give different results.
;;; ===========================================================================

(defun c:DT-PREFIX ( / *error* doc pre ss i n obj)

  (defun *error* (msg)
    (dt:undo-end doc)
    (dt:report-error msg)
  )

  (princ "\nSelect texts to prefix: ")
  (setq ss (ssget "_:L" '((0 . "TEXT,MTEXT,MULTILEADER"))))

  (cond
    ((null ss) (princ "\nNothing selected."))
    ((= (setq pre (getstring t "\nPrefix: ")) "")
     (princ "\nNo prefix given; nothing changed."))
    (t
     (setq doc (dt:undo-begin)
           i   0
           n   0)
     ;; TextString, not DXF group 1: long MTEXT keeps its start in group 3.
     (while (< i (sslength ss))
       (setq obj (vlax-ename->vla-object (ssname ss i)))
       ;; A multileader carrying a block instead of text has nothing to prefix.
       (if (or (/= (vla-get-ObjectName obj) "AcDbMLeader")
               (= (vla-get-ContentType obj) acMTextContent))
         (progn
           (vla-put-TextString obj (strcat pre (vla-get-TextString obj)))
           (setq n (1+ n))))
       (setq i (1+ i)))
     (setq doc (dt:undo-end doc))
     (princ (strcat "\n" (itoa n) " text(s) prefixed with \"" pre "\"."))))
  (princ)
)

(defun c:PFX () (c:DT-PREFIX))
