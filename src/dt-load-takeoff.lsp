;;; ===========================================================================
;;; DT-LOAD-TAKEOFF.LSP  --  Circuits and connected load.
;;;
;;; Commands:  DT-SETCIRCUIT   tag a selection with panel + circuit      (SC)
;;;            DT-RENCIRCUIT   rename a circuit within one panel
;;;            DT-RENPANEL     rename a panel everywhere
;;;            DT-LOAD         load table + CSV, grouped by panel        (LD)
;;;
;;; ---------------------------------------------------------------------------
;;; WHY IT COUNTS THIS WAY
;;;
;;; One row per circuit, within a panel. The circuit is the unit that gets a
;;; breaker, a wire size and a line on the panel schedule, so its connected load
;;; is the number the drawing exists to produce. Each device contributes its own
;;; power attribute -- 60 VA lights and 150 VA outlets on the same circuit
;;; simply add up -- and the description shown is the first one seen, a hint at
;;; what the circuit feeds rather than an inventory of it.
;;;
;;; The panel is half of a circuit's identity, not decoration. Circuit 1 of TD-A
;;; and circuit 1 of TD-B are different circuits that share a number, so rows
;;; key on both and every total is per panel. A device carrying no panel
;;; attribute falls into an unnamed bucket rather than failing, which is what
;;; lets a drawing whose blocks predate TABLERO still total as one panel.
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
;;;   0. DT-FIXATTS        once per block, add the attributes it is missing
;;;   1. DT-SETCIRCUIT     group devices under any label -- "cocina", "A", "1"
;;;   2. DT-LOAD           export every panel, one CSV each
;;;   3. balance in Excel  decide that "cocina" is really circuit 3
;;;   4. DT-RENCIRCUIT     apply that decision back to the drawing
;;;
;;; Nothing here requires a number to exist before the load is known, which is
;;; what would put the workflow backwards.
;;;
;;; Config: *dt:ld:desc-tag*, *dt:ld:power-tag*, *dt:ld:volt-tag*,
;;;         *dt:ld:circuit-tag*, *dt:ld:panel-tag*, *dt:ld:file*
;;; ===========================================================================

(setq ld:none    "(sin circuito)"  ;; bucket for devices with no circuit yet
      ld:nopanel "(sin tablero)")  ;; and for those with no panel

;; Last panel and circuit used, offered as the default at the next prompt. The
;; panel especially: it serves many circuits, so it is set once and then Enter
;; carries it through every selection that follows.
(if (null *dt:ld:current*) (setq *dt:ld:current* nil))
(if (null *dt:ld:panel*)   (setq *dt:ld:panel*   nil))

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

(defun ld:unassigned-p (s)
  (or (= s ld:none) (= s ld:nopanel))
)

(defun ld:circuit-lt (a b)
  ;; Numeric labels compare numerically, everything else alphabetically, and
  ;; the unassigned bucket always sorts last. Equal inputs return nil, so this
  ;; stays a strict order and vl-sort cannot discard a circuit. Used for panel
  ;; labels too -- "TD-2" before "TD-10" is wanted in both places.
  (cond
    ((= a b) nil)
    ((ld:unassigned-p a) nil)
    ((ld:unassigned-p b) t)
    ((and (ld:numeric-p a) (ld:numeric-p b))
     (if (/= (atof a) (atof b)) (< (atof a) (atof b)) (< a b)))
    (t (< a b)))
)

(defun ld:panel-circuit-lt (pa ca pb cb)
  ;; Panel first, then circuit inside it.
  (if (/= pa pb) (ld:circuit-lt pa pb) (ld:circuit-lt ca cb))
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

(defun ld:read-map (path / f line fields first out n panel old new)
  ;; Three columns: panel, old circuit, new circuit. A header row is optional
  ;; and skipped.
  ;;
  ;; Two columns are still accepted and mean "any panel", which is both what
  ;; older mapping files contain and what a single-panel job wants to write.
  ;; Circuit numbers repeat across panels, so a two-column file that renames "1"
  ;; on a multi-panel job would hit every panel -- the caller warns about that
  ;; rather than this silently guessing.
  (setq out nil first t)
  (if (setq f (open path "r"))
    (progn
      (while (setq line (read-line f))
        (setq fields (mapcar '(lambda (s) (vl-string-trim " \t" s))
                             (ld:split-csv line))
              n      (length fields))
        (cond
          ((< n 2))                                  ; blank or one column
          ((and first
                (member (strcase (car fields))
                        '("OLD" "CIRCUIT" "CIRCUITO" "ANTERIOR" "FROM" "DE"
                          "PANEL" "TABLERO"))))
          (t
           (if (>= n 3)
             (setq panel (car fields) old (cadr fields) new (caddr fields))
             (setq panel nil        old (car fields)  new (cadr fields)))
           (if (/= old "")
             (setq out (cons (list panel old new) out)))))
        (setq first nil))
      (close f)))
  (reverse out)
)

