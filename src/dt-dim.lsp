;;; ===========================================================================
;;; DT-DIM.LSP  --  Dimensioning a row of fixtures in one pass.
;;;
;;; Command:  DT-FIXDIM   dimension a row of blocks, wall to wall  (alias: FDM)
;;;
;;; ---------------------------------------------------------------------------
;;; WHAT THIS IS FOR
;;;
;;; The technician mounting the fixtures needs to know how far from the wall the
;;; first one goes and how far apart the rest are. Drawing that by hand is a
;;; dozen picks, each one fighting the running osnaps for the centre of a
;;; symbol whose circle, stubs and bounding box all snap.
;;;
;;; Three things make this worth a command rather than DIMLINEAR and patience:
;;;
;;;   1. The insertion point is read out of the block reference, not snapped to.
;;;      "_non" forces it through, so no osnap can land the extension line on a
;;;      stub tip that happens to be nearer the cursor.
;;;
;;;   2. Fixtures are never perfectly aligned. Two lights three millimetres
;;;      apart in Y give a slanted dimension and a number that is not the number
;;;      anyone wanted. Every point is projected onto one axis first, so the
;;;      chain is straight by construction and each figure is the true distance
;;;      along the run.
;;;
;;;   3. The order comes from that same projection, not from the order the
;;;      blocks were selected or drawn.
;;;
;;; It drives the native DIMLINEAR and DIMALIGNED, so the office dimension
;;; style, scale, arrowheads, units and precision all apply untouched, and the
;;; dimensions land on whatever layer is current.
;;;
;;; Config: *dt:dm:square-tol*
;;; ===========================================================================

;;; --- Geometry --------------------------------------------------------------

(defun dm:unit (a b / dx dy len)
  ;; Unit vector from A to B, nil if they are the same point.
  (setq dx  (- (car b) (car a))
        dy  (- (cadr b) (cadr a))
        len (sqrt (+ (* dx dx) (* dy dy))))
  (if (> len 1e-9) (list (/ dx len) (/ dy len)))
)

