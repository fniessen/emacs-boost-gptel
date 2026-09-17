;;; gptel-tools-test.el --- ERT tests for GPTel tools -*- lexical-binding: t; -*-

;; This file is generated to test each GPTel tool defined in emacs-boost-gptel.
;; Run with M-x ert RET t RET

(require 'ert)
(require 'emacs-boost-gptel)
(require 'org)

(defmacro with-temp-gptel-roots (&rest body)
  "Temporarily bind `boost-gptel-root' and `boost-gptel-note-directory' to a temp dir."
  `(let* ((temp-root (make-temp-file "gptel-test-root" t))
          (boost-gptel-root temp-root)
          (boost-gptel-note-directory temp-root))
     ,@body))

;;; Emacs runtime tools

(ert-deftest boost-gptel-test-emacs-version ()
  "emacs-version should return a non-empty string."
  (should (stringp (boost-gptel--emacs-version)))
  (should (> (length (boost-gptel--emacs-version)) 0)))

(ert-deftest boost-gptel-test-symbol-exists ()
  "symbol_exists should detect interned symbols."
  (should (equal (boost-gptel--symbol-exists "car") "true"))
  (should (equal (boost-gptel--symbol-exists "nonexistent-symbol-xyz") "false")))

(ert-deftest boost-gptel-test-function-documentation ()
  "function_documentation should return documentation for a known function."
  (let ((doc (boost-gptel--function-documentation "car")))
    (should (string-match-p "Function: car" doc))))

(ert-deftest boost-gptel-test-variable-documentation ()
  "variable_documentation should return documentation or a message."
  (let ((doc (boost-gptel--variable-documentation "major-mode")))
    (should (string-match-p "variable\\|No documentation found" doc))))

(ert-deftest boost-gptel-test-lookup-key ()
  "lookup_key should return binding info."
  (let ((res (boost-gptel--lookup-key "C-f")))
    (should (string-match-p "Key: C-f" res))
    (should (string-match-p "Binding:" res))))

(ert-deftest boost-gptel-test-list-packages ()
  "list_packages should return a printed list."
  (let ((out (boost-gptel--list-packages)))
    (should (stringp out))
    (should (string-match-p "^(" out))))

(ert-deftest boost-gptel-test-package-installed ()
  "package_installed should return true or false."
  (should (member (boost-gptel--package-installed "emacs") '("true" "false"))))

(ert-deftest boost-gptel-test-current-major-mode ()
  "current_major_mode should return a symbol name as string."
  (with-temp-buffer
    (emacs-lisp-mode)
    (should (string-match-p "emacs-lisp-mode" (boost-gptel--current-major-mode)))))

(ert-deftest boost-gptel-test-list-buffers ()
  "list_buffers should list current buffers."
  (let ((buffers (read (boost-gptel--list-buffers))))
    (should (listp buffers))
    (should (member (buffer-name (current-buffer)) buffers))))

(ert-deftest boost-gptel-test-eval-elisp ()
  "eval_elisp should evaluate code and return its printed result."
  (should (string-match-p "42" (boost-gptel--eval-elisp "(+ 19 23)"))))

(ert-deftest boost-gptel-test-eval-elisp-sandbox ()
  "eval_elisp_sandbox should evaluate in a fresh Emacs process."
  (let ((out (boost-gptel--eval-elisp-sandbox "(* 3 7)")))
    (should (string= out "21"))))

(ert-deftest boost-gptel-test-current-datetime ()
  "current_datetime should return timestamp in Org format."
  (let ((ts (boost-gptel--current-datetime)))
    (should (string-match-p "\\[.*\\]" ts))))

;;; Buffer access tools

(ert-deftest boost-gptel-test-read-buffer ()
  "read_buffer should return buffer contents."
  (with-temp-buffer
    (insert "Hello GPTel")
    (should (string-match-p "Hello GPTel" (boost-gptel--read-buffer (buffer-name))))) )

;;; File management tools

(ert-deftest boost-gptel-test-list-files ()
  "list_files should list files under boost-gptel-root."
  (with-temp-gptel-roots
    ;; create two files
    (write-region "A" nil (expand-file-name "f1.txt" boost-gptel-root))
    (write-region "B" nil (expand-file-name "f2.org" boost-gptel-root))
    (let ((out (split-string (boost-gptel--list-files) "\\n" t)))
      (should (member "f1.txt" out))
      (should (member "f2.org" out)))))

(ert-deftest boost-gptel-test-list-project-files-no-project ()
  "list_project_files errors outside a project."
  (should-error (boost-gptel--list-project-files)))

(ert-deftest boost-gptel-test-search-files ()
  "search_files should find files matching pattern."
  (with-temp-gptel-roots
    ;; create two files
    (write-region "foo" nil (expand-file-name "a.txt" boost-gptel-root))
    (write-region "bar" nil (expand-file-name "b.txt" boost-gptel-root))
    (let ((res (read (boost-gptel--search-files "foo"))))
      (should (member (expand-file-name "a.txt" default-directory) res)))))

(ert-deftest boost-gptel-test-search-project-files-no-project ()
  "search_project_files errors outside a project."
  (should-error (boost-gptel--search-project-files "x")))

(ert-deftest boost-gptel-test-read-file-and-edit-file ()
  "read_file and edit_file should round-trip contents."
  (with-temp-gptel-roots
    (let ((path "t1.txt")
          (content "Test-content"))
      (should (equal
               (boost-gptel--write-file path content)
               (format "Wrote %d bytes to %s" (string-bytes content) path)))
      (should (string-match-p content (boost-gptel--read-file path))))))

(ert-deftest boost-gptel-test-edit-rename-delete-file ()
  "edit_file, rename_file, delete_file chain should work."
  (with-temp-gptel-roots
    ;; edit_file writes a file
    (should (string-match-p "Wrote" (boost-gptel--edit-file "x.txt" "X")))
    (should (file-exists-p (expand-file-name "x.txt" boost-gptel-root)))
    ;; rename
    (should (string-match-p "Renamed" (boost-gptel--rename-file "x.txt" "y.txt")))
    (should (file-exists-p (expand-file-name "y.txt" boost-gptel-root)))
    (should-not (file-exists-p (expand-file-name "x.txt" boost-gptel-root)))
    ;; delete
    (should (string-match-p "Deleted" (boost-gptel--delete-file "y.txt")))
    (should-not (file-exists-p (expand-file-name "y.txt" boost-gptel-root)))))

(ert-deftest boost-gptel-test-create-directory ()
  "create_directory should create nested dirs."
  (with-temp-gptel-roots
    (let ((msg (boost-gptel--create-directory "d1/d2")))
      (should (string-match-p "Created directory" msg))
      (should (file-directory-p (expand-file-name "d1/d2" boost-gptel-root))))))

;;; Shell and web tools

(ert-deftest boost-gptel-test-run-shell-command ()
  "run_shell_command should execute and return status."
  (with-temp-gptel-roots
    (let ((out (boost-gptel--run-shell-command "echo OK")))
      (should (string-match-p "Exit status: 0" out))
      (should (string-match-p "OK" out)))))

(ert-deftest boost-gptel-test-man-page ()
  "man_page should return content or error for known command."
  (let ((out (boost-gptel--man-page "echo")))
    (should (string-match-p "ECHO" (upcase out)))))

(ert-deftest boost-gptel-test-search-web ()
  "search_web should return JSON string."
  (let ((res (boost-gptel--search-web "emacs")))
    (should (string-match-p "{.*" res))))

(ert-deftest boost-gptel-test-read-webpage ()
  "read_webpage should fetch a known URL."
  (let ((res (boost-gptel--read-webpage "https://example.com")))
    (should (string-match-p "Example Domain" res))))

;;; Org-mode task tools

(ert-deftest boost-gptel-test-org-list-and-find-and-delete-tasks ()
  "org_list_tasks, org_find_tasks, org_delete_task should work in a buffer."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Alpha\\n* TODO Beta\\n")
    (let ((all (read (boost-gptel--org-list-tasks)))
          (found (read (boost-gptel--org-find-tasks "Alpha"))))
      (should (equal all '("TODO: Alpha" "TODO: Beta")))
      (should (equal found '("TODO: Alpha")))
      ;; delete Alpha
      (should (string-match-p "Deleted TODO heading" (boost-gptel--org-delete-task "Alpha")))
      (should (not (string-match-p "Alpha" (buffer-string)))))))

;;; Note creation tool

(ert-deftest boost-gptel-test-create-note ()
  "create_note should write a timestamped Org note."
  (with-temp-gptel-roots
    (let ((msg (boost-gptel--create-note "Test Note" "Content line")))
      (should (string-match-p "Created note:" msg))
      ;; file should exist
      (let ((files (directory-files boost-gptel-note-directory nil "Test-Note.*\\\\.org$")))
        (should files)))) )

(provide 'gptel-tools-test)

;;; gptel-tools-test.el ends here
