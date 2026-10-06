;;; ===========================================================================
;;; DT-LABEL.LSP  --  Sequential numbering of block attributes, by group.
;;;
;;; Commands:  DT-RENUMBER      renumber every group once, now   (alias: RNB)
;;;            DT-SETGROUP      set the group tag on picked blocks (alias: SG)
;;;            DT-SETORDER      number by plan order or insert order (alias: SO)
;;;            DT-COUNTS        report how many of each group exist
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
;;; Renumbering is on demand only. There was once a reactor that renumbered as
;;; you drew; it was removed because DT-RENUMBER covers the need and a live
;;; reactor is a standing cost in every drawing for a command you can just type.
;;;
;;; Config: *dt:lbl:block*, *dt:lbl:group-tag*, *dt:lbl:number-tag*,
;;;         *dt:lbl:format*, *dt:lbl:order*, *dt:lbl:row-tol*
;;; ===========================================================================

;;; --- Text helpers ----------------------------------------------------------

(defun lbl:padzeros (str len)
  (if (< (strlen str) len)
    (lbl:padzeros (strcat "0" str) len)
    str)
)

(defun lbl:letter (n / out r)
  ;; 1 -> A, 26 -> Z, 27 -> AA. Bijective base 26: there is no zero digit, so
  ;; the 1- before the rem and again before the divide is what carries Z to AA
  ;; rather than to BA. Past Z is rare on a plan but costs nothing to get right.
  (setq out "")
  (if (< n 1) (setq n 1))               ; a start of 0 would give a blank tag
  (while (> n 0)
    (setq r   (rem (1- n) 26)
          out (strcat (chr (+ 65 r)) out)
          n   (/ (- n 1 r) 26)))
  out
)

