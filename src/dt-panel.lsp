;;; ===========================================================================
;;; DT-PANEL.LSP  --  Panel blocks: list them, export them, fill them from CSV.
;;;
;;; Commands:  DT-PANELS    (PNL)  list the panels; write a CSV template
;;;            DT-SETPANEL  (SPN)  fill panel attributes from that CSV
;;;
;;; ---------------------------------------------------------------------------
;;; WHY A ROUND TRIP AND NOT A HAND-WRITTEN FILE
;;;
;;; A one-line diagram carries seventy-odd panels. Nobody types that list
;;; twice. DT-PANELS writes out the names the drawing already has, with
;;; whatever values sit on them now; the kVA column gets filled in Excel once
;;; the loads are real; DT-SETPANEL puts them back.
;;;
;;; The drawing is always the source of the names. The spreadsheet is always
;;; the source of the numbers. Neither one has to be retyped from the other,
;;; which is the whole point -- during design the numbers change every week and
;;; the names barely change at all.
;;;
;;; ---------------------------------------------------------------------------
;;; WHAT COUNTS AS A PANEL
;;;
;;; Any attributed block carrying the name attribute -- *dt:pn:name-tag*,
;;; PANEL by default. Not a block name: a one-line uses a different symbol for
;;; a switchboard, a panelboard and a meter module, and all three want filling
;;; from the same sheet. Blocks without the attribute are ignored in silence,
;;; so windowing round part of the diagram and catching title text is harmless.
;;;
;;; This is the same rule dt-load-takeoff.lsp uses for devices, and for the
;;; same reason.
;;;
;;; ---------------------------------------------------------------------------
;;; THE CSV
;;;
;;;   PANEL,KVA,VOLTAJE,MAIN
;;;   LC.PS.001,412,480/277,800
;;;   LC.MM.001,98,480/277,200
;;;
;;; Row 1 names the attributes. Column 1 is the key, matched
;;; case-insensitively; every other column is written to the attribute its own
;;; header names. Add a column, get a column filled -- there is nothing to
;;; change here when the schedule grows a kAIC or a NIVEL field.
;;;
;;; An EMPTY CELL LEAVES THE ATTRIBUTE ALONE. A half-filled spreadsheet can
;;; never blank out what is already on the drawing, which is what makes it safe
;;; to import the same file repeatedly as the design firms up.
;;;
;;; Zero-pad the numbering -- LC.PN01, not LC.PN1. Panels list alphabetically,
;;; and that only matches riser order if the digits line up.
;;;
;;; Config: *dt:pn:name-tag*, *dt:pn:kva-tag*, *dt:pn:file*
;;; ===========================================================================

;;; --- Text ------------------------------------------------------------------

(defun pn:trim (s) (vl-string-trim " \t\r\n" s))

(defun pn:pad (s n / out)
  (setq out "")
  (repeat (max 1 (- n (strlen s))) (setq out (strcat out " ")))
  out
)

(defun pn:lpad (s n / out)
  (setq out "")
  (repeat (max 1 (- n (strlen s))) (setq out (strcat out " ")))
  (strcat out s)
)