(defun dm:square (u / a)
  ;; A run that is within a couple of degrees of horizontal or vertical is
  ;; almost certainly meant to be exactly that, and the drawing wants a clean
  ;; orthogonal dimension line. Snapping costs accuracy of one part in 1500 at
  ;; two degrees -- well under a millimetre per metre, and under the tolerance
  ;; anyone mounts to. A genuinely diagonal run is left diagonal.
  (setq a (dt:rad->deg (atan (cadr u) (car u))))
  (cond
    ((< (abs (rem (+ a 360.0) 180.0)) *dt:dm:square-tol*)          '(1.0 0.0))
    ((< (abs (- (rem (+ a 360.0) 180.0) 180.0)) *dt:dm:square-tol*) '(1.0 0.0))
    ((< (abs (- (rem (+ a 360.0) 180.0) 90.0)) *dt:dm:square-tol*)  '(0.0 1.0))
    (t u))
)

(defun dm:t (p origin u)
  ;; How far along the axis P sits: the dot product of (P - ORIGIN) with U.
  ;; This single number is both the sort key and the measured distance.
  (+ (* (- (car p) (car origin)) (car u))
     (* (- (cadr p) (cadr origin)) (cadr u)))
)

(defun dm:at (origin u d)
  ;; The point D along the axis. Every extension line origin is one of these,
  ;; which is what makes the chain straight no matter how the blocks sit.
  (list (+ (car origin) (* d (car u)))
        (+ (cadr origin) (* d (cadr u))))
)

(defun dm:square-of (a b / v)
  ;; The squared-up direction from A to B, nil if they are the same point.
  (if (setq v (dm:unit a b)) (dm:square v))
)

(defun dm:axis (pts / best u bi bj i j d)
  ;; Direction of the run: the line through the two points farthest apart.
  ;; Taken from the fixtures themselves rather than from a wall, because the
  ;; wall the drafter wants to measure FROM is the one across the end of the
  ;; run, which says nothing about its direction.
  ;;
  ;; ponytail: O(n^2) over the selection. A row is five to thirty fixtures, so
  ;; this is microseconds; reach for a convex hull if someone ever dimensions a
  ;; whole floor in one go.
  (setq best -1.0 i 0)
  (while (< i (length pts))
    (setq j (1+ i))
    (while (< j (length pts))
      (setq d (distance (nth i pts) (nth j pts)))
      (if (> d best) (setq best d bi i bj j))
      (setq j (1+ j)))
    (setq i (1+ i)))
  (if (> best 1e-9)
    (dm:square (dm:unit (nth bi pts) (nth bj pts))))
)

;;; --- Selection -------------------------------------------------------------

(defun dm:points (ss / i pts)
  ;; Insertion points of the selected blocks, as 2D. Group 10 is read straight
  ;; from the entity: no snap, no bounding box, no guessing at a centre.
  (setq i 0 pts nil)
  (while (< i (sslength ss))
    (setq pts (cons (dt:2d (cdr (assoc 10 (entget (ssname ss i))))) pts)
          i   (1+ i)))
  (reverse pts)
)

;;; --- Drawing ---------------------------------------------------------------

(defun dm:draw (pa pb loc square)
  ;; One dimension. DIMLINEAR measures the X or Y component only, which is what
  ;; is wanted on an orthogonal run and wrong on a diagonal one, so a diagonal
  ;; run gets DIMALIGNED and its true length.
  (command (if square "_.DIMLINEAR" "_.DIMALIGNED")
           "_non" pa "_non" pb "_non" loc)
)

(defun dm:report (ds / out)
  (setq out "")
  (foreach d ds (setq out (strcat out (if (= out "") "" ", ") (rtos d))))
  out
)


;;; --- DT-FIXDIM -------------------------------------------------------------

(defun dm:run (force / *error* doc saved ss pts u origin square ds stops
                      start finish loc base done merged gaps perp step i)
  ;; FORCE is the axis the caller insists on, or nil to take it from the way
  ;; the fixtures are lined up. DT-FIXDIMH and DT-FIXDIMV are this function
  ;; with the answer already given, because "dimension this row across" is a
  ;; thing you know before you start, not a keyword you want to type each time.

  (defun *error* (msg)
    (dt:restore-vars saved)
    (dt:undo-end doc)
    (dt:report-error msg)
  )

  (princ "\nSelect the fixtures to dimension: ")
  (setq ss (ssget '((0 . "INSERT"))))

  (cond
    ((null ss) (princ "\nNothing selected."))
    (t
     ;; U may well be nil here: one fixture, or several stacked on one point,
     ;; is not a run and says nothing about direction. That is not an error --
     ;; wall to a single fixture is a dimension anybody might want -- so the
     ;; direction is picked up further down from the force, the wall points or
     ;; the keyword, and only the absence of ALL of those is a dead end.
     (setq pts    (dm:points ss)
           origin (car pts)
           u      (cond (force) ((dm:axis pts))))

     ;; The two wall prompts take a POINT, not the wall entity: with osnaps on,
     ;; picking the wall face is one click and it works on a line, a polyline, a
     ;; hatch edge or a block, none of which need their own case here. A point
     ;; anywhere on a wall square to the run projects to the same distance.
     (setq start  (getpoint "\nPoint on the wall to measure from <first fixture>: "))
     (setq finish (getpoint "\nPoint on the wall to finish at <last fixture>: "))

     ;; Wall to one fixture: the wall point and the fixture are themselves the
     ;; run, so they give the direction the fixtures could not.
     (if (null u)
       (setq u (cond
                 ((and start finish) (dm:square-of start finish))
                 (start              (dm:square-of start origin))
                 (finish             (dm:square-of origin finish)))))

     ;; One prompt carries the mode, the direction and the location, since
     ;; getpoint hands back a keyword as a string. A prompt of its own for the
     ;; direction would stand in front of every run that does not need one.
     (setq base nil done nil)
     (while (not done)
       (initget "Baseline Chain Horizontal Vertical")
       (setq loc (getpoint
                   (strcat "\nDimension line location"
                           " [Chain/Baseline/Horizontal/Vertical] <"
                           (if base "baseline" "chain")
                           (cond ((null u) ", direction not known yet")
                                 ((equal u '(1.0 0.0) 1e-9) ", horizontal")
                                 ((equal u '(0.0 1.0) 1e-9) ", vertical")
                                 (t ", aligned"))
                           ">: ")))
       (cond
         ((= loc "Baseline") (setq base t))
         ((= loc "Chain")    (setq base nil))
         ;; Forcing the direction is what dimensions a COLUMN of fixtures ACROSS
         ;; to a wall. Left to itself the axis comes from the fixtures, and a
         ;; column of them can only be measured down its own length.
         ((= loc "Horizontal") (setq u '(1.0 0.0)))
         ((= loc "Vertical")   (setq u '(0.0 1.0)))
         (t (setq done t))))            ; a point, or nil from Enter

     (setq square (or (equal u '(1.0 0.0) 1e-9) (equal u '(0.0 1.0) 1e-9))
           merged 0)

     ;; Everything below is distances ALONG the axis, so none of it can be
     ;; worked out until there is one.
     (if u
       (progn
         ;; Stops along the axis, in order.
         (setq stops (mapcar '(lambda (p) (dm:t p origin u)) pts))
         (if start  (setq stops (cons (dm:t start origin u) stops)))
         (if finish (setq stops (cons (dm:t finish origin u) stops)))
         (setq stops (vl-sort stops '<))

         ;; Stops closer together than the merge tolerance count as one. Two
         ;; fixtures at the same spot on a run would otherwise emit a
         ;; zero-length dimension -- and measuring a column across to a wall
         ;; projects every fixture in that column onto nearly the same point,
         ;; which is one distance however many are stacked there.
         (setq ds nil)
         (foreach d stops
           (if (or (null ds) (> (abs (- d (car ds))) *dt:dm:merge-tol*))
             (setq ds (cons d ds))))
         (setq merged (- (length stops) (length ds))
               stops  (reverse ds))))

     (cond
       ((null loc) (princ "\nNo dimension line location; nothing drawn."))
       ((null u)
        (princ (strcat "\nNothing to measure along: one fixture on its own"
                       " needs a wall point to measure from,"
                       " or run FDMH / FDMV to say which way.")))
       ((< (length stops) 2)
        (princ (strcat "\nEverything lands on one point measured that way"
                       " -- nothing to dimension.")))
       (t
        (setq saved (dt:save-vars '("CMDECHO"))
              doc   (dt:undo-begin))
        (setvar "CMDECHO" 0)

        (if base
          (progn
            ;; Every dimension from the first stop, each one stacked further
            ;; out by DIMDLI, which is what DIMBASELINE itself uses. Scaled by
            ;; DIMSCALE so it matches the rest of the style; DIMSCALE 0 means
            ;; annotative, where 1.0 is the honest fallback.
            (setq perp (list (- (cadr u)) (car u))
                  step (* (getvar "DIMDLI")
                          (if (> (getvar "DIMSCALE") 0.0)
                            (getvar "DIMSCALE") 1.0))
                  i    0)
            (foreach d (cdr stops)
              (dm:draw (dm:at origin u (car stops))
                       (dm:at origin u d)
                       (list (+ (car loc) (* (car perp) step i))
                             (+ (cadr loc) (* (cadr perp) step i)))
                       square)
              (setq i (1+ i))))
          ;; Chain: one dimension per gap, every one placed on the same
          ;; dimension line, which is what DIMCONTINUE would have produced
          ;; without having to drive its prompt loop.
          (progn
            (setq i 0)
            (repeat (1- (length stops))
              (dm:draw (dm:at origin u (nth i stops))
                       (dm:at origin u (nth (1+ i) stops))
                       loc
                       square)
              (setq i (1+ i)))))

        (setq saved (dt:restore-vars saved)
              doc   (dt:undo-end doc))

        ;; The figures, so an obviously wrong one is caught here rather than on
        ;; site. Gaps in both modes -- a baseline run measures the same
        ;; spacings, it just draws them from one end.
        (setq gaps nil i 0)
        (repeat (1- (length stops))
          (setq gaps (cons (- (nth (1+ i) stops) (nth i stops)) gaps)
                i    (1+ i)))
        (princ (strcat "\n" (itoa (1- (length stops))) " dimension(s): "
                       (dm:report (reverse gaps))))
        (if (> merged 0)
          (princ (strcat "\n" (itoa merged)
                         " fixture(s) shared a point along that direction"
                         " and were dimensioned once.")))
        (if (not square)
          (princ "\nRun is not square to the drawing; dimensions are aligned."))))))
  (princ)
)

(defun c:DT-FIXDIM  () (dm:run nil))          ; direction from the fixtures
(defun c:DT-FIXDIMH () (dm:run '(1.0 0.0)))   ; across the sheet
(defun c:DT-FIXDIMV () (dm:run '(0.0 1.0)))   ; up the sheet

(defun c:FDM  () (c:DT-FIXDIM))
(defun c:FDMH () (c:DT-FIXDIMH))
(defun c:FDMV () (c:DT-FIXDIMV))

(princ)
