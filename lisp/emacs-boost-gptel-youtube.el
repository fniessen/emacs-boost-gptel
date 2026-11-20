;;; emacs-boost-gptel-youtube.el --- YouTube transcript support -*- lexical-binding: t; -*-

(require 'seq)
(require 'subr-x)
(require 'url)
(require 'gptel-agent-tools nil 'noerror)

(declare-function gptel-agent--yt-parse-captions "gptel-agent-tools" (xml-string))
(declare-function gptel-agent--yt-format-captions "gptel-agent-tools" (caption-dom &optional chunk-time))
(declare-function gptel-agent--yt-fetch-captions "gptel-agent-tools" (callback description caption-tracks))
(declare-function gptel-agent--yt-video-id "gptel-agent-tools" (url))
(declare-function gptel-agent--yt-fetch-watch-page "gptel-agent-tools" (callback video-id))

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

(defconst boost-gptel-youtube-timeout 240
  "Maximum seconds to wait for a YouTube transcript or summary.")

(defun boost-gptel--youtube-transcript (url)
  "Fetch and return the transcript for YouTube URL without using an LLM."
  (unless (and (stringp url) (not (string-empty-p url)))
    (user-error "YouTube URL must not be empty"))
  (unless (and (fboundp 'gptel-agent--yt-video-id)
               (fboundp 'gptel-agent--yt-fetch-watch-page))
    (user-error "Install gptel-agent to fetch YouTube transcripts"))
  (let ((video-id (gptel-agent--yt-video-id url))
        (completed nil)
        (response nil))
    (unless video-id
      (user-error "Not a supported YouTube video URL: %s" url))
    (gptel-agent--yt-fetch-watch-page
     (lambda (result)
       (setq response result
             completed t))
     video-id)
    (let ((deadline (+ (float-time) boost-gptel-youtube-timeout)))
      (while (and (not completed)
                  (< (float-time) deadline))
        (accept-process-output nil 1)))
    (unless completed
      (error "YouTube transcript timed out after %d seconds"
             boost-gptel-youtube-timeout))
    (let ((start (and (stringp response)
                      (string-match
                       "^# Transcript\\(?: ([^)]*)\\)?\n\n" response))))
      (unless start
        (error "Could not fetch YouTube transcript: %s" response))
      (setq response (substring response (match-end 0)))
      (when (or (string-match-p
                 "\\`\\(?:Error\\|No transcript available\\)" response)
                (string-empty-p (string-trim response)))
        (error "Could not fetch YouTube transcript: %s" response))
      (string-trim-right response))))

(defun boost-gptel-youtube-transcript-to-stdout (url)
  "Fetch the transcript for YouTube URL and print it to stdout."
  (let ((transcript (boost-gptel--youtube-transcript url)))
    (princ transcript)
    (princ "\n")
    transcript))

(provide 'emacs-boost-gptel-youtube)

;;; emacs-boost-gptel-youtube.el ends here