(defun pn:numeric-p (s / i c ok dots)
  ;; Only for the kVA total in the report. A value this rejects is still
  ;; written to the drawing untouched -- the drafter may want "ver nota".
  (setq i 1 ok (> (strlen s) 0) dots 0)
  (while (and ok (<= i (strlen s)))
    (setq c (substr s i 1))
    (cond
      ((and (= i 1) (member c '("-" "+"))) (setq ok (> (strlen s) 1)))
      ((and (>= (ascii c) 48) (<= (ascii c) 57)))
      ((= c ".") (setq dots (1+ dots) ok (< dots 2)))
      (t (setq ok nil)))
    (setq i (1+ i)))
  ok
)

;;; --- CSV -------------------------------------------------------------------
;;; dt-load-takeoff.lsp carries its own copy of these two as ld:split-csv and
;;; ld:csv-cell. Both modules want them and core does not have them yet; see
;;; the loose ends in STATUS.md.

(defun pn:escape-quotes (s / out i c)
  (setq out "" i 1)
  (while (<= i (strlen s))
    (setq c   (substr s i 1)
          out (strcat out (if (= c "\"") "\"\"" c))
          i   (1+ i)))
  out
)

(defun pn:csv-cell (s)
  ;; Quote unconditionally. Panel names hold periods today and could hold a
  ;; comma tomorrow; deciding per cell is more code than always quoting.
  (strcat "\"" (pn:escape-quotes s) "\"")
)

(defun pn:join-csv (cells / out first)
  (setq out "" first t)
  (foreach c cells
    (setq out   (strcat out (if first "" ",") (pn:csv-cell c))
          first nil))
  out
)

(defun pn:split-csv (line / out cur i c n inq)
  ;; Comma separated, optional double quotes, "" for a literal quote inside a
  ;; quoted field. Enough to read back what Excel writes.
  (setq out nil cur "" i 1 n (strlen line) inq nil)
  (while (<= i n)
    (setq c (substr line i 1))
    (cond
      (inq
       (cond
         ((/= c "\"") (setq cur (strcat cur c)))
         ((= (substr line (1+ i) 1) "\"")
          (setq cur (strcat cur "\"") i (1+ i)))
         (t (setq inq nil))))
      ((= c "\"") (setq inq t))
      ((= c ",")  (setq out (cons cur out) cur ""))
      (t (setq cur (strcat cur c))))
    (setq i (1+ i)))
  (reverse (cons cur out))
)

;;; --- Attributes ------------------------------------------------------------

(defun pn:att-obj (obj tag)
  (if (vlax-method-applicable-p obj 'getattributes)
    (vl-some '(lambda (x)
                (if (= (strcase (vla-get-tagstring x)) (strcase tag)) x))
             (vlax-invoke obj 'getattributes)))
)

(defun pn:att (obj tag / a)
  (if (setq a (pn:att-obj obj tag)) (pn:trim (vla-get-textstring a)))
)

(defun pn:att-tags (obj)
  ;; Every tag this insert carries, in block order.
  (if (vlax-method-applicable-p obj 'getattributes)
    (mapcar '(lambda (x) (strcase (vla-get-tagstring x)))
            (vlax-invoke obj 'getattributes)))
)

;;; --- Finding panels --------------------------------------------------------

(defun pn:all ( / ss i obj nm out)
  ;; (name index vla-object) for every panel in the space the drafter is
  ;; looking at, sorted by name.
  ;;
  ;; The index rides along only so that no two entries ever compare equal:
  ;; vl-sort drops one of any pair it considers a tie, and a panel drawn twice
  ;; -- once on the riser, once on a floor plan -- has to keep both instances,
  ;; because both of them need the kVA written to them.
  (setq out nil i 0)
  (if (setq ss (ssget "_X" (list '(0 . "INSERT")
                                 '(66 . 1)
                                 (dt:space-filter))))
    (while (< i (sslength ss))
      (setq obj (vlax-ename->vla-object (ssname ss i)))
      (if (setq nm (pn:att obj *dt:pn:name-tag*))
        (setq out (cons (list nm i obj) out)))
      (setq i (1+ i))))
  (vl-sort out
    '(lambda (a b)
       (if (= (strcase (car a)) (strcase (car b)))
         (< (cadr a) (cadr b))
         (< (strcase (car a)) (strcase (car b))))))
)

(defun pn:tag-union (panels / out)
  ;; Name tag first, then every other tag any panel carries, first seen first.
  ;; One header row has to cover blocks that do not all agree on their
  ;; attributes -- a meter module and a switchboard rarely do.
  (setq out (list (strcase *dt:pn:name-tag*)))
  (foreach p panels
    (foreach tg (pn:att-tags (caddr p))
      (if (not (member tg out)) (setq out (append out (list tg))))))
  out
)

;;; --- Files -----------------------------------------------------------------

(defun pn:csv-path ( / dir name)
  (cond
    (*dt:pn:file*)
    (t
     (setq dir  (getvar "DWGPREFIX")
           name (vl-filename-base (getvar "DWGNAME")))
     (if (or (null dir) (= dir "")) (setq dir *dt:root*))
     (strcat dir name "-panels.csv")))
)

(defun pn:write-csv (path panels tags / f)
  (if (setq f (open path "w"))
    (progn
      (write-line (pn:join-csv tags) f)
      (foreach p panels
        (write-line
          (pn:join-csv
            (cons (car p)
                  (mapcar '(lambda (tg) (cond ((pn:att (caddr p) tg)) (t "")))
                          (cdr tags))))
          f))
      (close f)
      t))
)

(defun pn:zip (tags vals / out)
  ;; Pair a header with a data row, stopping when either runs out: a short row
  ;; is normal, Excel drops trailing empty cells. Empty values are dropped
  ;; here, which is the single place "an empty cell leaves the attribute
  ;; alone" is implemented.
  (setq out nil)
  (while (and tags vals)
    (if (/= (pn:trim (car vals)) "")
      (setq out (cons (cons (car tags) (pn:trim (car vals))) out)))
    (setq tags (cdr tags) vals (cdr vals)))
  (reverse out)
)

(defun pn:read-csv (path / f line fields tags rows first)
  ;; Returns (tags . rows), rows being (NAME (tag . value) ...).
  ;; Row 1 is the header: without it nothing says which column is which.
  (setq rows nil tags nil first t)
  (if (setq f (open path "r"))
    (progn
      (while (setq line (read-line f))
        (setq fields (mapcar 'pn:trim (pn:split-csv line)))
        (cond
          (first (setq tags (mapcar 'strcase fields) first nil))
          ((or (null (car fields)) (= (car fields) "")))   ; blank row
          (t (setq rows (cons (cons (car fields)
                                    (pn:zip (cdr tags) (cdr fields)))
                              rows)))))
      (close f)))
  (cons tags (reverse rows))
)

;;; --- DT-PANELS -------------------------------------------------------------
;;; Read-only on the drawing. It reports, and it writes the template beside the
;;; DWG. Nothing here needs an undo mark.

(defun c:DT-PANELS ( / *error* panels tags path total n kva)

  (defun *error* (msg) (dt:report-error msg))

  (setq panels (pn:all))
  (cond
    ((null panels)
     (princ (strcat "\nNo panels here -- no block carries a "
                    *dt:pn:name-tag* " attribute.")))
    (t
     (setq tags  (pn:tag-union panels)
           total 0.0
           n     0)
     (princ (strcat "\n " (itoa (length panels)) " panel(s):\n"))
     (foreach p panels
       (setq kva (pn:att (caddr p) *dt:pn:kva-tag*))
       (if (null kva) (setq kva ""))
       (princ (strcat "\n   " (car p) (pn:pad (car p) 22)
                      (pn:lpad (if (= kva "") "--" kva) 10)))
       (if (pn:numeric-p kva)
         (setq total (+ total (atof kva)) n (1+ n))))
     (princ (strcat "\n   " (pn:pad "" 22) "  --------"))
     (princ (strcat "\n   " (pn:pad "" 22) (pn:lpad (rtos total 2 1) 10)
                    "  " *dt:pn:kva-tag* " on " (itoa n) " of "
                    (itoa (length panels))))
     (setq path (pn:csv-path))
     (if (pn:write-csv path panels tags)
       (princ (strcat "\n\nTemplate written to " path))
       (princ (strcat "\n\nCould not write " path)))))
  (princ)
)

;;; --- DT-SETPANEL -----------------------------------------------------------
;;; The whole write list is built before any of it is applied, so a fault
;;; halfway through cannot leave the diagram half-updated -- the same reason
;;; ld:apply-map plans first.

(defun c:DT-SETPANEL ( / *error* doc path parsed tags rows panels up
                         plan seen missing unmatched noattr p nm hit kv att)

  (defun *error* (msg)
    (dt:undo-end doc)
    (dt:report-error msg)
  )

  (setq path (getfiled "Panel schedule (CSV)" "" "csv" 8))
  (cond
    ((null path) (princ "\nCancelled."))
    (t
     (setq parsed (pn:read-csv path)
           tags   (car parsed)
           rows   (cdr parsed))
     (cond
       ((or (null tags) (< (length tags) 2))
        (princ (strcat "\nThe first row has to name the columns, e.g.  "
                       *dt:pn:name-tag* "," *dt:pn:kva-tag*)))
       ((null rows)
        (princ "\nNo data rows in the file."))
       ((null (setq panels (pn:all)))
        (princ (strcat "\nNo panels here -- no block carries a "
                       *dt:pn:name-tag* " attribute.")))
       (t
        (setq up (mapcar '(lambda (r) (cons (strcase (car r)) (cdr r))) rows)
              plan nil seen nil missing nil noattr 0)

        (foreach p panels
          (setq nm (strcase (car p)))
          (if (setq hit (assoc nm up))
            (progn
              (if (not (member nm seen)) (setq seen (cons nm seen)))
              (foreach kv (cdr hit)
                (if (setq att (pn:att-obj (caddr p) (car kv)))
                  (setq plan (cons (cons att (cdr kv)) plan))
                  (setq noattr (1+ noattr)))))
            (if (not (member nm missing)) (setq missing (cons nm missing)))))

        (setq unmatched
          (vl-remove-if '(lambda (r) (member (strcase (car r)) seen)) rows))

        (if (null plan)
          (princ (strcat "\nNothing written -- no name in the file matches a "
                         "panel in this drawing."))
          (progn
            (setq doc (dt:undo-begin))
            (foreach kv plan (vla-put-textstring (car kv) (cdr kv)))
            (setq doc (dt:undo-end doc))
            (princ (strcat "\n" (itoa (length plan))
                           " attribute(s) written on " (itoa (length seen))
                           " panel(s)."))))

        ;; The three ways the file and the drawing can disagree. All are
        ;; reported: during design every one of them is a real omission
        ;; somebody has to chase, not noise to hide.
        (if (> noattr 0)
          (princ (strcat "\n" (itoa noattr) " value(s) had no matching "
                         "attribute on the block and were skipped.")))
        (if missing
          (progn
            (princ (strcat "\n\n" (itoa (length missing))
                           " panel(s) in the drawing have no row in the file:"))
            (foreach nm (reverse missing) (princ (strcat "\n    " nm)))))
        (if unmatched
          (progn
            (princ (strcat "\n\n" (itoa (length unmatched))
                           " row(s) in the file match no panel:"))
            (foreach p unmatched (princ (strcat "\n    " (car p))))))))))
  (princ)
)

(defun c:PNL () (c:DT-PANELS))
(defun c:SPN () (c:DT-SETPANEL))

(princ)
