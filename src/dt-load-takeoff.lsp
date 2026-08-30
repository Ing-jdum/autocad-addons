;;; ===========================================================================
;;; DT-LOAD-TAKEOFF.LSP  --  Circuits and connected load.
;;;
;;; Commands:  DT-SETCIRCUIT   tag a selection with a circuit label  (SC)
;;;            DT-RENCIRCUIT   rename a circuit everywhere
;;;            DT-LOAD         load table + CSV, grouped by circuit  (LD)
;;;
;;; ---------------------------------------------------------------------------
;;; WHY IT COUNTS THIS WAY
;;;
;;; Not by block. The same symbol is used for different things -- a general
;;; purpose outlet and a refrigerator can both be TOMACORRIENTE 120V -- so
;;; counting the block would merge loads that have nothing to do with each
;;; other. Rows key on (circuit, description, voltage, power) read from each
;;; device's own attributes, so one block splits into as many rows as it has
;;; uses.
;;;
;;; A block counts as a device if it carries the power attribute at all.
;;; Anything else in the selection is ignored rather than reported: a window
;;; around a circuit will catch text, tags and furniture, and complaining about
;;; those would be noise. A device whose power is blank IS reported, because
;;; that is a real omission and treating it as zero would understate the load.
;;;
;;; ---------------------------------------------------------------------------
;;; THE WORKFLOW THIS IS SHAPED AROUND
;;;
;;; Circuit numbers are decided AFTER the loads are known, by balancing them.
;;; So the label is provisional and stays editable:
;;;
;;;   1. DT-SETCIRCUIT     group devices under any label -- "cocina", "A", "1"
;;;   2. DT-LOAD           export every circuit to one CSV
;;;   3. balance in Excel  decide that "cocina" is really circuit 3
;;;   4. DT-RENCIRCUIT     apply that decision back to the drawing
;;;
;;; Nothing here requires a number to exist before the load is known, which is
;;; what would put the workflow backwards.
;;;
;;; Config: *dt:ld:desc-tag*, *dt:ld:power-tag*, *dt:ld:volt-tag*,
;;;         *dt:ld:circuit-tag*, *dt:ld:file*
;;; ===========================================================================

(setq ld:none "(sin circuito)")   ;; bucket for devices with no label yet

;;; --- Text helpers ----------------------------------------------------------

(defun ld:pad (s n / out)
  (setq out "")
  (repeat (max 1 (- n (strlen s))) (setq out (strcat out " ")))
  out
)

(defun ld:lpad (s n / out)
  (setq out "")
  (repeat (max 1 (- n (strlen s))) (setq out (strcat out " ")))
  (strcat out s)
)

(defun ld:num->str (v)
  ;; Whole numbers print without a decimal tail; VA values are usually integers
  ;; and "180" reads better than "180.00" in both the table and the CSV.
  (rtos v 2 (if (equal v (float (fix v)) 1e-9) 0 2))
)

