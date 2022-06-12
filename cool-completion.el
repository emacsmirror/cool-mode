;;; cool-completion.el --- Completion for cool-mode  -*- lexical-binding: t; -*-

;; This is free and unencumbered software released into the public domain.

;; Author: Noah Peart <noah.v.peart@gmail.com>
;; URL: https://github.com/nverno/cool-mode
;; Created: 14 October 2016
;; Version: 1.0.0

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

;;  Some completion support for `cool-mode'.

;;; Code:
(eval-when-compile (require 'cl-lib))
(require 'company nil t)

(defconst cool-completion-keywords
  '("class"  "else"       "false"    "fi"    "if"
    "in"     "inherits"   "isvoid"   "let"   "loop"
    "pool"   "then"       "while"    "case"  "esac"
    "new"    "of"         "not"      "true"
    "Int" "IO" "String" "SELF_TYPE" "Bool" "Object"
    "length" "concat" "substr" "abort" "type_name" "copy"
    "new" "out_string" "out_int" "in_string" "in_int"
    "self" "true" "false"))

(defconst cool-completion-types '("IO" "Object" "String" "SELF_TYPE" "Int" "Bool"))

;; completion at point

(defun cool-completion--types ()
  "Return list of types identified in current buffer, plus builtins."
  (save-excursion
    (goto-char (point-min))
    (let ((vars cool-completion-types))
      (while
          (re-search-forward
           "\\(?:\\<\\(?:class\\|inherits\\|new\\)\\>\\)[ \t]*\\([A-Z]\\w*\\)"
           nil t)
        (cl-pushnew (match-string-no-properties 1) vars :test #'string=))
      vars)))

(defun cool-completion-at-point-function ()
  "Cool mode `completion-at-point' function."
  (save-excursion
    (skip-chars-forward "A-Za-z_")
    (let ((end (point))
          (_ (skip-chars-backward "A-Za-z_"))
          (start (point)))
      (cond
       ((looking-back ":[ \t]*" (line-beginning-position))
        (list start end (cool-completion--types)))))))

;; company keywords

(defvar company-keywords-alist)

;;;###autoload
(defun cool-completion-company-add-keywords ()
  "Add Cool keywords to `company-keywords-alist'."
  (setcdr
   (nthcdr (1- (length company-keywords-alist)) company-keywords-alist)
   `(,(append '(cool-mode) cool-completion-keywords))))

;;;###autoload
(with-eval-after-load 'company-keywords
  (when (not (assq 'cool-mode company-keywords-alist))
    (cool-completion-company-add-keywords)))

(provide 'cool-completion)

;;; cool-completion.el ends here
