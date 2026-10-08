;;; ======================================================
;;; DT-LABELS.LSP  --  GENERATED FILE, DO NOT EDIT.
;;;
;;; Written by DT-SETPREFIX, DT-SETROW, DT-SETORDER and
;;; DT-SETLETTERS. Loaded after dt-config.lsp, so what is
;;; here overrides the defaults recorded there.
;;;
;;;   (group . prefix)   and the groups that count A, B, C
;;;
;;; A group not listed uses the prefix in *dt:lbl:format*.
;;; To change one, run the command again. To go back to the
;;; config defaults, delete this file.
;;; ======================================================

(setq *dt:lbl:prefix-overrides*
  '(
    ("PL-" . "PL-")
    ("C.MM." . "C.MM.")
    ("C.PS." . "C.PS.")
    ("C.PBS." . "C.PBS.")
    ("C.EB." . "C.EB.")
    ("C.TRB." . "C.TRB.")
    ("C.PN." . "C.PN.")
    ("C.PCL." . "C.PCL.")
    ("C.PL." . "C.PL.")
    ("C.PNA" . "C.PNA.")
    ("C.PNA." . "C.PNA.")
    ("C.PLA." . "C.PLA.")
    ("C.PCLA." . "C.PCLA.")
    ("N.PN" . "NIVEL.")
    ("N.PCL" . "NIVEL.")
    ("N.PL" . "NIVEL.")
    ("N.PNA" . "NIVEL.")
    ("N.PCLA" . "NIVEL.")
    ("N.PLA" . "NIVEL.")
    ("N.PNS" . "NIVEL.-")
    ("N.PCLS" . "NIVEL.-")
    ("N.PLS" . "NIVEL.-")
    ("C.PNS" . "C.PNS.")
    ("C.PNS." . "C.PNS.")
    ("C.PCLS." . "C.PCLS.")
    ("C.PLS." . "C.PLS.")
    ("C.BOM." . "C.BOM.")
    ("C.PA/A." . "C.PA/A.")
    ("C.A/A." . "C.PA/A.")
    ("C.HVAC" . "C.HVAC.")
    ("C.HVAC." . "C.HVAC.")
    ("PO" . "PO-")
    ("NOF1" . "NIVEL.")
    ("POF2" . "NIVEL.")
    ("NOF2" . "NIVEL.")
    ("PCL3" . "PCL3-")
    ("PCL1" . "PCL1-")
    ("PO-" . "PO")
    ("PO-IL-" . "PO")
   )
)

(setq *dt:lbl:row-tol* 23.623310)

(setq *dt:lbl:order* 'DATABASE)

(setq *dt:lbl:skip-groups*
  '(
    "IL_DER"
    "IL-DER"
   )
)

(setq *dt:lbl:pad-overrides*
  '(
    ("PO-" . 1)
    ("PO-IL-" . 1)
    ("IL-IZQ" . 1)
    ("IL-DER" . 1)
    ("IL-DER-GP2" . 1)
    ("LIGTH-TIPO-B" . 1)
   )
)

(setq *dt:lbl:letter-groups*
  '(
    "LUCESCOMUNN1"
    "LUCESCOMUNN2"
    "IL-IZQ"
    "IL-DER"
    "IL-DER-GP2"
    "LIGTH-TIPO-B"
   )
)

(princ)
