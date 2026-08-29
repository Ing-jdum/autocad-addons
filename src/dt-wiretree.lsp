;;; ===========================================================================
;;; DT-WIRETREE.LSP  --  Arc "wiring" between device blocks, no loops.
;;;
;;; Commands:  DT-WTREE     wire the selected blocks     (WTREE, WTR)
;;;            DT-SETPORT   measure a symbol             (SP)
;;;            DT-PORTS     list what has been measured
;;;
;;; Builds a Euclidean minimum spanning tree over the insertion points of the
;;; selected blocks and draws each tree edge as a bulged arc. A spanning tree
;;; is loop-free by construction: N nodes give exactly N-1 edges.
;;;
;;; ---------------------------------------------------------------------------
;;; ATTACHMENT PROFILES
;;;
;;; Where a run meets a symbol is a per-block property in *dt:blocks*,
;;; stored as a list of POINTS IN BLOCK COORDINATES -- the coordinates you would
;;; read inside the block editor, with the insertion point at the origin:
;;;
;;;   ("L24" ((0.376 0.0) (0.0 0.376) (-0.376 0.0) (0.0 -0.376)))
;;;   ("TC"  ((0.376 0.05)))
;;;
;;; A point, not a distance and a direction. That distinction is the whole
;;; reason outlets work:
;;;
;;;   - The light fixture's stubs radiate from the centre, so distance-and-angle
;;;     happened to describe it.
;;;   - The outlet's bars sit OFF the centre line. Its connection point is not
;;;     on a ray from the insertion point, so a radial model cannot place it.
;;;     A coordinate can.
;;;
;;; At draw time each point is put through the block reference's own transform:
;;;
;;;   world = insertion + R(rotation) . S(x-scale, y-scale) . point
;;;
;;; which is what makes rotated, scaled and MIRRORED inserts all come out right.
;;; Mirroring matters here: outlets on facing walls are mirrored copies, and a
;;; mirrored insert carries a negative scale factor. The old radial model
;;; multiplied a distance by that negative factor and threw the attachment point
;;; 180 degrees to the wrong side -- invisible on a symmetric fixture, plainly
;;; wrong on an outlet.
;;;
;;; A block with fewer ports than it has runs is normal, not an error: an outlet
;;; mid-chain has a wire in and a wire out, both meeting it at the same point.
;;; Those are counted and reported, never silently dropped.
;;;
;;; Config: *dt:wt:layer*, *dt:wt:color*, *dt:wt:arc-angle*, *dt:wt:fuzz*,
;;;         *dt:blocks*
;;; ===========================================================================

;;; --- Small helpers ---------------------------------------------------------

(defun wt:dist2 (a b)
  ;; Squared distance: avoids a sqrt in the inner loop of Prim's algorithm.
  (+ (expt (- (car a) (car b)) 2)
     (expt (- (cadr a) (cadr b)) 2))
)

(defun wt:tan (a) (/ (sin a) (cos a)))

(defun wt:norm (a)
  ;; Normalise an angle into [0, 2*pi).
  (setq a (rem a (* 2 pi)))
  (if (< a 0) (+ a (* 2 pi)) a)
)

(defun wt:angdiff (a b / d)
  ;; Smallest absolute angle between two bearings, in [0, pi].
  (setq d (wt:norm (- a b)))
  (if (> d pi) (- (* 2 pi) d) d)
)

;;; --- The block reference transform -----------------------------------------
;;; Insert data as one record: (insertion-point rotation x-scale y-scale).
;;; Scale factors are legitimately negative on a mirrored insert, so they are
;;; only guarded against zero, never forced positive.

(defun wt:insert-data (ed / sx sy)
  (setq sx (cond ((cdr (assoc 41 ed))) (1.0))
        sy (cond ((cdr (assoc 42 ed))) (1.0)))
  (list (dt:2d (cdr (assoc 10 ed)))
        (cond ((cdr (assoc 50 ed))) (0.0))
        (if (equal sx 0.0 1e-12) 1.0 sx)
        (if (equal sy 0.0 1e-12) 1.0 sy))
)

