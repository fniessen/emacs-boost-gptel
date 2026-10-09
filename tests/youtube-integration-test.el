;;; youtube-integration-test.el --- Live GPTel YouTube integration -*- lexical-binding: t; -*-

(require 'ert)
(require 'emacs-boost-gptel)
(require 'gptel-agent)

(defconst boost-gptel-test-youtube-url
  "https://www.youtube.com/watch?v=sD5sKXG2w7s"
  "Video used by the live YouTube transcript integration test.")

(defconst boost-gptel-test-youtube-timeout boost-gptel-youtube-timeout
  "Maximum seconds to wait for the live YouTube summary request.")

(defun boost-gptel-test--youtube-response-complete-p ()
  "Return non-nil when the live YouTube summary response has completed."
  (or (and (boundp 'gptel--fsm-last)
           gptel--fsm-last
           (not (gptel--fsm-live-p gptel--fsm-last)))
      (and (boundp 'gptel--fsm-last)
           gptel--fsm-last
           (memq (gptel-fsm-state gptel--fsm-last) '(DONE ERRS ABRT)))))

(defun boost-gptel-test--youtube-summary (text)
  "Return the final model response from gptel chat TEXT."
  (let ((start 0)
        (end nil)
        (marker (regexp-quote "#+end_tool")))
    (while (string-match marker text start)
      (setq end (match-end 0)
            start end))
    (when end
      (string-trim (substring text end)))))

(defun boost-gptel-test--youtube-numbered-points (text)
  "Count numbered list items in summary TEXT."
  (let ((start 0)
        (count 0)
        (regexp "^[ \t]*[1-8][.)][ \t]+"))
    (while (string-match regexp text start)
      (setq count (1+ count)
            start (match-end 0)))
    count))

(ert-deftest boost-gptel-live-youtube-summary ()
  "Fetch captions and summarize a short YouTube video through OpenAI."
  (unless boost-gptel-openai-backend
    (ert-fail "OpenAI backend is not configured"))
  (unless (file-readable-p (expand-file-name "~/.openai_api_key"))
    (ert-fail "OpenAI API key file ~/.openai_api_key is unavailable"))
  (let ((gptel-backend boost-gptel-openai-backend)
        (gptel-model boost-gptel-openai-model)
        (default-directory temporary-file-directory)
        buffer
        completed)
    (message "Live integration test: sending a YouTube request to OpenAI.")
    (unwind-protect
        (progn
          (setq buffer
                (boost-gptel-summarize-youtube boost-gptel-test-youtube-url))
          (with-current-buffer buffer
            (add-hook 'gptel-post-response-functions
                      (lambda (&rest _)
                        (setq completed t))
                      nil t))
          (let ((deadline (+ (float-time) boost-gptel-test-youtube-timeout)))
            (while (and (not completed)
                        (< (float-time) deadline)
                        (not (boost-gptel-test--youtube-response-complete-p)))
              (accept-process-output nil 1)))
          (unless (or completed
                      (boost-gptel-test--youtube-response-complete-p))
            (gptel-abort buffer)
            (ert-fail
             (format "OpenAI request timed out after %d seconds"
                     boost-gptel-test-youtube-timeout)))
          (with-current-buffer buffer
            (let* ((chat (buffer-string))
                   (summary (boost-gptel-test--youtube-summary chat)))
              (unless (string-match-p "# Transcript (" chat)
                (ert-fail "gptel did not include a YouTube transcript"))
              (unless (string-match-p "\\[[0-9]+:[0-9][0-9]\\]" chat)
                (ert-fail "YouTube transcript contains no timestamps"))
              (unless (and summary (not (string-empty-p summary)))
                (ert-fail "OpenAI returned no final summary"))
              (unless (>= (boost-gptel-test--youtube-numbered-points summary) 8)
                (ert-fail "OpenAI summary contains fewer than eight numbered points")))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(provide 'youtube-integration-test)

;;; youtube-integration-test.el ends here
