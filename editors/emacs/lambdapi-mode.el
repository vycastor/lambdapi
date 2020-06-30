;;; lambdapi-mode.el --- A major mode for editing Lambdapi source code -*- lexical-binding: t; -*-

;; Copyright (C) 2020 Deducteam

;; Author: Rodolphe Lepigre, Gabriel Hondet
;; Maintainer: Deducteam <dedukti-dev@inria.fr>
;; Version: 1.0
;; SPDX-License-Identifier: CeCILL Free Software License Agreement v2.1
;; Homepage: https://github.com/Deducteam/lambdapi
;; Keywords: languages
;; Compatibility: GNU Emacs 26.1
;; Package-Requires: ((emacs "26.1") (eglot "1.5") (math-symbol-lists "1.2.1"))

;;; Commentary:

;;  A major mode for editing Lambdapi source code. This major mode provides
;;  indentation, syntax highlighting, completion, easy unicode input, and more.

;;; Code:

(require 'lambdapi-vars)
(require 'lambdapi-smie)
(require 'lambdapi-capf)
(require 'lambdapi-abbrev)
(require 'lambdapi-input)
(require 'highlight)
(require 'eglot)
;;; Legacy
;; Syntax table (legacy syntax)
(defvar lambdapi-mode-legacy-syntax-table nil "Syntax table for LambdaPi.")

(setq lambdapi-mode-legacy-syntax-table
  (let ((syn-table (make-syntax-table)))
    (modify-syntax-entry ?\( "()1n" syn-table)
    (modify-syntax-entry ?\) ")(4n" syn-table)
    (modify-syntax-entry ?\; ". 23" syn-table)
    syn-table))

;; Keywords (legacy syntax)
(defconst lambdapi-legacy-font-lock-keywords
  (list
   (cons
    (concat
     "\\<"
     (regexp-opt '("def" "thm" "inj"))
     "\\>") 'font-lock-keyword-face)
   (cons
    (concat
     "#"
     (regexp-opt '("REQUIRE" "EVAL" "INFER" "ASSERT" "ASSERTNOT"))
     "\\>") 'font-lock-preprocessor-face))
  "Keyword highlighting for the LambdaPi mode (legacy syntax).")


;; Main function creating the mode (legacy syntax)
;;;###autoload
(define-derived-mode lambdapi-legacy-mode prog-mode "LambdaPi (legacy)"
  "A mode for editing LambdaPi files (in legacy syntax)."
  (set-syntax-table lambdapi-mode-legacy-syntax-table)
  (setq-local font-lock-defaults '(lambdapi-legacy-font-lock-keywords))
  (setq-local comment-start "(;")
  (setq-local comment-end ";)")
  (setq-default indent-tabs-mode nil)
  (add-to-list 'eglot-server-programs
               '(lambdapi-legacy-mode . ("lambdapi" "lsp" "--standard-lsp")))
  (eglot-ensure))

(provide 'lambdapi-legacy-mode)

;;; lambdapi
;; Keywords
(defconst lambdapi-font-lock-keywords
  (list (cons
         (concat "\\<" (regexp-opt lambdapi-sig-commands) "\\>")
         'font-lock-keyword-face)
        (cons
         (concat "\\<" (regexp-opt lambdapi-misc-commands) "\\>")
         'font-lock-preprocessor-face)
        (cons
         (concat "\\<" (regexp-opt lambdapi-tactics) "\\>")
         'font-lock-builtin-face)
        (cons
         (concat "\\<" (regexp-opt lambdapi-warning) "\\>")
         'font-lock-warning-face)
        (cons
         (concat "\\<" (regexp-opt lambdapi-misc-keywords) "\\>")
         'font-lock-constant-face))
  "Keyword highlighting for the LambdaPi mode.")

(defconst lp-goal-line-prefix "---------------------------------------------------")

(defun display-goals (goals)
  (let ((goalsbuf (get-buffer-create "*Goals*")))
    (with-current-buffer goalsbuf
      (read-only-mode -1)
      (if (> (length goals) 0)
          (let* ((fstgoal  (elt goals 0))
                 (hs       (plist-get fstgoal :hyps))
                 (hypsstr  (mapcar
                            (lambda (hyp)
                              (let ((name (plist-get hyp :hname))
                                    (type (plist-get hyp :htype)))
                                (format "%s: %s\n" name type)))
                            (reverse hs)))
                 (goalsstr (mapcar
                            (lambda (goal)
                              (let ((id (plist-get goal :gid))
                                    (type (plist-get goal :type)))
                                (format "%s\nGoal %d: %s\n\n" lp-goal-line-prefix id type)))
                            goals)))
            (erase-buffer)
            (goto-char (point-max))
            (mapc 'insert hypsstr)
            (mapc 'insert goalsstr))
        (erase-buffer))
      (read-only-mode 1))))

(defun eglot--signal-proof/goals (position)
  "Send proof/goals to server."
  (let ((server (eglot-current-server))
        (params `(:textDocument ,(eglot--TextDocumentIdentifier)
                  :position ,position)))
    (if server
        (let ((response (jsonrpc-request server :proof/goals params)))
          (if response
              (display-goals (plist-get response :goals))
            (let ((goalsbuf (get-buffer-create "*Goals*")))
              (with-current-buffer goalsbuf
                (read-only-mode -1)
                (erase-buffer)
                (read-only-mode 1))))))))

(defun lp-display-goals ()
  (interactive)
  (eglot--signal-proof/goals (eglot--pos-to-lsp-position)))

(defvar proof-line-position (list :line 0 :character 0))
(defvar interactive-goals 't)

(defun move-proof-line (move-fct)
  (save-excursion
    (let ((line (plist-get proof-line-position :line)))
      (setq proof-line-position (eglot--widening
                                 (list :line (funcall move-fct line) :character 0)))
      (goto-line line)
      (hlt-unhighlight-region (line-beginning-position) (line-end-position))
      (goto-line (funcall move-fct line))
      (hlt-highlight-region (line-beginning-position) (line-end-position))
      (lp-display-goals))))

(defun lp-proof-forward ()
  (interactive)
  (move-proof-line #'1+))

(defun lp-proof-backward ()
  (interactive)
  (move-proof-line #'1-))

(defun toggle-interactive-goals ()
  (interactive)
  (save-excursion
    (let ((line (plist-get proof-line-position :line)))
      (if interactive-goals
          (progn
              (setq proof-line-position (eglot--widening
                                         (list :line (line-number-at-pos) :character 0)))
              (goto-line (line-number-at-pos))
              (hlt-highlight-region (line-beginning-position) (line-end-position)))
        (progn
          (goto-line line)
          (hlt-unhighlight-region (line-beginning-position) (line-end-position))))))
  (setq interactive-goals (not interactive-goals)))

;; Hook to be run when changing line
;; From https://emacs.stackexchange.com/questions/46081/hook-when-line-number-changes
(defvar current-line-number (line-number-at-pos))
(defvar changed-line-hook nil)

(defun update-line-number ()
  (if interactive-goals
      (let ((new-line-number (line-number-at-pos)))
        (when (not (equal new-line-number current-line-number))
          (setq current-line-number new-line-number)
          (run-hooks 'changed-line-hook)))))

(defun create-goals-buffer ()
  (let ((goalsbuf (get-buffer-create "*Goals*"))
        (goalswindow (split-window nil -10 'below)))
    (set-window-buffer goalswindow goalsbuf)
    (set-window-dedicated-p goalswindow 't)))

;; Main function creating the mode (lambdapi)
;;;###autoload
(define-derived-mode lambdapi-mode prog-mode "LambdaPi"
  "A mode for editing LambdaPi files."
  (set-syntax-table lambdapi-syntax-table)
  (setq-local font-lock-defaults '(lambdapi-font-lock-keywords))
  (setq-default indent-tabs-mode nil) ; Indent with spaces
  (set-input-method "LambdaPi")

  ;; Comments
  (setq-local comment-start "//")
  (setq-local comment-end "")

  ;; Completion
  (lambdapi-capf-setup)

  ;; Indentation
  (smie-setup
   lambdapi--smie-prec
   'lambdapi--smie-rules
   :forward-token #'lambdapi--smie-forward-token
   :backward-token #'lambdapi--smie-backward-token)
  ;; Reindent on colon
  (electric-indent-mode -1) ; Disable electric indent by default
  (setq-local electric-indent-chars (append '(?↪ ?≔ ?:) electric-indent-chars))

  ;; Abbrev mode
  (lambdapi-abbrev-setup)

  ;; LSP
  (add-to-list
   'eglot-server-programs
   '(lambdapi-mode . ("lambdapi" "lsp" "--standard-lsp")))
  (eglot-ensure)

  ;; Hooks for goals
  (add-hook 'post-command-hook #'update-line-number nil :local)
  ;; Hook binding line change to re-execution of proof/goals
  (add-hook 'changed-line-hook #'lp-display-goals)
  (create-goals-buffer))

;; Register mode the the ".lp" extension
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.lp\\'" . lambdapi-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.dk\\'" . lambdapi-legacy-mode))

;; Keybinding for goals display
(global-set-key (kbd "C-x C-d") 'lp-display-goals)
(global-set-key (kbd "C-M-c")   'toggle-interactive-goals)
(global-set-key (kbd "<M-up>")  'lp-proof-backward)
(global-set-key (kbd "<M-down>") 'lp-proof-forward)

(provide 'lambdapi-mode)
;;; lambdapi-mode.el ends here
