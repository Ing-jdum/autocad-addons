;;; ===========================================================================
;;; WIRETREE.LSP  --  Arc "wiring" between fixture blocks, no loops.
;;;
;;; Command:  WTREE
;;;
;;; Builds a Euclidean minimum spanning tree over the insertion points of the
;;; selected blocks and draws each tree edge as a bulged arc. A spanning tree
;;; is loop-free by construction: N nodes give exactly N-1 edges.
;;;
;;; Runs attach at the four cardinal stubs of the fixture symbol (N/E/S/W),
;;; never at the insertion point, and at most one run per stub. Assumes blocks
;;; are inserted upright at scale 1.
;;; ===========================================================================

(vl-load-com)

;;; --- Configuration ---------------------------------------------------------

(setq *wt:layer*     "E-WIRE"  ; layer the arcs are created on
      *wt:color*     4         ; ACI colour for that layer
      *wt:arc-angle* 90.0      ; included angle of each run, degrees
      *wt:fuzz*      1e-8      ; tolerance for coincident points

      ;; Distance from the insertion point out to a stub tip, in drawing
      ;; units. Measured from the fixture symbol.
      ;;
      ;; Set to nil to measure it per block from the bounding box instead:
      ;; for a circle with four symmetric stubs, half the box width is exactly
      ;; the stub length. That fallback breaks on blocks carrying attributes
      ;; or text, which inflate the box, so an explicit number is safer.
      *wt:port-dist* 0.376

      ;; Attachment directions, in degrees CCW from east. Order is irrelevant.
      *wt:port-angles* '(0.0 90.0 180.0 270.0)
)

;;; --- Small helpers ---------------------------------------------------------

(defun wt:2d (p) (list (car p) (cadr p)))

(defun wt:dist2 (a b)
  ;; Squared distance: avoids a sqrt in the inner loop of Prim's algorithm.
  (+ (expt (- (car a) (car b)) 2)
     (expt (- (cadr a) (cadr b)) 2))
)

(defun wt:tan (a) (/ (sin a) (cos a)))
(defun wt:deg->rad (d) (/ (* pi d) 180.0))

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

(defun wt:polar-pt (c ang r)
  (list (+ (car c)  (* r (cos ang)))
        (+ (cadr c) (* r (sin ang))))
)

