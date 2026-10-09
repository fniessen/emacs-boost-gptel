;;; agent-todo-test.el --- TODO tests for coding agents -*- lexical-binding: t; -*-

;; These tests deliberately start skipped. An agent should implement the
;; assertions and remove the corresponding `ert-skip' as each item is solved.

(require 'ert)
(require 'emacs-boost-gptel)

(ert-deftest boost-gptel-agent-todo-tool-registration ()
  "TODO: verify every tool named by a preset is registered exactly once."
  (ert-skip "Agent TODO: inspect presets and gptel-tools."))

(ert-deftest boost-gptel-agent-todo-write-confirmation ()
  "TODO: verify every mutating tool requires confirmation."
  (ert-skip "Agent TODO: inspect tool objects and confirmation properties."))

(ert-deftest boost-gptel-agent-todo-sensitive-buffer ()
  "TODO: verify sensitive buffers are rejected by read_buffer."
  (ert-skip "Agent TODO: create a matching buffer and assert user-error."))

(ert-deftest boost-gptel-agent-todo-invalid-search-regexp ()
  "TODO: verify search_project_files reports invalid regexps clearly."
  (ert-skip "Agent TODO: call the search helper with an invalid regexp."))

(ert-deftest boost-gptel-agent-todo-symlink-write-boundary ()
  "TODO: verify rename and delete cannot cross a symlink boundary."
  (ert-skip "Agent TODO: create a temporary project and an escaping symlink."))

(ert-deftest boost-gptel-agent-todo-output-limits ()
  "TODO: verify project search and reads respect configured output limits."
  (ert-skip "Agent TODO: bind small limits and assert truncation and bounds."))

(provide 'agent-todo-test)

;;; agent-todo-test.el ends here