(defun ld:strip (s / out i c)
  ;; Drop spaces and thousands separators so "1,500" and "1 500" both read as
  ;; 1500. A decimal must be written with a period: "180.5", not "180,5".
  (setq out "" i 1)
  (while (<= i (strlen s))
    (setq c (substr s i 1))
    (if (not (member c '(" " "," "\t"))) (setq out (strcat out c)))
    (setq i (1+ i)))
  out
)

(defun ld:numeric-p (s / i c dots ok)
  ;; T if S is a plain number, so circuit "2" sorts before "10" rather than
  ;; after it.
  (setq i 1 dots 0 ok (> (strlen s) 0))
  (while (and ok (<= i (strlen s)))
    (setq c (substr s i 1))
    (cond ((and (>= (ascii c) 48) (<= (ascii c) 57)))
          ((= c ".") (setq dots (1+ dots) ok (< dots 2)))
          (t (setq ok nil)))
    (setq i (1+ i)))
  ok
)

(defun ld:circuit-lt (a b)
  ;; Numeric labels compare numerically, everything else alphabetically, and
  ;; the unassigned bucket always sorts last. Equal inputs return nil, so this
  ;; stays a strict order and vl-sort cannot discard a circuit.
  (cond
    ((= a b) nil)
    ((= a ld:none) nil)
    ((= b ld:none) t)
    ((and (ld:numeric-p a) (ld:numeric-p b))
     (if (/= (atof a) (atof b)) (< (atof a) (atof b)) (< a b)))
    (t (< a b)))
)

(defun ld:csv-cell (s)
  ;; Quote every field and double any internal quote. Descriptions carry commas
  ;; often enough that quoting unconditionally is simpler than deciding.
  (strcat "\"" (ld:escape-quotes s) "\"")
)

(defun ld:escape-quotes (s / out i c)
  (setq out "" i 1)
  (while (<= i (strlen s))
    (setq c   (substr s i 1)
          out (strcat out (if (= c "\"") "\"\"" c))
          i   (1+ i)))
  out
)

;;; --- Reading a mapping CSV -------------------------------------------------

(defun ld:split-csv (line / out cur i c inq n)
  ;; Comma separated, double quotes optional, "" for a literal quote inside a
  ;; quoted field. Enough to read back what Excel writes.
  (setq out nil cur "" i 1 inq nil n (strlen line))
  (while (<= i n)
    (setq c (substr line i 1))
    (cond
      (inq
       (cond
         ((/= c "\"") (setq cur (strcat cur c)))
         ((= (substr line (1+ i) 1) "\"")           ; "" -> one quote
          (setq cur (strcat cur "\"") i (1+ i)))
         (t (setq inq nil))))
      ((= c "\"") (setq inq t))
      ((= c ",")  (setq out (cons cur out) cur ""))
      (t (setq cur (strcat cur c))))
    (setq i (1+ i)))
  (reverse (cons cur out))
)

(defun ld:read-map (path / f line fields first out)
  ;; Two columns: old label, new label. A header row is optional and skipped.
  (setq out nil first t)
  (if (setq f (open path "r"))
    (progn
      (while (setq line (read-line f))
        (setq fields (ld:split-csv line))
        (cond
          ((< (length fields) 2))                    ; blank or one column
          ((and first
                (member (strcase (vl-string-trim " \t" (car fields)))
                        '("OLD" "CIRCUIT" "CIRCUITO" "ANTERIOR" "FROM" "DE"))))
          (t
           (setq out (cons (cons (vl-string-trim " \t" (car fields))
                                 (vl-string-trim " \t" (cadr fields)))
                           out))))
        (setq first nil))
      (close f)))
  (reverse out)
)

(defun ld:apply-map (mapping / ss i obj att cur hit plan used up)
  ;; Returns (devices-changed . labels-in-the-file-that-matched-nothing).
  ;;
  ;; Every device is read BEFORE any is written. That is what stops a mapping
  ;; like A->B, B->C from cascading: each device is judged against the labels as
  ;; they were when the file was written, not against a half-applied drawing.
  (setq up (mapcar '(lambda (m) (cons (strcase (car m)) (cdr m))) mapping)
        plan nil used nil)
  (if (setq ss (ld:all-devices))
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq obj (vlax-ename->vla-object (ssname ss i))
              att (ld:att-obj obj *dt:ld:circuit-tag*))
        (if att
          (progn
            (setq cur (strcase (vl-string-trim " \t" (vla-get-textstring att))))
            (if (setq hit (assoc cur up))
              (setq plan (cons (cons att (cdr hit)) plan)
                    used (cons cur used)))))
        (setq i (1+ i)))))

  (foreach p plan (vla-put-textstring (car p) (cdr p)))

  (cons (length plan)
        (vl-remove-if '(lambda (m) (member (strcase (car m)) used)) mapping))
)

;;; --- Reading devices -------------------------------------------------------

(defun ld:att-obj (obj tag)
  (if (vlax-method-applicable-p obj 'getattributes)
    (vl-some '(lambda (x)
                (if (= (strcase (vla-get-tagstring x)) (strcase tag)) x))
             (vlax-invoke obj 'getattributes)))
)

(defun ld:att (obj tag / a)
  (if (setq a (ld:att-obj obj tag))
    (vl-string-trim " \t" (vla-get-textstring a)))
)

(defun ld:all-devices ( / ss)
  ;; Every attributed block in the space the drafter is looking at. Filtering
  ;; down to actual devices happens per command, by attribute.
  (ssget "_X" (list '(0 . "INSERT") '(66 . 1) (dt:space-filter)))
)

(defun ld:circuits ( / ss i obj c out hit)
  ;; (label . device-count) for every circuit label in the drawing, in order.
  (setq out nil)
  (if (setq ss (ld:all-devices))
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq obj (vlax-ename->vla-object (ssname ss i))
              c   (ld:att obj *dt:ld:circuit-tag*))
        (if (and c (/= c ""))
          (if (setq hit (assoc c out))
            (setq out (subst (cons c (1+ (cdr hit))) hit out))
            (setq out (cons (cons c 1) out))))
        (setq i (1+ i)))))
  (vl-sort out '(lambda (a b) (ld:circuit-lt (car a) (car b))))
)

(defun ld:show-circuits (circs / i)
  (if (null circs)
    (princ "\n  No circuits tagged yet.")
    (progn
      (princ "\n  Circuits in this drawing:")
      (setq i 1)
      (foreach c circs
        (princ (strcat "\n   " (itoa i) ". " (car c) (ld:pad (car c) 24)
                       (itoa (cdr c)) " device(s)"))
        (setq i (1+ i)))))
  (princ)
)

;;; --- Collecting rows -------------------------------------------------------

(defun ld:collect (ss fallback / i obj desc volt pwr circ key recs hit blank)
  ;; Returns (rows . blank-count). A row is
  ;; (key circuit description voltage power-text power-value quantity).
  ;; FALLBACK is the circuit label to use for devices carrying none.
  (setq i 0 recs nil blank 0)
  (while (< i (sslength ss))
    (setq obj (vlax-ename->vla-object (ssname ss i))
          pwr (ld:att obj *dt:ld:power-tag*))
    ;; No power attribute at all: not a device, not our business.
    (if pwr
      (progn
        (setq desc (ld:att obj *dt:ld:desc-tag*)
              volt (ld:att obj *dt:ld:volt-tag*)
              circ (ld:att obj *dt:ld:circuit-tag*))
        (if (or (null desc) (= desc ""))
          (setq desc (vla-get-EffectiveName obj)))
        (if (null volt) (setq volt ""))
        (if (or (null circ) (= circ "")) (setq circ fallback))
        (if (= pwr "")
          (setq blank (1+ blank))
          (progn
            ;; Key on the text as typed, not the parsed number: it groups
            ;; exactly what the drafter wrote and avoids comparing floats.
            (setq key (strcat circ "\037" (strcase desc) "\037" volt "\037" pwr))
            (if (setq hit (assoc key recs))
              (setq recs (subst (append (reverse (cdr (reverse hit)))
                                        (list (1+ (nth 6 hit))))
                                hit recs))
              (setq recs (cons (list key circ desc volt pwr
                                     (atof (ld:strip pwr)) 1)
                               recs)))))))
    (setq i (1+ i)))

  ;; Circuit order first, then description; the full key breaks any tie so
  ;; vl-sort -- which discards elements it considers equal -- cannot drop a row.
  (cons (vl-sort recs
          '(lambda (a b)
             (cond ((/= (cadr a) (cadr b)) (ld:circuit-lt (cadr a) (cadr b)))
                   ((/= (strcase (caddr a)) (strcase (caddr b)))
                    (< (strcase (caddr a)) (strcase (caddr b))))
                   (t (< (car a) (car b))))))
        blank)
)

(defun ld:row-circuits (rows / out)
  (foreach r rows
    (if (not (member (cadr r) out)) (setq out (cons (cadr r) out))))
  (reverse out)
)

;;; --- Output ----------------------------------------------------------------

(defun ld:csv-path ( / dir name)
  (cond
    (*dt:ld:file*)
    (t
     (setq dir  (getvar "DWGPREFIX")
           name (vl-filename-base (getvar "DWGNAME")))
     (if (or (null dir) (= dir "")) (setq dir *dt:root*))
     (strcat dir name "-load.csv")))
)

(defun ld:write-csv (path rows / f)
  ;; Always a fresh file: the rows now carry their own circuit, so one run
  ;; describes the whole job and appending would only duplicate it.
  (if (setq f (open path "w"))
    (progn
      (write-line "Circuit,Description,Voltage,VA each,Qty,Total VA" f)
      (foreach r rows
        (write-line
          (strcat (ld:csv-cell (cadr r)) ","
                  (ld:csv-cell (caddr r)) ","
                  (ld:csv-cell (cadddr r)) ","
                  (ld:num->str (nth 5 r)) ","
                  (itoa (nth 6 r)) ","
                  (ld:num->str (* (nth 5 r) (nth 6 r))))
          f))
      (close f)
      t)
    nil)
)

(defun ld:show-table (rows / circ qty total gtotal)
  (setq gtotal 0.0)
  (foreach circ (ld:row-circuits rows)
    (setq qty 0 total 0.0)
    (princ (strcat "\n\n  Circuito " circ))
    (princ "\n  Descripcion                        V      VA   Cant     Total")
    (princ "\n  ---------------------------------- ---- ----- ------ ---------")
    (foreach r rows
      (if (= (cadr r) circ)
        (progn
          (princ (strcat "\n  " (caddr r) (ld:pad (caddr r) 35)
                         (ld:lpad (cadddr r) 4) " "
                         (ld:lpad (ld:num->str (nth 5 r)) 5) " "
                         (ld:lpad (itoa (nth 6 r)) 6) " "
                         (ld:lpad (ld:num->str (* (nth 5 r) (nth 6 r))) 9)))
          (setq qty   (+ qty (nth 6 r))
                total (+ total (* (nth 5 r) (nth 6 r)))))))
    (princ "\n  ---------------------------------- ---- ----- ------ ---------")
    (princ (strcat "\n  " (ld:pad "" 36) (ld:lpad (itoa qty) 16) " "
                   (ld:lpad (ld:num->str total) 9)))
    (setq gtotal (+ gtotal total)))
  (princ (strcat "\n\n  Total connected load: " (ld:num->str gtotal) " VA"))
  gtotal
)

;;; --- DT-SETCIRCUIT ---------------------------------------------------------

(defun c:DT-SETCIRCUIT ( / *error* doc ss circs ans label i obj att n missing)

  (defun *error* (msg)
    (dt:undo-end doc)
    (dt:report-error msg)
  )

  (princ "\nSelect the devices in one circuit: ")
  (setq ss (ssget '((0 . "INSERT") (66 . 1))))

  (cond
    ((null ss) (princ "\nNothing selected."))
    (t
     (setq circs (ld:circuits))
     (setq label
       (if (null circs)
         ;; First circuit in the drawing: there is no list to pick from, so ask
         ;; for the label outright. Offering a numbered menu of nothing and
         ;; making the drafter find the New keyword is no way to start.
         (progn
           (princ "\n  No circuits tagged yet -- this will be the first.")
           (getstring t "\nCircuit label: "))
         (progn
           (ld:show-circuits circs)
           ;; Once there are circuits, picking by number rather than retyping
           ;; avoids the failure that matters here: "cocina" and "Cocina" would
           ;; silently become two circuits. A number stays unambiguous even once
           ;; the labels are themselves numbers.
           (initget "New Clear")
           (setq ans (getint (strcat "\nCircuit number, or [New/Clear]"
                                     (if *dt:ld:current*
                                       (strcat " <" *dt:ld:current* ">") "")
                                     ": ")))
           (cond
             ((= ans "Clear") "")
             ((= ans "New")   (getstring t "\nNew circuit label: "))
             ((null ans)      *dt:ld:current*)
             ((and (> ans 0) (<= ans (length circs)))
              (car (nth (1- ans) circs)))
             (t (princ "\nNo such number.") nil)))))

     (cond
       ((null label) (princ "\nNothing changed."))
       (t
        (setq label   (vl-string-trim " \t" label)
              doc     (dt:undo-begin)
              i       0
              n       0
              missing 0)
        (while (< i (sslength ss))
          (setq obj (vlax-ename->vla-object (ssname ss i))
                att (ld:att-obj obj *dt:ld:circuit-tag*))
          (if att
            (progn (vla-put-textstring att label) (setq n (1+ n)))
            (setq missing (1+ missing)))
          (setq i (1+ i)))
        (setq doc (dt:undo-end doc))

        (if (/= label "") (setq *dt:ld:current* label))
        (princ (strcat "\n" (itoa n) " device(s) "
                       (if (= label "")
                         "cleared."
                         (strcat "set to circuit " label "."))))
        (if (> missing 0)
          (princ (strcat "\n" (itoa missing) " selected block(s) have no "
                         *dt:ld:circuit-tag* " attribute and were skipped.")))))))
  (princ)
)

;;; --- Renaming from a mapping file ------------------------------------------
;;; The balancing happens in Excel, so the mapping already exists there. Rather
;;; than retyping it one circuit at a time, hand the file back:
;;;
;;;     old,new
;;;     cocina,3
;;;     habitaciones1,1
;;;     sala,2
;;;
;;; The header row is optional. Two circuits mapping to the same new label is a
;;; merge, which is a normal outcome of balancing and is reported, not blocked.

(defun ld:rename-from-file ( / *error* doc path mapping result n unmatched)

  (defun *error* (msg)
    (dt:undo-end doc)
    (dt:report-error msg)
  )

  (setq path (getfiled "Circuit mapping (old,new)" "" "csv" 8))
  (cond
    ((null path) (princ "\nCancelled."))
    ((null (setq mapping (ld:read-map path)))
     (princ "\nNo usable rows in that file. It needs two columns: old,new"))
    (t
     (setq doc       (dt:undo-begin)
           result    (ld:apply-map mapping)
           doc       (dt:undo-end doc)
           n         (car result)
           unmatched (cdr result))

     (princ (strcat "\n" (itoa n) " device(s) renumbered from "
                    (itoa (- (length mapping) (length unmatched)))
                    " of " (itoa (length mapping)) " mapping(s)."))
     (if unmatched
       (progn
         (princ "\nNot found in the drawing:")
         (foreach m unmatched (princ (strcat "
  " (car m))))))))
  (princ)
)

;;; --- DT-RENCIRCUIT ---------------------------------------------------------
;;; The step after balancing: "cocina" turns out to be circuit 3. Without this
;;; you would re-select every circuit and re-tag it by hand, which is the work
;;; the whole feature exists to remove.

(defun c:DT-RENCIRCUIT ( / *error* doc circs ans old new ss i obj att n merge)

  (defun *error* (msg)
    (dt:undo-end doc)
    (dt:report-error msg)
  )

  (setq circs (ld:circuits))

  (cond
    ((null circs) (princ "\nNo circuits tagged yet. Use DT-SETCIRCUIT first."))
    (t
     (ld:show-circuits circs)
     (initget 6 "File")                ; no zero, no negative
     (setq ans (getint "\nRename which number, or [File]? "))
     (cond
       ((= ans "File") (ld:rename-from-file))
       ((or (null ans) (> ans (length circs))) (princ "\nNothing changed."))
       (t
        (setq old (car (nth (1- ans) circs))
              new (vl-string-trim " \t"
                    (getstring t (strcat "\nNew label for \"" old "\": "))))
        (cond
          ((= new "") (princ "\nNothing changed."))
          ((= new old) (princ "\nThat is the same label; nothing changed."))
          (t
           ;; Renaming onto a label that already exists merges two circuits.
           ;; That may be intended, but it is not reversible by re-running, so
           ;; it gets a question rather than a note afterwards.
           (setq merge (assoc new circs))
           (if merge
             (progn (initget "Yes No")
                    (setq ans (getkword
                                (strcat "\nCircuit " new " already exists with "
                                        (itoa (cdr merge))
                                        " device(s). Merge into it? [Yes/No] <No>: ")))))
           (if (and merge (/= ans "Yes"))
             (princ "\nNothing changed.")
             (progn
               (setq doc (dt:undo-begin) n 0)
               (if (setq ss (ld:all-devices))
                 (progn
                   (setq i 0)
                   (while (< i (sslength ss))
                     (setq obj (vlax-ename->vla-object (ssname ss i))
                           att (ld:att-obj obj *dt:ld:circuit-tag*))
                     (if (and att (= (vl-string-trim " \t"
                                       (vla-get-textstring att)) old))
                       (progn (vla-put-textstring att new) (setq n (1+ n))))
                     (setq i (1+ i)))))
               (setq doc (dt:undo-end doc))
               (if (= *dt:ld:current* old) (setq *dt:ld:current* new))
               (princ (strcat "\n" (itoa n) " device(s) moved from "
                              old " to " new "."))))))))))
  (princ)
)

;;; --- DT-LOAD ---------------------------------------------------------------

(defun c:DT-LOAD ( / *error* ss result rows blank fallback path)

  (defun *error* (msg) (dt:report-error msg))

  (princ "\nSelect the devices to total (all of them, normally): ")
  (setq ss (ssget '((0 . "INSERT") (66 . 1))))

  (cond
    ((null ss) (princ "\nNothing selected."))
    (t
     ;; First pass with the real bucket name, to find out whether anything is
     ;; tagged at all.
     (setq result (ld:collect ss ld:none)
           rows   (car result)
           blank  (cdr result))

     (cond
       ((null rows)
        (princ (strcat "\nNo devices in that selection -- nothing carries a "
                       *dt:ld:power-tag* " attribute."))
        (if (> blank 0)
          (princ (strcat "\n" (itoa blank) " device(s) have a blank "
                         *dt:ld:power-tag* "."))))
       (t
        ;; Nothing tagged: fall back to asking for one label, which is the
        ;; quick "what does this selection draw" case during balancing.
        (if (= (ld:row-circuits rows) (list ld:none))
          (progn
            (setq fallback
              (vl-string-trim " \t"
                (getstring t (strcat "\nNo circuits tagged. Label for this one"
                                     (if *dt:ld:current*
                                       (strcat " <" *dt:ld:current* ">") "")
                                     ": "))))
            (if (= fallback "")
              (setq fallback (if *dt:ld:current* *dt:ld:current* "A")))
            (setq *dt:ld:current* fallback
                  rows            (car (ld:collect ss fallback)))))

        (ld:show-table rows)
        (if (> blank 0)
          (princ (strcat "\n  " (itoa blank) " device(s) have a blank "
                         *dt:ld:power-tag* " and are NOT in the totals.")))

        (setq path (ld:csv-path))
        (if (ld:write-csv path rows)
          (princ (strcat "\nWritten to " path))
          (princ (strcat "\nCould not write " path)))))))
  (princ)
)

(defun c:SC () (c:DT-SETCIRCUIT))
(defun c:LD () (c:DT-LOAD))

(princ)