(defun wt:ensure-layer (name color)
  (if (not (tblsearch "LAYER" name))
    (entmake
      (list '(0 . "LAYER")
            '(100 . "AcDbSymbolTableRecord")
            '(100 . "AcDbLayerTableRecord")
            (cons 2 name)
            (cons 62 color)
            '(70 . 0))))
  name
)

;;; --- Node records ----------------------------------------------------------
;;; A node is (id point port-distance). Integer ids keep every later lookup a
;;; plain assoc on an atom rather than an assoc keyed by a list.

(defun wt:nid (n) (car n))
(defun wt:npt (n) (cadr n))
(defun wt:nd  (n) (caddr n))

(defun wt:bbox-halfwidth (obj / mn mx w h)
  ;; Half the shorter side of the bounding box, or nil if unavailable.
  (if (vl-catch-all-error-p
        (vl-catch-all-apply 'vla-GetBoundingBox (list obj 'mn 'mx)))
    nil
    (progn
      (setq mn (vlax-safearray->list mn)
            mx (vlax-safearray->list mx)
            w  (- (car mx) (car mn))
            h  (- (cadr mx) (cadr mn)))
      (if (> (min w h) *wt:fuzz*) (/ (min w h) 2.0) nil)))
)

(defun wt:port-dist (obj)
  (cond (*wt:port-dist*)
        ((wt:bbox-halfwidth obj))
        (t 0.0))
)

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

(defun wt:nearest-port (bearing ports / best bd d)
  (foreach p ports
    (setq d (wt:angdiff bearing p))
    (if (or (null best) (< d bd)) (setq best p bd d)))
  best
)

(defun wt:assign-ports (runs ports / cands used-run used-port out over)
  ;; RUNS is a list of (run-id . bearing) arriving at one fixture. Match them
  ;; onto PORTS so that total angular error is small and no stub is used
  ;; twice, and return (assignments . overflow-count) where assignments is a
  ;; list of (run-id . port-angle).
  ;;
  ;; Greedy over all (run, port) pairs cheapest first. Not guaranteed optimal,
  ;; but a fixture carries at most six runs against four ports, and greedy and
  ;; optimal agree on every case that size in practice.
  ;;
  ;; An MST vertex can carry up to six edges - any two edges meeting at a
  ;; vertex are at least 60 degrees apart, or a shorter swap would exist - so
  ;; four ports can genuinely be over-subscribed. Runs left unmatched fall
  ;; back to their nearest port, doubling up, and are counted in the overflow
  ;; so the caller can report them rather than failing silently.
  (setq cands nil)
  (foreach r runs
    (foreach p ports
      (setq cands (cons (list (wt:angdiff (cdr r) p) (car r) p) cands))))

  ;; vl-sort discards elements it cannot order, so the comparison has to be a
  ;; strict total order. Cost alone would drop genuine ties.
  (setq cands
    (vl-sort cands
      '(lambda (a b)
         (cond ((not (equal (car a) (car b) *wt:fuzz*)) (< (car a) (car b)))
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

;;; --- Command ---------------------------------------------------------------

(defun c:WTREE ( / doc ss i id ent obj pt nodes seen bulge ports edges
                   na nb pa pb incident result assigned overflow
                   pmap qa qb drawn)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))

  (princ "\nSelect fixture blocks to wire: ")
  (setq ss (ssget '((0 . "INSERT"))))

  (cond
    ((null ss) (princ "\nNothing selected."))
    (t
     ;; --- collect nodes, dropping coincident insertion points ---------------
     (setq i 0 id 0 nodes nil seen nil)
     (while (< i (sslength ss))
       (setq ent (ssname ss i)
             obj (vlax-ename->vla-object ent)
             pt  (wt:2d (cdr (assoc 10 (entget ent)))))
       (if (not (vl-some '(lambda (q) (equal pt q *wt:fuzz*)) seen))
         (setq seen  (cons pt seen)
               nodes (cons (list id pt (wt:port-dist obj)) nodes)
               id    (1+ id)))
       (setq i (1+ i)))
     (setq nodes (reverse nodes))

     (if (< (length nodes) 2)
       (princ "\nNeed at least two distinct blocks.")
       (progn
         (vla-StartUndoMark doc)
         (wt:ensure-layer *wt:layer* *wt:color*)
         (setq bulge (wt:tan (/ (wt:deg->rad *wt:arc-angle*) 4.0))
               ports (mapcar 'wt:deg->rad *wt:port-angles*)
               edges (wt:mst nodes))

         ;; --- pass 1: record the bearing each run arrives on, per fixture ---
         ;; incident: (node-id . ((run-id . bearing) ...)), run-id = edge index
         (setq incident nil i 0)
         (foreach e edges
           (setq pa (wt:npt (assoc (car e) nodes))
                 pb (wt:npt (assoc (cadr e) nodes))
                 incident (wt:push-run incident (car e)  (cons i (angle pa pb)))
                 incident (wt:push-run incident (cadr e) (cons i (angle pb pa)))
                 i (1+ i)))

         ;; --- pass 2: match runs to stubs, one run per stub -----------------
         ;; pmap: (node-id . ((run-id . port-angle) ...))
         (setq pmap nil overflow 0)
         (foreach grp incident
           (setq result   (wt:assign-ports (cdr grp) ports)
                 pmap     (cons (cons (car grp) (car result)) pmap)
                 overflow (+ overflow (cdr result))))

         ;; --- pass 3: draw ---------------------------------------------------
         (setq drawn 0 i 0)
         (foreach e edges
           (setq na (assoc (car e) nodes)
                 nb (assoc (cadr e) nodes)
                 qa (wt:polar-pt (wt:npt na)
                                 (cdr (assoc i (cdr (assoc (car e) pmap))))
                                 (wt:nd na))
                 qb (wt:polar-pt (wt:npt nb)
                                 (cdr (assoc i (cdr (assoc (cadr e) pmap))))
                                 (wt:nd nb)))
           ;; Flip the sign for runs heading into the lower half-plane so every
           ;; arc bows to the same physical side on the plan.
           (wt:draw-edge qa qb
                         (if (< (angle qa qb) pi) bulge (- bulge))
                         *wt:layer*)
           (setq drawn (1+ drawn) i (1+ i)))

         (vla-EndUndoMark doc)
         (princ (strcat "\n" (itoa drawn) " runs drawn on layer " *wt:layer* "."))
         (if (> overflow 0)
           (princ (strcat " " (itoa overflow)
                          " run(s) share a stub: more than four runs meet at a fixture.")))))))
  (princ)
)

(princ "\nWIRETREE loaded. Type WTREE to wire selected blocks.")
(princ)