(defun wt:ins-pt  (d) (car d))
(defun wt:ins-rot (d) (cadr d))
(defun wt:ins-sx  (d) (caddr d))
(defun wt:ins-sy  (d) (cadddr d))

(defun wt:to-world (p ins / x y c s)
  ;; Block coordinates -> world. Scale first, then rotate, then translate.
  (setq x (* (wt:ins-sx ins) (car  p))
        y (* (wt:ins-sy ins) (cadr p))
        c (cos (wt:ins-rot ins))
        s (sin (wt:ins-rot ins)))
  (list (+ (car  (wt:ins-pt ins)) (- (* x c) (* y s)))
        (+ (cadr (wt:ins-pt ins)) (+ (* x s) (* y c))))
)

(defun wt:to-block (w ins / dx dy c s x y)
  ;; World -> block coordinates. The exact inverse of wt:to-world, which is what
  ;; lets DT-SETPORT measure an instance that is rotated, scaled or mirrored and
  ;; still record a profile that is true for every other instance.
  (setq dx (- (car  w) (car  (wt:ins-pt ins)))
        dy (- (cadr w) (cadr (wt:ins-pt ins)))
        c  (cos (wt:ins-rot ins))
        s  (sin (wt:ins-rot ins))
        x  (+ (* dx c) (* dy s))
        y  (+ (* dx (- s)) (* dy c)))
  (list (/ x (wt:ins-sx ins)) (/ y (wt:ins-sy ins)))
)

;;; --- Attachment profiles ---------------------------------------------------

