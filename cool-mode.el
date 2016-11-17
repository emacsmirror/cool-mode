;;; cool-mode --- Major mode for cool compiler language editing

;; Author: Noah Peart <noah.v.peart@gmail.com>
;; URL: https://github.com/nverno/cool-mode
;; Package-Requires: 
;; Copyright (C) 2016, Noah Peart, all rights reserved.
;; Created: 13 October 2016

;; This file is not part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 3, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth
;; Floor, Boston, MA 02110-1301, USA.

;;; Commentary:

;; [![Build Status](https://travis-ci.org/nverno/cool-mode.svg?branch=master)](https://travis-ci.org/nverno/cool-mode)

;;; Description:

;;  Editing mode for cool compiler language.

;; TODO:
;; - compiler/assembler
;; - case-insensitive keywords only
;; - annotate company

;;; Code:
(eval-when-compile
  (require 'cl-lib))
(require 'smie)
(require 'cool-completion)

(defgroup cool nil
  "Major mode for cool compiler language files."
  :link '(custom-group-link :tag "Font Lock Faces group" font-lock-faces)
  :group 'languages)

(defcustom cool-indent-offset 2
  "Default number of spaces to indent in `cool-mode'."
  :type 'integer
  :group 'cool)
;;;###autoload (put 'cool-indent-offset 'safe-local-variable 'integerp)

(defcustom cool-compiler "coolc"
  "Cool compiler."
  :type 'string
  :group 'cool)

(defcustom cool-assembler "spim"
  "Cool assembler."
  :type 'string
  :group 'cool)

(defcustom cool-dynamic-complete-functions nil
  "Functions for dynamic completion."
  :type '(repeat function)
  :group 'cool)

;;--- Font-Locking ---------------------------------------------------

(defun cool-syms-re (syms)
  (concat "\\_<" (regexp-opt syms t) "\\_>"))

;; type/class names start with uppercase letter
;; "IO" "Object" "String" "SELF_TYPE" "Int" "Bool"
(defconst cool-type-name-re "\\([A-Z][A-Z0-9a-z_]*\\)")

(defvar cool-font-lock-keywords
  ;; FIXME: keywords are case-insensitive, but constants are not (true, false)
  (let ((keywords '("class" "else" "fi" "if" "in" "inherits" "isvoid" "let" "loop"
                    "pool" "then" "while" "case" "esac" "new" "of" "not"))
        (builtins '("length" "concat" "substr" "abort" "type_name" "copy"
                    "new" "out_string" "out_int" "in_string" "in_int" "self"))
        (constants '("true" "false")))
    `((,(cool-syms-re keywords) . font-lock-keyword-face)
      (,(cool-syms-re builtins) . font-lock-builtin-face)
      (,(cool-syms-re constants) . font-lock-constant-face)
      ;; Features (methods or attributes) must start with lowercase letter
      ("\\([[:alnum:]_]+\\)\\s *(" (1 font-lock-function-name-face))
      ;; variables
      (,(concat "\\([[:alnum:]_]+\\)[ \t]*\\(?::\\s-*" cool-type-name-re "[ \t]*\\|<-\\)")
       (1 font-lock-variable-name-face))
      ("\\([[:alnum:]_]+\\)[.]" (1 font-lock-variable-name-face))
      ;; types / classes
      (,(concat
         "\\(?:\\<\\(?:class\\|inherits\\|new\\)\\>\\|\\:\\)[ \t]*" 
         cool-type-name-re)
       (1 font-lock-type-face))
      ;; type conversion
      (,(concat "\\.\\s *(" cool-type-name-re)
       (1 font-lock-type-face))))
  "Default expressions to font lock in cool-mode.")

;; nested comments, unusual string escape sequences -- sml-mode
(defvar cool-syntax-prop-table
  (let ((st (make-syntax-table)))
    (modify-syntax-entry ?\\ "." st)
    (modify-syntax-entry ?* "." st)
    st)
  "Syntax table for text-properties.")

(defconst cool-font-lock-syntactic-keywords
  `(("^\\s-*\\(\\\\\\)" (1 ',cool-syntax-prop-table))))

(defconst cool-font-lock-defaults
  '(cool-font-lock-keywords
    nil nil nil nil
    (font-lock-syntactic-keywords . cool-font-lock-syntactic-keywords)))

;;--- Indentation ----------------------------------------------------

;; smie references
;; #<marker at 52833 in smie.el>
;; #<marker at 14780 in sml-mode.el>
;; #<marker at 67654 in sh-script.el>
;; #<marker at 11868 in ruby-mode.el>

;; precedence: high -> low
;; . @ ~ isvoid [* /] [+ -] [<= < =] not <-

;; binary ops are left-associative, except assignment <- is right
;; comparison ops are nonassoc

(defconst cool-smie-grammar
  (smie-prec2->grammar
   (smie-merge-prec2s
    (smie-bnf->prec2
     '((id)
       (exp ("if" exp "then" exp "else" exp "fi")
            ("while" exp "loop" exp "pool")
            ("let" exp "in" exp)
            ("case" exp "of" branches "esac"))
       (branches (id "=>" exp) (branches ";" branches)))
     '((right ";")))
    (smie-precs->prec2
     '((assoc ",") (assoc " ") (nonassoc "=>"))))))

(defun cool-smie-rules (kind token)
  (pcase (cons kind token)
    (`(:elem . basic) cool-indent-offset)
    (`(:elem . args) 0)
    (`(:list-intro . ,(or `"\n" `"" `";")) t)
    ;; (`(:close-all . ,_) t)
    ;; "else if", cant put two non-terminals in a row in bnf
    (`(:before . "if")
     (if (smie-rule-prev-p "else")
         (smie-rule-parent)))
    (`(:before . "=>") cool-indent-offset)
    (`(:after . "else")
     (if (and (smie-rule-hanging-p) (smie-rule-next-p "if")) 0))
    (`(:after . "(") (if (and (smie-rule-next-p "let")) 1))
    (`(:after . "{") (if (smie-rule-hanging-p) cool-indent-offset))
    ))

;;--- Syntax ---------------------------------------------------------

;; comments '--' or '(*', '*)', latter are nestable
(defvar cool-mode-syntax-table
  (let ((st (make-syntax-table)))
    (modify-syntax-entry ?- ". 12b" st)
    (modify-syntax-entry ?\n "> b" st)
    (modify-syntax-entry ?\* ". 23c" st)
    (modify-syntax-entry ?\( "( 1cn" st)
    (modify-syntax-entry ?\) ") 4cn" st)
    (modify-syntax-entry ?_ "_" st)
    (modify-syntax-entry ?+ "." st)
    (modify-syntax-entry ?~ "." st)
    (modify-syntax-entry ?= "." st)
    (modify-syntax-entry ?< "." st)
    (modify-syntax-entry ?> "." st)
    (modify-syntax-entry ?\/ "." st)
    st))

;;--- Interactive Functions ------------------------------------------

;; compile
(defun cool-compile ()
  "Compile current file with `cool-compiler'."
  (interactive)
  (let ((compile-command
         (format "%s %s" cool-compiler buffer-file-name))
        (compilation-read-command))
    (call-interactively 'compile)))

(defun cool-compile-and-run ()
  "Compile and run current file, showing output in *cool-output*."
  (interactive)
  (call-interactively 'cool-compile)
  (async-shell-command
   (format "%s %s.s" cool-assembler
           (file-name-sans-extension buffer-file-name))
   "*cool-output*"))

;; comment as multi-line box if region spans more than one line,
;; otherwise use single line comment
(defun cool-comment-dwim (arg)
  (interactive "*P")
  (comment-normalize-vars)
  (if (use-region-p)
      (let* ((start (save-excursion
                      (goto-char (region-beginning))
                      (while (looking-at-p "\\s-*$")
                        (forward-line))
                      (point-at-eol)))
             (end (save-excursion
                    (goto-char (region-end))
                    (skip-chars-backward " \n\t\r")
                    (point)))
             (multi (> end start))
             (comment-style (if multi 'multi-line 'indent))
             (comment-start (if multi "(* " "-- "))
             (comment-end (if multi " *)" "")))
        (comment-dwim arg))
    (comment-dwim arg)))

;; add " * " after newline in "(* ... *)" comment blocks
(defun cool-newline-dwim ()
  (interactive)
  (let ((ppss (syntax-ppss)))
    (cond
     ((and (nth 4 ppss)
           (save-excursion
             (forward-line 0)
             (looking-at-p " *\\(?:(\\*\\|\\*\\)")))
      (when (save-excursion
              (end-of-line)
              (looking-back "\\*) *" (line-beginning-position)))
        (save-excursion
          (newline-and-indent)))
      (newline)
      (insert " * ")
      (indent-according-to-mode))
     (t (newline)
        (indent-according-to-mode)))))

;;--- Major Mode -----------------------------------------------------

(defvar cool-menu
  '("Cool"
    ["Compile" cool-compile t]
    ["Compile and Run" cool-compile-and-run t]))

(defvar cool-mode-map
  (let ((km (make-sparse-keymap)))
    (easy-menu-define nil km nil cool-menu)
    (define-key km (kbd "RET")     #'cool-newline-dwim)
    (define-key km (kbd "M-;")     #'cool-comment-dwim)
    (define-key km (kbd "<f5>")    #'cool-compile)
    (define-key km (kbd "C-c C-c") #'cool-compile-and-run)
    km))

(define-abbrev-table 'cool-mode-abbrev-table ())

;;;###autoload
(define-derived-mode cool-mode prog-mode "Cool"
  "Major mode for editing cool source code.\n
\\{cool-mode-map\}"
  (setq-local local-abbrev-table cool-mode-abbrev-table)
  (setq-local font-lock-defaults cool-font-lock-defaults)
  (setq-local comment-start "-- ")
  (setq-local comment-end "")
  (setq-local comment-start-skip "\\(?:--+\\|(\\*+\\)\\s-*")
  (setq-local comment-end-skip "\\s-*\\*+)")
  (setq-local comment-quote-nested nil)

  ;; indentation
  (smie-setup cool-smie-grammar #'cool-smie-rules
              :backward-token #'smie-default-backward-token
              :forward-token #'smie-default-forward-token)

  ;; completion
  (add-hook 'completion-at-point-functions
            #'cool-completion-at-point-function nil t))

;; not using .cl because of common-lisp
;;;###autoload
(add-to-list 'auto-mode-alist (cons "\\.cool$" #'cool-mode))

(provide 'cool-mode)

;;; cool-mode.el ends here
