;;; ===========================================================================
;;; DT-TEXT.LSP  --  Bulk edits to TEXT and MTEXT.
;;;
;;; Commands:  DT-PREFIX   put the same string in front of every picked text
;;;                        or multileader
;;;                        (alias: PFX)
;;;            DT-BYLAYER  set picked texts / mleaders to colour ByLayer,
;;;                        including colour painted inside the MTEXT editor
;;;                        (alias: BYL)
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

;;; MTEXT contents with the inline colour codes removed: \C<aci>; and
;;; \c<truecolor>;. SETBYLAYER and the Properties palette leave these, which is
;;; why a text can stay red after its colour reads ByLayer. A doubled backslash
;;; is a literal one, so "\\C1;" is text and survives. Every other code (\P, \H,
;;; \f, braces) is copied as is.
(defun dt:tx:strip-color (s / i n c p out)
  (setq i 1 n (strlen s) out "")
  (while (<= i n)
    (setq c (substr s i 1))
    (cond
      ((and (= c "\\") (< i n) (= (substr s (1+ i) 1) "\\"))
       (setq out (strcat out "\\\\") i (+ i 2)))
      ((and (= c "\\") (< i n) (wcmatch (substr s (1+ i) 1) "C,c"))
       ;; vl-string-search is 0-based: char i (1-based) sits at i - 1.
       (if (setq p (vl-string-search ";" s i))
         (setq i (+ p 2))
         (setq out (strcat out (substr s i)) i (1+ n))))   ; unterminated: keep
      (t (setq out (strcat out c) i (1+ i)))))
  out
)

(defun c:DT-BYLAYER ( / *error* doc ss i n obj old new col)

  (defun *error* (msg)
    (dt:undo-end doc)
    (dt:report-error msg)
  )

  (princ "\nSelect texts to set ByLayer: ")
  (setq ss (ssget "_:L" '((0 . "TEXT,MTEXT,MULTILEADER"))))

  (if (null ss)
    (princ "\nNothing selected.")
    (progn
      (setq doc (dt:undo-begin)
            i   0
            n   0)
      (while (< i (sslength ss))
        (setq obj (vlax-ename->vla-object (ssname ss i))
              old (vla-get-Color obj))
        (vla-put-Color obj acByLayer)
        (if (/= old acByLayer) (setq new t) (setq new nil))
        ;; TEXT has no inline codes; MTEXT and mleader text may.
        (if (or (= (vla-get-ObjectName obj) "AcDbMText")
                (and (= (vla-get-ObjectName obj) "AcDbMLeader")
                     (= (vla-get-ContentType obj) acMTextContent)))
          (progn
            (setq old (vla-get-TextString obj))
            (if (/= old (dt:tx:strip-color old))
              (progn
                (vla-put-TextString obj (dt:tx:strip-color old))
                (setq new t)))))
        ;; An mleader's text colour is its own override, apart from Color.
        (if (= (vla-get-ObjectName obj) "AcDbMLeader")
          (progn
            (setq col (vla-get-TextColor obj))
            (if (/= (vla-get-ColorMethod col) acColorMethodByLayer)
              (progn
                (vla-put-ColorMethod col acColorMethodByLayer)
                (vla-put-TextColor obj col)
                (setq new t)))))
        (if new (setq n (1+ n)))
        (setq i (1+ i)))
      (setq doc (dt:undo-end doc))
      (princ (strcat "\n" (itoa n) " of " (itoa (sslength ss))
                     " text(s) changed to ByLayer."))))
  (princ)
)

(defun c:BYL () (c:DT-BYLAYER))
