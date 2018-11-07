;;; companion.el --- A company-mode backend for TabNine, the all-language autocompleter: https://tabnine.com/

;; Copyright (c) 2018 Tommy Xiang

;; Author: Tommy Xiang <tommyx058@gmail.com>
;; Keywords: convenience
;; Version: 1.0.0
;; URL: https://github.com/TommyX12/company-tabnine/
;; Package-Requires: ((emacs "24.1") (company "0.8.0") (cl-lib "0.5") json unicode-escape s)

;; Permission is hereby granted, free of charge, to any person obtaining a copy
;; of this software and associated documentation files (the "Software"), to deal
;; in the Software without restriction, including without limitation the rights
;; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;; copies of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:

;; The above copyright notice and this permission notice shall be included in all
;; copies or substantial portions of the Software.

;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;; SOFTWARE.

;;; Commentary:

;; TODO

;;; Code:

;;
;; Dependencies
;;

(require 'cl-lib)
(require 'company)
(require 'json)
(require 's)
(require 'unicode-escape)

;;
;; Constants
;;

(defconst company-tabnine--process-name "company-tabnine-process")
(defconst company-tabnine--buffer-name "*company-tabnine-log*")
(defconst company-tabnine--hooks-alist nil)
(defconst company-tabnine--protocol-version "0.11.1")

;;
;; Macros
;;

;;
;; Customization
;;

(defgroup company-tabnine nil
  "Options for company-tabnine."
  :prefix "company-tabnine-")

(defcustom company-tabnine-max-num-results 10
  "Maximum number of results to show."
  :group 'company-tabnine
  :type 'integer)

(defcustom company-tabnine-context-radius 100
  "The number of chars before and after point to send for completion.
For example, setting this to 100 will send 200 chars in total per query."
  :group 'company-tabnine
  :type 'integer)

(defcustom company-tabnine-wait 0.25
  "Number of seconds to wait for TabNine to respond."
  :group 'company-tabnine
  :type 'float)

;;
;; Faces
;;

;;
;; Variables
;;

(defvar company-tabnine-executable-command
  (expand-file-name
   "binaries/0.11.1/x86_64-apple-darwin/TabNine"
   (file-name-directory load-file-name)))
(defvar company-tabnine-executable-args nil)

(defvar company-tabnine-process nil)

(defvar company-tabnine--result nil)

;;
;; Major mode definition
;;

;;
;; Global methods
;;

(defun company-tabnine-start-process ()
	"Start TabNine process."
	(company-tabnine-kill-process)
	(let ((process-connection-type nil))
		(setq company-tabnine-process
					(make-process
					 :name company-tabnine--process-name
					 :command (cons
										 company-tabnine-executable-command
										 company-tabnine-executable-args)
					 :coding 'no-conversion
					 :connection-type 'pipe
					 :filter #'company-tabnine-process-filter
           :noquery t)))
	; hook setup
	(dolist (hook company-tabnine--hooks-alist)
		(add-hook (car hook) (cdr hook))))

(defun company-tabnine-kill-process ()
	"Kill TabNine process."
	(when company-tabnine-process
		(delete-process company-tabnine-process)
		(setq company-tabnine-process nil))
  ; hook remove
	(dolist (hook company-tabnine--hooks-alist)
		(remove-hook (car hook) (cdr hook))))

(defun company-tabnine-send-request (request)
	"TODO"
	(when (null company-tabnine-process)
    (company-tabnine-start-process))
	(when company-tabnine-process
    (let ((json-null nil)
				  (json-encoding-pretty-print nil)
				  (encoded (concat (unicode-escape* (json-encode-plist request)) "\n")))
      (setq company-tabnine--result nil)
		  (process-send-string company-tabnine-process encoded)
      (accept-process-output company-tabnine-process company-tabnine-wait))))

(defun company-tabnine-query ()
	"TODO"
	(let* ((point-min 1)
         (point-max (1+ (buffer-size)))
         (before-point
          (max point-min (- (point) company-tabnine-context-radius)))
         (after-point
          (min point-max (+ (point) company-tabnine-context-radius))))

    (company-tabnine-send-request
	   (list
		  :version company-tabnine--protocol-version :request
      (list :Autocomplete
            (list
             :before (buffer-substring before-point (point))
             :after (buffer-substring (point) after-point)
             :filename (or (buffer-file-name) nil)
             :region_includes_beginning (if (= before-point point-min)
                                            json-true json-false)
             :region_includes_end (if (= before-point point-min)
                                      json-true json-false)
             :max_num_results company-tabnine-max-num-results))))))

(defun company-tabnine--decode (msg)
  "TODO"
  (let ((json-array-type 'list))
    (json-read-from-string msg)))

(defun company-tabnine-process-filter (process output)
  "TODO"
	(setq output (s-split "\n" output t))
	(setq company-tabnine--result
        (company-tabnine--decode (car (last output)))))

(defun company-tabnine--word-char-p (char)
  "TODO"
  (or
   (and (>= char ?a) (<= char ?z))
   (and (>= char ?A) (<= char ?Z))
   (and (>= char ?0) (<= char ?9))
   (= char ?_)))

(defun company-tabnine--grab-prefix ()
  "TODO"
  (let ((i (point)) (k 0) c)
    (while (and (< k company-tabnine-max-prefix-chars)
                (> i (point-min))
                (company-tabnine--word-char-p (char-before i)))
      (setq i (1- i))
      (setq k (1+ k)))
    (buffer-substring i (point))))

(defun company-tabnine--prefix ()
  "TODO"
  (if (null company-tabnine--result)
      nil
    (alist-get 'suffix_to_substitute company-tabnine--result)))

(defun company-tabnine--candidates ()
  "TODO"
  (if (null company-tabnine--result)
      nil
    (let ((results (alist-get 'results company-tabnine--result)))
      (mapcar
       (lambda (entry)
         (let ((result (alist-get 'result entry))
               (suffix (alist-get 'prefix_to_substitute entry)))
           (substring result 0 (- (length result) (length suffix)))))
        results))))

;;
;; Interactive functions
;;

(defun company-tabnine (command &optional arg &rest ignored)
  "TODO"
  (interactive (list 'interactive))
  (cl-case command
    (interactive (company-begin-backend 'company-tabnine))
    (prefix
     (company-tabnine-query)
     `(,(company-tabnine--prefix) . t))
    (candidates
     (company-tabnine--candidates))

		(no-cache t)
		(sorted t)))

;;
;; Advices
;;

;;
;; Hooks
;;



(provide 'company-tabnine)
;;; company-tabline.el ends here