(defun ld:map-hit (mapping panel circuit)
  ;; The first mapping row matching this device. A row naming a panel only
  ;; matches that panel; a row without one matches anywhere.
  (vl-some '(lambda (m)
              (if (and (= (strcase (cadr m)) circuit)
                       (or (null (car m))
                           (= (strcase (car m)) (strcase panel))))
                m))
           mapping)
)

(defun ld:apply-map (mapping / ss i obj att cur pnl hit plan used)
  ;; Returns (devices-changed . rows-in-the-file-that-matched-nothing).
  ;;
  ;; Every device is read BEFORE any is written. That is what stops a mapping
  ;; like A->B, B->C from cascading: each device is judged against the labels as
  ;; they were when the file was written, not against a half-applied drawing.
  (setq plan nil used nil)
  (if (setq ss (ld:all-devices))
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq obj (vlax-ename->vla-object (ssname ss i))
              att (ld:att-obj obj *dt:ld:circuit-tag*))
        (if att
          (progn
            (setq cur (strcase (vl-string-trim " \t" (vla-get-textstring att)))
                  pnl (ld:device-panel obj))
            (if (setq hit (ld:map-hit mapping pnl cur))
              (setq plan (cons (cons att (caddr hit)) plan)
                    used (cons hit used)))))
        (setq i (1+ i)))))

  (foreach p plan (vla-put-textstring (car p) (cdr p)))

  (cons (length plan)
        (vl-remove-if '(lambda (m) (member m used)) mapping))
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

;;; --- Adding missing attributes ---------------------------------------------
;;; A block drawn before this feature existed has no TABLERO, and editing every
;;; symbol by hand in the Block Editor is the kind of chore that stops a feature
;;; being adopted. DT-FIXATTS adds whatever is missing to the definition and
;;; syncs the inserts already placed.

(defun ld:blockdef (name / doc blk)
  ;; The BlockTableRecord for NAME, or nil. Anonymous dynamic-block records
  ;; ("*U12") are never the right target -- the definition to edit is the one
  ;; the drafter named, which EffectiveName gives us.
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (if (not (vl-catch-all-error-p
             (setq blk (vl-catch-all-apply
                         'vla-Item (list (vla-get-Blocks doc) name)))))
    blk)
)

(defun ld:def-tags (blk / out)
  ;; Tags already defined in the block record.
  (vlax-for e blk
    (if (= (vla-get-ObjectName e) "AcDbAttributeDefinition")
      (setq out (cons (strcase (vla-get-TagString e)) out))))
  (reverse out)
)

(defun ld:add-attdef (blk tag prompt default)
  ;; One invisible attribute definition. None of these belong on the printed
  ;; plan -- they are data, read through Properties, EATTEDIT and this toolset.
  ;;
  ;; Height and insertion point are arbitrary: an invisible attribute is never
  ;; drawn, so there is nothing to collide with the symbol geometry and nothing
  ;; to line up. They just have to be legal values.
  (vla-AddAttribute blk 1.0 acAttributeModeInvisible
                    prompt (vlax-3d-point '(0.0 0.0 0.0)) tag default)
)

(defun ld:sync-block (name)
  ;; Push the changed definition out to the inserts already in the drawing.
  ;; ATTSYNC is the only thing that does this correctly for existing inserts,
  ;; and _N answers its "which block" prompt with a name.
  (vl-cmdf "_.ATTSYNC" "_N" name)
  (while (> (getvar 'cmdactive) 0) (vl-cmdf ""))
)

(defun ld:needed-tags ( / out)
  ;; The load-takeoff attributes, in the order they should appear.
  (list (list *dt:ld:desc-tag*    "Descripcion"  "")
        (list *dt:ld:power-tag*   "Potencia VA"  "")
        (list *dt:ld:volt-tag*    "Voltaje"      "")
        (list *dt:ld:circuit-tag* "Circuito"     "")
        (list *dt:ld:panel-tag*   "Tablero"      ""))
)

(defun ld:fix-block (name / blk have added)
  ;; Returns the list of tags added, or nil if the block already had them all.
  (cond
    ((null (setq blk (ld:blockdef name))) nil)
    (t
     (setq have (ld:def-tags blk) added nil)
     (foreach w (ld:needed-tags)
       (if (not (member (strcase (car w)) have))
         (progn
           (ld:add-attdef blk (car w) (cadr w) (caddr w))
           (setq added (cons (car w) added)))))
     (if added (ld:sync-block name))
     (reverse added)))
)

(defun ld:join (items sep / out)
  (foreach s items
    (setq out (if out (strcat out sep s) s)))
  (if out out "")
)

(defun ld:selected-block-names (ss / i obj n out)
  ;; Distinct effective names in a selection, so picking six outlets edits the
  ;; definition once rather than six times.
  (setq i 0 out nil)
  (while (< i (sslength ss))
    (setq obj (vlax-ename->vla-object (ssname ss i))
          n   (vla-get-EffectiveName obj))
    (if (not (member n out)) (setq out (cons n out)))
    (setq i (1+ i)))
  (reverse out)
)

(defun ld:device-panel (obj / p)
  ;; The panel bucket a device belongs to. A missing attribute and a blank one
  ;; are the same thing here: not assigned yet.
  (setq p (ld:att obj *dt:ld:panel-tag*))
  (if (or (null p) (= p "")) ld:nopanel p)
)

(defun ld:circuits ( panel / ss i obj c out hit)
  ;; (label . device-count) for every circuit label, in order. PANEL restricts
  ;; the count to one panel; nil counts across the whole drawing.
  (setq out nil)
  (if (setq ss (ld:all-devices))
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq obj (vlax-ename->vla-object (ssname ss i))
              c   (ld:att obj *dt:ld:circuit-tag*))
        (if (and c (/= c "")
                 (or (null panel) (= (ld:device-panel obj) panel)))
          (if (setq hit (assoc c out))
            (setq out (subst (cons c (1+ (cdr hit))) hit out))
            (setq out (cons (cons c 1) out))))
        (setq i (1+ i)))))
  (vl-sort out '(lambda (a b) (ld:circuit-lt (car a) (car b))))
)

(defun ld:panels ( / ss i obj p out hit)
  ;; (label . device-count) for every panel, unnamed bucket included so it is
  ;; visible rather than silently absorbing devices.
  (setq out nil)
  (if (setq ss (ld:all-devices))
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq obj (vlax-ename->vla-object (ssname ss i)))
        ;; Only things that are actually devices; a panel is not a property of
        ;; the furniture that happened to be in the window.
        (if (ld:att obj *dt:ld:power-tag*)
          (progn
            (setq p (ld:device-panel obj))
            (if (setq hit (assoc p out))
              (setq out (subst (cons p (1+ (cdr hit))) hit out))
              (setq out (cons (cons p 1) out)))))
        (setq i (1+ i)))))
  (vl-sort out '(lambda (a b) (ld:circuit-lt (car a) (car b))))
)

(defun ld:show-list (items empty title / i)
  (if (null items)
    (princ (strcat "\n  " empty))
    (progn
      (princ (strcat "\n  " title))
      (setq i 1)
      (foreach c items
        (princ (strcat "\n   " (itoa i) ". " (car c) (ld:pad (car c) 24)
                       (itoa (cdr c)) " device(s)"))
        (setq i (1+ i)))))
  (princ)
)

(defun ld:show-circuits (circs)
  (ld:show-list circs "No circuits tagged yet." "Circuits in this panel:")
)

(defun ld:show-panels (panels)
  (ld:show-list panels "No panels tagged yet." "Panels in this drawing:")
)

;;; --- Collecting rows -------------------------------------------------------

(defun ld:collect (ss fallback / i obj desc volt pwr circ pnl key recs hit blank va)
  ;; Returns (rows . blank-count). A row is
  ;; (key panel circuit description voltage quantity total-va).
  ;; FALLBACK is the circuit label to use for devices carrying none.
  ;;
  ;; One row per circuit per panel, nothing finer. What the panel needs is the
  ;; connected load of the circuit; splitting it by description only forces the
  ;; drafter to add the pieces back together in Excel. The description kept is
  ;; the first one seen -- a hint at what the circuit feeds, not an inventory.
  (setq i 0 recs nil blank 0)
  (while (< i (sslength ss))
    (setq obj (vlax-ename->vla-object (ssname ss i))
          pwr (ld:att obj *dt:ld:power-tag*))
    ;; No power attribute at all: not a device, not our business.
    (if pwr
      (progn
        (setq desc (ld:att obj *dt:ld:desc-tag*)
              volt (ld:att obj *dt:ld:volt-tag*)
              circ (ld:att obj *dt:ld:circuit-tag*)
              pnl  (ld:device-panel obj))
        (if (or (null desc) (= desc ""))
          (setq desc (vla-get-EffectiveName obj)))
        (if (null volt) (setq volt ""))
        (if (or (null circ) (= circ "")) (setq circ fallback))
        (if (= pwr "")
          (setq blank (1+ blank))
          (progn
            (setq va  (atof (ld:strip pwr))
                  key (strcat pnl "\037" circ))
            (if (setq hit (assoc key recs))
              (setq recs (subst (list key pnl circ (nth 3 hit) (nth 4 hit)
                                      (1+ (nth 5 hit))
                                      (+ (nth 6 hit) va))
                                hit recs))
              (setq recs (cons (list key pnl circ desc volt 1 va) recs)))))))
    (setq i (1+ i)))

  ;; Panel then circuit. One row per (panel, circuit) pair, so that ordering is
  ;; total and vl-sort -- which discards elements it considers equal -- cannot
  ;; drop a row.
  (cons (vl-sort recs
          '(lambda (a b)
             (ld:panel-circuit-lt (cadr a) (caddr a) (cadr b) (caddr b))))
        blank)
)

(defun ld:row-panels (rows / out)
  (foreach r rows
    (if (not (member (cadr r) out)) (setq out (cons (cadr r) out))))
  (reverse out)
)

(defun ld:row-circuits (rows)
  (mapcar 'caddr rows)
)

;;; --- Output ----------------------------------------------------------------

(defun ld:safe-name (s / out i c)
  ;; A panel label goes into a filename, and "TD-1/2" is a legal label but not
  ;; a legal path. Anything Windows rejects becomes an underscore.
  (setq out "" i 1)
  (while (<= i (strlen s))
    (setq c   (substr s i 1)
          out (strcat out (if (member c '("\\" "/" ":" "*" "?" "\"" "<" ">" "|"))
                            "_" c))
          i   (1+ i)))
  (vl-string-trim " ." out)
)

(defun ld:csv-base ( / dir name)
  ;; Path without the "-load.csv" tail; the panel name goes in between.
  (cond
    (*dt:ld:file*
     (strcat (vl-filename-directory *dt:ld:file*) "\\"
             (vl-filename-base *dt:ld:file*)))
    (t
     (setq dir  (getvar "DWGPREFIX")
           name (vl-filename-base (getvar "DWGNAME")))
     (if (or (null dir) (= dir "")) (setq dir *dt:root*))
     (strcat dir name)))
)

(defun ld:panel-csv-path (base panel)
  ;; The unnamed bucket has no useful name to put in a filename, so it keeps
  ;; the plain <drawing>-load.csv it would have had before panels existed.
  (if (= panel ld:nopanel)
    (strcat base "-load.csv")
    (strcat base "-" (ld:safe-name panel) "-load.csv"))
)

(defun ld:write-csv (path rows with-panel / f)
  ;; Always a fresh file: the rows carry their own panel and circuit, so one run
  ;; describes the whole job and appending would only duplicate it.
  ;;
  ;; WITH-PANEL adds the Panel column. The per-panel files leave it out -- the
  ;; filename already says it -- while the combined file needs it to stay
  ;; readable as a single table.
  (if (setq f (open path "w"))
    (progn
      (write-line (if with-panel
                    "Panel,Circuit,Description,Voltage,Qty,Total VA"
                    "Circuit,Description,Voltage,Qty,Total VA")
                  f)
      (foreach r rows
        (write-line
          (strcat (if with-panel (strcat (ld:csv-cell (cadr r)) ",") "")
                  (ld:csv-cell (caddr r))  ","
                  (ld:csv-cell (nth 3 r))  ","
                  (ld:csv-cell (nth 4 r))  ","
                  (itoa (nth 5 r))         ","
                  (ld:num->str (nth 6 r)))
          f))
      (close f)
      t)
    nil)
)

(defun ld:write-all (rows / base ok written path sub)
  ;; One file per panel, plus a combined one. Returns the paths written.
  ;;
  ;; The per-panel files are what a drafter opens; the combined file is what a
  ;; program reads, so it does not have to guess which of the files in a folder
  ;; belong to this drawing.
  (setq base (ld:csv-base) written nil)
  (foreach p (ld:row-panels rows)
    (setq sub  (vl-remove-if-not '(lambda (r) (= (cadr r) p)) rows)
          path (ld:panel-csv-path base p))
    (if (ld:write-csv path sub nil)
      (setq written (cons path written))))
  ;; Only worth a combined file when there is more than one panel to combine.
  (if (> (length (ld:row-panels rows)) 1)
    (progn
      (setq path (strcat base "-load-all.csv"))
      (if (ld:write-csv path rows t)
        (setq written (cons path written)))))
  (reverse written)
)

(defun ld:show-table (rows / panels qty total gtotal)
  ;; Grouped by panel, because the per-panel subtotal is what each panel gets
  ;; sized from. The grand total only means anything at the service.
  (setq gtotal 0.0 panels (ld:row-panels rows))
  (foreach p panels
    (setq qty 0 total 0.0)
    (princ (strcat "\n\n  Tablero " p))
    (princ "\n  Circuito   Descripcion                        V     Cant     Total")
    (princ "\n  ---------- ---------------------------------- ---- ------ ---------")
    (foreach r rows
      (if (= (cadr r) p)
        (progn
          (princ (strcat "\n  " (caddr r) (ld:pad (caddr r) 11)
                         (nth 3 r) (ld:pad (nth 3 r) 35)
                         (ld:lpad (nth 4 r) 4) " "
                         (ld:lpad (itoa (nth 5 r)) 6) " "
                         (ld:lpad (ld:num->str (nth 6 r)) 9)))
          (setq qty   (+ qty (nth 5 r))
                total (+ total (nth 6 r))))))
    (princ "\n  ---------- ---------------------------------- ---- ------ ---------")
    (princ (strcat "\n  " (ld:pad "" 52) (ld:lpad (itoa qty) 6) " "
                   (ld:lpad (ld:num->str total) 9)))
    (setq gtotal (+ gtotal total)))
  (if (> (length panels) 1)
    (princ (strcat "\n\n  Total connected load, all panels: "
                   (ld:num->str gtotal) " VA"))
    (princ (strcat "\n\n  Total connected load: " (ld:num->str gtotal) " VA")))
  gtotal
)

;;; --- DT-SETCIRCUIT ---------------------------------------------------------

(defun ld:ask-label (items current what first-msg / ans)
  ;; Pick from a numbered list, or type a new one. Returns the label, "" to
  ;; clear, or nil to cancel.
  ;;
  ;; Picking by number rather than retyping avoids the failure that matters
  ;; here: "cocina" and "Cocina" would silently become two circuits. A number
  ;; stays unambiguous even once the labels are themselves numbers.
  (if (null items)
    ;; Nothing to pick from yet, so ask outright. A numbered menu of nothing,
    ;; with the New keyword to find, is no way to start.
    (progn
      (princ (strcat "\n  " first-msg))
      (getstring t (strcat "\n" what " label: ")))
    (progn
      (initget "New Clear")
      (setq ans (getint (strcat "\n" what " number, or [New/Clear]"
                                (if current (strcat " <" current ">") "")
                                ": ")))
      (cond
        ((= ans "Clear") "")
        ((= ans "New")   (getstring t (strcat "\nNew " what " label: ")))
        ((null ans)      current)
        ((and (> ans 0) (<= ans (length items))) (car (nth (1- ans) items)))
        (t (princ "\nNo such number.") nil))))
)

(defun ld:put-att (obj tag value / att)
  ;; T if the attribute was there to write to.
  (if (setq att (ld:att-obj obj tag))
    (progn (vla-put-textstring att value) t))
)

(defun c:DT-SETCIRCUIT ( / *error* doc ss panels circs panel label
                           i obj n missing nopanel)

  (defun *error* (msg)
    (dt:undo-end doc)
    (dt:report-error msg)
  )

  (princ "\nSelect the devices in one circuit: ")
  (setq ss (ssget '((0 . "INSERT") (66 . 1))))

  (cond
    ((null ss) (princ "\nNothing selected."))
    (t
     ;; Panel first, and sticky. A panel serves many circuits, so it is set once
     ;; and rides along until it is changed -- pressing Enter through this
     ;; prompt is the common case, not the exception.
     (setq panels (vl-remove-if '(lambda (p) (= (car p) ld:nopanel)) (ld:panels)))
     (if panels (ld:show-panels panels))
     (setq panel (ld:ask-label panels *dt:ld:panel* "Panel"
                               "No panels tagged yet -- this will be the first."))

     (cond
       ((null panel) (princ "\nNothing changed."))
       (t
        (setq panel (vl-string-trim " \t" panel))
        ;; Circuits are listed for the panel being worked on. Showing every
        ;; circuit in the drawing would offer TD-B's numbers while tagging TD-A.
        (setq circs (ld:circuits (if (= panel "") nil panel)))
        (if circs (ld:show-circuits circs))
        (setq label (ld:ask-label circs *dt:ld:current* "Circuit"
                                  "No circuits in this panel yet -- this will be the first."))

        (cond
          ((null label) (princ "\nNothing changed."))
          (t
           (setq label   (vl-string-trim " \t" label)
                 doc     (dt:undo-begin)
                 i       0
                 n       0
                 missing 0
                 nopanel 0)
           (while (< i (sslength ss))
             (setq obj (vlax-ename->vla-object (ssname ss i)))
             (if (ld:put-att obj *dt:ld:circuit-tag* label)
               (setq n (1+ n))
               (setq missing (1+ missing)))
             ;; A block that predates TABLERO still takes its circuit; only the
             ;; panel is lost, and that is reported rather than failing the run.
             (if (not (ld:put-att obj *dt:ld:panel-tag* panel))
               (setq nopanel (1+ nopanel)))
             (setq i (1+ i)))
           (setq doc (dt:undo-end doc))

           (if (/= label "") (setq *dt:ld:current* label))
           (if (/= panel "") (setq *dt:ld:panel* panel))
           (princ (strcat "\n" (itoa n) " device(s) "
                          (if (= label "")
                            "cleared."
                            (strcat "set to circuit " label
                                    (if (= panel "") ""
                                      (strcat " of panel " panel)) "."))))
           (if (> missing 0)
             (princ (strcat "\n" (itoa missing) " selected block(s) have no "
                            *dt:ld:circuit-tag* " attribute and were skipped.")))
           (if (> nopanel 0)
             (princ (strcat "\n" (itoa nopanel) " block(s) have no "
                            *dt:ld:panel-tag*
                            " attribute -- run DT-FIXATTS to add it.")))))))))
  (princ)
)

;;; --- Renaming from a mapping file ------------------------------------------
;;; The balancing happens in Excel, so the mapping already exists there. Rather
;;; than retyping it one circuit at a time, hand the file back:
;;;
;;;     panel,old,new
;;;     TD-A,cocina,3
;;;     TD-A,habitaciones1,1
;;;     TD-B,sala,2
;;;
;;; The header row is optional. Two circuits mapping to the same new label is a
;;; merge, which is a normal outcome of balancing and is reported, not blocked.
;;;
;;; A two-column file (old,new) still works and applies to every panel. That is
;;; right for a single-panel job and dangerous for the rest -- circuit 1 exists
;;; in every panel -- so it is confirmed rather than assumed.

(defun ld:rename-from-file ( / *error* doc path mapping result n unmatched
                               loose ans)

  (defun *error* (msg)
    (dt:undo-end doc)
    (dt:report-error msg)
  )

  (setq path (getfiled "Circuit mapping (panel,old,new)" "" "csv" 8))
  (cond
    ((null path) (princ "\nCancelled."))
    ((null (setq mapping (ld:read-map path)))
     (princ "\nNo usable rows in that file. It needs: panel,old,new"))
    (t
     ;; Rows with no panel hit every panel. Harmless on a one-panel drawing,
     ;; wrong on any other, so ask before doing it rather than reporting it
     ;; afterwards -- the rename is not reversible by re-running.
     (setq loose (length (vl-remove-if 'car mapping)))
     (if (and (> loose 0) (> (length (ld:panels)) 1))
       (progn
         (princ (strcat "\n  " (itoa loose)
                        " row(s) name no panel, and this drawing has "
                        (itoa (length (ld:panels))) " panels."))
         (initget "Yes No")
         (setq ans (getkword
                     "\n  Apply those to every panel? [Yes/No] <No>: ")))
       (setq ans "Yes"))

     (if (/= ans "Yes")
       (princ "\nNothing changed. Add a panel column to the file.")
       (progn
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
             (foreach m unmatched
               (princ (strcat "\n  " (if (car m) (strcat (car m) " / ") "")
                              (cadr m))))))))))
  (princ)
)

;;; --- DT-RENCIRCUIT ---------------------------------------------------------
;;; The step after balancing: "cocina" turns out to be circuit 3. Without this
;;; you would re-select every circuit and re-tag it by hand, which is the work
;;; the whole feature exists to remove.

(defun ld:pick-panel (prompt / panels ans)
  ;; Which panel a rename applies to. With one panel there is nothing to ask.
  ;; Returns the label, or nil to cancel.
  (setq panels (ld:panels))
  (cond
    ((null panels) nil)
    ((= (length panels) 1) (car (car panels)))
    (t
     (ld:show-panels panels)
     (initget 6)                       ; no zero, no negative
     (setq ans (getint prompt))
     (if (and ans (<= ans (length panels))) (car (nth (1- ans) panels)))))
)

(defun c:DT-RENCIRCUIT ( / *error* doc panel circs ans old new ss i obj att
                           n merge)

  (defun *error* (msg)
    (dt:undo-end doc)
    (dt:report-error msg)
  )

  ;; Panel first: circuit numbers repeat across panels, so "rename circuit 1"
  ;; has no single answer until the panel is known.
  (setq panel (ld:pick-panel "\nRename a circuit in which panel? "))

  (cond
    ((null (ld:panels))
     (princ "\nNo devices tagged yet. Use DT-SETCIRCUIT first."))
    ((null panel) (princ "\nNothing changed."))
    (t
     (setq circs (ld:circuits panel))
     (cond
       ((null circs)
        (princ (strcat "\nNo circuits tagged in panel " panel ".")))
       (t
        (princ (strcat "\n  Panel " panel ":"))
        (ld:show-circuits circs)
        (initget 6 "File")             ; no zero, no negative
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
              ;; That may be intended, but it is not reversible by re-running,
              ;; so it gets a question rather than a note afterwards.
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
                        ;; Scoped to the chosen panel, so the identically
                        ;; numbered circuits elsewhere are left alone.
                        (if (and att
                                 (= (ld:device-panel obj) panel)
                                 (= (vl-string-trim " \t"
                                      (vla-get-textstring att)) old))
                          (progn (vla-put-textstring att new) (setq n (1+ n))))
                        (setq i (1+ i)))))
                  (setq doc (dt:undo-end doc))
                  (if (= *dt:ld:current* old) (setq *dt:ld:current* new))
                  (princ (strcat "\n" (itoa n) " device(s) moved from "
                                 old " to " new " in panel " panel
                                 "."))))))))))))
  (princ)
)

;;; --- DT-RENPANEL -----------------------------------------------------------
;;; Same reasoning as DT-RENCIRCUIT one level up: the panel names are
;;; provisional too, and "TABLERO PRINCIPAL" becomes "TD-1" once the riser is
;;; settled.

(defun c:DT-RENPANEL ( / *error* doc panels ans old new ss i obj att n merge)

  (defun *error* (msg)
    (dt:undo-end doc)
    (dt:report-error msg)
  )

  (setq panels (ld:panels))

  (cond
    ((null panels) (princ "\nNo devices tagged yet. Use DT-SETCIRCUIT first."))
    (t
     (ld:show-panels panels)
     (initget 6)                       ; no zero, no negative
     (setq ans (getint "\nRename which number? "))
     (cond
       ((or (null ans) (> ans (length panels))) (princ "\nNothing changed."))
       (t
        (setq old (car (nth (1- ans) panels))
              new (vl-string-trim " \t"
                    (getstring t (strcat "\nNew label for \"" old "\": "))))
        (cond
          ((= new "") (princ "\nNothing changed."))
          ((= new old) (princ "\nThat is the same label; nothing changed."))
          (t
           ;; Merging panels also merges their circuit numbering, so two
           ;; circuit 1s would become one circuit 1 holding both loads. Worth
           ;; more than the usual warning.
           (setq merge (assoc new panels))
           (if merge
             (progn (initget "Yes No")
                    (setq ans (getkword
                                (strcat "\nPanel " new " already exists with "
                                        (itoa (cdr merge))
                                        " device(s). Circuits sharing a number "
                                        "will merge. Continue? [Yes/No] <No>: ")))))
           (if (and merge (/= ans "Yes"))
             (princ "\nNothing changed.")
             (progn
               (setq doc (dt:undo-begin) n 0)
               (if (setq ss (ld:all-devices))
                 (progn
                   (setq i 0)
                   (while (< i (sslength ss))
                     (setq obj (vlax-ename->vla-object (ssname ss i))
                           att (ld:att-obj obj *dt:ld:panel-tag*))
                     (if (and att (= (ld:device-panel obj) old))
                       (progn (vla-put-textstring att new) (setq n (1+ n))))
                     (setq i (1+ i)))))
               (setq doc (dt:undo-end doc))
               (if (= *dt:ld:panel* old) (setq *dt:ld:panel* new))
               (princ (strcat "\n" (itoa n) " device(s) moved from panel "
                              old " to " new "."))
               ;; The unnamed bucket is not stored in an attribute, so devices
               ;; that never had one cannot be moved by writing to it.
               (if (= old ld:nopanel)
                 (princ (strcat "\n  Devices with no " *dt:ld:panel-tag*
                                " attribute were skipped -- run DT-FIXATTS "
                                "first, then tag them.")))))))))))
  (princ)
)

;;; --- DT-LOAD ---------------------------------------------------------------

(defun c:DT-LOAD ( / *error* ss result rows blank fallback written)

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

        (setq written (ld:write-all rows))
        (if written
          (progn
            (princ "\n\nWritten:")
            (foreach p written (princ (strcat "\n  " p))))
          (princ "\nCould not write the CSV."))))))
  (princ)
)

;;; --- DT-FIXATTS ------------------------------------------------------------
;;; The migration path. A symbol drawn before TABLERO existed has no such
;;; attribute, and opening every block in the Block Editor to add one by hand is
;;; the kind of chore that stops a feature being used at all. This adds whatever
;;; is missing to the definition and syncs the inserts already placed.
;;;
;;; ATTSYNC rewrites every insert of the block from its definition, which is why
;;; this is a separate deliberate command and not something DT-LOAD does
;;; quietly: attribute values that were overridden per insert are reset by it.
;;; New attributes come in blank, so the values this toolset writes survive.

(defun c:DT-FIXATTS ( / *error* doc ss names added total touched)

  (defun *error* (msg)
    (dt:undo-end doc)
    (dt:report-error msg)
  )

  (princ "\nSelect one of each block to fix (or all of them): ")
  (setq ss (ssget '((0 . "INSERT"))))

  (cond
    ((null ss) (princ "\nNothing selected."))
    (t
     (setq names   (ld:selected-block-names ss)
           doc     (dt:undo-begin)
           total   0
           touched 0)
     (foreach n names
       (setq added (ld:fix-block n))
       (if added
         (progn
           (setq total   (+ total (length added))
                 touched (1+ touched))
           (princ (strcat "\n  " n ": added " (ld:join added ", "))))
         (princ (strcat "\n  " n ": already complete"))))
     (setq doc (dt:undo-end doc))
     (princ (strcat "\n\n" (itoa total) " attribute(s) added across "
                    (itoa touched) " of " (itoa (length names)) " block(s)."))
     (if (> total 0)
       (princ "\n  Values are blank -- set them with EATTEDIT or DT-SETCIRCUIT."))))
  (princ)
)

(defun c:SC () (c:DT-SETCIRCUIT))
(defun c:LD () (c:DT-LOAD))

(princ)