(defun lbl:letters-p (group)
  ;; Upper-cased on both sides, so a group recorded in lower case still hits --
  ;; the same reason lbl:prefix-entry does not use a raw assoc.
  (if (member (strcase group) (mapcar 'strcase *dt:lbl:letter-groups*)) t)
)

(defun lbl:seq (group num)
  ;; What goes between the prefix and the suffix. Padding is a number's idea of
  ;; width and means nothing to a letter, so letters skip it.
  (if (lbl:letters-p group)
    (lbl:letter num)
    (lbl:padzeros (itoa num) (lbl:pad-for group)))
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

;;; --- The block itself ------------------------------------------------------
;;; Normally COUNT_TAG arrives with the office template and none of this runs.
;;; It exists so a drawing that started without one does not send you hunting
;;; through an old file for a block to copy.

(defun lbl:make-block ( / h)
  ;; A visible NUMBER and an invisible GROUP -- the two attributes the rest of
  ;; this file reads, and nothing else. Both go on layer 0 so the tag takes the
  ;; layer of whatever you insert it onto, as a template block would. GROUP is
  ;; invisible because it is data, not annotation; ATTDISP On shows it when you
  ;; want to eyeball which tag is in which group.
  ;; No circle, no frame -- just the number. Anything you want drawn around it
  ;; belongs in the office template's own COUNT_TAG, which this never overrides.
  ;;
  ;; nil height means "match this drawing", the same way *dt:fx:layer* nil means
  ;; "use the current layer". TEXTSIZE reads 0 when the current text style has a
  ;; fixed height, so DIMTXT is the fallback before any hardcoded number.
  (setq h (cond (*dt:lbl:tag-height*)
                ((> (getvar "TEXTSIZE") 0.0) (getvar "TEXTSIZE"))
                ((> (getvar "DIMTXT") 0.0) (getvar "DIMTXT"))
                (t 2.5)))

  ;; 70 bit 2 on the BLOCK record declares that it carries attribute defs.
  (entmake (list '(0 . "BLOCK")
                 (cons 2 *dt:lbl:block*)
                 '(10 0.0 0.0 0.0)
                 '(70 . 2)))

  ;; 72/74 centre the text on the insertion point, and group 11 has to carry
  ;; it for that to take -- with justification set, 10 is not what is read.
  ;;
  ;; Flag 8 is "preset": the attribute takes its default and INSERT never stops
  ;; to ask. That is what keeps DT-TAG and any later copy silent. NUMBER is
  ;; filled by RNB and GROUP by SG, so there is nothing to type at insert time.
  (entmake (list '(0 . "ATTDEF")
                 '(8 . "0")
                 '(10 0.0 0.0 0.0)
                 '(11 0.0 0.0 0.0)
                 (cons 40 h)
                 ;; A preset attribute takes this default and never prompts, so
                 ;; an empty default would put down a blank bubble you cannot
                 ;; see until RNB runs. The configured start number, padded the
                 ;; configured way, is a placeholder shaped like the real thing.
                 ;; Prefix and suffix stay out of it: they can carry %G, and
                 ;; there is no group to expand it against until SG says so.
                 (cons 1 (lbl:padzeros (itoa (nth 2 *dt:lbl:format*))
                                       (nth 3 *dt:lbl:format*)))
                 (cons 3 *dt:lbl:number-tag*)
                 (cons 2 *dt:lbl:number-tag*)
                 '(70 . 8)
                 '(72 . 1)
                 '(74 . 2)))

  (entmake (list '(0 . "ATTDEF")
                 '(8 . "0")
                 '(10 0.0 0.0 0.0)
                 '(11 0.0 0.0 0.0)
                 (cons 40 h)
                 '(1 . "")
                 (cons 3 *dt:lbl:group-tag*)
                 (cons 2 *dt:lbl:group-tag*)
                 '(70 . 9)              ; 1 invisible + 8 preset
                 '(72 . 1)
                 '(74 . 2)))

  (entmake '((0 . "ENDBLK")))
  (tblsearch "BLOCK" *dt:lbl:block*)
)

(defun lbl:ensure-block ()
  ;; Same contract as dt:ensure-layer: build it if missing, never touch it if
  ;; it is already there. A tag that came from the template always wins, even
  ;; if it looks nothing like the one above.
  (cond
    ((or (null *dt:lbl:block*) (= *dt:lbl:block* ""))
     (princ "\nNo block name configured. Check dt-config.lsp.")
     nil)
    ((tblsearch "BLOCK" *dt:lbl:block*) t)
    ((lbl:make-block)
     (princ (strcat "\nCreated block \"" *dt:lbl:block* "\" in this drawing."))
     t)
    (t
     (princ (strcat "\nCould not create block \"" *dt:lbl:block* "\"."))
     nil))
)

;;; --- Collection ------------------------------------------------------------
;;; A record is (ename x y idx group), group nil when the drafter left it blank.
;;;
;;; IDX is the original selection index and exists purely as a sort tiebreak:
;;; vl-sort DISCARDS elements its comparator calls equal, so a comparator that
;;; could report "neither is less" would silently drop blocks from renumbering.

(defun lbl:collect ( / sel i ent obj grp pt recs)
  (setq recs nil i 0)
  ;; One guard for all three commands, since every one of them collects.
  (if (lbl:ensure-block)
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
      (setq i (1+ i)))))
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
;;; Reading order is rows top to bottom, then left to right across each row.
;;; Rows are found by lbl:band before any sorting happens; see the note there
;;; for why the tolerance cannot live inside the comparator.

(defun lbl:band (recs / out band prev)
  ;; Tags into numbered rows, top row first. Returns each record with its row
  ;; number consed on: (band ename x y idx group).
  ;;
  ;; Done as one pass over Y rather than by asking a comparator "same row?",
  ;; because that question cannot be answered transitively once the tolerance
  ;; is above zero: A within tolerance of B and B of C does not make A within
  ;; tolerance of C. Fed to vl-sort, a comparator like that cycles, and the
  ;; numbering comes out depending on which pairs the sort happened to compare.
  ;; A row number assigned once, up front, cannot cycle.
  ;;
  ;; The gap is measured from the previous tag, not from the row's first tag,
  ;; so a row that drifts gently stays one row -- which is what a slightly
  ;; wavy run of fixtures actually is.
  ;;
  ;; ponytail: a long gentle slope of tags, each within tolerance of the last
  ;; but spanning several real rows, merges into one band. Cluster on the gap
  ;; distribution instead if a drawing ever shows that.
  (setq out nil band 0 prev nil)
  (foreach r (vl-sort recs
               '(lambda (a b)
                  (if (= (caddr a) (caddr b))
                    (< (cadddr a) (cadddr b))
                    (> (caddr a) (caddr b)))))
    (if (and prev (> (- prev (caddr r)) *dt:lbl:row-tol*))
      (setq band (1+ band)))
    (setq prev (caddr r)
          out  (cons (cons band r) out)))
  (reverse out)
)

(defun lbl:less-columns (a b)
  ;; ponytail: 'columns compares X exactly, so it has the banding problem
  ;; 'reading just lost. Nobody in this office runs it -- config ships
  ;; 'reading -- so it is left alone. Band it on X the same way if that changes.
  (cond ((/= (cadr a) (cadr b)) (< (cadr a) (cadr b)))        ; X ascending
        ((/= (caddr a) (caddr b)) (< (caddr a) (caddr b)))    ; then Y up
        (t (< (cadddr a) (cadddr b))))
)

(defun lbl:handle< (a b / ha hb)
  ;; Oldest entity first, by handle. AutoCAD hands out handles in ascending hex
  ;; as entities are created, so this IS insertion order -- and unlike the order
  ;; a selection set happens to come back in, it does not depend on how the set
  ;; was built. Sorting on it is what stops 'database numbering the last tag you
  ;; placed as 01.
  ;;
  ;; Compared as hex text: shorter is smaller ("FF" before "100"), and at equal
  ;; length plain string order is already hex order, since "0"-"9" sort before
  ;; "A"-"F" in ASCII. Parsing them into integers would overflow on a drawing
  ;; old enough to have handles past eight digits.
  ;;
  ;; Handles are unique, so no two records ever compare equal and vl-sort has
  ;; nothing it could discard.
  (setq ha (strcase (cdr (assoc 5 (entget (car a)))))
        hb (strcase (cdr (assoc 5 (entget (car b))))))
  (if (= (strlen ha) (strlen hb))
    (< ha hb)
    (< (strlen ha) (strlen hb)))
)

(defun lbl:sort (recs)
  ;; Banded record is (band ename x y idx group): car band, caddr X, cadddr Y,
  ;; nth 4 idx. Row, then across the row, then down a stack, then the original
  ;; index -- four total orders read in turn, so the comparator cannot cycle and
  ;; no two records ever compare equal, which is what stops vl-sort discarding
  ;; one of a pair of tags sitting on the exact same point.
  (cond
    ((= *dt:lbl:order* 'database) (vl-sort recs 'lbl:handle<))
    ((= *dt:lbl:order* 'columns)  (vl-sort recs 'lbl:less-columns))
    (t (mapcar 'cdr
         (vl-sort (lbl:band recs)
           '(lambda (a b)
              (cond ((/= (car a) (car b)) (< (car a) (car b)))
                    ((/= (caddr a) (caddr b)) (< (caddr a) (caddr b)))
                    ;; Same row and same X means a stack. Read it downwards
                    ;; rather than in the order it happened to be drawn.
                    ((/= (cadddr a) (cadddr b)) (> (cadddr a) (cadddr b)))
                    (t (< (nth 4 a) (nth 4 b)))))))))
)

(setq *dt:lbl:prefix-overrides* nil)   ; replaced by dt-labels.lsp when it loads
(setq *dt:lbl:pad-overrides*    nil)   ; likewise -- (group . digits)
(setq *dt:lbl:skip-groups*      nil)   ; likewise -- groups RNB leaves alone

(defun lbl:skip-p (group)
  ;; Numbered by hand, so RNB must not touch it. The tags are still COUNT_TAG
  ;; and still counted by DT-COUNTS -- the only thing that changes is that
  ;; nothing overwrites what the drafter typed.
  (if (member (strcase group) (mapcar 'strcase *dt:lbl:skip-groups*)) t)
)

(defun lbl:put-skip (group on)
  (setq *dt:lbl:skip-groups*
    (append
      (vl-remove-if '(lambda (g) (= (strcase g) (strcase group)))
                    *dt:lbl:skip-groups*)
      (if on (list (strcase group)) nil)))
)

(defun lbl:put-prefix (group prefix)
  ;; Replace or append. An empty prefix drops the override rather than storing
  ;; an empty string, so clearing one is the same command with no answer.
  (setq *dt:lbl:prefix-overrides*
    (append
      (vl-remove-if '(lambda (e) (= (strcase (car e)) (strcase group)))
                    *dt:lbl:prefix-overrides*)
      (if (= prefix "") nil (list (cons (strcase group) prefix)))))
)

(defun lbl:put-pad (group digits)
  ;; A nil width drops the override, the same way an empty prefix does.
  (setq *dt:lbl:pad-overrides*
    (append
      (vl-remove-if '(lambda (e) (= (strcase (car e)) (strcase group)))
                    *dt:lbl:pad-overrides*)
      (if digits (list (cons (strcase group) digits)) nil)))
)

(defun lbl:put-letters (group on)
  ;; Letters or numbers for one group. Off drops it from the list rather than
  ;; recording a "no", so the list stays a plain roll of the letter groups.
  (setq *dt:lbl:letter-groups*
    (append
      (vl-remove-if '(lambda (g) (= (strcase g) (strcase group)))
                    *dt:lbl:letter-groups*)
      (if on (list (strcase group)) nil)))
)

(defun lbl:safe-text (what str)
  ;; This string gets written into a file that is LOADed at startup, so a quote
  ;; or a backslash in it would not merely look wrong -- it would break the load
  ;; and take every command down with it. Refuse them at the prompt instead.
  ;;
  ;; Group names go through here as well as prefixes: they are written into the
  ;; same file, and a group is typed by hand on a block where nothing has ever
  ;; checked it. WHAT is the word for the message ("prefix", "group").
  ;;
  ;; vl-string-search rather than wcmatch: wcmatch would read the pattern for
  ;; wildcards, and a prefix is exactly the place someone types a * or a ?.
  (cond
    ((vl-string-search "\"" str)
     (princ (strcat "\nA " what " cannot contain a double quote."))
     nil)
    ((vl-string-search "\\" str)
     (princ (strcat "\nA " what " cannot contain a backslash."))
     nil)
    (t t))
)

(defun lbl:save-labels ( / path f)
  ;; Same contract as dt:save-blocks: a generated file, rewritten whole, loaded
  ;; after dt-config.lsp so what the drafter set here wins over the default.
  ;; Carries every drafter-facing label setting, so both commands write it and
  ;; neither can drop what the other set.
  (cond
    ((null *dt:root*)
     (princ "
Cannot save: load the tools through dt-load.lsp first.")
     nil)
    ((null (setq f (open (setq path (strcat *dt:root* "dt-labels.lsp")) "w")))
     (princ (strcat "
Cannot write " path " -- is it read-only?"))
     nil)
    (t
     (write-line ";;; ======================================================" f)
     (write-line ";;; DT-LABELS.LSP  --  GENERATED FILE, DO NOT EDIT." f)
     (write-line ";;;" f)
     (write-line ";;; Written by DT-SETPREFIX, DT-SETROW, DT-SETORDER and" f)
     (write-line ";;; DT-SETLETTERS. Loaded after dt-config.lsp, so what is" f)
     (write-line ";;; here overrides the defaults recorded there." f)
     (write-line ";;;" f)
     (write-line ";;;   (group . prefix)   and the groups that count A, B, C" f)
     (write-line ";;;" f)
     (write-line ";;; A group not listed uses the prefix in *dt:lbl:format*." f)
     (write-line ";;; To change one, run the command again. To go back to the" f)
     (write-line ";;; config defaults, delete this file." f)
     (write-line ";;; ======================================================" f)
     (write-line "" f)
     (write-line "(setq *dt:lbl:prefix-overrides*" f)
     (write-line "  '(" f)
     (foreach e *dt:lbl:prefix-overrides*
       (write-line (strcat "    (\"" (car e) "\" . \"" (cdr e) "\")") f))
     (write-line "   )" f)
     (write-line ")" f)
     (write-line "" f)
     ;; rtos with an explicit mode and precision, so the drawing's own units
     ;; settings cannot turn this into something LOAD will not read back.
     (write-line (strcat "(setq *dt:lbl:row-tol* "
                         (rtos *dt:lbl:row-tol* 2 6) ")") f)
     (write-line "" f)
     ;; A quoted symbol, the same three values dt-config.lsp documents.
     (write-line (strcat "(setq *dt:lbl:order* '"
                         (vl-princ-to-string *dt:lbl:order*) ")") f)
     (write-line "" f)
     (write-line "(setq *dt:lbl:skip-groups*" f)
     (write-line "  '(" f)
     (foreach g *dt:lbl:skip-groups*
       (write-line (strcat "    \"" g "\"") f))
     (write-line "   )" f)
     (write-line ")" f)
     (write-line "" f)
     (write-line "(setq *dt:lbl:pad-overrides*" f)
     (write-line "  '(" f)
     (foreach e *dt:lbl:pad-overrides*
       (write-line (strcat "    (\"" (car e) "\" . " (itoa (cdr e)) ")") f))
     (write-line "   )" f)
     (write-line ")" f)
     (write-line "" f)
     (write-line "(setq *dt:lbl:letter-groups*" f)
     (write-line "  '(" f)
     (foreach g *dt:lbl:letter-groups*
       (write-line (strcat "    \"" g "\"") f))
     (write-line "   )" f)
     (write-line ")" f)
     (write-line "" f)
     (write-line "(princ)" f)
     (close f)
     t))
)

(defun lbl:prefix-entry (group)
  ;; The (group . prefix) pair recorded for GROUP, or nil if it has none.
  ;; DT-SETPREFIX needs the pair, not just the prefix, to tell a group that was
  ;; set from one that is merely falling back to the shared prefix.
  ;;
  ;; Matched with vl-some rather than assoc so a key recorded in lower case
  ;; still hits: lbl:collect upper-cases every GROUP value it reads, so a raw
  ;; assoc would quietly miss ("tug" . "T-") and fall back instead.
  (vl-some '(lambda (e) (if (= (strcase (car e)) (strcase group)) e))
           *dt:lbl:prefix-overrides*)
)

(defun lbl:prefix-for (group / hit)
  ;; A group with an entry uses its own prefix; every other group falls back to
  ;; the shared one in *dt:lbl:format*. The result still goes through
  ;; lbl:expand, so %G works inside an override too.
  (if (setq hit (lbl:prefix-entry group))
    (cdr hit)
    (nth 0 *dt:lbl:format*))
)

(defun lbl:pad-for (group / hit)
  ;; Digits for this group: its own if DT-SETPAD set one, otherwise the shared
  ;; width in *dt:lbl:format*. Matched the same case-insensitive way as prefixes.
  (if (setq hit (vl-some '(lambda (e)
                            (if (= (strcase (car e)) (strcase group)) e))
                         *dt:lbl:pad-overrides*))
    (cdr hit)
    (nth 3 *dt:lbl:format*))
)

;;; --- Renumbering -----------------------------------------------------------

(defun lbl:label (group num)
  ;; Everything a tag reads at position NUM: prefix, the number or letter, and
  ;; suffix. One definition, so DT-RENUMBER, DT-SWITCH and the DT-SETPAD preview
  ;; cannot drift into showing three different ideas of the same tag.
  (strcat (lbl:expand (lbl:prefix-for group) group)
          (lbl:seq group num)
          (lbl:expand (nth 1 *dt:lbl:format*) group))
)

(defun lbl:renumber-group (group recs / num obj att want done)
  (setq num  (nth 2 *dt:lbl:format*)
        done 0)

  ;; One guard, here rather than in the callers: every renumber in the file goes
  ;; through this function, and a group that some other path can still overwrite
  ;; is the failure that loses work nobody can get back except by retyping it.
  (if (not (lbl:skip-p group))
    (foreach r (lbl:sort recs)
      (setq obj (vlax-ename->vla-object (car r))
            att (lbl:find-att obj *dt:lbl:number-tag*))
      (if att
        (progn
          (setq want (lbl:label group num))
          ;; Skip writes that would change nothing, so the reported count is
          ;; what actually moved rather than the size of the drawing, and the
          ;; undo step stays small on a plan carrying a few hundred tags.
          (if (/= (vla-get-textstring att) want)
            (progn (vla-put-textstring att want)
                   (setq done (1+ done))))
          (setq num (1+ num))))))
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

(defun c:DT-RENUMBER ( / *error* doc recs n skipped)

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
  ;; Say what was left alone. A group that silently stops renumbering looks
  ;; exactly like a broken command to whoever did not set it.
  (if (setq skipped (vl-remove-if-not '(lambda (g) (lbl:skip-p (car g)))
                                      (lbl:group-by recs)))
    (princ (strcat "\n" (itoa (length skipped)) " group(s) set to skip: "
                   (apply 'strcat
                     (mapcar '(lambda (g) (strcat (car g) " ")) skipped)))))
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

(defun c:DT-TAG ( / *error* doc pt)
  ;; Puts a counter tag down, building COUNT_TAG first if the drawing has none.
  ;; Place them, then name the batch with SG.

  (defun *error* (msg)
    (dt:undo-end doc)
    (dt:report-error msg)
  )

  (if (lbl:ensure-block)
    (progn
      (setq doc (dt:undo-begin))
      ;; Loops so a run of tags is one command and one undo step. Enter ends it.
      (while (setq pt (getpoint (strcat "\nTag insertion point"
                                        " <Enter to finish>: ")))
        ;; "_non" forces the literal pick through, ignoring running OSNAPs.
        (command "_.-INSERT" *dt:lbl:block* "_non" pt 1.0 1.0 0.0)
        (dt:force-unit-scale (entlast)))
      (setq doc (dt:undo-end doc))
      (princ (strcat "\nName the batch with " "SG" "."))))
  (princ)
)

(defun c:DT-SETPREFIX ( / *error* doc groups grp val cur n)
  ;; Sets the prefix for one group, from the keyboard. Writes dt-labels.lsp, so
  ;; it survives the drawing and nobody has to open a .lsp file to change it.

  (defun *error* (msg)
    (dt:undo-end doc)
    (dt:report-error msg)
  )

  ;; Show what is set now. Picking from real group names beats guessing at one
  ;; and quietly recording a prefix that no block in the drawing will ever use.
  (setq groups (lbl:group-by (lbl:collect)))
  (if (null groups)
    (princ "\nNo counter blocks in this drawing yet.")
    (progn
      (princ "\n  Group                       Prefix")
      (princ "\n  --------------------------- ---------------")
      (foreach g groups
        (setq cur (lbl:prefix-entry (car g)))
        (princ (strcat "\n  " (car g) (lbl:pad-right (car g) 28)
                       (if cur (cdr cur) "(shared)"))))))

  (setq grp (strcase (vl-string-trim " \t"
              (getstring t (strcat "\n" *dt:lbl:group-tag*
                                   " to set a prefix for: ")))))
  (cond
    ((or (= grp "") (not (lbl:safe-text "group" grp)))
     (princ "\nNo usable group given; nothing changed."))
    (t
     (setq val (vl-string-trim " \t"
                 (getstring t (strcat "\nPrefix for " grp
                                      " <Enter to clear>: "))))
     (if (lbl:safe-text "prefix" val)
       (progn
         (lbl:put-prefix grp val)
         ;; Renumber before reporting: the sequences changed the moment the
         ;; prefix did, and this is the same bargain DT-SETGROUP makes.
         (setq doc (dt:undo-begin)
               n   (lbl:renumber-all)
               doc (dt:undo-end doc))
         (princ (strcat "\n" grp " -> "
                        (if (= val "") "the shared prefix" val)
                        ", " (itoa n) " number(s) updated."))
         ;; The renumber above already happened, so this is a persistence
         ;; warning, not a failure to act. Say which it is.
         (if (not (lbl:save-labels))
           (princ (strcat "\nNot written to dt-labels.lsp"
                          " -- this holds for this session only.")))))))
  (princ)
)

(defun c:DT-SETROW ( / *error* doc d n)
  ;; Sets how far apart in Y two tags can be and still count as one row.
  ;;
  ;; getdist takes either a typed number or two picked points, so the answer can
  ;; be shown rather than known: pick two tags that belong to the same row and
  ;; the drawing supplies the units.

  (defun *error* (msg)
    (dt:undo-end doc)
    (dt:report-error msg)
  )

  (princ (strcat "\nRow tolerance is "
                 (rtos *dt:lbl:row-tol* 2 3) " drawing units."))
  (princ "\nTags closer than this in Y count as one row and number left to right.")
  (if (setq d (getdist "\nNew tolerance, or pick two points <keep>: "))
    (progn
      ;; getdist hands back a signed value when a number is typed rather than
      ;; picked, and a negative tolerance would put every tag in its own row.
      (setq *dt:lbl:row-tol* (abs d)
            doc              (dt:undo-begin)
            n                (lbl:renumber-all)
            doc              (dt:undo-end doc))
      (princ (strcat "\nRow tolerance " (rtos *dt:lbl:row-tol* 2 3)
                     ", " (itoa n) " number(s) updated."))
      (if (not (lbl:save-labels))
        (princ (strcat "\nNot written to dt-labels.lsp"
                       " -- this holds for this session only."))))
    (princ "\nNothing changed."))
  (princ)
)

;;; --- DT-SWITCH -------------------------------------------------------------
;;; Switch legs are not a count. Three lights on one switch all read "a", and no
;;; 1..N run describes that. So these tags are stamped as they are placed, and
;;; they are a SEPARATE BLOCK -- a clone of COUNT_TAG under another name.
;;;
;;; The clone is the whole trick. lbl:collect only ever selects *dt:lbl:block*,
;;; so a tag of any other name is invisible to DT-RENUMBER, DT-COUNTS and every
;;; per-group setting, with no flag to check and nothing added to the renumber
;;; path. A duplicate block definition is cheaper than teaching the counting
;;; code about tags it is not allowed to count.

(defun sw:clone-block ( / src ent skip)
  ;; Copies the COUNT_TAG definition under *dt:sw:block*, so the switch tag
  ;; looks exactly like the counter tag the office already draws -- same circle,
  ;; same height, same attribute tags -- without anyone redrawing it.
  ;;
  ;; Sub-entities are re-made from their own DXF data with the identity groups
  ;; dropped: -1 and 5 are this entity's ename and handle, and 330 is the block
  ;; it currently belongs to. Carry those over and entmake refuses the lot.
  (cond
    ((null (setq src (tblsearch "BLOCK" *dt:lbl:block*)))
     (princ (strcat "\nNo \"" *dt:lbl:block* "\" to clone -- place one counter"
                    " tag with TG first."))
     nil)
    (t
     (setq skip '(-1 5 102 330 331 360))
     (entmake (list '(0 . "BLOCK")
                    (cons 2 *dt:sw:block*)
                    (assoc 10 src)
                    (cons 70 (cdr (assoc 70 src)))))
     (setq ent (cdr (assoc -2 src)))
     (while ent
       (entmake (vl-remove-if '(lambda (p) (member (car p) skip))
                              (entget ent)))
       (setq ent (entnext ent)))
     (entmake '((0 . "ENDBLK")))
     (cond
       ((tblsearch "BLOCK" *dt:sw:block*)
        (princ (strcat "\nCloned \"" *dt:lbl:block* "\" as \""
                       *dt:sw:block* "\"."))
        t)
       (t (princ (strcat "\nCould not create \"" *dt:sw:block* "\".")) nil))))
)

(defun sw:ensure-block ()
  (cond ((tblsearch "BLOCK" *dt:sw:block*) t)
        (t (sw:clone-block)))
)

(defun sw:tags (group / sel i ent obj g recs)
  ;; (ename . label) for every switch tag in this group. Its own selection,
  ;; because lbl:collect deliberately cannot see this block.
  ;;
  ;; G is tested before strcase rather than after: a SWITCH_TAG that somebody
  ;; drew by hand without a GROUP attribute reads nil here, and strcase of nil
  ;; is an error, not a miss.
  (setq i 0 recs nil)
  (if (setq sel (ssget "_X" (list '(-4 . "<AND")
                                  '(0 . "INSERT")
                                  '(66 . 1)
                                  (cons 2 (strcat "`*U*," *dt:sw:block*))
                                  '(-4 . "AND>")
                                  (dt:space-filter))))
    (while (< i (sslength sel))
      (setq ent (ssname sel i)
            obj (vlax-ename->vla-object ent)
            g   (lbl:att-value obj *dt:lbl:group-tag*))
      (if (and g
               (= (strcase (vla-get-EffectiveName obj))
                  (strcase *dt:sw:block*))
               ;; A nil GROUP asks for every switch tag in the space, which is
               ;; what sw:model needs when this group has none yet.
               (or (null group) (= (strcase g) (strcase group))))
        (setq recs (cons (cons ent (lbl:att-value obj *dt:lbl:number-tag*))
                         recs)))
      (setq i (1+ i))))
  recs
)

(defun sw:labels (group)
  (mapcar 'cdr (sw:tags group))
)

(setq *dt:sw:current* nil)   ; last group tagged, this session

(defun sw:model (group / tags)
  ;; The tag to copy, as an ename: the most recent one in this group, or failing
  ;; that the most recent switch tag anywhere in the space. Most recent by
  ;; handle, so it is the one carrying whatever the drafter last decided.
  ;; cond, not or: AutoLISP's or answers T/nil rather than handing back the
  ;; value that was non-nil, so (or a b) here would sort the symbol T.
  (if (setq tags (cond ((sw:tags group)) ((sw:tags nil))))
    (car (last (vl-sort tags 'lbl:handle<))))
)

(defun sw:place (group num pt / src obj att)
  ;; One tag, stamped and done. Shared by DT-SWITCH and DT-SWNEXT so the two
  ;; cannot drift into placing slightly different things.
  ;;
  ;; Copied from the tag already on the sheet rather than inserted fresh. An
  ;; INSERT takes the block definition and the current layer and nothing else,
  ;; so in a drawing where the tags were scaled, rotated, put on their own layer
  ;; or given a colour, every new one arrived wrong and had to be fixed by hand.
  ;; A copy inherits all of it -- scale, rotation, layer, colour, linetype --
  ;; because it IS the same tag, moved and restamped. Which is what the drafter
  ;; was doing with COPY anyway.
  ;;
  ;; Only the first tag in a drawing goes in through INSERT, and that one is
  ;; the one worth adjusting by hand: everything after it follows.
  ;;
  ;; Driven through the COPY command rather than vla-copy and vla-move, so that
  ;; everything crossing the boundary is an ename or a plain point list. The
  ;; ActiveX pair wants its points as variants and threw a type error here.
  ;; "_non" on both points keeps running osnaps out of a displacement that is
  ;; already exact. entlast is the new INSERT: attributes and the SEQEND are
  ;; subentities, which entlast steps over.
  (if (setq src (sw:model group))
    (command "_.COPY" src "" "_non" (cdr (assoc 10 (entget src))) "_non" pt)
    (progn
      (command "_.-INSERT" *dt:sw:block* "_non" pt 1.0 1.0 0.0)
      (dt:force-unit-scale (entlast))))
  (setq obj (vlax-ename->vla-object (entlast)))
  (if (setq att (lbl:find-att obj *dt:lbl:group-tag*))
    (vla-put-textstring att group))
  (if (setq att (lbl:find-att obj *dt:lbl:number-tag*))
    (vla-put-textstring att (lbl:label group num)))
  (setq *dt:sw:current* group)
)

(defun sw:next (group)
  ;; The label after the last one used. Read from the drawing rather than
  ;; remembered, so it is still right after a COPY, an undo, a closed drawing,
  ;; or a tag deleted in between.
  (if (sw:tags group)
    (1+ (sw:resume group))
    (nth 2 *dt:lbl:format*))
)

(defun sw:ask-group ( / g)
  (setq g (strcase (vl-string-trim " \t"
            (getstring t (strcat "\n" *dt:lbl:group-tag*
                                 (if *dt:sw:current*
                                   (strcat " <" *dt:sw:current* ">") "")
                                 ": ")))))
  (if (and (= g "") *dt:sw:current*) *dt:sw:current* g)
)

(defun sw:restamp (group / tags order map num done att obj want)
  ;; Rewrites this group's labels with the CURRENT prefix, padding and letters,
  ;; keeping every leg intact. Nothing extra is stored on the tags to make this
  ;; work: the distinct labels, taken in the order they were first placed, ARE
  ;; the legs, so mapping them onto positions 1, 2, 3 ... reproduces what the
  ;; drafter stamped and re-formats it.
  ;;
  ;; Placement order comes from the handle, the same reason 'database numbering
  ;; uses it -- a selection set's own order cannot be relied on.
  ;;
  ;; Skipped labels close up: a run that jumped A to C comes back A, B. For a
  ;; switch leg that is a fix. It is also the only thing here that changes more
  ;; than formatting, which is why the command says how many legs it found.
  (setq tags  (vl-sort (sw:tags group) 'lbl:handle<)
        order nil)
  (foreach r tags
    (if (not (member (cdr r) order))
      (setq order (append order (list (cdr r))))))

  (setq num (nth 2 *dt:lbl:format*) map nil)
  (foreach lbl order
    (setq map (cons (cons lbl (lbl:label group num)) map)
          num (1+ num)))

  (setq done 0)
  (foreach r tags
    (setq obj  (vlax-ename->vla-object (car r))
          att  (lbl:find-att obj *dt:lbl:number-tag*)
          want (cdr (assoc (cdr r) map)))
    (if (and att (/= (vla-get-textstring att) want))
      (progn (vla-put-textstring att want)
             (setq done (1+ done)))))
  (list done (length order))
)

(defun sw:resume (group / vals i hit)
  ;; Where a second run picks up: the highest position already stamped on this
  ;; group. Resuming ON that label rather than past it is deliberate -- a leg
  ;; usually carries on into the next room, and Next is one keystroke away when
  ;; it does not.
  ;;
  ;; Bounded by the number of tags, which is safe because the command refuses
  ;; to advance onto a label it has not placed anything on: there are never
  ;; more positions in use than there are tags.
  (setq vals (sw:labels group)
        i    (nth 2 *dt:lbl:format*)
        hit  i)
  (repeat (length vals)
    (if (member (lbl:label group i) vals) (setq hit i))
    (setq i (1+ i)))
  hit
)

(defun c:DT-SWITCH ( / *error* doc grp num pt att obj placed stamped n)
  ;; Click to place a tag reading the current label. Click again and it reads
  ;; the same -- repeating is the default, because that is what a switch leg is.
  ;; Next moves to the next label, Back steps down if you overshoot.

  (defun *error* (msg)
    (dt:undo-end doc)
    (dt:report-error msg)
  )

  (if (sw:ensure-block)
    (progn
      (setq grp (strcase (vl-string-trim " \t"
                  (getstring t (strcat "\n" *dt:lbl:group-tag*
                                       (if *dt:sw:current*
                                         (strcat " <" *dt:sw:current* ">") "")
                                       " for these tags, or R to restamp: ")))))
      (if (and (= grp "") *dt:sw:current*) (setq grp *dt:sw:current*))
      (cond
        ((= grp "") (princ "\nNo group given; nothing placed."))
        ;; getstring cannot carry an initget keyword, so R is matched by hand.
        ;; The cost is that a group cannot be called R, which is a name nobody
        ;; gives a switch anyway, and the gain is no second command to remember.
        ((member grp '("R" "RESTAMP"))
         (setq grp (strcase (vl-string-trim " \t"
                     (getstring t (strcat "\n" *dt:lbl:group-tag*
                                          " to restamp: ")))))
         (cond
           ((= grp "") (princ "\nNo group given; nothing changed."))
           ((null (sw:tags grp))
            (princ (strcat "\nNo " *dt:sw:block* " tags in " grp ".")))
           (t
            (setq doc (dt:undo-begin)
                  n   (sw:restamp grp)
                  doc (dt:undo-end doc))
            (princ (strcat "\n" (itoa (car n)) " tag(s) restamped in " grp
                           ", " (itoa (cadr n)) " leg(s): "
                           (lbl:label grp (nth 2 *dt:lbl:format*))
                           " through "
                           (lbl:label grp (+ (nth 2 *dt:lbl:format*)
                                             (1- (cadr n)))) ".")))))
        (t
         ;; Resuming lands ON the last label used, which already has tags under
         ;; it, so Next is allowed straight away. In a group with nothing in it
         ;; yet there is nothing to move on from.
         (setq num     (sw:resume grp)
               stamped (if (sw:tags grp) t nil)
               placed  0
               doc     (dt:undo-begin))

         ;; getpoint hands back a string for a keyword and nil for Enter, so one
         ;; loop reads the clicks and the keys together. Enter ends the command.
         (while
           (progn
             (initget "Next Back")
             (setq pt (getpoint (strcat "\nTag point [Next/Back] <"
                                        (lbl:label grp num) ">: ")))
             pt)
           (cond
             ;; Next only moves once this label is actually on the drawing.
             ;; Pressing it twice by accident used to leave a label with no tags
             ;; on it, which is a gap in the run and a resume that lands low.
             ((= pt "Next")
              (if stamped
                (setq num (1+ num) stamped nil)
                (princ (strcat "\nNothing placed on " (lbl:label grp num)
                               " yet."))))
             ((= pt "Back")
              (setq num     (max (nth 2 *dt:lbl:format*) (1- num))
                    stamped t))
             (t
              (sw:place grp num pt)
              (setq placed  (1+ placed)
                    stamped t))))

         (setq doc (dt:undo-end doc))
         (princ (strcat "\n" (itoa placed) " tag(s) placed in " grp
                        ", last one reads " (lbl:label grp num) "."))))))
  (princ)
)

(defun c:DT-SWNEXT ( / *error* doc grp num pt go)
  ;; One tag at the next label, then out of the way. For the drafter who places
  ;; one, COPYs it along the leg, nudges the text, and only then wants the next
  ;; letter -- a loop that owns the session is the wrong shape for that.
  ;;
  ;; No group prompt once you have tagged something this session: type SWN,
  ;; click, done. Group changes it.

  (defun *error* (msg)
    (dt:undo-end doc)
    (dt:report-error msg)
  )

  (if (sw:ensure-block)
    (progn
      (if (null *dt:sw:current*) (setq *dt:sw:current* (sw:ask-group)))
      (setq grp *dt:sw:current*
            go  t)
      (if (= grp "")
        (princ "\nNo group given; nothing placed.")
        (while go
          ;; Recomputed each time round, so changing the group re-reads where
          ;; that group had got to rather than carrying the old position over.
          (setq num (sw:next grp))
          (initget "Group")
          (setq pt (getpoint (strcat "\nPoint for " (lbl:label grp num)
                                     " or [Group]: ")))
          (cond
            ((= pt "Group")
             (setq grp (sw:ask-group))
             (if (= grp "") (setq go nil) (setq *dt:sw:current* grp)))
            ((null pt) (princ "\nNothing placed.") (setq go nil))
            (t
             (setq doc (dt:undo-begin))
             (sw:place grp num pt)
             (setq doc (dt:undo-end doc)
                   go  nil)
             (princ (strcat "\n" (lbl:label grp num) " placed in " grp
                            ". COPY it for the rest of the leg."))))))))
  (princ)
)

(defun c:DT-SETPAD ( / *error* doc groups grp w n)
  ;; How many digits one group's number is padded to: 1 -> 1, 2 -> 01, 3 -> 001.
  ;; Per group, because a drawing with 8 panels and 240 fixtures wants different
  ;; widths for each and one shared setting cannot give both.

  (defun *error* (msg)
    (dt:undo-end doc)
    (dt:report-error msg)
  )

  (setq groups (lbl:group-by (lbl:collect)))
  (if (null groups)
    (princ "\nNo counter blocks in this drawing yet.")
    (progn
      (princ "\n  Group                       Digits   Example")
      (princ "\n  --------------------------- -------- -------")
      (foreach g groups
        (princ (strcat "\n  " (car g) (lbl:pad-right (car g) 28)
                       (itoa (lbl:pad-for (car g)))
                       (lbl:pad-right (itoa (lbl:pad-for (car g))) 9)
                       ;; What this group's first tag actually reads, prefix
                       ;; and all -- the answer to "01 or 1?" is easier to see
                       ;; than to work out from a number in a column.
                       (lbl:label (car g) (nth 2 *dt:lbl:format*)))))))

  (setq grp (strcase (vl-string-trim " \t"
              (getstring t (strcat "\n" *dt:lbl:group-tag*
                                   " to change: ")))))
  (cond
    ((or (= grp "") (not (lbl:safe-text "group" grp)))
     (princ "\nNo usable group given; nothing changed."))
    (t
     (initget 4)                        ; no negative width
     (setq w (getint (strcat "\nDigits for " grp
                             " (1 = 1, 2 = 01, 3 = 001) <keep>: ")))
     (cond
       ((null w) (princ "\nNothing changed."))
       ;; lbl:padzeros recurses once per digit, so a fat-fingered 5000 is a
       ;; stack overflow rather than a silly-looking tag. Refuse it here.
       ((> w 10)
        (princ "\nTen digits is the most this pads to."))
       (t
        (lbl:put-pad grp w)
        (setq doc (dt:undo-begin)
              n   (lbl:renumber-all)
              doc (dt:undo-end doc))
        (princ (strcat "\n" grp " -> "
                       (lbl:expand (lbl:prefix-for grp) grp)
                       (lbl:seq grp (nth 2 *dt:lbl:format*))
                       ", " (itoa n) " number(s) updated."))
        ;; Letters ignore the width entirely, so say so rather than leave the
        ;; drafter wondering why the tags did not change.
        (if (lbl:letters-p grp)
          (princ (strcat "\n" grp " counts in letters, where padding"
                         " does not apply. LTR switches it back.")))
        (if (not (lbl:save-labels))
          (princ (strcat "\nNot written to dt-labels.lsp"
                         " -- this holds for this session only.")))))))
  (princ)
)

(defun c:DT-SETSKIP ( / *error* doc groups grp kw n)
  ;; Turns RNB off for one group and leaves every other group renumbering as
  ;; before. For a group whose numbers were decided by hand and have to stay
  ;; exactly as typed -- out of order, repeated, with gaps, whatever they are.

  (defun *error* (msg)
    (dt:undo-end doc)
    (dt:report-error msg)
  )

  (setq groups (lbl:group-by (lbl:collect)))
  (if (null groups)
    (princ "\nNo counter blocks in this drawing yet.")
    (progn
      (princ "\n  Group                       RNB")
      (princ "\n  --------------------------- -------")
      (foreach g groups
        (princ (strcat "\n  " (car g) (lbl:pad-right (car g) 28)
                       (if (lbl:skip-p (car g)) "skipped" "renumbers"))))))

  (setq grp (strcase (vl-string-trim " \t"
              (getstring t (strcat "\n" *dt:lbl:group-tag*
                                   " to change: ")))))
  (cond
    ((or (= grp "") (not (lbl:safe-text "group" grp)))
     (princ "\nNo usable group given; nothing changed."))
    (t
     (initget "Renumber Skip")
     (setq kw (getkword (strcat "\nRNB should [Renumber/Skip] " grp
                                " <keep>: ")))
     (cond
       ((null kw) (princ "\nNothing changed."))
       (t
        (lbl:put-skip grp (= kw "Skip"))
        ;; Renumbering now is the point of saying Renumber, and saying Skip is
        ;; worth a run too: every OTHER group closes the gaps this one leaves.
        (setq doc (dt:undo-begin)
              n   (lbl:renumber-all)
              doc (dt:undo-end doc))
        (princ (strcat "\nRNB " (if (= kw "Skip") "skips " "renumbers ") grp
                       ", " (itoa n) " number(s) updated."))
        (if (not (lbl:save-labels))
          (princ (strcat "\nNot written to dt-labels.lsp"
                         " -- this holds for this session only.")))))))
  (princ)
)

(defun c:DT-SETLETTERS ( / *error* doc groups grp kw n)
  ;; Switches one group between 1, 2, 3 and A, B, C. Per group, because a plan
  ;; usually wants both at once: transformers lettered, fixtures numbered.
  ;; Writes dt-labels.lsp, the same as DT-SETPREFIX.

  (defun *error* (msg)
    (dt:undo-end doc)
    (dt:report-error msg)
  )

  ;; Same table DT-SETPREFIX opens with, and for the same reason: pick from the
  ;; groups the drawing really has rather than guessing at a name.
  (setq groups (lbl:group-by (lbl:collect)))
  (if (null groups)
    (princ "\nNo counter blocks in this drawing yet.")
    (progn
      (princ "\n  Group                       Counts in")
      (princ "\n  --------------------------- ---------")
      (foreach g groups
        (princ (strcat "\n  " (car g) (lbl:pad-right (car g) 28)
                       (if (lbl:letters-p (car g)) "letters" "numbers"))))))

  (setq grp (strcase (vl-string-trim " \t"
              (getstring t (strcat "\n" *dt:lbl:group-tag*
                                   " to change: ")))))
  (cond
    ((or (= grp "") (not (lbl:safe-text "group" grp)))
     (princ "\nNo usable group given; nothing changed."))
    (t
     (initget "Numbers Letters")
     (setq kw (getkword (strcat "\n" grp " counts in [Numbers/Letters]"
                                " <keep>: ")))
     (cond
       ((null kw) (princ "\nNothing changed."))
       (t
        (lbl:put-letters grp (= kw "Letters"))
        ;; Renumber before reporting: the sequences changed the moment this did,
        ;; the same bargain DT-SETPREFIX and DT-SETROW make.
        (setq doc (dt:undo-begin)
              n   (lbl:renumber-all)
              doc (dt:undo-end doc))
        (princ (strcat "\n" grp " counts in " (strcase kw t)
                       ", " (itoa n) " number(s) updated."))
        (if (not (lbl:save-labels))
          (princ (strcat "\nNot written to dt-labels.lsp"
                         " -- this holds for this session only.")))))))
  (princ)
)

(defun c:DT-SETORDER ( / *error* doc kw n)
  ;; Switches between numbering by where the tags sit and numbering by the order
  ;; they were inserted. Both are right, on different days: plan order is what a
  ;; reader expects, insert order is what you want when you walked the drawing
  ;; in the sequence that matters and the geometry does not show it.

  (defun *error* (msg)
    (dt:undo-end doc)
    (dt:report-error msg)
  )

  (princ (strcat "\nNumbering order is "
                 (strcase (vl-princ-to-string *dt:lbl:order*) t) "."))
  (initget "Reading Columns Database")
  (setq kw (getkword "\nOrder [Reading/Columns/Database] <keep>: "))
  (cond
    ((null kw) (princ "\nNothing changed."))
    (t
     (setq *dt:lbl:order* (cond ((= kw "Reading")  'reading)
                                ((= kw "Columns")  'columns)
                                (t                 'database))
           doc            (dt:undo-begin)
           n              (lbl:renumber-all)
           doc            (dt:undo-end doc))
     (princ (strcat "\nNumbering order " (strcase kw t)
                    ", " (itoa n) " number(s) updated."))
     (if (not (lbl:save-labels))
       (princ (strcat "\nNot written to dt-labels.lsp"
                      " -- this holds for this session only.")))))
  (princ)
)

(defun c:RNB () (c:DT-RENUMBER))
(defun c:SG  () (c:DT-SETGROUP))
(defun c:TG  () (c:DT-TAG))
(defun c:PFX () (c:DT-SETPREFIX))
(defun c:SR  () (c:DT-SETROW))
(defun c:SO  () (c:DT-SETORDER))
(defun c:LTR () (c:DT-SETLETTERS))
(defun c:PAD () (c:DT-SETPAD))
(defun c:SWL () (c:DT-SWITCH))
(defun c:SKP () (c:DT-SETSKIP))
(defun c:SWN () (c:DT-SWNEXT))

(princ)
