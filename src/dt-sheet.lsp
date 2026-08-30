;;; ===========================================================================
;;; DT-SHEET.LSP  --  Number the layout tabs by tab order.
;;;
;;; Command:  DT-SHEETS      (alias: SHT)
;;;
;;; Renames every paper space layout to <prefix><number>, left to right along
;;; the tabs, so reordering the tabs and re-running renumbers the set. The Model
;;; tab is never touched.
;;;
;;;     EL-03 LIGHTING          EL-01 LIGHTING
;;;     PLANTA            ->    EL-02 PLANTA
;;;     EL-01 DETAILS           EL-03 DETAILS
;;;
;;; ---------------------------------------------------------------------------
;;; WHAT IT KEEPS
;;;
;;; Descriptive text survives. A tab called "EL-03 LIGHTING" keeps LIGHTING; only
;;; the number in front is rewritten. A tab that was never numbered, like
;;; "PLANTA", keeps its whole name and simply gains a number.
;;;
;;; The rule for what counts as an existing number is deliberately narrow: an
;;; optional run of letters, an optional - or _, then digits. A SPACE is not
;;; accepted as the separator, so "PLANO 2 DE 5" is treated as an unnumbered
;;; name and kept whole rather than being read as prefix PLANO, number 2.
;;;
;;; Config: *dt:sh:prefix* (first-run default only), *dt:sh:pad*
;;; ===========================================================================

;;; --- Small helpers ---------------------------------------------------------

(defun sh:digit-p (c / a) (setq a (ascii c)) (and (>= a 48) (<= a 57)))

(defun sh:alpha-p (c / a) (setq a (ascii (strcase c))) (and (>= a 65) (<= a 90)))

(defun sh:padzeros (str len)
  (if (< (strlen str) len) (sh:padzeros (strcat "0" str) len) str)
)

(defun sh:describe (name / n i ds)
  ;; The descriptive half of a layout name -- whatever follows a leading
  ;; <letters><optional - or _><digits> token. Returns the whole name when it
  ;; does not look numbered, so an unnumbered tab keeps its word.
  (setq n (strlen name) i 1)
  (while (and (<= i n) (sh:alpha-p (substr name i 1))) (setq i (1+ i)))
  (if (and (<= i n) (member (substr name i 1) '("-" "_"))) (setq i (1+ i)))
  (setq ds i)
  (while (and (<= i n) (sh:digit-p (substr name i 1))) (setq i (1+ i)))
  (if (= i ds)
    name                                  ; no digits: not a numbered name
    (vl-string-trim " -_" (substr name i)))
)

(defun sh:bad-chars (s)
  ;; AutoCAD refuses these in a layout name; catching them here gives a clear
  ;; message instead of a COM error partway through renaming.
  (vl-some '(lambda (c) (vl-string-search c s))
           (list "<" ">" "/" "\\" "\"" ":" ";" "?" "*" "|" "," "=" "`"))
)

;;; --- Layouts ---------------------------------------------------------------

(defun sh:layouts ( / out)
  ;; Paper space layouts in tab order, Model excluded. Sorted on tab order with
  ;; the name as tiebreak: vl-sort discards elements it considers equal, and
  ;; layout names are unique, so this cannot drop a tab.
  (vlax-for lay (vla-get-Layouts (dt:doc))
    (if (/= (strcase (vla-get-Name lay)) "MODEL")
      (setq out (cons (list (vla-get-TabOrder lay) (vla-get-Name lay) lay) out))))
  (mapcar 'caddr
    (vl-sort out '(lambda (a b)
                    (if (/= (car a) (car b))
                      (< (car a) (car b))
                      (< (cadr a) (cadr b))))))
)

(defun sh:rename (lay name)
  ;; T on success. Renaming can fail for reasons we did not anticipate, and the
  ;; caller has half a set renamed by then, so failures have to be catchable.
  (not (vl-catch-all-error-p
         (vl-catch-all-apply 'vla-put-Name (list lay name))))
)

(defun sh:restore (pairs)
  (foreach p pairs (sh:rename (car p) (cdr p)))
  nil
)

;;; --- Command ---------------------------------------------------------------

(defun c:DT-SHEETS ( / *error* lays before prefix ans pad i n name new ok)

  (defun *error* (msg) (dt:report-error msg))

  (setq lays (sh:layouts)
        pad  *dt:sh:pad*)

  (cond
    ((null lays) (princ "\nThis drawing has no layouts."))
    (t
     ;; Prefix is asked every run, defaulting to whatever was used last; the
     ;; config value only seeds the very first prompt of a session.
     (if (null *dt:sh:current*) (setq *dt:sh:current* *dt:sh:prefix*))
     (setq ans (getstring t (strcat "\nSheet prefix <" *dt:sh:current* ">: "))
           prefix (if (= ans "") *dt:sh:current* ans))

     (cond
       ((sh:bad-chars prefix)
        (princ "\nA layout name cannot contain  < > / \\ \" : ; ? * | , = `"))
       (t
        (setq *dt:sh:current* prefix)

        ;; Remember every original name so a failure halfway can put the whole
        ;; set back rather than leaving it half renamed.
        (setq before (mapcar '(lambda (l) (cons l (vla-get-Name l))) lays))

        ;; Two passes. Renaming EL-02 to EL-01 fails while EL-01 still exists,
        ;; so everything goes to a unique temporary name first.
        (setq i 0 ok t)
        (foreach lay lays
          (if ok
            (setq i  (1+ i)
                  ok (sh:rename lay (strcat "~DT~" (itoa i))))))

        (if (not ok)
          (progn (sh:restore before)
                 (princ "\nCould not rename the layouts; nothing changed."))
          (progn
            (setq i 0 n 0)
            (foreach p before
              (if ok
                (progn
                  (setq i    (1+ i)
                        name (sh:describe (cdr p))
                        new  (strcat prefix (sh:padzeros (itoa i) pad)
                                     (if (= name "") "" (strcat " " name)))
                        ok   (sh:rename (car p) new))
                  (if ok (setq n (1+ n))))))

            (if ok
              (princ (strcat "\n" (itoa n) " layout(s) numbered "
                             prefix (sh:padzeros "1" pad) " to "
                             prefix (sh:padzeros (itoa n) pad) "."))
              (progn (sh:restore before)
                     (princ (strcat "\nRenaming failed at sheet " (itoa i)
                                    "; put the original names back."))))))))))
  (princ)
)

(defun c:SHT () (c:DT-SHEETS))

(princ)