(defun wt:bbox-halfwidth (obj fuzz / mn mx w h)
  ;; Half the shorter side of the bounding box, or nil if unavailable.
  (if (vl-catch-all-error-p
        (vl-catch-all-apply 'vla-GetBoundingBox (list obj 'mn 'mx)))
    nil
    (progn
      (setq mn (vlax-safearray->list mn)
            mx (vlax-safearray->list mx)
            w  (- (car mx) (car mn))
            h  (- (cadr mx) (cadr mn)))
      (if (> (min w h) fuzz) (/ (min w h) 2.0) nil)))
)

(defun wt:world-ports (obj ins prof fuzz / h)
  ;; The world points where runs may attach to this block reference.
  (cond
    (prof (mapcar '(lambda (p) (wt:to-world p ins)) prof))
    ;; Never measured: fall back to four cardinal points off the bounding box,
    ;; turned with the block. Good enough to draw something sensible, and
    ;; DT-SETPORT is how you replace a guess with the real thing.
    ((setq h (wt:bbox-halfwidth obj fuzz))
     (mapcar '(lambda (a / ang) (setq ang (+ (wt:ins-rot ins) (dt:deg->rad a)))
                (list (+ (car  (wt:ins-pt ins)) (* h (cos ang)))
                      (+ (cadr (wt:ins-pt ins)) (* h (sin ang)))))
             '(0.0 90.0 180.0 270.0)))
    ;; Nothing to go on: attach at the insertion point itself.
    (t (list (wt:ins-pt ins))))
)

;;; --- Node records ----------------------------------------------------------
;;; A node is (id centre world-ports). Integer ids keep every later lookup a
;;; plain assoc on an atom rather than an assoc keyed by a list.

(defun wt:nid    (n) (car n))
(defun wt:npt    (n) (cadr n))
(defun wt:nports (n) (caddr n))

;;; --- Graph construction ----------------------------------------------------

(defun wt:mst (nodes / tree-pt frontier edges best newnode)
  ;; Euclidean minimum spanning tree via Prim's algorithm, O(n^2).
  ;; NODES is a list of node records; returns a list of (id-a id-b) edges.
  ;;
  ;; FRONTIER holds one entry per node not yet in the tree, as
  ;; (node squared-distance-to-tree nearest-tree-node). Each pass pulls the
  ;; cheapest entry into the tree, then relaxes the rest against the node just
  ;; added. That relaxation is what keeps this quadratic rather than cubic.
  (setq tree-pt  (wt:npt (car nodes))
        edges    nil
        frontier (mapcar
                   '(lambda (n) (list n (wt:dist2 tree-pt (wt:npt n)) (car nodes)))
                   (cdr nodes)))
  (while frontier
    (setq best nil)
    (foreach item frontier
      (if (or (null best) (< (cadr item) (cadr best)))
        (setq best item)))

    (setq newnode  (car best)
          edges    (cons (list (wt:nid (caddr best)) (wt:nid newnode)) edges)
          frontier (vl-remove best frontier)
          tree-pt  (wt:npt newnode))

    (setq frontier
      (mapcar
        '(lambda (item / d)
           (setq d (wt:dist2 (wt:npt (car item)) tree-pt))
           (if (< d (cadr item)) (list (car item) d newnode) item))
        frontier)))
  (reverse edges)
)

;;; --- Port assignment -------------------------------------------------------
;;; Ports are indexed (index bearing point) so every comparison below is between
;;; integers or reals; points themselves are never ordered.

(defun wt:index-ports (centre pts / out i)
  (setq out nil i 0)
  (foreach p pts
    (setq out (cons (list i (angle centre p) p) out)
          i   (1+ i)))
  (reverse out)
)

(defun wt:nearest-port (bearing ports / best bd d)
  (foreach p ports
    (setq d (wt:angdiff bearing (cadr p)))
    (if (or (null best) (< d bd)) (setq best (car p) bd d)))
  best
)

(defun wt:assign-ports (runs ports fuzz / cands used-run used-port out over)
  ;; RUNS is a list of (run-id . bearing) arriving at one block. Match them onto
  ;; that block's PORTS so total angular error is small and no port is used
  ;; twice, and return (assignments . shared-count) where assignments is a list
  ;; of (run-id . port-index).
  ;;
  ;; Greedy over all (run, port) pairs cheapest first. Not guaranteed optimal,
  ;; but a block carries at most six runs against a handful of ports, and greedy
  ;; and optimal agree on every case that size in practice.
  ;;
  ;; Ports genuinely run out. An MST vertex can carry up to six edges -- any two
  ;; edges meeting at a vertex are at least 60 degrees apart, or a shorter swap
  ;; would exist -- and a one-port outlet mid-chain is over-subscribed by two
  ;; runs as a matter of course. Runs left unmatched fall back to their nearest
  ;; port, doubling up, and are counted so the caller can report them.
  (setq cands nil)
  (foreach r runs
    (foreach p ports
      (setq cands (cons (list (wt:angdiff (cdr r) (cadr p)) (car r) (car p))
                        cands))))

  ;; vl-sort discards elements it cannot order, so the comparison has to be a
  ;; strict total order. Cost alone would drop genuine ties.
  (setq cands
    (vl-sort cands
      '(lambda (a b)
         (cond ((not (equal (car a) (car b) fuzz)) (< (car a) (car b)))
               ((/= (cadr a) (cadr b)) (< (cadr a) (cadr b)))
               (t (< (caddr a) (caddr b)))))))

  (setq used-run nil used-port nil out nil over 0)
  (foreach c cands
    (if (and (not (member (cadr c) used-run))
             (not (member (caddr c) used-port)))
      (setq out       (cons (cons (cadr c) (caddr c)) out)
            used-run  (cons (cadr c) used-run)
            used-port (cons (caddr c) used-port))))

  (foreach r runs
    (if (not (member (car r) used-run))
      (setq out  (cons (cons (car r) (wt:nearest-port (cdr r) ports)) out)
            over (1+ over))))

  (cons out over)
)

(defun wt:port-point (ports idx)
  (caddr (assoc idx ports))
)

(defun wt:push-run (table key entry / hit)
  ;; Append ENTRY to the list held against KEY, creating the group if needed.
  (if (setq hit (assoc key table))
    (subst (cons key (cons entry (cdr hit))) hit table)
    (cons (list key entry) table))
)

;;; --- Drawing ---------------------------------------------------------------

(defun wt:draw-edge (p1 p2 bulge layer)
  ;; One run, as a 2-vertex bulged LWPOLYLINE. A positive bulge sweeps
  ;; counter-clockwise from P1 to P2, putting the arc on the right of the
  ;; P1->P2 vector.
  (entmake
    (list '(0 . "LWPOLYLINE")
          '(100 . "AcDbEntity")
          (cons 8 layer)
          '(100 . "AcDbPolyline")
          '(90 . 2)
          '(70 . 0)
          (cons 10 p1) (cons 42 bulge)
          (cons 10 p2)))
)

;;; --- DT-WTREE --------------------------------------------------------------

(defun c:DT-WTREE ( / *error* doc ss i id ent obj ed ins pt nodes seen bulge
                      edges na nb pa pb incident result shared pmap ports qa qb
                      drawn layer fuzz)

  (defun *error* (msg)
    (dt:undo-end doc)
    (dt:report-error msg)
  )

  (setq layer *dt:wt:layer*
        fuzz  *dt:wt:fuzz*
        bulge (wt:tan (/ (dt:deg->rad *dt:wt:arc-angle*) 4.0)))

  (princ "\nSelect device blocks to wire: ")
  (setq ss (ssget (list '(0 . "INSERT") (dt:space-filter))))

  (cond
    ((null ss) (princ "\nNothing selected."))
    (t
     ;; --- collect nodes, dropping coincident insertion points ---------------
     (setq i 0 id 0 nodes nil seen nil)
     (while (< i (sslength ss))
       (setq ent (ssname ss i)
             obj (vlax-ename->vla-object ent)
             ed  (entget ent)
             ins (wt:insert-data ed)
             pt  (wt:ins-pt ins))
       (if (not (vl-some '(lambda (q) (equal pt q fuzz)) seen))
         (setq seen  (cons pt seen)
               nodes (cons (list id pt
                                 (wt:world-ports
                                   obj ins
                                   (dt:block-ports (vla-get-EffectiveName obj))
                                   fuzz))
                           nodes)
               id    (1+ id)))
       (setq i (1+ i)))
     (setq nodes (reverse nodes))

     (if (< (length nodes) 2)
       (princ "\nNeed at least two distinct blocks.")
       (progn
         (setq doc (dt:undo-begin))
         (dt:ensure-layer layer *dt:wt:color*)
         (setq edges (wt:mst nodes))

         ;; --- pass 1: record the bearing each run arrives on, per block -----
         ;; incident: (node-id . ((run-id . bearing) ...)), run-id = edge index
         (setq incident nil i 0)
         (foreach e edges
           (setq pa (wt:npt (assoc (car e) nodes))
                 pb (wt:npt (assoc (cadr e) nodes))
                 incident (wt:push-run incident (car e)  (cons i (angle pa pb)))
                 incident (wt:push-run incident (cadr e) (cons i (angle pb pa)))
                 i (1+ i)))

         ;; --- pass 2: match runs to that block's own ports ------------------
         ;; pmap: (node-id indexed-ports ((run-id . port-index) ...))
         (setq pmap nil shared 0)
         (foreach grp incident
           (setq na     (assoc (car grp) nodes)
                 ports  (wt:index-ports (wt:npt na) (wt:nports na))
                 result (wt:assign-ports (cdr grp) ports fuzz)
                 pmap   (cons (list (car grp) ports (car result)) pmap)
                 shared (+ shared (cdr result))))

         ;; --- pass 3: draw --------------------------------------------------
         (setq drawn 0 i 0)
         (foreach e edges
           (setq na (assoc (car e)  pmap)
                 nb (assoc (cadr e) pmap)
                 qa (wt:port-point (cadr na) (cdr (assoc i (caddr na))))
                 qb (wt:port-point (cadr nb) (cdr (assoc i (caddr nb)))))
           ;; Flip the sign for runs heading into the lower half-plane so every
           ;; arc bows to the same physical side on the plan.
           (wt:draw-edge qa qb
                         (if (< (angle qa qb) pi) bulge (- bulge))
                         layer)
           (setq drawn (1+ drawn) i (1+ i)))

         (setq doc (dt:undo-end doc))

         (princ (strcat "\n" (itoa drawn) " runs drawn on layer " layer "."))
         (if (> shared 0)
           (princ (strcat " " (itoa shared)
                          " run(s) share an attachment point.")))))))
  (princ)
)

;;; --- DT-SETPORT ------------------------------------------------------------
;;; Measure a symbol instead of typing numbers into config.
;;;
;;;   Command: DT-SETPORT
;;;   Select the symbol to measure:            <- pick any instance
;;;   Attachment point:                        <- pick where a wire should meet
;;;   ...                                         it, Enter when done
;;;
;;; Every pick is converted straight into block coordinates, so it does not
;;; matter whether the instance you measured is rotated, scaled or mirrored --
;;; the profile that comes out is true for every other instance of that block.

(defun c:DT-SETPORT ( / *error* opt obj ed name ins pt bp pts desc)

  (defun *error* (msg) (dt:report-error msg))

  (setq opt (entsel "\nSelect the symbol to measure: "))

  (cond
    ((null opt) (princ "\nCancelled."))
    ((progn (setq obj (vlax-ename->vla-object (car opt)))
            (/= "AcDbBlockReference" (vla-get-ObjectName obj)))
     (princ "\nThat is not a block reference."))
    (t
     (setq ed   (entget (car opt))
           name (vla-get-EffectiveName obj)
           ins  (wt:insert-data ed)
           pts  nil)

     (princ (strcat "\nMeasuring " name
                    ". Pick each point where a wire should meet it."))
     (while (setq pt (getpoint (wt:ins-pt ins)
                       "\nAttachment point (Enter when done): "))
       (setq bp (wt:to-block (dt:2d pt) ins))
       (setq pts (cons bp pts))
       (princ (strcat "\n  " (itoa (length pts)) ": block x "
                      (rtos (car bp) 2 4) ", y " (rtos (cadr bp) 2 4))))

     (cond
       ((null pts) (princ "\nNothing measured; nothing changed."))
       (t
        ;; A symbol we have never seen gets registered here, so measuring it is
        ;; the whole of setting it up: it joins DT-SETBLOCK's menu at the same
        ;; time. Nothing to add to dt-config.lsp, ever.
        (setq desc (dt:block-desc name))
        (if (null (dt:block-entry name))
          (progn
            (princ (strcat "\n" name " is new."))
            (setq desc (getstring t "\nShort description for the menu: "))
            (if (= desc "") (setq desc name))))
        (dt:put-block name desc (reverse pts))
        (princ (strcat "\n" name ": " (itoa (length pts))
                       " attachment point(s) recorded."))
        (if (dt:save-blocks)
          (princ "\nSaved to dt-blocks.lsp -- it will load automatically.")
          (princ "\nSet for this session only; could not write the file."))))))
  (princ)
)

;;; --- DT-PORTS --------------------------------------------------------------

(defun c:DT-PORTS ( / w)
  (defun w (s n / out)
    (setq out "")
    (repeat (max 1 (- n (strlen s))) (setq out (strcat out " ")))
    out)

  (if (null *dt:blocks*)
    (princ "\nNo symbols registered yet. Use DT-SETPORT.")
    (progn
      (princ "\n  Block         Description             Attachment points (x y)")
      (princ "\n  ------------- ----------------------- -----------------------")
      (foreach b *dt:blocks*
        (princ (strcat "\n  " (car b) (w (car b) 14)
                       (cadr b) (w (cadr b) 24)
                       (if (caddr b) (dt:pts->str (caddr b))
                         "not measured -- bounding box"))))
      (princ "\n\n  Anything not listed falls back to its bounding box.")
      (princ "\n  Measure or add one with DT-SETPORT.")))
  (princ)
)

;;; --- Aliases ---------------------------------------------------------------

(defun c:WTREE () (c:DT-WTREE))
(defun c:WTR   () (c:DT-WTREE))
(defun c:SP    () (c:DT-SETPORT))

(princ)
