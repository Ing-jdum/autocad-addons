;;; ===========================================================================
;;; DT-LABEL.LSP  --  Sequential numbering of block attributes, by group.
;;;
;;; Commands:  DT-RENUMBER      renumber every group once, now   (alias: RNB)
;;;            DT-SETGROUP      set the group tag on picked blocks (alias: SG)
;;;            DT-COUNTS        report how many of each group exist
;;;            DT-AUTOLABELON   renumber automatically as you draw
;;;            DT-AUTOLABELOFF  stop doing that
;;;
;;; ---------------------------------------------------------------------------
;;; THE GROUPING MODEL
;;;
;;; One counter block carries two attributes:
;;;
;;;     GROUP    what this thing is    -- the drafter fills this in ("C", "P")
;;;     NUMBER   its sequence number   -- filled in automatically
;;;
;;; Each distinct GROUP value gets its own independent 1..N run. Counting a new
;;; kind of thing means typing a new GROUP value on the block. It does not mean
;;; a new block definition, and it does not mean editing any code or config.
;;;
;;; Group values are upper-cased, so "tug" and "TUG" are the same group. Typos
;;; still make silent new groups -- DT-COUNTS is how you spot them.
;;;
;;; Blocks with a blank GROUP are skipped and reported, never guessed at.
;;;
;;; Config: *dt:lbl:block*, *dt:lbl:group-tag*, *dt:lbl:number-tag*,
;;;         *dt:lbl:format*, *dt:lbl:order*, *dt:lbl:row-tol*,
;;;         *dt:lbl:commands*, *dt:lbl:startup*
;;; ===========================================================================

;;; --- Text helpers ----------------------------------------------------------

(defun lbl:padzeros (str len)
  (if (< (strlen str) len)
    (lbl:padzeros (strcat "0" str) len)
    str)
)

(defun lbl:pad-right (str width / out)
  ;; Spaces needed to carry STR out to WIDTH columns, for the DT-COUNTS table.
  (setq out "")
  (repeat (max 1 (- width (strlen str))) (setq out (strcat out " ")))
  out
)

(defun lbl:expand (str group / pos out rest)
  ;; %G in the prefix or suffix expands to the group value. Scans once rather
  ;; than looping on vl-string-subst, which would spin forever if a group value
  ;; ever contained "%G" itself.
  (setq out "" rest str)
  (while (setq pos (vl-string-search "%G" rest))
    (setq out  (strcat out (substr rest 1 pos) group)
          rest (substr rest (+ pos 3))))
  (strcat out rest)
)

;;; --- Attribute access ------------------------------------------------------

