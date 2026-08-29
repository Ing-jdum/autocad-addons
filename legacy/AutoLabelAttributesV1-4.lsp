;;---------------------=={ AutoLabel Attributes }==---------------------;;
;;                     MULTI-BLOCK VERSION - FIXED                      ;;
;;----------------------------------------------------------------------;;

(setq

;;----------------------------------------------------------------------;;
;;                    CONFIGURATION - EDIT HERE                         ;;
;;----------------------------------------------------------------------;;

    autolabel:blocks '(
        (
            "AUTO_LABEL_CIRCUIT"        ;; Block name
            "NUMBER"                           ;; Attribute tag
            ""                              ;; Prefix
            ""                              ;; Suffix
            1                               ;; Starting number
            2                               ;; Length (padding zeros: 0=none, 3=01)
        )
	(
            "SELF_COUNT_PANEL"        ;; Block name
            "NUMBER"                           ;; Attribute tag
            ""                              ;; Prefix
            ""                              ;; Suffix
            1                               ;; Starting number
            2                               ;; Length (padding zeros: 0=none, 3=01)
        )
    )
    
    autolabel:startup   t                   ;; Enable on startup

;;----------------------------------------------------------------------;;

)

;;----------------------------------------------------------------------;;
;;                            Main Functions                            ;;
;;----------------------------------------------------------------------;;

(defun autolabel:padzeros (str len)
    (if (< (strlen str) len)
        (autolabel:padzeros (strcat "0" str) len)
        str
    )
)

(defun autolabel:renumberallblocks ()
    "Renumber all configured blocks"
    (foreach block-cfg autolabel:blocks
        (autolabel:renumberblock block-cfg)
    )
)

(defun autolabel:renumberblock (cfg / sel num idx obj att bname btag prefix suffix start len)
    "Renumber specific block type"
    (setq bname   (nth 0 cfg)
          btag    (nth 1 cfg)
          prefix  (nth 2 cfg)
          suffix  (nth 3 cfg)
          start   (nth 4 cfg)
          len     (nth 5 cfg)
    )
    
    ;; Find all instances of this block
    (if (setq sel (ssget "_X"
            (list
                '(-4 . "<AND")
                '(0 . "INSERT")
                '(66 . 1)
                (cons 2 (strcat "`*U*," bname))
                '(-4 . "AND>")
                (if (= 1 (getvar 'cvport))
                    (cons 410 (getvar 'ctab))
                    '(410 . "Model")
                )
            )
        ))
        (progn
            (setq num start)
            (repeat (setq idx (sslength sel))
                (setq obj (vlax-ename->vla-object (ssname sel (setq idx (1- idx)))))
                
                ;; Get attribute
                (if (vlax-method-applicable-p obj 'getattributes)
                    (setq att
                        (vl-some
                            '(lambda (a)
                                (if (= (strcase (vla-get-tagstring a)) (strcase btag)) a)
                            )
                            (vlax-invoke obj 'getattributes)
                        )
                    )
                )
                
                ;; Update attribute value
                (if att
                    (progn
                        (vla-put-textstring att
                            (strcat
                                prefix
                                (autolabel:padzeros (itoa num) len)
                                suffix
                            )
                        )
                        (setq num (1+ num))
                    )
                )
            )
        )
    )
)

;;----------------------------------------------------------------------;;
;;                         Reactor Callbacks                            ;;
;;----------------------------------------------------------------------;;

(defun autolabel:undocheck (rtr arg)
    (setq autolabel:undoflag (= (strcase (car arg) t) "undo"))
    (princ)
)

(defun autolabel:aftercommand (rtr arg)
    (if (not autolabel:undoflag)
        (autolabel:renumberallblocks)
    )
    (princ)
)

(defun autolabel:aftermodify (own rtr arg)
    (if (not autolabel:undoflag)
        (autolabel:renumberallblocks)
    )
    (princ)
)

;;----------------------------------------------------------------------;;
;;                      Enable/Disable Functions                        ;;
;;----------------------------------------------------------------------;;

(defun autolabel:disable (key)
    (foreach grp (vlr-reactors :vlr-command-reactor :vlr-object-reactor)
        (foreach obj (cdr grp)
            (if (= key (vlr-data obj)) (vlr-remove obj))
        )
    )
    (setq autolabel:undoflag       nil
          autolabel:objectreactor  nil
          autolabel:commandreactor nil
    )
)

(defun autolabel:enable (key)
    (autolabel:disable key)
    
    ;; Object Reactor
    (vlr-set-notification
        (setq autolabel:objectreactor
            (vlr-object-reactor nil key
                '(
                    (:vlr-erased   . autolabel:aftermodify)
                    (:vlr-copied   . autolabel:aftermodify)
                    (:vlr-unerased . autolabel:aftermodify)
                )
            )
        )
        'active-document-only
    )
    
    ;; Command Reactor
    (vlr-set-notification
        (vlr-command-reactor key
            '(
                (:vlr-commandwillstart . autolabel:undocheck)
                (:vlr-commandended     . autolabel:aftercommand)
            )
        )
        'active-document-only
    )
    
    ;; Initial renumbering
    (autolabel:renumberallblocks)
    
    (princ "\nAutoLabel enabled for all blocks.")
    (princ)
)

;;----------------------------------------------------------------------;;
;;                         User Commands                                ;;
;;----------------------------------------------------------------------;;

(defun c:autolabelon nil
    (autolabel:enable "autolabel")
)

(defun c:autolabeloff nil
    (autolabel:disable "autolabel")
    (princ "\nAutoLabel disabled.")
    (princ)
)

;;----------------------------------------------------------------------;;
;;                      Initialization                                  ;;
;;----------------------------------------------------------------------;;

(vl-load-com)
(if autolabel:startup (autolabel:enable "autolabel"))

(princ "\nAutoLabel Multi-Block loaded.")
(princ)

;;----------------------------------------------------------------------;;
;;                       Custom COPY Command                            ;;
;;----------------------------------------------------------------------;;

(defun c:COPY ( / )
    "Custom COPY command with auto-renumbering"
    (command "._COPY")
    (autolabel:renumberallblocks)
    (princ "\nCopy complete - blocks renumbered.")
    (princ)
)

(defun c:CN ( / )
    "Shortcut for COPY with auto-renumbering (CN = Copy Number)"
    (c:COPY)
)

;;----------------------------------------------------------------------;;
;;                             End of File                              ;;
;;----------------------------------------------------------------------;