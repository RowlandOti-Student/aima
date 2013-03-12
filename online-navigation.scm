
;; [[file:~/prg/scm/aima/aima.org::*Simulation][Simulation:1]]

(use aima-tessellation
     animation
     define-record-and-printer
     debug
     files
     format
     miscmacros
     random-bsd
     shell
     srfi-95
     stack)

(define-record-and-printer agent
  point
  score
  program)

(define zero-motion (make-point 0 0))
(define (zero-motion? move) (equal? move zero-motion))

(define origin (make-point 0 0))
(define (origin? move) (equal? move zero-motion))

(define-record-and-printer stop)
(define stop (make-stop))

(define (write-dot-preamble width height title score)
 (display "digraph G {")
 (display "node [shape=point];")
 (let ((width-in-inches (/ width 96))
       (height-in-inches (/ height 96)))
   (format #t "graph [fontsize=48, label=\"~a (Score: ~,2f)\", ratio=fill, viewport=\"~a,~a\", size=\"~a,~a!\", labelloc=t];"
           title
           score
           (* width-in-inches 72)
           (* height-in-inches 72)
           width-in-inches
           height-in-inches)))

;;; Oh, shit; we're going to have to assign absolute points here
;;; starting arbitrarily with the first node.
;;;
;;; Unless we have some kind of path, this is problematic; should we
;;; assign absolute coördinates as we discover them?
;;;
;;; Christ, maybe we should label these things as we find them, too.
;;;
;;; No, in order to coordinates rigorously; we're going to have to
;;; backtrack. Can we update as we go along? The map may change,
;;; depending on what root we find.
;;;
;;; No; let's wipe the absolute coordinates clean every time we
;;; teleport, but keep the relative ones.
(define (write-agent-as-dot points
                            coordinates
                            labels
                            result
                            untried
                            unbacktracked
                            previous-state
                            previous-action
                            start
                            goal
                            score)
  (write-dot-preamble 1600 900 "Online DFS" score)
  (let ((displayed (make-hash-table))
        (linear-scale (* 5 72)))
    (define (node-maybe-display state label)
      (hash-table-update!
       displayed
       state
       identity
       (lambda ()
         (let ((coordinate
                (coordinate-point
                 (hash-table-ref coordinates state))))
           (format #t "~a [pos=\"~a,~a\"~a];"
                   label
                   (* (point-x coordinate) linear-scale)
                   (* (point-y coordinate) linear-scale)
                   (cond ((equal? state start)
                          ", shape=circle, label=S")
                         ((equal? state goal)
                          ", shape=circle, label=G")
                         (else ""))))
         #t)))
    (hash-table-walk result
      (lambda (whence whither->action)
        (hash-table-walk whither->action
          (lambda (whither action)
            (let ((whence-label
                   (hash-table-ref labels whence))
                  (whither-label
                   (hash-table-ref labels whither)))
              (node-maybe-display whence whence-label)
              (node-maybe-display whither whither-label)
              (format #t "~a -> ~a [color=~a, penwidth=~a];"
                      whence-label
                      whither-label
                      (if (equal? whence previous-state)
                          "orange"
                          "blue")
                      (if (equal? whence previous-state)
                          2
                          1))))))))
  (display "}"))

(define (write-agent-as-png png
                            points
                            coordinates
                            labels
                            result
                            untried
                            unbacktracked
                            previous-state
                            previous-action
                            start
                            goal
                            score)
  (let ((dot (create-temporary-file ".dot")))
    (with-output-to-file dot
      (lambda () (write-agent-as-dot points
                                coordinates
                                labels
                                result
                                untried
                                unbacktracked
                                previous-state
                                previous-action
                                start
                                goal
                                score)))
    (run (neato -n1 -Tpng -o ,png < ,dot))))

(define-record-and-printer coordinate
  point
  time)

(define (simulate-navigation make-agent
                             #!key
                             (n-points 50)
                             (n-steps 1000)
                             (p-slippage 0)
                             (animation-file #f))
  (let ((world (tessellate n-points)))
    (let ((points (tessellation-points world))
          (neighbors (tessellation-neighbors world))
          (goal (tessellation-end world)))
      ;; (debug (length points))
      (receive (next-frame finalize!)
        (make-animator)
        (let* ((start (list-ref points (random (length points))))
               (agent (make-agent start next-frame)))
          (dotimes (step n-steps agent)
            (let* ((agent-point (agent-point agent))
                   (visible-points (hash-table-ref neighbors agent-point))
                   (relative-points
                    (map (lambda (point)
                           (make-point (- (point-x point) (point-x agent-point))
                                       (- (point-y point) (point-y agent-point))))
                         visible-points)))
              (let* ((goal? (equal? agent-point goal))
                     (move (if (< (random-real) p-slippage)
                               (list-ref relative-points (random (length relative-points)))
                               ((agent-program agent) relative-points goal? (agent-score agent)))))
                (debug move)
                (let* ((relative->visible-points
                        (alist->hash-table (zip relative-points visible-points)))
                       (new-point
                        (if (and (zero-motion? move) goal?)
                            (begin
                              (agent-score-set! agent (+ (agent-score agent) 1000))
                              (list-ref points (random (length points))))
                            (if (stop? move)
                                (error "Stop!")
                                (begin
                                  (agent-score-set! agent (- (agent-score agent)
                                                             (point-distance zero-motion move)))
                                  (make-point (+ (point-x move) (point-x agent-point))
                                              (+ (point-y move) (point-y agent-point)))
                                  (car (hash-table-ref relative->visible-points move)))))))
                  (if goal? (debug (agent-score agent)))
                  (agent-point-set! agent new-point)))))
          (debug (agent-score agent))
          (when animation-file
            (finalize! animation-file)
            (run (mplayer -loop 0 ,animation-file))))))))

;; Simulation:1 ends here