(defun lbl:find-att (obj tag)
  (if (vlax-method-applicable-p obj 'getattributes)
    (vl-some
      '(lambda (a) (if (= (strcase (vla-get-tagstring a)) (strcase tag)) a))
      (vlax-invoke obj 'getattributes)))
)

(defun lbl:att-value (obj tag / a)
  (if (setq a (lbl:find-att obj tag))
    (vl-string-trim " \t" (vla-get-textstring a)))
)

;;; --- Collection ------------------------------------------------------------
;;; A record is (ename x y idx group), group nil when the drafter left it blank.
;;;
;;; IDX is the original selection index and exists purely as a sort tiebreak:
;;; vl-sort DISCARDS elements its comparator calls equal, so a comparator that
;;; could report "neither is less" would silently drop blocks from renumbering.

(defun lbl:collect ( / sel i ent obj grp pt recs)
  (setq recs nil i 0)
  (if (setq sel (ssget "_X"
                  (list '(-4 . "<AND")
                        '(0 . "INSERT")
                        '(66 . 1)
                        ;; The `*U* wildcard also catches the anonymous names a
                        ;; dynamic block takes on once a parameter is changed;
                        ;; EffectiveName below is what narrows it back down.
                        (cons 2 (strcat "`*U*," *dt:lbl:block*))
                        '(-4 . "AND>")
                        (dt:space-filter))))
    (while (< i (sslength sel))
      (setq ent (ssname sel i)
            obj (vlax-ename->vla-object ent))
      (if (= (strcase (vla-get-EffectiveName obj))
             (strcase *dt:lbl:block*))
        (progn
          (setq grp (lbl:att-value obj *dt:lbl:group-tag*)
                pt  (cdr (assoc 10 (entget ent))))
          (if (= grp "") (setq grp nil))
          (setq recs (cons (list ent (car pt) (cadr pt) i
                                 (if grp (strcase grp)))
                           recs))))
      (setq i (1+ i))))
  (reverse recs)
)

(defun lbl:tagged   (recs) (vl-remove-if-not '(lambda (r) (nth 4 r)) recs))
(defun lbl:untagged (recs) (vl-remove-if     '(lambda (r) (nth 4 r)) recs))

(defun lbl:group-by (recs / out hit key)
  ;; Alist of (group . records), groups in alphabetical order. Keys are unique
  ;; by construction, so vl-sort has nothing it could consider equal and drop.
  (setq out nil)
  (foreach r (lbl:tagged recs)
    (setq key (nth 4 r))
    (if (setq hit (assoc key out))
      (setq out (subst (cons key (cons r (cdr hit))) hit out))
      (setq out (cons (list key r) out))))
  (mapcar '(lambda (g) (cons (car g) (reverse (cdr g))))
          (vl-sort out '(lambda (a b) (< (car a) (car b)))))
)

;;; --- Ordering --------------------------------------------------------------
;;; Row banding under 'reading is deliberately not transitive -- two fixtures
;;; can each be within tolerance of a third but not of each other. That only
;;; affects where a band boundary lands, never whether a block is numbered,
;;; because IDX still breaks every pair.

(defun lbl:less (a b)
  (if (= *dt:lbl:order* 'columns)
    (cond ((/= (cadr a) (cadr b)) (< (cadr a) (cadr b)))        ; X ascending
          ((/= (caddr a) (caddr b)) (< (caddr a) (caddr b)))    ; then Y up
          (t (< (cadddr a) (cadddr b))))
    (cond ((not (equal (caddr a) (caddr b) *dt:lbl:row-tol*))
           (> (caddr a) (caddr b)))                             ; higher Y first
          ((/= (cadr a) (cadr b)) (< (cadr a) (cadr b)))         ; then X across
          (t (< (cadddr a) (cadddr b)))))
)

(defun lbl:sort (recs)
  (if (= *dt:lbl:order* 'database)
    recs
    (vl-sort recs 'lbl:less))
)

;;; --- Renumbering -----------------------------------------------------------

(defun lbl:renumber-group (group recs / prefix suffix num obj att want done)
  (setq prefix (lbl:expand (nth 0 *dt:lbl:format*) group)
        suffix (lbl:expand (nth 1 *dt:lbl:format*) group)
        num    (nth 2 *dt:lbl:format*)
        done   0)

  (foreach r (lbl:sort recs)
    (setq obj (vlax-ename->vla-object (car r))
          att (lbl:find-att obj *dt:lbl:number-tag*))
    (if att
      (progn
        (setq want (strcat prefix
                           (lbl:padzeros (itoa num) (nth 3 *dt:lbl:format*))
                           suffix))
        ;; Skip writes that would change nothing. On a drawing with a few
        ;; hundred tags this is the difference between a reactor you notice and
        ;; one you do not.
        (if (/= (vla-get-textstring att) want)
          (progn (vla-put-textstring att want)
                 (setq done (1+ done))))
        (setq num (1+ num)))))
  done
)

(defun lbl:renumber-all ( / total)
  (setq total 0)
  (foreach g (lbl:group-by (lbl:collect))
    (setq total (+ total (lbl:renumber-group (car g) (cdr g)))))
  total
)

(defun lbl:warn-untagged (recs / n)
  (if (> (setq n (length (lbl:untagged recs))) 0)
    (princ (strcat "\n" (itoa n) " block(s) have no " *dt:lbl:group-tag*
                   " value and were skipped.")))
)

;;; --- Commands --------------------------------------------------------------

(defun c:DT-RENUMBER ( / *error* doc recs n)

  (defun *error* (msg)
    (dt:undo-end doc)
    (dt:report-error msg)
  )

  (setq doc  (dt:undo-begin)
        recs (lbl:collect)
        n    0)
  (foreach g (lbl:group-by recs)
    (setq n (+ n (lbl:renumber-group (car g) (cdr g)))))
  (setq doc (dt:undo-end doc))

  (princ (strcat "\n" (itoa n) " attribute(s) renumbered."))
  (lbl:warn-untagged recs)
  (princ)
)

(defun c:DT-COUNTS ( / recs groups total)
  ;; What is in the drawing, per group. Also the quickest way to catch a typo:
  ;; a group with a count of 1 that you expected to see 30 of.
  (setq recs   (lbl:collect)
        groups (lbl:group-by recs)
        total  0)
  (if (null groups)
    (princ "\nNo counter blocks found.")
    (progn
      (princ "\n  Group                       Count")
      (princ "\n  --------------------------- -----")
      (foreach g groups
        (princ (strcat "\n  " (car g) (lbl:pad-right (car g) 28)
                       (itoa (length (cdr g)))))
        (setq total (+ total (length (cdr g)))))
      (princ "\n  --------------------------- -----")
      (princ (strcat "\n  " (itoa (length groups)) " group(s)"
                     (lbl:pad-right (strcat (itoa (length groups)) " group(s)") 28)
                     (itoa total)))))
  (lbl:warn-untagged recs)
  (princ)
)

(defun c:DT-SETGROUP ( / *error* doc val ss i obj att set missing n)

  (defun *error* (msg)
    (dt:undo-end doc)
    (dt:report-error msg)
  )

  (princ "\nSelect blocks to tag as one group: ")
  (setq ss (ssget '((0 . "INSERT") (66 . 1))))

  (cond
    ((null ss) (princ "\nNothing selected."))
    ((= (setq val (vl-string-trim " \t"
                    (getstring t (strcat "\n" *dt:lbl:group-tag* " value: "))))
        "")
     (princ "\nNo value given; nothing changed."))
    (t
     (setq doc     (dt:undo-begin)
           val     (strcase val)
           i       0
           set     0
           missing 0)
     (while (< i (sslength ss))
       (setq obj (vlax-ename->vla-object (ssname ss i))
             att (lbl:find-att obj *dt:lbl:group-tag*))
       (if att
         (progn (vla-put-textstring att val) (setq set (1+ set)))
         (setq missing (1+ missing)))
       (setq i (1+ i)))

     ;; Renumbering here is the point: the groups changed, so the sequences did.
     (setq n   (lbl:renumber-all)
           doc (dt:undo-end doc))

     (princ (strcat "\n" (itoa set) " block(s) set to "
                    *dt:lbl:group-tag* " = " val
                    ", " (itoa n) " number(s) updated."))
     (if (> missing 0)
       (princ (strcat "\n" (itoa missing) " selected block(s) have no "
                      *dt:lbl:group-tag* " attribute and were skipped.")))))
  (princ)
)

(defun c:RNB () (c:DT-RENUMBER))
(defun c:SG  () (c:DT-SETGROUP))

;;; --- Reactor callbacks -----------------------------------------------------
;;; lbl:current holds the name of the command that is running, captured at
;;; start, because :vlr-commandended does not tell us what ended. It is the one
;;; deliberate global here: it has to survive between two callbacks.

(defun lbl:command-start (rtr arg)
  (setq lbl:current (strcase (car arg)))
  (princ)
)

(defun lbl:command-end (rtr arg)
  ;; UNDO and REDO are skipped on purpose. Renumbering right after an undo
  ;; would stack a fresh operation on top of the one just reversed, discarding
  ;; the redo and making the drafter's next U undo our renumber instead of
  ;; their own work.
  (if (and lbl:current
           (not (member lbl:current '("UNDO" "U" "REDO" "MREDO")))
           (member lbl:current *dt:lbl:commands*))
    ;; No undo mark here, deliberately: the writes fold into the undo step of
    ;; the command that just ended, so undoing that COPY also undoes the
    ;; renumbering it triggered. DT-RENUMBER marks its own, being standalone.
    (lbl:renumber-all))
  (setq lbl:current nil)
  (princ)
)

;;; --- Enable / disable ------------------------------------------------------

(defun lbl:disable (key)
  (foreach grp (vlr-reactors :vlr-command-reactor)
    (foreach obj (cdr grp)
      (if (= key (vlr-data obj)) (vlr-remove obj))))
  (setq lbl:current nil)
  nil
)

(defun lbl:enable (key)
  (lbl:disable key)
  (vlr-set-notification
    (vlr-command-reactor key
      '((:vlr-commandwillstart . lbl:command-start)
        (:vlr-commandended     . lbl:command-end)))
    'active-document-only)
  (lbl:renumber-all)
  t
)

(defun c:DT-AUTOLABELON ()
  (lbl:enable "dt-autolabel")
  (princ "\nAuto numbering ON for this drawing.")
  (princ)
)

(defun c:DT-AUTOLABELOFF ()
  (lbl:disable "dt-autolabel")
  (princ "\nAuto numbering OFF.")
  (princ)
)

;;; --- Startup ---------------------------------------------------------------
;;; Off unless the office explicitly opts in via config (README 6.8).

(if *dt:lbl:startup* (lbl:enable "dt-autolabel"))

(princ)
