(require 'albin-timeclock)
(require 'nerd-icons)
(require 'recentf)
(require 'project)
(require 'org-agenda)
(require 'org-capture)
(require 'seq)

;; Initialize the random seed and Recentf
(random t)
(recentf-mode 1)

;; ==========================================
;; KONSTANTER
;; ==========================================

(defconst albin-dashboard-right-col 63
  "Screen column where right-column content starts.")

(defconst albin-dashboard-bar-max-width 8
  "Maximum number of filled blocks in the weekly bar chart (one block per hour).")

(defconst albin-dashboard-agenda-days 3
  "Number of days to show in the agenda widget (today + N-1 upcoming days).")

(defconst albin-dashboard-left-width 58
  "Suggested visual width for the left dashboard column.")

(defconst albin-dashboard-min-gap 4
  "Minimum spacing between left and right columns.")

(defvar albin-dashboard--render-window nil
  "Window used to compute dashboard layout during rendering.")

;; ==========================================
;; 1. KEYMAP AND MODE
;; ==========================================

(defvar albin-dashboard-mode-map (make-sparse-keymap)
  "Keymap for Albin Dashboard.")

(define-key albin-dashboard-mode-map (kbd "i") 'albin/timeclock-in)
(define-key albin-dashboard-mode-map (kbd "o") 'albin/timeclock-out)
(define-key albin-dashboard-mode-map (kbd "b") 'albin/timeclock-break)
(define-key albin-dashboard-mode-map (kbd "r") 'albin/timeclock-resume)
(define-key albin-dashboard-mode-map (kbd "C") 'albin/timeclock-change)
(define-key albin-dashboard-mode-map (kbd "p") 'albin/timeclock-switch-profile)
(define-key albin-dashboard-mode-map (kbd "P") 'albin/timeclock-edit-project)
(define-key albin-dashboard-mode-map (kbd "e") 'albin/timeclock-export-csv)
(define-key albin-dashboard-mode-map (kbd "s") 'albin/timeclock-weekly-summary)
(define-key albin-dashboard-mode-map (kbd "d") 'albin/timeclock-open-diary)
(define-key albin-dashboard-mode-map (kbd "c") 'org-capture)
(define-key albin-dashboard-mode-map (kbd "g") 'albin/dashboard)
(define-key albin-dashboard-mode-map (kbd "q") 'quit-window)

(define-derived-mode albin-dashboard-mode special-mode "Dashboard"
  "A custom dashboard mode for Albin's Emacs."
  (setq buffer-read-only t)
  (setq truncate-lines t)
  (use-local-map albin-dashboard-mode-map)
  (when (bound-and-true-p display-line-numbers-mode)
    (display-line-numbers-mode -1)))

(with-eval-after-load 'evil
  ;; Motion state keeps the buffer read-only while allowing Doom leader keys.
  (evil-set-initial-state 'albin-dashboard-mode 'motion)
  ;; Ensure one-key dashboard shortcuts work in Evil states too.
  (evil-define-key '(motion normal) albin-dashboard-mode-map
    (kbd "i") #'albin/timeclock-in
    (kbd "o") #'albin/timeclock-out
    (kbd "b") #'albin/timeclock-break
    (kbd "r") #'albin/timeclock-resume
    (kbd "C") #'albin/timeclock-change
    (kbd "p") #'albin/timeclock-switch-profile
    (kbd "P") #'albin/timeclock-edit-project
    (kbd "e") #'albin/timeclock-export-csv
    (kbd "s") #'albin/timeclock-weekly-summary
    (kbd "d") #'albin/timeclock-open-diary
    (kbd "c") #'org-capture
    (kbd "g") #'albin/dashboard
    (kbd "q") #'quit-window))

;; ==========================================
;; 2. WEATHER AND QUOTES
;; ==========================================

(defvar albin-dashboard-weather-string "Fetching weather..."
  "Stores the latest weather data.")

(defun albin/dashboard-fetch-weather ()
  "Fetches weather data asynchronously."
  (when (executable-find "curl")
    (make-process
     :name "dashboard-weather"
     :buffer (generate-new-buffer " *dashboard-weather*")
     :command '("curl" "-s" "wttr.in/Jonkoping?format=3")
     :sentinel (lambda (proc event)
                 (when (string-match-p "finished" event)
                   (with-current-buffer (process-buffer proc)
                     (goto-char (point-min))
                     (let ((result (string-trim (buffer-string))))
                       (if (string-prefix-p "Unknown" result)
                           (setq albin-dashboard-weather-string "Could not fetch weather")
                         (setq albin-dashboard-weather-string result))))
                   (kill-buffer (process-buffer proc))
                   (when (get-buffer "*Albin Dashboard*")
                     (albin/dashboard t)))))))

(albin/dashboard-fetch-weather)

(defvar albin-dashboard-quotes
  '("Welcome home. Everything is a buffer."
    "M-x is not a command. It is a lifestyle."
    "C-h k shows what a key does."
    "C-h f explains any function."
    "C-h v explains any variable."
    "C-x b is often faster than mouse navigation."
    "M-/ expands words from open buffers."
    "C-x 1 focuses the current window."
    "Org is your planner. Roam is your map."
    "Keep notes small. Links make them powerful.")
  "A list of nerd quotes and Emacs tips.")

;; ==========================================
;; 3. HELPERS
;; ==========================================

(defun albin/dashboard-sep ()
  "Insert a horizontal separator for the left column."
  (insert (propertize "  -----------------------------------------------------\n"
                      'face 'font-lock-comment-face)))

(defun albin/dashboard-section-header (icon title)
  "Insert a styled section header with ICON and TITLE."
  (insert (propertize (format " %s %s\n" icon title)
                      'face '(:inherit font-lock-keyword-face :weight bold)))
  (albin/dashboard-sep))

(defun albin/dashboard-right-column-start ()
  "Return an adaptive start column for the right-hand widgets."
  (let* ((win (if (window-live-p albin-dashboard--render-window)
                  albin-dashboard--render-window
                (selected-window)))
         (width (window-body-width win))
         (target (max albin-dashboard-right-col
                      (+ albin-dashboard-left-width albin-dashboard-min-gap))))
    (min target (- width 32))))

(defun albin/dashboard-progress-bar (ratio width)
  "Return a simple text progress bar from RATIO with total WIDTH.
RATIO is clamped to [0,1]."
  (let* ((clamped (max 0.0 (min 1.0 ratio)))
         (filled (round (* clamped width)))
         (empty (max 0 (- width filled))))
    (concat (make-string filled ?#) (make-string empty ?.))))

(defun albin/dashboard-insert-button-inline (label func &optional face)
  "Insert a clickable button inline (no leading spaces or trailing newline)."
  (insert-text-button
   (concat "[ " label " ]")
   'action (lambda (_)
             (cond ((commandp func) (call-interactively func))
                   ((functionp func) (funcall func)))
             (albin/dashboard))
   'follow-link t
   'face (or face 'font-lock-function-name-face)))

;; ==========================================
;; 4. WIDGETS (LEFT SIDE)
;; ==========================================

(defun albin/dashboard-insert-banner ()
  "Insert an Emacs-style startup banner."
  (let ((banner "
   _____                          
  | ____|_ __ ___   __ _  ___ ___ 
  |  _| | '_ ` _ \\ / _` |/ __/ __|
  | |___| | | | | | (_| | (__\\__ \\
  |_____|_| |_| |_|\\__,_|\\___|___/
"))
    (insert (propertize banner 'face 'font-lock-keyword-face))
    (insert (propertize "  GNU's Not Unix. Lisp all the way down.\n"
                        'face 'font-lock-doc-face))
    (insert "\n")))

(defun albin/dashboard-insert-quote ()
  "Insert a random Emacs tip."
  (let* ((idx (random (length albin-dashboard-quotes)))
         (q (nth idx albin-dashboard-quotes)))
    (insert "  ")
    (insert (propertize (format "Tip of the moment: %s" q) 'face 'font-lock-doc-face))
    (insert "\n\n")))

(defun albin/dashboard-insert-startup-widget ()
  "Insert startup/session information with an Emacs flavor."
  (albin/dashboard-section-header (nerd-icons-mdicon "nf-md-rocket_launch") "SESSION")
  (let* ((pkg-count (if (boundp 'package-activated-list)
                        (length package-activated-list)
                      0))
         (buffers (length (buffer-list)))
         (hour (string-to-number (format-time-string "%H")))
         (min (string-to-number (format-time-string "%M")))
         (day-ratio (/ (+ (* hour 60.0) min) (* 24.0 60.0))))
    (insert (format "  %-18s %s\n" "Today:" (format-time-string "%A, %d %B %Y")))
    (insert (format "  %-18s %s\n" "Current time:" (format-time-string "%H:%M")))
    (insert (format "  %-18s %s\n" "Init time:" (emacs-init-time)))
    (insert (format "  %-18s [%s] %d%%\n"
                    "Day progress:"
                    (albin/dashboard-progress-bar day-ratio 18)
                    (round (* day-ratio 100))))
    (insert (format "  %-18s %d\n" "Open buffers:" buffers))
    (insert (format "  %-18s %d\n" "Packages active:" pkg-count))
    (insert (format "  %-18s %d\n" "GC cycles:" gcs-done))
    (insert "\n")))

(defun albin/dashboard-insert-roam-widget ()
  "Insert a compact org-roam summary."
  (albin/dashboard-section-header (nerd-icons-mdicon "nf-md-graph") "ORG + ROAM")
  (let* ((roam-ready (and (boundp 'org-roam-directory) org-roam-directory))
         (roam-dir (when roam-ready (expand-file-name org-roam-directory)))
         (org-files (if (and roam-dir (file-directory-p roam-dir))
                        (directory-files-recursively roam-dir "\\.org$")
                      '()))
         (daily-file (if roam-dir
                         (expand-file-name (format-time-string "%Y-%m-%d.org")
                                           (expand-file-name "daily" roam-dir))
                       nil)))
    (insert (format "  %-18s %s\n"
                    "Org directory:"
                    (if roam-ready (abbreviate-file-name roam-dir) "Not configured")))
    (insert (format "  %-18s %s\n"
                    "Org files:"
                    (if roam-ready (number-to-string (length org-files)) "0")))
    (insert (format "  %-18s %s\n"
                    "Daily note:"
                    (if (and daily-file (file-exists-p daily-file))
                        (propertize "Present" 'face 'success)
                      (propertize "Not created" 'face 'warning))))
    (insert (format "  %-18s %s\n"
                    "Weather:"
                    (propertize albin-dashboard-weather-string 'face 'font-lock-string-face)))
    (insert "\n")))

(defun albin/dashboard-insert-jump-widget ()
  "Insert quick-jump links to frequently edited config files."
  (albin/dashboard-section-header (nerd-icons-octicon "nf-oct-file_code") "JUMP")
  (insert "  ")
  (albin/dashboard-insert-button-inline
   "config.el"
   (lambda () (find-file (expand-file-name "config.el" doom-user-dir)))
   'font-lock-constant-face)
  (insert "  ")
  (albin/dashboard-insert-button-inline
   "init.el"
   (lambda () (find-file (expand-file-name "init.el" doom-user-dir)))
   'font-lock-constant-face)
  (insert "  ")
  (albin/dashboard-insert-button-inline
   "packages.el"
   (lambda () (find-file (expand-file-name "packages.el" doom-user-dir)))
   'font-lock-constant-face)
  (insert "\n  ")
  (albin/dashboard-insert-button-inline
   "dashboard.el"
   (lambda () (find-file (expand-file-name "lisp/albin-dashboard.el" doom-user-dir)))
   'font-lock-constant-face)
  (insert "\n\n"))

(defun albin/dashboard-insert-timeclock-widget ()
  "Insert the time tracking status widget."
  (albin/dashboard-section-header (nerd-icons-faicon "nf-fa-bar_chart") "TIME STATUS")
  (let* ((raw-sessions (albin/get-timelog-sessions))
         (merged-sessions (albin/prepare-report-sessions raw-sessions))
         (sessions (car (albin/apply-time-carry merged-sessions)))
         (flex-data (albin/calculate-flex merged-sessions))
         (total-flex (nth 0 flex-data))
         (is-clocked-in (and timeclock-last-event (string= (car timeclock-last-event) "i")))
         (current-proj (if is-clocked-in (nth 2 timeclock-last-event) nil))
         (session-start (if is-clocked-in (nth 1 timeclock-last-event) nil))
         (elapsed-hours (if is-clocked-in
                            (/ (float-time (time-subtract (current-time) session-start)) 3600.0)
                          0.0))
         (daily-hours (make-hash-table :test 'equal))
         (today-str (format-time-string "%Y-%m-%d")))

    (dolist (s sessions)
      (let ((date (nth 0 s)) (hrs (nth 3 s)))
        (puthash date (+ (gethash date daily-hours 0.0) hrs) daily-hours)))

        (let* ((logged-today (gethash today-str daily-hours 0.0))
           ;; Include the currently open session in today's running total
          (today-hours (+ logged-today elapsed-hours))
          (to-target (max 0.0 (- 8.0 today-hours))))
      (insert (format "  %-16s %s\n" "Current profile:"
                      (propertize albin-timeclock-current-profile 'face 'font-lock-string-face)))
      (insert (format "  %-16s %s\n" "Total Flex:"
                      (propertize (format "%s%.2f h" (if (> total-flex 0) "+" "") total-flex)
                                  'face (if (>= total-flex 0) 'success 'error))))
      (insert (format "  %-16s %s\n" "Status:"
                      (if is-clocked-in
                          (propertize (format "● Clocked in on %s (%s)"
                                             current-proj
                                             (albin/format-hours-to-hm elapsed-hours))
                                      'face 'success)
                        (propertize "○ Clocked out / On break" 'face 'warning))))
      (insert (format "  %-16s %s\n" "Today:"
                      (propertize (format "%.2f h" today-hours) 'face 'font-lock-constant-face)))
      (insert (format "  %-16s %s\n"
                      "To 8h target:"
                      (if (> to-target 0.0)
                          (propertize (format "%.2f h left" to-target) 'face 'warning)
                        (propertize "Target met" 'face 'success)))))

    ;; 7-day mini bar chart with labeled day-of-week row
    (let* ((today (current-time))
           (bars ["_" "▁" "▂" "▃" "▄" "▅" "▆" "▇" "█"])
           (day-chars ["M" "Tu" "W" "Th" "F" "Sa" "Su"]))
      (insert (format "  %-16s" "Last 7 days:"))
      (dotimes (i 7)
        (let* ((day-time (time-subtract today (days-to-time (- 6 i))))
               (date-str (format-time-string "%Y-%m-%d" day-time))
               (hrs (gethash date-str daily-hours 0.0))
               (bar-idx (min albin-dashboard-bar-max-width (max 0 (round hrs))))
               (bar-char (aref bars bar-idx))
               (color (cond ((>= hrs 8.0) 'success)
                            ((> hrs 0.0) 'warning)
                            (t 'font-lock-comment-face))))
          (insert (propertize bar-char 'face color))
          (insert " ")))
      (insert "\n")
      ;; Day-of-week labels
      (insert (format "  %-16s" ""))
      (dotimes (i 7)
        (let* ((day-time (time-subtract today (days-to-time (- 6 i))))
               (dow (1- (string-to-number (format-time-string "%u" day-time))))
               (day-char (aref day-chars dow))
               (is-today (= i 6)))
          (insert (propertize day-char
                              'face (if is-today 'font-lock-keyword-face 'font-lock-comment-face)))
          (insert " ")))
      (insert "\n\n"))))

(defun albin/dashboard-insert-agenda ()
  "Insert upcoming org-agenda items for today and the next few days.
The number of days shown is controlled by `albin-dashboard-agenda-days'."
  (albin/dashboard-section-header (nerd-icons-faicon "nf-fa-calendar") "UPCOMING AGENDA")
  (if (not org-agenda-files)
      (insert "  No org-agenda files are configured.\n")
    (let ((any-entries nil))
      (dotimes (offset albin-dashboard-agenda-days)
        (let* ((date-time (time-add (current-time) (days-to-time offset)))
               (decoded (decode-time date-time))
               ;; org-agenda-get-day-entries expects (month day year)
               (date (list (nth 4 decoded) (nth 3 decoded) (nth 5 decoded)))
               (day-label (cond ((= offset 0) "Today")
                                ((= offset 1) "Tomorrow")
                                (t (format-time-string "%A" date-time))))
               (entries (apply 'append
                               (mapcar (lambda (file)
                                         (condition-case nil
                                             (org-agenda-get-day-entries file date :scheduled :deadline :timestamp)
                                           (error nil)))
                                       (org-agenda-files)))))
          (when entries
            (setq any-entries t)
            (insert (format "  %s\n"
                            (propertize day-label 'face 'font-lock-variable-name-face)))
            ;; Show up to 5 items per day to keep the widget compact
            (dolist (entry (seq-take entries 5))
              (let ((txt (get-text-property 0 'txt entry)))
                (insert (format "  • %s\n" (string-trim txt))))))))
      (unless any-entries
        (insert (format "  Nothing planned! %s\n" (nerd-icons-faicon "nf-fa-smile_o"))))))
  (insert "\n"))

(defun albin/dashboard-insert-projects ()
  "Insert known project list."
  (albin/dashboard-section-header (nerd-icons-faicon "nf-fa-folder_open") "PROJECTS")
  (let ((projs (when (boundp 'project-known-project-roots) project-known-project-roots)))
    (if projs
        (dolist (proj (seq-take projs 5))
          (let ((p proj))
            (insert "  ")
            (insert-text-button
             (abbreviate-file-name p)
             'action (lambda (_) (find-file p))
             'follow-link t
             'face 'font-lock-constant-face)
            (insert "\n")))
        (insert "  No projects tracked yet. Visit one and it will show up here.\n")))
  (insert "\n"))

(defun albin/dashboard-insert-recentf ()
  "Insert recently opened files."
  (albin/dashboard-section-header (nerd-icons-faicon "nf-fa-file_text_o") "RECENT FILES")
  (if recentf-list
      (dolist (file (seq-take recentf-list 5))
        (let ((f file))
          (insert "  ")
          (insert-text-button
           (file-name-nondirectory f)
           'action (lambda (_) (find-file f))
           'follow-link t
           'face 'font-lock-keyword-face)
          (insert (propertize (concat "  " (abbreviate-file-name (file-name-directory f)))
                              'face 'font-lock-comment-face))
          (insert "\n")))
    (insert "  No recent files found.\n"))
  (insert "\n"))

(defun albin/dashboard-insert-quick-commands ()
  "Insert command center buttons in an Emacs-centric layout."
  (albin/dashboard-section-header (nerd-icons-mdicon "nf-md-keyboard") "COMMAND CENTER")
  ;; Row 1: core Emacs
  (insert "  ")
  (albin/dashboard-insert-button-inline "M-x" 'execute-extended-command 'font-lock-keyword-face)
  (insert "  ")
  (albin/dashboard-insert-button-inline "Find file" 'find-file 'font-lock-keyword-face)
  (insert "  ")
  (albin/dashboard-insert-button-inline "Switch buffer" 'switch-to-buffer 'font-lock-keyword-face)
  (insert "\n  ")
  ;; Row 2: org/notes
  (albin/dashboard-insert-button-inline "Capture (c)" 'org-capture 'font-lock-doc-face)
  (insert "  ")
  (albin/dashboard-insert-button-inline "Agenda" 'org-agenda 'font-lock-doc-face)
  (insert "  ")
  (when (fboundp 'org-roam-node-find)
    (albin/dashboard-insert-button-inline "Roam find" 'org-roam-node-find 'font-lock-doc-face))
  (insert "  ")
  (when (fboundp 'org-roam-dailies-capture-today)
    (albin/dashboard-insert-button-inline "Daily" 'org-roam-dailies-capture-today 'font-lock-doc-face))
  (insert "\n  ")
  ;; Row 3: timeclock
  (albin/dashboard-insert-button-inline "IN (i)" 'albin/timeclock-in 'success)
  (insert "  ")
  (albin/dashboard-insert-button-inline "OUT (o)" 'albin/timeclock-out 'error)
  (insert "  ")
  (albin/dashboard-insert-button-inline "Break (b)" 'albin/timeclock-break 'warning)
  (insert "  ")
  (albin/dashboard-insert-button-inline "Resume (r)" 'albin/timeclock-resume)
  (insert "\n  ")
  ;; Row 4: dashboard flow
  (albin/dashboard-insert-button-inline "Refresh (g)" 'albin/dashboard 'font-lock-comment-face)
  (insert "  ")
  (albin/dashboard-insert-button-inline "Quit (q)" 'quit-window 'font-lock-comment-face)
  (insert "\n\n"))

(defun albin/dashboard-insert-focus-widget ()
  "Insert today's priority slice from org agenda entries."
  (albin/dashboard-section-header (nerd-icons-mdicon "nf-md-crosshairs_gps") "TODAY'S FOCUS")
  (let* ((decoded (decode-time (current-time)))
         (date (list (nth 4 decoded) (nth 3 decoded) (nth 5 decoded)))
         (entries (when org-agenda-files
                    (apply #'append
                           (mapcar (lambda (file)
                                     (condition-case nil
                                         (org-agenda-get-day-entries file date :scheduled :deadline :timestamp)
                                       (error nil)))
                                   (org-agenda-files)))))
         (items (seq-take entries 3)))
    (if (not items)
        (insert "  No urgent agenda entries for today. Capture one and make momentum.\n\n")
      (insert "  Next actions:\n")
      (dolist (entry items)
        (let ((txt (string-trim (or (get-text-property 0 'txt entry) ""))))
          (insert (format "  -> %s\n" txt))))
      (insert "\n"))))

(defun albin/dashboard-insert-tips ()
  "Insert compact key hints."
  (albin/dashboard-section-header (nerd-icons-codicon "nf-cod-terminal_cmd") "KEY HINTS")
  (insert "  ")
  (insert (propertize "C-h k  describe key   |   C-h f  describe function   |   M-x  command palette"
                      'face 'font-lock-comment-face))
  (insert "\n  ")
  (insert (propertize "i=in  o=out  b=break  r=resume  p=profile  C=switch  e=csv  s=week  d=diary  g=refresh  q=quit"
                      'face 'font-lock-comment-face))
  (insert "\n\n"))

(defun albin/dashboard-insert-footer ()
  "Insert footer with a startup-style message." 
  (insert "  ")
  (insert (propertize "Ready. Press g to refresh, q to close, or SPC n for your notes flow."
                      'face 'font-lock-comment-face))
  (insert "\n\n"))

;; ==========================================
;; 5. WIDGETS (RIGHT SIDE)
;; ==========================================

(defun albin/dashboard-get-month-logs ()
  "Return a list of propertized strings for this month's time log entries."
  (let* ((raw-sessions (albin/get-timelog-sessions))
         (merged-sessions (albin/merge-empty-sessions raw-sessions))
         (sessions (car (albin/apply-time-carry merged-sessions)))
         (current-month (format-time-string "%Y-%m"))
         (lines '())
         (total-month-hours 0.0)
         (month-sessions '()))

    (dolist (s sessions)
      (when (string-prefix-p current-month (nth 0 s))
        (push s month-sessions)
        (setq total-month-hours (+ total-month-hours (nth 3 s)))))

    (push (propertize (format "%s THIS MONTH'S ENTRIES"
                              (nerd-icons-faicon "nf-fa-clock_o"))
                      'face '(:inherit font-lock-type-face :weight bold))
          lines)
    (push (propertize "─────────────────────────────────────────────────"
                      'face 'font-lock-comment-face)
          lines)

    (if (null month-sessions)
        (push "No entries this month yet." lines)
      (push (format "Total accumulated: %s"
                    (propertize (format "%.2f h" total-month-hours) 'face 'success))
            lines)
      (push "" lines)
      (let ((d (propertize "Datum" 'face 'font-lock-comment-face))
            (p (propertize "Project" 'face 'font-lock-comment-face))
            (t-str (propertize "Tid" 'face 'font-lock-comment-face)))
        (push (concat d
                      (propertize " " 'display '(space :align-to 65)) p
                      (propertize " " 'display '(space :align-to 90)) t-str)
              lines))
      (dolist (s (seq-take month-sessions 20))
        (let* ((date (substring (nth 0 s) 5))
               (proj-raw (nth 1 s))
               (proj (if (albin/is-empty proj-raw) "Other" proj-raw))
               (proj-clean (truncate-string-to-width proj 22 nil nil "…"))
               (hrs (format "%.2f h" (nth 3 s))))
          (push (concat date
                        (propertize " " 'display '(space :align-to 65)) proj-clean
                        (propertize " " 'display '(space :align-to 90)) hrs)
                lines))))
    (reverse lines)))

(defun albin/dashboard-get-weekly-report ()
  "Return a list of propertized strings for this week's daily hour breakdown."
  (let* ((raw-sessions (albin/get-timelog-sessions))
         (merged-sessions (albin/merge-empty-sessions raw-sessions))
         (sessions (car (albin/apply-time-carry merged-sessions)))
         (today (current-time))
         (today-str (format-time-string "%Y-%m-%d" today))
         (today-dow (1- (string-to-number (format-time-string "%u" today))))
         (week-start (time-subtract today (days-to-time today-dow)))
         (daily-hours (make-hash-table :test 'equal))
         (lines '()))

    (dolist (s sessions)
      (let ((date (nth 0 s)) (hrs (nth 3 s)))
        (puthash date (+ (gethash date daily-hours 0.0) hrs) daily-hours)))

    (push (propertize (format "%s WEEKLY REPORT"
                              (nerd-icons-faicon "nf-fa-calendar_o"))
                      'face '(:inherit font-lock-type-face :weight bold))
          lines)
    (push (propertize "─────────────────────────────────────────────────"
                      'face 'font-lock-comment-face)
          lines)

    (let* ((week-total 0.0)
           (day-names ["Mon" "Tue" "Wed" "Thu" "Fri" "Sat" "Sun"]))

      (dotimes (i 7)
        (let* ((date-str (format-time-string "%Y-%m-%d"
                                             (time-add week-start (days-to-time i)))))
          (setq week-total (+ week-total (gethash date-str daily-hours 0.0)))))

      (push (format "This week: %s"
                    (propertize (format "%.2f h" week-total) 'face 'font-lock-constant-face))
            lines)
      (push "" lines)

      (dotimes (i 7)
        (let* ((date-str (format-time-string "%Y-%m-%d"
                                             (time-add week-start (days-to-time i))))
               (hrs (gethash date-str daily-hours 0.0))
               (bar-blocks (min albin-dashboard-bar-max-width (floor hrs)))
               (bar-str (concat (make-string bar-blocks #x2588)
                                (make-string (- albin-dashboard-bar-max-width bar-blocks) #x00B7)))
               (day-name (aref day-names i))
               (is-today (string= date-str today-str))
               (name-face (if is-today 'font-lock-keyword-face 'font-lock-variable-name-face))
               (bar-face (cond ((>= hrs 8.0) 'success)
                               ((> hrs 0.0) 'warning)
                               (t 'font-lock-comment-face))))
          (push (concat
                 (propertize day-name 'face name-face)
                 "  "
                 (propertize bar-str 'face bar-face)
                 (format "  %.2f h" hrs))
                lines))))

    (reverse lines)))

(defun albin/dashboard-get-right-column ()
  "Combine right-column widgets into one line list."
  (append (albin/dashboard-get-month-logs)
          (list "" "")
          (albin/dashboard-get-weekly-report)))

;; ==========================================
;; 6. MAIN FUNCTION FOR RENDERING THE DASHBOARD
;; ==========================================

(defun albin/dashboard (&optional silent)
  "Render the custom Emacs dashboard. If SILENT is non-nil, update in background."
  (interactive)
  (let* ((buf-name "*Albin Dashboard*")
         (buf (get-buffer-create buf-name))
         ;; Render against the actual dashboard window to avoid first-draw misalignment.
         (render-win (or (get-buffer-window buf t)
                         (and (not silent)
                              (display-buffer buf '(display-buffer-same-window)))))
         (old-point (when (get-buffer buf-name)
                      (with-current-buffer buf-name (point)))))

    (with-current-buffer buf
      (let ((albin-dashboard--render-window (or render-win (selected-window))))
      (albin-dashboard-mode)
      (let ((inhibit-read-only t))
        (erase-buffer)

        ;; Full-width header
        (insert "\n")
        (albin/dashboard-insert-banner)
        (unless silent
          (albin/dashboard-insert-quote))

        ;; Date and async weather
        (insert "  ")
        (insert (propertize (format-time-string "%A, %d %B %Y") 'face 'font-lock-keyword-face))
        (insert "  │  ")
        (insert (propertize albin-dashboard-weather-string 'face 'font-lock-string-face))
        (insert "\n\n")

        ;; Record where dual-column section starts
        (let ((dual-start (point-marker)))

          ;; LEFT COLUMN
          (albin/dashboard-insert-startup-widget)
          (albin/dashboard-insert-roam-widget)
          (albin/dashboard-insert-jump-widget)
          (albin/dashboard-insert-timeclock-widget)
          (albin/dashboard-insert-agenda)
          (albin/dashboard-insert-focus-widget)
          (albin/dashboard-insert-quick-commands)
          (albin/dashboard-insert-projects)
          (albin/dashboard-insert-recentf)
          (albin/dashboard-insert-tips)
          (albin/dashboard-insert-footer)

          ;; RIGHT COLUMN: walk back to dual-start and append content line-by-line
          (let ((right-lines (albin/dashboard-get-right-column)))
            (let ((right-col (albin/dashboard-right-column-start)))
              (goto-char dual-start)
              (dolist (r-line right-lines)
                (end-of-line)
                (delete-trailing-whitespace (line-beginning-position) (line-end-position))
                (insert (propertize " " 'display `(space :align-to ,right-col)))
                (insert r-line)
                (when (= (forward-line 1) 1)
                  (insert "\n")))))))

      (if old-point
          (goto-char old-point)
        (goto-char (point-min)))

      ;; Prevent Emacs from asking to save this buffer on exit
      (set-buffer-modified-p nil)))

    (unless silent
      (switch-to-buffer buf))))

;; ==========================================
;; 7. AUTO-REFRESH TIMER
;; ==========================================

(defvar albin-dashboard-timer nil
  "Timer that updates the dashboard in the background.")

(defun albin/dashboard-start-timer ()
  "Start the background auto-refresh for the dashboard."
  (interactive)
  (when albin-dashboard-timer
    (cancel-timer albin-dashboard-timer))
  (setq albin-dashboard-timer
        (run-at-time t 60
                     (lambda ()
                       (when (get-buffer "*Albin Dashboard*")
                         (albin/dashboard-fetch-weather)
                         (albin/dashboard t))))))

(albin/dashboard-start-timer)

(defun albin/dashboard-open-for-doom (&rest _)
  "Open Albin dashboard from Doom startup hooks."
  (albin/dashboard))

(provide 'albin-dashboard)
