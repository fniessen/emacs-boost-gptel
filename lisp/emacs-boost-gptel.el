;;; emacs-boost-gptel.el --- GPTel configuration  -*- lexical-binding: t; -*-

;; This file is generated from README.org.
;; Edit the Org source, then tangle it again.

;;; Code:

(require 'cl-lib)               ; cl-incf, cl-delete-if-not, cl-remove-if
(require 'seq)                  ; seq-remove, seq-filter, seq-take
(require 'subr-x)               ; string-trim, string-empty-p, string-join, when-let*
;; (require 'auth-source nil 'noerror)
(require 'project)
(require 'pp)
(require 'org)
(require 'hl-line)

(require 'package)
(unless package--initialized
  (package-initialize))

(unless (require 'gptel nil 'noerror)
  (error "GPTel is required by emacs-boost-gptel"))

(require 'gptel-context)

(declare-function gptel-make-openai "gptel-openai")
(declare-function gptel-make-anthropic "gptel-anthropic")
(declare-function gptel-menu "gptel")
(declare-function gptel-rewrite "gptel-rewrite")

(defgroup boost-gptel nil
  "Personal configuration layered on top of GPTel."
  :group 'gptel
  :prefix "boost-gptel-")

(defcustom boost-gptel-prompt-directory
  (expand-file-name "prompts/gptel/" user-emacs-directory)
  "Directory containing optional external prompt files."
  :type 'directory
  :group 'boost-gptel)

(defcustom boost-gptel-note-directory
  "~/org/"
  "Directory in which the confirmed create_note tool may write Org files."
  :type 'directory
  :group 'boost-gptel)

(defcustom boost-gptel-private-file
  (expand-file-name "init_local_gptel.el" user-emacs-directory)
  "Optional non-versioned file loaded before backend registration."
  :type 'file
  :group 'boost-gptel)

(defcustom boost-gptel-tool-max-output-chars 120000
  "Maximum number of characters returned by a read tool."
  :type 'natnum
  :group 'boost-gptel)

(defcustom boost-gptel-tool-max-search-files 300
  "Maximum number of project files inspected by search_project_files."
  :type 'natnum
  :group 'boost-gptel)

(defcustom boost-gptel-tool-max-search-matches 80
  "Maximum number of matches returned by search_project_files."
  :type 'natnum
  :group 'boost-gptel)

(defcustom boost-gptel-command-max-input-chars 120000
  "Maximum amount of buffer text used by custom one-shot commands."
  :type 'natnum
  :group 'boost-gptel)

(defcustom boost-gptel-move-point-after-response nil
  "Whether to move point to the end of a completed response."
  :type 'boolean
  :group 'boost-gptel)

(defcustom boost-gptel-sensitive-file-regexp
  (rx
   (or string-start "/")
   (or ".env" ".envrc" ".direnv" ".authinfo" ".netrc"
       ".ssh" ".gnupg" "id_rsa" "id_ed25519"
       "credentials" "secret" "secrets")
   (or string-end "/" "." "-" "_"))
  "Regexp matching paths rejected by GPTel file-reading tools.

This is a conservative guardrail, not a complete secret-detection mechanism."
  :type 'regexp
  :group 'boost-gptel)

(defcustom boost-gptel-sensitive-buffer-regexp
  (rx string-start
      (or " " "*auth-source" "*password" "*secret" "*credentials"))
  "Regexp for buffer names that the read_buffer tool must reject."
  :type 'regexp
  :group 'boost-gptel)

(when (file-readable-p boost-gptel-private-file)
  (load boost-gptel-private-file nil 'nomessage))

(defun boost-gptel--api-key-from-file (file)
  "Return a function that reads an API key from FILE."
  (lambda ()
    (unless (file-readable-p file)
      (user-error "[API key file is not readable: %s]" file))
    (let ((key
           (string-trim
            (with-temp-buffer
              (insert-file-contents file)
              (buffer-string)))))
      (when (string-empty-p key)
        (user-error "[API key file is empty: %s]" file))
      key)))

(defcustom boost-gptel-enable-openai t
  "Whether to register the example OpenAI API backend."
  :type 'boolean
  :group 'boost-gptel)

(defcustom boost-gptel-openai-model 'gpt-5-mini
  "Example model identifier for the OpenAI API backend."
  :type 'symbol
  :group 'boost-gptel)

(defcustom boost-gptel-enable-anthropic t
  "Whether to register the example Anthropic backend."
  :type 'boolean
  :group 'boost-gptel)

(defcustom boost-gptel-anthropic-model 'claude-opus-4-6
  "Example model identifier for the Anthropic backend."
  :type 'symbol
  :group 'boost-gptel)

(defcustom boost-gptel-default-provider 'current
  "Provider used as the global default after backend registration.

The value `current' leaves GPTel's existing backend and model unchanged."
  :type '(choice
          (const :tag "Keep the current GPTel default" current)
          (const :tag "OpenAI API" openai)
          (const :tag "Anthropic" anthropic))
  :group 'boost-gptel)

(defvar boost-gptel-openai-backend nil)

(when boost-gptel-enable-openai
  (require 'gptel-openai)
  (let ((backend (gptel-make-openai "OpenAI"
                   :stream t
                   :key (boost-gptel--api-key-from-file "~/.openai_api_key"))))
    (unless (member boost-gptel-openai-model (gptel-backend-models backend))
      (user-error "Model %s is not available in GPTel's \"OpenAI\" backend"
                  boost-gptel-openai-model))
    (setq boost-gptel-openai-backend backend)))

(defvar boost-gptel-anthropic-backend nil)

(when boost-gptel-enable-anthropic
  (require 'gptel-anthropic)
  (let ((backend (gptel-make-anthropic "Anthropic"
                   :stream t
                   :key (boost-gptel--api-key-from-file "~/.anthropic_api_key"))))
    (unless (cl-find boost-gptel-anthropic-model (gptel-backend-models backend)
                     :key (lambda (m) (if (consp m) (car m) m)))
      (user-error "[Model %s is not available in GPTel's \"Anthropic\" backend]"
                  boost-gptel-anthropic-model))
    (setq boost-gptel-anthropic-backend backend)))

;; ;; Default backend.
;; (setq gptel-backend 'openai)
;;
;; ;; Default OpenAI model.
;; (setq gptel-openai-model "gpt-3.5-turbo")

(defun boost-gptel--select-default-provider ()
  "Set the global GPTel backend and model from `boost-gptel-default-provider'."
  (pcase boost-gptel-default-provider
    ('current
     nil)
    ('openai
     (if boost-gptel-openai-backend
         (setq gptel-backend boost-gptel-openai-backend
               gptel-model boost-gptel-openai-model)
       (display-warning
        'boost-gptel
        "[OpenAI was selected as default but its backend is disabled.]")))
    ('anthropic
     (if boost-gptel-anthropic-backend
         (setq gptel-backend boost-gptel-anthropic-backend
               gptel-model boost-gptel-anthropic-model)
       (display-warning
        'boost-gptel
        "[Anthropic was selected as default but its backend is disabled.]")))))

(boost-gptel--select-default-provider)

;; Do not include the reasoning at all.
(setq gptel-include-reasoning nil)

(setq gptel-context-restrict-to-project-files t)

(setq gptel-track-media nil)

(setq gptel-log-level nil)

;; Enable GPTel's expert/power-user commands.
(setq gptel-expert-commands t)

;; Rewrite UI.
(setq gptel-rewrite-default-action 'dispatch)

(defconst boost-gptel-prompt-default
  (string-join
   '("You are a precise technical assistant working inside Emacs."
     ""
     "Lead with the answer to the actual question asked -- don't bury it under setup or preamble."
     "Clearly separate what is confirmed, what is assumed, and what is your recommendation; never blur the three together."
     "When a claim depends on information you don't have, say what's missing instead of filling the gap with a plausible guess."
     "Never claim to have read a file, run code, or performed an action unless a tool result actually confirms it -- point to the specific result backing the claim."
     "Default to plain prose for short answers; reach for structure (lists, headers, code blocks) only when the content is genuinely long or complex enough to need it, not as decoration."
     "Match code and configuration to the conventions already present in the user's files rather than imposing a different style."
     "If something you or the user assumed earlier turns out to be wrong, say so plainly and correct course -- don't quietly work around it.")
   "\n"))

(defconst boost-gptel-prompt-precise
  (concat
   boost-gptel-prompt-default
   "\n\n"
   (string-join
    '("Keep the answer compact."
      "Lead with the conclusion."
      "Include only details needed to justify or apply the conclusion.")
    "\n")))

(defconst boost-gptel-prompt-programming
  (string-join
   '("You are a senior software engineer working inside Emacs."
     "Inspect the supplied code and context before proposing changes."
     "Preserve existing behavior unless the user explicitly requests a change."
     "State important assumptions."
     "Prefer small, reviewable changes over broad rewrites."
     "Return complete code when the user asks for code."
     "Mention security, compatibility, and failure-mode implications when relevant."
     "Never claim that code was executed unless a tool result confirms execution.")
   "\n"))

(defconst boost-gptel-prompt-code-review
  (string-join
   '("Act as a rigorous code reviewer."
     "Prioritize correctness, data loss, security, concurrency, and compatibility."
     "Separate confirmed defects from possible risks."
     "For every finding, identify the relevant code and explain the failure scenario."
     "Avoid style-only comments unless they materially affect maintenance or correctness."
     "End with a short assessment of residual risk.")
   "\n"))

(defconst boost-gptel-prompt-writing
  (string-join
   '("You are an exacting writing editor."
     "Preserve the author's meaning, factual claims, and intended audience."
     "Improve clarity, structure, rhythm, and precision."
     "Do not introduce new facts."
     "Keep terminology consistent."
     "When rewriting, return the revised text first.")
   "\n"))

(defconst boost-gptel-prompt-research
  (string-join
   '("You are a cautious research assistant."
     "Base conclusions only on the material supplied in the conversation or by tools."
     "Separate direct evidence from inference."
     "Identify disagreements, missing evidence, and uncertainty."
     "Do not fabricate citations, quotations, dates, or source details."
     "Use a comparison table when it genuinely improves the analysis.")
   "\n"))

(defconst boost-gptel-prompt-summarization
  (string-join
   '("Summarize the supplied material faithfully."
     "Preserve decisions, constraints, numbers, dates, names, and unresolved questions."
     "Do not add information that is not present in the source."
     "Use headings only when they improve navigation."
     "Finish with a short list of open questions when any remain.")
   "\n"))

(defconst boost-gptel-prompt-emacser
  (string-join
   '("You are an Emacs Maven."
     "Reply only with the most appropriate built-in Emacs comment for the requested task."
     "Do not generate any explanation, description, or commentary."
     "Return only the comment text.")
   "\n"))

(defun boost-gptel--project-directive ()
  "Return a programming directive enriched with current Emacs context."
  (format
   "%s\n\nCurrent Emacs context:\n- Project: %s\n- Major mode: %s\n- File: %s"
   boost-gptel-prompt-programming
   (boost-gptel--project-name)
   major-mode
   (if buffer-file-name
       (abbreviate-file-name buffer-file-name)
     "no-file")))

(defun boost-gptel--house-style-directive ()
  "Return the external house-style prompt or a safe built-in fallback."
  (boost-gptel--read-prompt-file
   "house-style"
   boost-gptel-prompt-writing))

(defconst boost-gptel-pair-programming-template
  (list
   boost-gptel-prompt-programming
   "Before changing code, briefly restate the requirement and list material
assumptions."
   "Understood. I will first restate the requirement and identify material
assumptions, then propose the smallest safe change."))

(dolist
    (entry
     (list
      (cons 'default           boost-gptel-prompt-default)
      (cons 'precise           boost-gptel-prompt-precise)
      (cons 'programming       boost-gptel-prompt-programming)
      (cons 'code-review       boost-gptel-prompt-code-review)
      (cons 'writing           boost-gptel-prompt-writing)
      (cons 'research          boost-gptel-prompt-research)
      (cons 'summarize         boost-gptel-prompt-summarization)
      (cons 'emacser           boost-gptel-prompt-emacser)
      (cons 'project-aware     #'boost-gptel--project-directive)
      (cons 'house-style       #'boost-gptel--house-style-directive)
      (cons 'pair-programming  boost-gptel-pair-programming-template)))
  (setf (alist-get (car entry) gptel-directives) (cdr entry)))

(setq gptel-system-prompt (alist-get 'default gptel-directives))

(defun boost-gptel--shell-rewrite-directive ()
  "Rewrite directive used in `shell-mode'."
  (when (derived-mode-p 'shell-mode)
    (concat
     "You are an expert Unix shell engineer. "
     "Rewrite or answer according to my request. "
     "Output ONLY the final text that should be inserted into the buffer. "
     "Do not add introductions, explanations, commentary, notes, markdown fences, "
     "headings, bullet lists, or conversational text. "
     "Preserve shell syntax, quoting, indentation, line breaks, and formatting. "
     "Return raw shell content only.")))

(add-hook 'gptel-rewrite-directives-hook #'boost-gptel--shell-rewrite-directive)

(defcustom boost-gptel-project-context-files
  '("README.md" "README.org" "CONTRIBUTING.md" "AGENTS.md")
  "Project-relative files considered by `boost-gptel-add-project-context'."
  :type '(repeat string)
  :group 'boost-gptel)

(defun boost-gptel--ensure-local-context ()
  "Ensure that the current buffer has an independent GPTel context."
  (unless (local-variable-p 'gptel-context)
    (setq-local gptel-context nil)))

(defun boost-gptel-add-project-context ()
  "Add existing files from `boost-gptel-project-context-files' to local context."
  (interactive)
  (boost-gptel--ensure-local-context)
  (let ((root (or (boost-gptel--project-root)
                  (user-error "No current project")))
        (added 0))
    (dolist (relative boost-gptel-project-context-files)
      (let ((file (expand-file-name relative root)))
        (when (file-readable-p file)
          (gptel-context-add-file
           (boost-gptel--safe-project-file relative))
          (cl-incf added))))
    (message "[Added %d project context file%s]"
             added
             (if (= added 1) "" "s"))))

(defun boost-gptel-clear-buffer-context ()
  "Remove every GPTel context source local to the current buffer."
  (interactive)
  (boost-gptel--ensure-local-context)
  (gptel-context-remove-all)
  (message "[Cleared buffer-local GPTel context]"))

(defun boost-gptel-show-context ()
  "Display the active GPTel context value in a temporary buffer."
  (interactive)
  (with-help-window "*boost-gptel-context*"
    (princ "Active GPTel context:\n\n")
    (pp gptel-context)))

(defun boost-gptel--project-root (&optional directory)
  "Return the current project root for DIRECTORY, or nil."
  (when-let* ((project (project-current nil directory)))
    (file-name-as-directory
     (expand-file-name (project-root project)))))

(defun boost-gptel--project-name ()
  "Return a short name for the current project."
  (if-let* ((root (boost-gptel--project-root)))
      (file-name-nondirectory (directory-file-name root))
    "no-project"))

(defun boost-gptel--sensitive-file-p (file)
  "Return non-nil when FILE matches the configured sensitive path regexp."
  (let ((case-fold-search t))
    (string-match-p
     boost-gptel-sensitive-file-regexp
     (expand-file-name file))))

(defun boost-gptel--sensitive-buffer-p (buffer)
  "Return non-nil when BUFFER should not be exposed through a read tool."
  (if (not (buffer-live-p buffer))
      t
    (with-current-buffer buffer
      (let ((case-fold-search t))
        (or (string-match-p boost-gptel-sensitive-buffer-regexp (buffer-name))
            (and buffer-file-name
                 (boost-gptel--sensitive-file-p buffer-file-name)))))))

(defun boost-gptel--safe-project-file (relative-path)
  "Return an existing project file identified by RELATIVE-PATH.

The resolved file must remain inside the current project, including after
symbolic links are resolved."
  (when (file-name-absolute-p relative-path)
    (user-error "Expected a path relative to the current project"))
  (let* ((root (or (boost-gptel--project-root)
                   (file-name-as-directory
                    (expand-file-name default-directory))))
         (candidate (expand-file-name relative-path root)))
    (unless (file-exists-p candidate)
      (user-error "Project file does not exist: %s" relative-path))
    (let ((true-root (file-truename root))
          (true-file (file-truename candidate)))
      (unless (file-in-directory-p true-file true-root)
        (user-error "Path escapes the current project: %s" relative-path))
      (when (boost-gptel--sensitive-file-p true-file)
        (user-error "Refusing to read a sensitive project path: %s"
                    relative-path))
      true-file)))

(defun boost-gptel--safe-project-destination (relative-path)
  "Return a new project path for RELATIVE-PATH without following escapes."
  (when (file-name-absolute-p relative-path)
    (user-error "Expected a path relative to the current project"))
  (let* ((root (or (boost-gptel--project-root)
                   (file-name-as-directory
                    (expand-file-name default-directory))))
         (candidate (expand-file-name relative-path root))
         (parent (file-name-directory candidate)))
    (while (and parent (not (file-directory-p parent)))
      (setq parent (file-name-directory (directory-file-name parent))))
    (unless (and parent
                 (file-in-directory-p (file-truename parent)
                                      (file-truename root)))
      (user-error "Path escapes the current project: %s" relative-path))
    (when (boost-gptel--sensitive-file-p candidate)
      (user-error "Refusing to write a sensitive project path: %s"
                  relative-path))
    candidate))

(defun boost-gptel--truncate-string (text limit)
  "Return TEXT truncated to LIMIT characters with a clear marker."
  (if (<= (length text) limit)
      text
    (concat
     (substring text 0 limit)
     (format "\n\n[Output truncated after %d characters.]" limit))))

(defun boost-gptel--buffer-substring-limited (beg end limit)
  "Return buffer text from BEG to END without copying more than LIMIT chars."
  (let* ((start (min beg end))
         (finish (max beg end))
         (cutoff (min finish (+ start limit)))
         (text (buffer-substring-no-properties start cutoff)))
    (if (< cutoff finish)
        (concat
         text
         (format "\n\n[Output truncated after %d characters.]" limit))
      text)))

(defun boost-gptel--read-file-limited (file &optional limit)
  "Read FILE and return no more than LIMIT decoded characters.

LIMIT defaults to `boost-gptel-tool-max-output-chars'."
  (let ((max-chars (or limit boost-gptel-tool-max-output-chars)))
    (unless (and (file-regular-p file) (file-readable-p file))
      (user-error "Not a readable regular file: %s" file))
    (with-temp-buffer
      (insert-file-contents file nil 0 (min (file-attribute-size
                                             (file-attributes file))
                                            (* 4 max-chars)))
      (when (save-excursion
              (goto-char (point-min))
              (search-forward "\0" nil t))
        (user-error "Refusing to read a binary file: %s" file))
      (boost-gptel--truncate-string
       (buffer-substring-no-properties (point-min) (point-max))
       max-chars))))

(defun boost-gptel--read-prompt-file (name &optional fallback)
  "Read prompt NAME from `boost-gptel-prompt-directory'.

NAME is read from NAME.txt.  Return FALLBACK when the file is absent."
  (let ((file (expand-file-name (concat name ".txt")
                                boost-gptel-prompt-directory)))
    (cond
     ((file-readable-p file)
      (string-trim (boost-gptel--read-file-limited file 100000)))
     (fallback fallback)
     (t
      (user-error "Prompt file is not readable: %s" file)))))

(defun boost-gptel--slugify (text)
  "Convert TEXT to a conservative lowercase file-name component."
  (let ((slug (downcase (string-trim text))))
    (setq slug (replace-regexp-in-string "[^[:alnum:]]+" "-" slug))
    (setq slug (replace-regexp-in-string "^-+\\|-+$" "" slug))
    (if (string-empty-p slug) "note" slug)))

(defun boost-gptel--project-files ()
  "Return readable, non-sensitive project files as relative paths."
  (let ((root (or (boost-gptel--project-root)
                  (user-error "No current project")))
        (files nil)
        (inspected 0))
    (dolist (file (directory-files-recursively root "^[^.].*" t))
      (when (and (< inspected boost-gptel-tool-max-search-files)
                 (file-regular-p file)
                 (not (boost-gptel--sensitive-file-p file)))
        (cl-incf inspected)
        (push (file-relative-name file root) files)))
    (sort files #'string<)))

(defun boost-gptel--list-project-files ()
  "Return a bounded list of readable project files as relative paths."
  (prin1-to-string (boost-gptel--project-files)))

(defun boost-gptel--read-project-file (relative-path)
  "Read RELATIVE-PATH from the current project with standard safety guards."
  (boost-gptel--read-file-limited
   (boost-gptel--safe-project-file relative-path)))

(defun boost-gptel--search-project-files (pattern)
  "Search readable project files for regexp PATTERN.

Return matches as relative-path:line-number:line-text records, bounded by the
configured file and match limits."
  (condition-case err
      (progn
        (string-match-p pattern "")
        (let ((root (or (boost-gptel--project-root)
                        (user-error "No current project")))
              (matches nil)
              (inspected 0))
          (dolist (file (boost-gptel--project-files))
            (when (< (length matches) boost-gptel-tool-max-search-matches)
              (cl-incf inspected)
              (condition-case nil
                  (with-temp-buffer
                    (insert-file-contents
                     (expand-file-name file root) nil 0
                     (* 4 boost-gptel-tool-max-output-chars))
                    (unless (save-excursion
                              (goto-char (point-min))
                              (search-forward "\0" nil t))
                      (goto-char (point-min))
                      (let ((line-number 1))
                        (while (and (< (length matches)
                                       boost-gptel-tool-max-search-matches)
                                      (not (eobp)))
                          (let ((line (buffer-substring-no-properties
                                       (line-beginning-position)
                                       (line-end-position))))
                            (when (string-match-p pattern line)
                              (push (format "%s:%d: %s"
                                            file line-number line)
                                    matches)))
                          (cl-incf line-number)
                          (forward-line 1)))))
                (error nil))))
          (prin1-to-string
           (list :files-inspected inspected
                 :matches (nreverse matches)))))
    (invalid-regexp
     (user-error "Invalid search pattern: %s" (error-message-string err)))))

(defun boost-gptel--symbol-exists (symbol-name)
  "Return whether SYMBOL-NAME names a bound variable or function."
  (let ((symbol (intern-soft symbol-name)))
    (if (and symbol (or (boundp symbol) (fboundp symbol))) "true" "false")))

(defun boost-gptel--function-documentation (function-name)
  "Return the documentation for FUNCTION-NAME, or an explicit absence marker."
  (let ((symbol (intern-soft function-name)))
    (cond
     ((not (and symbol (fboundp symbol)))
      (user-error "Not a defined function: %s" function-name))
     ((documentation symbol t)
      (documentation symbol t))
     (t
      "No documentation is available."))))

(defun boost-gptel--emacs-version ()
  "Return the current Emacs version string."
  (emacs-version))

;; Register emacs_version.
(defvar boost-gptel-tool-emacs-version
  (gptel-make-tool
   :name "emacs_version"
   :description
   "Return the current Emacs version."
   :function #'boost-gptel--emacs-version
   :args nil
   :category "Emacs Runtime"
   :confirm nil
   :include t))

(add-to-list 'gptel-tools boost-gptel-tool-emacs-version)

(defun boost-gptel--lookup-key (key-sequence)
  "Return the effective current-buffer binding of KEY-SEQUENCE."
  (condition-case error-data
      (let ((binding (key-binding (kbd key-sequence) t)))
        (format
         "Key: %s\nMajor mode: %s\nBinding: %s"
         key-sequence
         major-mode
         (cond
          ((null binding) "unbound")
          ((symbolp binding) (symbol-name binding))
          (t (prin1-to-string binding)))))
    (error
     (user-error "Invalid key sequence `%s': %s"
                 key-sequence
                 (error-message-string error-data)))))

;; Register lookup_key.
(defvar boost-gptel-tool-lookup-key
  (gptel-make-tool
   :name "lookup_key"
   :description
   "Return the effective binding of a key sequence in the current buffer,
taking its active local and minor-mode keymaps into account."
   :function #'boost-gptel--lookup-key
   :args (list '(:name "key_sequence"
                 :type string
                 :description "Key sequence such as C-x C-f or C-c m R"))
   :category "Emacs Runtime"
   :confirm nil
   :include t))

(add-to-list 'gptel-tools boost-gptel-tool-lookup-key)

(defun boost-gptel--list-packages ()
  "Return a printed list of all installed package names."
  (let ((pkgs (mapcar (lambda (pkg) (symbol-name (car pkg)))
                      package-alist)))
    (prin1-to-string pkgs)))

;; Register list_packages.
(defvar boost-gptel-tool-list-packages
  (gptel-make-tool
   :name "list_packages"
   :description
   "Return the list of all installed Emacs packages."
   :function #'boost-gptel--list-packages
   :args nil
   :category "Emacs Runtime"
   :confirm nil
   :include t))

(add-to-list 'gptel-tools boost-gptel-tool-list-packages)

(defun boost-gptel--package-installed (pkg-name)
  "Return \"true\" if the package named PKG-NAME is installed, \"false\" otherwise."
  (condition-case err
      (let ((sym (intern pkg-name)))
        (if (package-installed-p sym)
            "true"
          "false"))
    (error
     (format "Error: %s" (error-message-string err)))))

;; Register package_installed.
(defvar boost-gptel-tool-package-installed
  (gptel-make-tool
   :name "package_installed"
   :description
   "Return “true” if a given Emacs package is installed, “false” otherwise."
   :function #'boost-gptel--package-installed
   :args (list
          '(:name "pkg_name"
            :type string
            :description "Name of the package to check"))
   :category "Emacs Runtime"
   :confirm nil
   :include t))

(add-to-list 'gptel-tools boost-gptel-tool-package-installed)

(defun boost-gptel--current-major-mode ()
  "Return the current buffer’s major mode as a string."
  (prin1-to-string major-mode))

;; Register current_major_mode.
(defvar boost-gptel-tool-current-major-mode
  (gptel-make-tool
   :name "current_major_mode"
   :description
   "Return the current buffer’s major mode."
   :function #'boost-gptel--current-major-mode
   :args nil
   :category "Emacs Runtime"
   :confirm nil
   :include t))

(add-to-list 'gptel-tools boost-gptel-tool-current-major-mode)

(defun boost-gptel--list-buffers ()
  "Return a printed list of all currently open buffer names."
  (let ((names (mapcar #'buffer-name (buffer-list))))
    (prin1-to-string names)))

;; Register list_buffers.
(defvar boost-gptel-tool-list-buffers
  (gptel-make-tool
   :name "list_buffers"
   :description
   "Return the list of all open Emacs buffer names."
   :function #'boost-gptel--list-buffers
   :args nil
   :category "Emacs Runtime"
   :confirm nil
   :include t))

(add-to-list 'gptel-tools boost-gptel-tool-list-buffers)

(defun boost-gptel--eval-elisp-sandbox (code)
  "Evaluate the Emacs Lisp string CODE in a fresh Emacs process (-Q, --batch)
and return its printed result or an error message."
  (let* ((wrapped
          ;; Wrap CODE so we catch errors, convert to string, and explicitly print.
          (format
           "(princ (condition-case err
                       (prin1-to-string (progn %s))
                     (error
                       (format \"Error: %%s\" (error-message-string err)))))"
           code))
         (cmd
          (format "LC_ALL=C emacs -Q --batch --eval %s"
                  (shell-quote-argument wrapped)))
         (output
          (let ((process-environment (copy-sequence process-environment)))
            (setenv "LC_ALL" "C")
            (shell-command-to-string cmd))))
    ;; Trim trailing newline and return.
    (string-trim-right output)))

;; Register eval_elisp_sandbox.
(defvar boost-gptel-tool-eval-elisp-sandbox
  (gptel-make-tool
   :name "eval_elisp_sandbox"
   :description
   "Evaluate a single Elisp sexp in a clean Emacs --batch -Q session and return its printed result."
   :function #'boost-gptel--eval-elisp-sandbox
   :args (list
          '(:name "code"
            :type string
            :description "A single elisp sexp to evaluate"))
   :category "Emacs Runtime"
   :confirm t
   :include t))

(add-to-list 'gptel-tools boost-gptel-tool-eval-elisp-sandbox)

(defun boost-gptel--current-datetime ()
  "Return the current local date and time."
  (format-time-string "[%Y-%m-%d %a %H:%M]"))

;; Register current_datetime.
(defvar boost-gptel-tool-current-datetime
  (gptel-make-tool
   :name "current_datetime"
   :description
   "Return the current local date, time, and weekday."
   :function #'boost-gptel--current-datetime
   :args nil
   :category "Emacs Runtime"
   :confirm nil
   :include t))

(add-to-list 'gptel-tools boost-gptel-tool-current-datetime)

(defvar boost-gptel-tool-symbol-exists
  (gptel-make-tool
   :name "symbol_exists"
   :description "Return whether an Emacs Lisp symbol names a bound variable or function."
   :function #'boost-gptel--symbol-exists
   :args (list '(:name "symbol_name" :type string
                 :description "Emacs Lisp symbol name"))
   :category "Emacs Runtime"
   :confirm nil
   :include t))

(add-to-list 'gptel-tools boost-gptel-tool-symbol-exists)

(defvar boost-gptel-tool-function-documentation
  (gptel-make-tool
   :name "function_documentation"
   :description "Return the documentation string for a defined Emacs Lisp function."
   :function #'boost-gptel--function-documentation
   :args (list '(:name "function_name" :type string
                 :description "Emacs Lisp function name"))
   :category "Emacs Runtime"
   :confirm nil
   :include t))

(add-to-list 'gptel-tools boost-gptel-tool-function-documentation)

(defun boost-gptel--read-buffer (buffer-name)
  "Return BUFFER-NAME contents, truncated to the configured limit."
  (let ((buffer (get-buffer buffer-name)))
    (unless buffer
      (user-error "No live buffer named %s" buffer-name))
    (when (boost-gptel--sensitive-buffer-p buffer)
      (user-error "Refusing to read a sensitive buffer: %s" buffer-name))
    (with-current-buffer buffer
      (boost-gptel--buffer-substring-limited
       (point-min)
       (point-max)
       boost-gptel-tool-max-output-chars))))

;; Register read_buffer.
(defvar boost-gptel-tool-read-buffer
  (gptel-make-tool
   :name "read_buffer"
   :description
   "Return bounded plain-text contents of a live Emacs buffer.
Sensitive buffers are rejected and long results are truncated."
   :function #'boost-gptel--read-buffer
   :args (list
          '(:name "buffer_name"
            :type string
            :description "Name of the Emacs buffer to read"))
   :category "Buffer Access"
   :confirm nil
   :include t))

(add-to-list 'gptel-tools boost-gptel-tool-read-buffer)

(defvar boost-gptel-tool-list-project-files
  (gptel-make-tool
   :name "list_project_files"
   :description "List bounded, readable, non-sensitive files in the current project."
   :function #'boost-gptel--list-project-files
   :args nil
   :category "Project"
   :confirm nil
   :include t))

(add-to-list 'gptel-tools boost-gptel-tool-list-project-files)

(defvar boost-gptel-tool-search-project-files
  (gptel-make-tool
   :name "search_project_files"
   :description "Search bounded, readable, non-sensitive project files with a regexp."
   :function #'boost-gptel--search-project-files
   :args (list '(:name "pattern" :type string
                 :description "Regexp to search for in project files"))
   :category "Project"
   :confirm nil
   :include t))

(add-to-list 'gptel-tools boost-gptel-tool-search-project-files)

(defvar boost-gptel-tool-read-project-file
  (gptel-make-tool
   :name "read_project_file"
   :description "Read a bounded text file relative to the current project."
   :function #'boost-gptel--read-project-file
   :args (list '(:name "relative_path" :type string
                 :description "Path relative to the current project root"))
   :category "Project"
   :confirm nil
   :include t))

(add-to-list 'gptel-tools boost-gptel-tool-read-project-file)

(defun boost-gptel--rename-file (old-path new-path)
  "Rename file OLD-PATH to NEW-PATH under the project root, creating directories
if needed."
  (condition-case err
      (let* ((old (boost-gptel--safe-project-file old-path))
             (new (boost-gptel--safe-project-destination new-path))
             (new-dir (file-name-directory new)))
        (unless (file-directory-p new-dir)
          (make-directory new-dir t))
        (rename-file old new t)  ; t = overwrite if exists.
        (format "Renamed %s to %s" old new))
    (error
     (format "Error renaming %s to %s: %s"
             old-path new-path (error-message-string err)))))

(defvar boost-gptel-tool-rename-file
  (gptel-make-tool
   :name "rename_file"
   :description "Rename a file under the project root."
   :function #'boost-gptel--rename-file
   :args (list
          '(:name "old_path" :type string
            :description "Relative path of the file to rename")
          '(:name "new_path" :type string
            :description "New relative path for the file"))
   :category "Filesystem"
   :confirm t
   :include t))

(add-to-list 'gptel-tools boost-gptel-tool-rename-file)

(defun boost-gptel--delete-file (file-path)
  "Delete the file at FILE-PATH under the project root."
  (condition-case err
      (let ((abs (boost-gptel--safe-project-file file-path)))
        (delete-file abs)
        (format "Deleted file: %s" abs))
    (error
     (format "Error deleting file %s: %s"
             file-path (error-message-string err)))))

;; Register delete_file.
(defvar boost-gptel-tool-delete-file
  (gptel-make-tool
   :name "delete_file"
   :description
   "Delete a file under the project root."
   :function #'boost-gptel--delete-file
   :args (list
          '(:name "file_path" :type string
            :description "Relative path to the file to delete"))
   :category "Filesystem"
   :confirm t
   :include t))

(add-to-list 'gptel-tools boost-gptel-tool-delete-file)

(defun boost-gptel--org-list-tasks ()
  "Return a printed list of all TODO headings in the current Org buffer."
  (let (tasks)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "^\\*+\\s-+TODO\\s-+\\(.*\\)$" nil t)
        (push (format "TODO: %s" (match-string 1)) tasks)))
    (prin1-to-string (nreverse tasks))))

;; Register org_list_tasks.
(defvar boost-gptel-tool-org-list-tasks
  (gptel-make-tool
   :name "org_list_tasks"
   :description
   "List all TODO entries in the current Org buffer."
   :function #'boost-gptel--org-list-tasks
   :args nil
   :category "Org-mode"
   :confirm nil
   :include t))

(add-to-list 'gptel-tools boost-gptel-tool-org-list-tasks)

(defun boost-gptel--org-find-tasks (pattern)
  "Return a printed list of TODO headings whose title matches PATTERN."
  (let (matches)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward
              (format "^\\*+\\s-+TODO\\s-+\\(.*%s.*\\)$" pattern)
              nil t)
        (push (format "TODO: %s" (match-string 1)) matches)))
    (prin1-to-string (nreverse matches))))

;; Register org_find_tasks.
(defvar boost-gptel-tool-org-find-tasks
  (gptel-make-tool
   :name "org_find_tasks"
   :description
   "List TODO entries in the current Org buffer whose titles match a given regexp."
   :function #'boost-gptel--org-find-tasks
   :args (list
          '(:name "pattern"
                  :type string
                  :description "Regexp to filter task titles"))
   :category "Org-mode"
   :confirm nil
   :include t))

(add-to-list 'gptel-tools boost-gptel-tool-org-find-tasks)

(defun boost-gptel--create-note (title content)
  "Create an Org note with TITLE and CONTENT in the configured note directory."
  (when (string-empty-p (string-trim title))
    (user-error "Note title must not be empty"))
  (let* ((clean-title
          (replace-regexp-in-string "[\r\n]+" " " (string-trim title)))
         (stamp (format-time-string "%Y-%m-%d-%a-%H-%M"))
         (slug
          (truncate-string-to-width
           (boost-gptel--slugify clean-title)
           60
           nil
           nil))
         (file
          (make-temp-file
           (expand-file-name
            (format "%s-%s-" stamp slug)
            boost-gptel-note-directory)
           nil
           ".org")))
    (with-temp-file file
      (insert "#+TITLE:     " clean-title "\n")
      (insert "#+DATE:      " (format-time-string "[%Y-%m-%d %a %H:%M]") "\n\n")
      (insert content)
      (unless (string-suffix-p "\n" content)
        (insert "\n")))
    (format "Created note: %s" (abbreviate-file-name file))))

;; Register create_note.
(defvar boost-gptel-tool-create-note
  (gptel-make-tool
   :name "create_note"
   :description
   "Create a new timestamped Org note inside the configured GPTel note directory. This tool cannot choose an arbitrary output path."
   :function #'boost-gptel--create-note
   :args (list
          '(:name "title"
            :type string
            :description "Short note title")
          '(:name "content"
            :type string
            :description "Complete Org-formatted note content"))
   :category "Org-mode"
   :confirm t
   :include t))

(add-to-list 'gptel-tools boost-gptel-tool-create-note)

(defun boost-gptel--org-delete-task (pattern)
  "Delete the first matching TODO heading in the current Org buffer.

PATTERN is a regular expression matched against the heading title."
  (require 'org)
  (save-excursion
    (goto-char (point-min))
    (if (re-search-forward
         (format "^\\*+\\s-+TODO\\s-+.*%s.*" pattern)
         nil t)
        (progn
          (org-cut-subtree)
          (when (buffer-file-name)
            (save-buffer))
          (format "Deleted TODO heading matching '%s'." pattern))
      (format "No TODO heading matching '%s' found." pattern))))

;; Register org_delete_task.
(defvar boost-gptel-tool-org-delete-task
  (gptel-make-tool
   :name "org_delete_task"
   :description
   "Delete the first TODO entry in the current Org buffer matching a given regexp."
   :function #'boost-gptel--org-delete-task
   :args (list
          '(:name "pattern"
            :type string
            :description "Regexp to match task title"))
   :category "Org-mode"
   :confirm t
   :include t))

(add-to-list 'gptel-tools boost-gptel-tool-org-delete-task)

(require 'gptel-agent nil 'noerror)

(defconst boost-gptel-youtube-caption-languages
  '("en" "fr" "es" "pt" "de" "it" "nl" "ru" "zh" "ja" "ar" "hi")
  "Preferred international languages when a YouTube original track is absent.")

(defun boost-gptel--youtube-caption-original-p (track)
  "Return non-nil when YouTube marks TRACK as an original-language caption."
  (let ((language (or (plist-get track :languageCode) ""))
        (name (or (plist-get (plist-get track :name) :simpleText) "")))
    (or (string-match-p "-orig\\'" language)
        (string-match-p "\\boriginal\\b" (downcase name)))))

(defun boost-gptel--youtube-caption-language (track)
  "Return the language code for caption TRACK."
  (or (plist-get track :languageCode) "unknown"))

(defun boost-gptel--youtube-caption-track (tracks)
  "Select the best available caption track from YouTube TRACKS."
  (or (seq-find #'boost-gptel--youtube-caption-original-p tracks)
      ;; YouTube marks automatic captions with `asr'; they follow the
      ;; spoken language even when no explicit original marker is present.
      (seq-find (lambda (track) (equal (plist-get track :kind) "asr"))
                tracks)
      (cl-loop
       for language in boost-gptel-youtube-caption-languages
       thereis
       (seq-find
        (lambda (track)
          (string-match-p
           (concat "\\`" (regexp-quote language) "\\(?:-\\|\\'\\)")
           (boost-gptel--youtube-caption-language track)))
        tracks))
      (car tracks)))

(defun boost-gptel--youtube-fetch-captions (_original callback description tracks)
  "Fetch a suitable caption track from TRACKS and call CALLBACK with it.
DESCRIPTION is the YouTube video description.  _ORIGINAL is the function
replaced by this advice."
  (let ((track (boost-gptel--youtube-caption-track tracks)))
    (if (not track)
        (funcall callback
                 (format "# Description\n\n%s\n\n# Transcript\n\nNo transcript available in any language."
                         (or description "No description available.")))
      (let ((base-url (replace-regexp-in-string
                       "&fmt=srv3" ""
                       (plist-get track :baseUrl)))
            (language (boost-gptel--youtube-caption-language track)))
        (url-retrieve
         base-url
         (lambda (status callback description language)
           (if-let* ((error (plist-get status :error)))
               (funcall callback
                        (format "# Description\n\n%s\n\n# Transcript (%s)\n\nError fetching transcript: %s"
                                (or description "No description available.")
                                language error))
             (goto-char (point-min))
             (search-forward "\n\n" nil t)
             (let* ((xml-string (buffer-substring (point) (point-max)))
                    (caption-dom (gptel-agent--yt-parse-captions xml-string))
                    (transcript
                     (gptel-agent--yt-format-captions caption-dom 30)))
               (funcall callback
                        (format "# Description\n\n%s\n\n# Transcript (%s)\n\n%s"
                                (or description "No description available.")
                                language
                                (or transcript "Error parsing transcript."))))))
         (list callback description language))))))

(when (fboundp 'gptel-agent--yt-fetch-captions)
  (advice-add 'gptel-agent--yt-fetch-captions
              :around #'boost-gptel--youtube-fetch-captions))

(defun boost-gptel-summarize-youtube (url)
  "Start a GPTel agent to summarize the YouTube video at URL."
  (interactive "sYouTube URL: ")
  (unless (and (stringp url) (not (string-empty-p url)))
    (user-error "YouTube URL must not be empty"))
  (unless (fboundp 'gptel-agent)
    (user-error "Install and load gptel-agent before using this command"))
  (let* ((buffers-before (buffer-list))
         (agent-result (gptel-agent default-directory))
         (buffer
          (or (and (buffer-live-p agent-result) agent-result)
              (seq-find
               (lambda (candidate)
                 (and (not (memq candidate buffers-before))
                      (string-prefix-p "*gptel-agent:"
                                       (buffer-name candidate))))
               (buffer-list)))))
    (unless (buffer-live-p buffer)
      (error "gptel-agent did not create a live agent buffer"))
    (pop-to-buffer buffer)
    (with-current-buffer buffer
      (goto-char (point-max))
      (unless (bolp)
        (insert "\n"))
      (insert
       (format
        (concat "Résume cette vidéo YouTube en français en 8 points, "
                "avec les idées principales et les timestamps utiles.\nURL : %s\n")
        url))
      (gptel-send))
    buffer))

(defun boost-gptel--post-tool-log (call)
  "Log completion of a GPTel tool CALL without logging sensitive contents."
  (message "[Ran `%s']" (plist-get call :name))
  nil)

(add-hook 'gptel-post-tool-call-functions #'boost-gptel--post-tool-log)

(gptel-make-preset 'boost-base
  :description
  "Conservative defaults with no tools selected."
  :system 'default
  :tools nil
  ;; :temperature 0.2
  :max-tokens nil
  :stream t
  :use-context 'system
  :track-media nil
  :include-reasoning 'ignore
  :confirm-tool-calls 'auto
  :include-tool-results 'auto)

(gptel-make-preset 'boost-precise
  :description
  "Compact answers with low randomness."
  :parents 'boost-base
  :system 'precise
  ;; :temperature 0.1
  )

(gptel-make-preset 'boost-coding
  :description
  "Project-aware programming with read-only inspection tools."
  :parents 'boost-base
  :system 'project-aware
  :tools '("current_datetime"
           "symbol_exists"
           "function_documentation"
           "lookup_key"
           "read_buffer"
           "list_project_files"
           "search_project_files"
           "read_project_file")
  ;; :temperature 0.2
  :use-context 'system)

(gptel-make-preset 'boost-code-review
  :description
  "Rigorous code review using read-only project tools."
  :parents 'boost-coding
  :system 'code-review
  ;; :temperature 0.1
  )

(gptel-make-preset 'boost-pair-programming
  :description
  "Programming with read-only inspection and confirmed file replacement."
  :parents 'boost-coding
  :system 'pair-programming
  :tools '("current_datetime"
           "symbol_exists"
           "function_documentation"
           "lookup_key"
           "read_buffer"
           "list_project_files"
           "search_project_files"
           "read_project_file"
           ;; "write_project_file"
           )
  :confirm-tool-calls 'auto)

(gptel-make-preset 'boost-writing
  :description
  "Editing and rewriting with access to the current buffer."
  :parents 'boost-base
  :system 'writing
  :tools '("read_buffer")
  ;; :temperature 0.6
  :use-context 'user)

(gptel-make-preset 'boost-house-style
  :description
  "Writing with an optional external house-style prompt."
  :parents 'boost-writing
  :system 'house-style
  ;; :temperature 0.4
  )

(gptel-make-preset 'boost-research
  :description
  "Evidence-focused analysis with bounded read-only tools."
  :parents 'boost-base
  :system 'research
  :tools '("current_datetime"
           "read_buffer"
           "list_project_files"
           "read_project_file"
           "search_project_files")
  ;; :temperature 0.2
  :use-context 'system)

(gptel-make-preset 'boost-visible-buffers
  :description
  "Research preset using all visible buffers in the selected frame as context."
  :parents 'boost-research
  :context
  '(:eval
    (cl-remove-if
     (lambda (buffer)
       (or (string-prefix-p " " (buffer-name buffer))
           (boost-gptel--sensitive-buffer-p buffer)))
     (delete-dups (mapcar #'window-buffer (window-list)))))
  :use-context 'user)

(gptel-make-preset 'boost-note-taking
  :description
  "Research plus confirmed creation of Org notes."
  :parents 'boost-research
  :tools '("current_datetime"
           "read_buffer"
           "list_project_files"
           "read_project_file"
           "search_project_files"
           "create_note")
  :confirm-tool-calls 'auto)

(when boost-gptel-openai-backend
  (gptel-make-preset 'boost-openai
    :description
    "Use the configured OpenAI backend."
    :parents 'boost-base
    :backend "OpenAI"
    :model boost-gptel-openai-model))

(when boost-gptel-anthropic-backend
  (gptel-make-preset 'boost-anthropic
    :description
    "Use the configured Anthropic backend."
    :parents 'boost-base
    :backend "Anthropic"
    :model boost-gptel-anthropic-model))

;; Use Org mode for GPTel chat buffers.
(setq gptel-default-mode 'org-mode)

(defun boost-gptel--context-item-label (src)
  "Return a human-readable label for a GPTel context SRC item."
  (let* ((type (plist-get src :type))
         (type-sym (if (symbolp type) type (and (stringp type) (intern type))))
         (label
          (cond
           ((eq type-sym 'file)
            (or (plist-get src :path)
                (plist-get src :file)
                "<unknown file>"))
           ((eq type-sym 'buffer)
            (let ((b (plist-get src :buffer)))
              (cond
               ((bufferp b) (format "#<buffer %s>" (buffer-name b)))
               ((stringp b) (format "#<buffer %s>" b))
               (t "#<unknown buffer>"))))
           ((memq type-sym '(string snippet))
            (let ((s (or (plist-get src :content)
                         (plist-get src :string)
                         (plist-get src :text)
                         "")))
              (format "text: %s"
                      (truncate-string-to-width
                       (replace-regexp-in-string "[\n\r]+" " " s)
                       60 nil nil "..."))))
           (t (or (plist-get src :name)
                  (plist-get src :label)
                  (format "%S" src))))))
    (format "[%s] %s" (or type 'unknown) label)))

(defun boost-gptel-review-context ()
  "Review `gptel-context' and ask whether to keep each item.

Update the buffer-local `gptel-context' variable with the retained items."
  (interactive)
  (unless (boundp 'gptel-context)
    (user-error "This buffer has no GPTel context (`gptel-context' is unbound)"))
  (if (null gptel-context)
      (message "GPTel context is empty")
    (let* ((ctx gptel-context)
           (kept nil))
      (map-y-or-n-p
       (lambda (src)
         (format "Keep %s? " (boost-gptel--context-item-label src)))
       (lambda (src) (push src kept))
       ctx
       '("y = keep, n = delete, ! = keep remaining, q = quit"))
      (setq-local gptel-context (nreverse kept))
      (message "GPTel context: %d kept, %d removed"
               (length gptel-context) (- (length ctx) (length gptel-context))))))

;; reView context.
(keymap-set gptel-mode-map "C-c g v" #'boost-gptel-review-context)

(setf (alist-get 'org-mode gptel-prompt-prefix-alist) " prompt  ")
(setf (alist-get 'org-mode gptel-response-prefix-alist) " response \n\n")

(defface boost-gptel-user-face
  '((t
     :background "#E8E8E8"
     :foreground "#000000"
     :box (:line-width 1 :color "#000000")
     :weight bold))
  "GPTel user label.")

(defface boost-gptel-assistant-face
  '((t
     :background "#79B6DE"
     :foreground "#FFFFFF"
     :box (:line-width 1 :color "#000000")
     :weight bold))
  "GPTel assistant label.")

(defun boost-gptel--font-lock ()
  (font-lock-add-keywords
   nil
   '(("^ prompt "
      (0 'boost-gptel-user-face prepend))
     ("^ response "
      (0 'boost-gptel-assistant-face prepend)))
   'append))

(add-hook 'gptel-mode-hook #'boost-gptel--font-lock)

(defun boost-gptel-open-chat ()
  "Switch to the GPTel chat buffer, creating it if it doesn't exist."
  (interactive)
  (pop-to-buffer (gptel "*gptel*")))

(global-set-key (kbd "C-<f1>") #'boost-gptel-open-chat)

;; Highlight GPTel responses with a light blue background and a slightly
;; darker bar in the left fringe.
(setq gptel-highlight-methods '(face fringe))

(set-face-attribute 'gptel-response-highlight nil
                    :background "#E8F3FE"
                    :extend t)

(set-face-attribute 'gptel-response-fringe-highlight nil
                    :foreground "#4A90E2"
                    :weight 'bold)

(add-hook 'gptel-pre-response-hook #'global-hl-line-unhighlight)

(defvar-local boost-gptel-response-tail-overlays nil
  "Overlays extending GPTel response backgrounds to the next line.

GPTel response regions can end immediately after the final character of the
response, before the terminating newline.  In that situation the `:extend'
attribute of `gptel-response-highlight' cannot paint the remainder of the
visual line.

These overlays cover the terminating newline without modifying GPTel's
`gptel' text property.")

(defun boost-gptel--delete-response-tail-overlays (&optional beg end)
  "Delete response-tail overlays intersecting BEG and END.

BEG defaults to `point-min' and END defaults to `point-max'."
  (let ((beg (or beg (point-min)))
        (end (or end (point-max))))
    (dolist (overlay (overlays-in beg end))
      (when (overlay-get overlay 'boost-gptel-response-tail-overlay)
        (delete-overlay overlay))))
  ;; Remove references to overlays that no longer exist.
  (setq boost-gptel-response-tail-overlays
        (cl-delete-if-not #'overlay-buffer
                          boost-gptel-response-tail-overlays)))

(defun boost-gptel--extend-response-background (beg end)
  "Extend a GPTel response background from END to the next line.

BEG and END are supplied by `gptel-post-response-functions'.

GPTel can terminate its response overlay immediately after the final response
character.  Since the terminating newline is then outside the overlay,
`:extend t' cannot paint the background through the remainder of the line.

This function adds a background-only overlay from END through the terminating
newline.  It deliberately does not add or modify the `gptel' text property."

  (when (and (< beg end)
             (< end (point-max)))
    (boost-gptel--delete-response-tail-overlays
     end
     (min (1+ end) (point-max)))

    (save-excursion
      (goto-char end)

      ;; Only extend when END is not already positioned after a newline.
      (unless (bolp)
        (let* ((tail-beg end)
               ;; Include the terminating newline, but do not colour the
               ;; contents of the following prompt.
               (tail-end
                (min (line-beginning-position 2)
                     (point-max)))
               (overlay
                (make-overlay tail-beg tail-end nil t nil)))

          (overlay-put overlay
                       'boost-gptel-response-tail-overlay
                       t)

          (overlay-put overlay 'evaporate t)

          ;; Use the same GPTel face.  Because the overlay includes the
          ;; newline, `:extend t' paints the background to the right edge.
          (overlay-put overlay
                       'face
                       'gptel-response-highlight)

          ;; Keep the extension above incidental low-priority overlays
          ;; such as `hl-line'.
          (overlay-put overlay 'priority 90)

          (push overlay
                boost-gptel-response-tail-overlays))))))

;; GPTel calls functions in this abnormal hook with the beginning and end
;; positions of the completed response.
(add-hook 'gptel-post-response-functions
          #'boost-gptel--extend-response-background
          90)

(defvar-local boost-gptel-org-src-overlays nil
  "Overlays restoring Org source-block backgrounds over GPTel highlighting.")

(defun boost-gptel--org-delete-src-overlays (&optional beg end)
  "Delete custom source-block overlays between BEG and END."
  (let ((beg (or beg (point-min)))
        (end (or end (point-max))))
    (dolist (overlay (overlays-in beg end))
      (when (overlay-get overlay 'boost-gptel-org-src-overlay)
        (delete-overlay overlay)))))

(defun boost-gptel--org-put-src-overlay (beg end face)
  "Put a background-only overlay from BEG to END.

FACE is used only to retrieve its background colour.  The overlay
deliberately does not inherit FACE, so that language-specific
font-lock faces remain visible inside Org source blocks."
  (when (and beg end (< beg end))
    (let ((overlay (make-overlay beg end nil t nil)))
      (overlay-put overlay 'boost-gptel-org-src-overlay t)
      (overlay-put overlay 'evaporate t)

      ;; Override only the background applied by GPTel.
      ;;
      ;; Do not use `:inherit FACE' here: inheriting `org-block' would
      ;; override the language-specific font-lock foreground colours.
      (overlay-put
       overlay 'face
       `(:background
         ,(or (face-background face nil t)
              (face-background 'default nil t))
         :extend t))

      ;; Higher than GPTel's response overlay.
      (overlay-put overlay 'priority 100)

      (push overlay boost-gptel-org-src-overlays))))

(defun boost-gptel--org-src-property-regions (beg end)
  "Return contiguous regions carrying the `src-block' property."
  (let ((position beg)
        regions)
    (while (< position end)
      (if (get-text-property position 'src-block)
          (let ((next
                 (or (next-single-property-change
                      position 'src-block nil end)
                     end)))
            (push (cons position next) regions)
            (setq position next))
        (setq position
              (or (next-single-property-change
                   position 'src-block nil end)
                  end))))
    (nreverse regions)))

(defun boost-gptel--org-refresh-src-backgrounds (beg end)
  "Restore Org source-block backgrounds in GPTel response BEG to END."
  (when (derived-mode-p 'org-mode)
    ;; Org must create `src-block' text properties before we inspect them.
    (font-lock-flush beg end)
    (font-lock-ensure beg end)

    (boost-gptel--org-delete-src-overlays beg end)

    ;; Code contents, identified by Org's own `src-block' property.
    (dolist (region
             (boost-gptel--org-src-property-regions beg end))
      (boost-gptel--org-put-src-overlay
       (car region)
       (cdr region)
       'org-block))

    ;; Delimiter lines do not necessarily carry `src-block'.
    (save-excursion
      (goto-char beg)

      (while (re-search-forward
              "^[ \t]*#\\+begin_src\\(?:[ \t].*\\)?$"
              end t)
        (boost-gptel--org-put-src-overlay
         (line-beginning-position)
         (min (1+ (line-end-position)) end)
         'org-block-begin-line))

      (goto-char beg)

      (while (re-search-forward
              "^[ \t]*#\\+end_src[ \t]*$"
              end t)
        (boost-gptel--org-put-src-overlay
         (line-beginning-position)
         (min (1+ (line-end-position)) end)
         'org-block-end-line)))))

(add-hook 'gptel-post-response-functions
          #'boost-gptel--org-refresh-src-backgrounds
          95)

(defun boost-gptel--chat-mode-setup ()
  "Configure presentation in buffers managed by `gptel-mode'."
  (visual-line-mode 1)
  (gptel-highlight-mode 1))

(add-hook 'gptel-mode-hook #'boost-gptel--chat-mode-setup)

;; Convenient chat sending (in GPTel conversation buffers).
(keymap-set gptel-mode-map "C-c C-c" #'gptel-send)

(defun boost--set-key-if-free (keymap key command &optional scope)
  "Bind KEY to COMMAND in KEYMAP only if KEY is unbound.
KEYMAP may be the map itself or a symbol naming it.
If already bound, emit a warning mentioning SCOPE (string)."
  (let* ((map (if (keymapp keymap)
                  keymap
                (when (and (symbolp keymap) (boundp keymap))
                  (symbol-value keymap))))
         (existing-binding (and map (lookup-key map key t))))
    (cond
     ((not map)
      (display-warning
       'boost
       "Keymap not available (yet)"
       :warning))
     ((or (null existing-binding) (numberp existing-binding))
      (define-key map key command))
     (t
      (when init-file-debug
        (display-warning
         'boost
         (format "Keyboard shortcut %s conflicts with an existing one%s!"
                 (key-description key)
                 (if scope (format " in %s" scope) ""))
         :warning))))))

(with-eval-after-load 'org
  (define-key org-mode-map (kbd "C-c <return>") nil))

;; Quick access to gptel-send (only if key is free).
(boost--set-key-if-free global-map (kbd "C-c <return>")
                        #'gptel-send "global map")

(global-set-key (kbd "C-c C-<return>") #'gptel-send)

;; Keep the streaming response visible.
(add-hook 'gptel-post-stream-hook #'gptel-auto-scroll)

(defun boost-gptel--scroll-to-end-of-response (_beg _end)
  "Move point to the end of the dedicated *gptel* buffer.

Do nothing when the GPTel response belongs to another buffer."
  (when (string= (buffer-name) "*gptel*")
    (let ((pos (point-max)))
      (goto-char pos)
      (dolist (window (get-buffer-window-list (current-buffer) nil t))
        (set-window-point window pos)))))

(add-hook 'gptel-post-response-functions
          #'boost-gptel--scroll-to-end-of-response
          90)

(defun boost-gptel--after-response (beg end)
  "Run lightweight UI actions after a response from BEG to END."
  (when (> end beg)
    (when boost-gptel-move-point-after-response
      (gptel-end-of-response beg end))
    (message "[GPTel response completed: %d character%s]"
             (- end beg)
             (if (= (- end beg) 1) "" "s"))))

(add-hook 'gptel-post-response-functions #'boost-gptel--after-response 100)

(defun boost-gptel-clear-buffer ()
  "Clear the current GPTel chat buffer and insert a fresh prompt."
  (interactive)
  (when (y-or-n-p "Clear chat buffer? ")
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (or (alist-get major-mode gptel-prompt-prefix-alist)
                  "Prompt "))
      (goto-char (point-max)))))

(keymap-set gptel-mode-map "C-c M-k" #'boost-gptel-clear-buffer)

(defun boost-gptel-previous-prompt ()
  "Jump to the previous GPTel prompt."
  (interactive)
  (let ((prefix (or (cdr (assq major-mode gptel-prompt-prefix-alist))
                    "### ")))
    (search-backward prefix nil t)))

(defun boost-gptel-next-prompt ()
  "Jump to the next GPTel prompt."
  (interactive)
  (let ((prefix (or (cdr (assq major-mode gptel-prompt-prefix-alist))
                    "### ")))
    (forward-char 1)
    (search-forward prefix nil t)
    (goto-char (match-beginning 0))))

(define-key gptel-mode-map (kbd "C-c C-p")
            #'boost-gptel-previous-prompt)

(define-key gptel-mode-map (kbd "C-c C-n")
            #'boost-gptel-next-prompt)

(define-key gptel-mode-map (kbd "M-p")
            #'boost-gptel-previous-prompt)

(define-key gptel-mode-map (kbd "M-n")
            #'boost-gptel-next-prompt)

(defun boost-gptel--directive (name)
  "Return directive NAME or signal a user-facing error."
  (or (alist-get name gptel-directives)
      (user-error "Unknown GPTel directive: %s" name)))

(defun boost-gptel--write-result (buffer response info)
  "Write a GPTel RESPONSE and INFO event into BUFFER."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (cond
         ((plist-get info :error)
          (insert
           (format "\nRequest failed: %s\n"
                   (or (plist-get info :error)
                       (plist-get info :status)
                       "unknown error"))))
         ((stringp response)
          (insert response))
         ((eq response t)
          (unless (bolp) (insert "\n"))
          (insert "\nRequest completed.\n"))
         ((eq response 'abort)
          (insert "\nRequest aborted.\n")))))))

(defun boost-gptel--result-callback (buffer)
  "Return a callback that writes GPTel events into BUFFER."
  (apply-partially #'boost-gptel--write-result buffer))

(defun boost-gptel--request-in-new-buffer (title prompt directive)
  "Send PROMPT with DIRECTIVE and display the result under TITLE."
  (let* ((buffer (generate-new-buffer (format "*gptel: %s*" title)))
         (backend gptel-backend)
         (model gptel-model)
         (backend-name
          (when backend
            (gptel-backend-name backend)))
         (gptel-use-context nil)
         (gptel-context nil)
         (gptel-use-tools nil)
         (gptel-tools nil)
         (gptel-include-reasoning nil)
         (gptel-temperature nil))
    (with-current-buffer buffer
      (org-mode)
      (insert "#+TITLE:     " title "\n")
      (insert "#+GPTEL_BACKEND: " (or backend-name "unknown") "\n")
      (insert "#+GPTEL_MODEL: " (format "%s" model) "\n\n")
      (insert "* Response\n\n"))
    (display-buffer buffer)
    (gptel-request
        prompt
      :system (boost-gptel--directive directive)
      :stream nil
      :callback (boost-gptel--result-callback buffer))
    buffer))

(defun boost-gptel-explain-region (beg end)
  "Explain the active region between BEG and END."
  (interactive "R")                     ; Emacs 31.1.
  (unless beg
    (user-error "Select a region first"))
  (let ((source
         (boost-gptel--buffer-substring-limited
          beg
          end
          boost-gptel-command-max-input-chars)))
    (boost-gptel--request-in-new-buffer
     "Region explanation"
     (format
      (concat
       "Explain the following material. "
       "Describe its purpose, structure, important assumptions, "
       "and likely failure modes.\n\n%s")
      source)
     'programming)))

(defun boost-gptel-summarize-buffer ()
  "Summarize the current buffer in a new Org buffer."
  (interactive)
  (let ((source
         (boost-gptel--buffer-substring-limited
          (point-min)
          (point-max)
          boost-gptel-command-max-input-chars)))
    (boost-gptel--request-in-new-buffer
     (format "Summary of %s" (buffer-name))
     (format "Summarize the following source faithfully.\n\n%s" source)
     'summarize)))

(defvar boost-gptel-default-target-languages
  '("French" "Dutch" "English" "Spanish")
  "List of default target languages proposed to `boost-gptel-translate-region'.")

(defun boost-gptel-translate-region (beg end target-language)
  "Translate the active region between BEG and END to TARGET-LANGUAGE."
  (interactive
   (if (use-region-p)
       (list
        (region-beginning)
        (region-end)
        (completing-read "Target language: "
                         boost-gptel-default-target-languages
                         nil        ;; Predicate.
                         nil        ;; Require-match (nil = allow custom input).
                         nil        ;; Initial-input.
                         nil        ;; History.
                         "English")) ;; Default.
     (user-error "Select a region first")))
  (let ((source
         (boost-gptel--buffer-substring-limited
          beg
          end
          boost-gptel-command-max-input-chars)))
    (boost-gptel--request-in-new-buffer
     (format "Translation to %s" target-language)
     (string-join
      (list
       "Translate the following text to " target-language ". "
       "Preserve meaning, formatting, names, numbers, and technical terms. "
       "Return only the translation.\n\n"
       source)
      "")
     'writing)))

(defvar-keymap boost-gptel-prefix-map
  :doc "Prefix map for GPTel commands."
  :prefix t

  "g" #'gptel                           ; Chat.
  "s" #'gptel-send                      ; Send.
  "m" #'gptel-menu                      ; Change configuration.
  "r" #'gptel-rewrite                   ; Rewrite this.
  "a" #'gptel-add                       ; AI, know about this.
  "f" #'gptel-add-file

  "p" #'boost-gptel-add-project-context
  "c" #'boost-gptel-clear-buffer-context
  "i" #'boost-gptel-show-context
  "e" #'boost-gptel-explain-region
  "S" #'boost-gptel-summarize-buffer
  "t" #'boost-gptel-translate-region)

(global-set-key (kbd "C-c g") boost-gptel-prefix-map)

(defcustom boost-gptel-enable-mcp-integration nil
  "Whether to load GPTel's optional MCP integration library."
  :type 'boolean
  :group 'boost-gptel)

(when boost-gptel-enable-mcp-integration
  (require 'gptel-integrations nil 'noerror))

(defun boost-gptel-describe-active-configuration ()
  "Display the active GPTel configuration without revealing API keys."
  (interactive)
  (with-help-window "*boost-gptel-configuration*"
    (princ "Active GPTel configuration\n\n")
    (pp
     (list
      :backend
      (when gptel-backend
        (gptel-backend-name gptel-backend))
      :model gptel-model
      :stream gptel-stream
      :temperature gptel-temperature
      :max-tokens gptel-max-tokens
      :system-prompt
      (cond
       ((stringp gptel-system-prompt) "string")
       ((functionp gptel-system-prompt) "function")
       ((listp gptel-system-prompt) "conversation-template")
       (t nil))
      :use-context gptel-use-context
      :context-count (length gptel-context)
      :use-tools gptel-use-tools
      :tools (mapcar #'gptel-tool-name gptel-tools)
      :confirm-tool-calls gptel-confirm-tool-calls
      :include-tool-results gptel-include-tool-results
      :include-reasoning gptel-include-reasoning
      :track-media gptel-track-media
      :log-level gptel-log-level))))

(defun boost-gptel-toggle-debug-logging ()
  "Toggle GPTel debug logging for the current Emacs session."
  (interactive)
  (setq gptel-log-level
        (if (eq gptel-log-level 'debug) nil 'debug))
  (message "[GPTel logging: %s]" (or gptel-log-level "disabled")))

(keymap-set boost-gptel-prefix-map
            "d" #'boost-gptel-describe-active-configuration)
(keymap-set boost-gptel-prefix-map
            "l" #'boost-gptel-toggle-debug-logging)

(require 'gptel-commit-msg nil 'noerror)

(when (locate-library "uuid")
  (require 'gptel-proof nil 'noerror))

(provide 'emacs-boost-gptel)

;;; emacs-boost-gptel.el ends here
