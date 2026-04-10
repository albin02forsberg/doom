(require 'time-date)
(require 'org)
(require 'timeclock)
(require 'subr-x)
(require 'nerd-icons)
(require 'transient)
(require 'calendar)

;; ==========================================
;; 1. PROFILES & PERSISTENCE
;; ==========================================

(defvar albin-timeclock-profiles '("Work" "Personal")
  "List of available timeclock profiles.")

(defvar albin-timeclock-profile-save-file 
  (expand-file-name "timeclock-active-profile.txt" user-emacs-directory)
  "File to remember the last used profile across Emacs restarts.")

(defun albin/save-active-profile ()
  "Save the current profile to disk as pure text."
  (write-region albin-timeclock-current-profile nil albin-timeclock-profile-save-file nil 'silent))

(defun albin/load-active-profile ()
  "Load the last active profile safely, default to Work."
  (let ((prof "Work"))
    (when (file-exists-p albin-timeclock-profile-save-file)
      (with-temp-buffer
        (insert-file-contents albin-timeclock-profile-save-file)
        (setq prof (string-trim (buffer-string)))))
    (if (member prof albin-timeclock-profiles) prof "Work")))

(defvar albin-timeclock-current-profile (albin/load-active-profile)
  "The currently active profile.")

(defvar albin-timeclock-projects-file nil)
(defvar albin-timeclock-diary-file nil)
(defvar albin-timeclock-paused-file nil)

(defcustom albin-timeclock-data-directory nil
  "Directory for albin timeclock data files.
If nil, try the directory of an existing `timeclock-file', otherwise fall back
to `user-emacs-directory'."
  :type '(choice (const :tag "Auto" nil) directory)
  :group 'timeclock)

(defun albin/timeclock-update-paths ()
  "Updates file paths depending on the currently selected profile and ensures they exist."
  (unless (stringp albin-timeclock-current-profile)
    (setq albin-timeclock-current-profile "Work"))
  
  (let* ((existing-timeclock-dir
          (when (and (stringp timeclock-file)
                     (file-exists-p timeclock-file))
            (file-name-directory timeclock-file)))
         (base-dir (or albin-timeclock-data-directory
                       existing-timeclock-dir
                       user-emacs-directory))
         (suffix (downcase albin-timeclock-current-profile)))
    (setq timeclock-file (expand-file-name (format "timelog-%s" suffix) base-dir))
    (setq albin-timeclock-projects-file (expand-file-name (format "timeclock-projects-%s.eld" suffix) base-dir))
    (setq albin-timeclock-diary-file (expand-file-name (format "dagbok-%s.org" suffix) base-dir))
    (setq albin-timeclock-paused-file (expand-file-name (format "timeclock-paused-%s.txt" suffix) base-dir))
    
    (unless (file-exists-p timeclock-file)
      (write-region "" nil timeclock-file nil 'silent))))

(albin/timeclock-update-paths)
(timeclock-reread-log)

;; ==========================================
;; 2. VARIABLES AND HELPER FUNCTIONS
;; ==========================================

(defvar albin-timeclock-paused-project nil)
(defvar albin-timeclock-last-nag-time nil)
(defvar albin-timeclock-nag-interval 10)
(defvar albin-timeclock-task-history nil
  "Minibuffer history for task descriptions.")
(defvar albin-timeclock-pending-reason nil
  "Suggested task description for the current active session.")

;; --- SWEDISH PUBLIC HOLIDAY HANDLING ---
(defun albin/calculate-easter (year)
  "Calculates Easter Sunday mathematically for a given year and returns an absolute calendar date."
  (let* ((a (% year 19))
         (b (/ year 100))
         (c (% year 100))
         (d (/ b 4))
         (e (% b 4))
         (f (/ (+ b 8) 25))
         (g (/ (+ b (- f) 1) 3))
         (h (% (+ (* 19 a) b (- d) (- g) 15) 30))
         (i (/ c 4))
         (k (% c 4))
         (l (% (+ 32 (* 2 e) (* 2 i) (- h) (- k)) 7))
         (m (/ (+ a (* 11 h) (* 22 l)) 451))
         (month (/ (+ h l (- (* 7 m)) 114) 31))
         (day (1+ (% (+ h l (- (* 7 m)) 114) 31))))
    (calendar-absolute-from-gregorian (list month day year))))

(defun albin/swedish-red-days (year)
  "Returns a list of date strings (YYYY-MM-DD) for Swedish public holidays for the given YEAR."
  (let* ((easter-abs (albin/calculate-easter year))
         ;; Midsummer Eve is the Friday between the 19th and 25th of June
         (midsommar-abs
          (let* ((june-19 (calendar-absolute-from-gregorian (list 6 19 year)))
                 (dow (calendar-day-of-week (list 6 19 year))))
            (+ june-19 (% (+ 12 (- dow)) 7)))) 
         (abs-dates
          (list
           ;; Fixed dates (Month, Day, Year)
           (calendar-absolute-from-gregorian (list 1 1 year))   ; New Year's Day
           (calendar-absolute-from-gregorian (list 1 6 year))   ; Epiphany
           (calendar-absolute-from-gregorian (list 5 1 year))   ; May 1st (Labour Day)
           (calendar-absolute-from-gregorian (list 6 6 year))   ; National Day
           (calendar-absolute-from-gregorian (list 12 24 year)) ; Christmas Eve
           (calendar-absolute-from-gregorian (list 12 25 year)) ; Christmas Day
           (calendar-absolute-from-gregorian (list 12 26 year)) ; Boxing Day
           (calendar-absolute-from-gregorian (list 12 31 year)) ; New Year's Eve
           ;; Variable dates based on Easter and Midsummer
           (- easter-abs 2)    ; Good Friday
           easter-abs          ; Easter Sunday
           (+ easter-abs 1)    ; Easter Monday
           (+ easter-abs 39)   ; Ascension Day
           midsommar-abs       ; Midsummer Eve
           (+ midsommar-abs 1) ; Midsummer Day
           )))
    (mapcar (lambda (abs-date)
              (let ((greg (calendar-gregorian-from-absolute abs-date)))
                (format "%04d-%02d-%02d" (nth 2 greg) (nth 0 greg) (nth 1 greg))))
            abs-dates)))

(defvar albin-timeclock--holiday-cache nil
  "Internal cache for Swedish public holidays.")

(defun albin/get-holidays-list ()
  "Returns a list of date strings for flex time calculation."
  (if albin-timeclock--holiday-cache
      albin-timeclock--holiday-cache
    (let* ((current-year (string-to-number (format-time-string "%Y")))
           (years (list (1- current-year) current-year (1+ current-year)))
           (all-data '()))
      (dolist (y years)
        (setq all-data (append all-data (albin/swedish-red-days y))))
      ;; We store only the dates (car of the pairs) in the cache for fast lookup
      (setq albin-timeclock--holiday-cache (mapcar #'car all-data))
      albin-timeclock--holiday-cache)))

(defun albin/expected-hours-for-date (date-str)
  "Returns 8.0 hours for weekdays, but 0.0 for weekends and Swedish public holidays."
  (let* ((year  (string-to-number (substring date-str 0 4)))
         (month (string-to-number (substring date-str 5 7)))
         (day   (string-to-number (substring date-str 8 10)))
         (time  (encode-time 0 0 0 day month year))
         (dow   (string-to-number (format-time-string "%u" time))) ;; 1=Mon, 7=Sun
         (is-weekend (> dow 5))
         (is-holiday (member date-str (albin/get-holidays-list))))
    
    (if (or is-weekend is-holiday)
        0.0
      8.0)))
;; ---------------------------------

(defun albin/is-empty (s)
  "Safe check for empty string or nil."
  (or (null s) (string-empty-p s)))

(defun albin/round-hours-custom (hours resolution round-up)
  "Round decimal HOURS to the given RESOLUTION."
  (if (or (null resolution) (<= resolution 0))
      hours
    (let ((factor (/ 1.0 resolution)))
      (if round-up
          (/ (float (ceiling (* hours factor))) factor)
        (/ (float (round (* hours factor))) factor)))))

(defun albin/format-hours-to-hm (decimal-hours)
  "Format decimal hours to a human readable Xh YYm string."
  (let* ((h (truncate decimal-hours)) 
         (m (truncate (* (- decimal-hours h) 60))))
    (if (> h 0) (format "%dh %02dm" h m) (format "%dm" m))))

(defun albin/load-timeclock-projects ()
  "Loads projects and migrates old data."
  (let ((mapping (if (file-exists-p albin-timeclock-projects-file)
                     (with-temp-buffer
                       (insert-file-contents albin-timeclock-projects-file)
                       (condition-case nil (read (current-buffer)) (error nil)))
                   nil))
        (migrated '()))
    (dolist (entry mapping)
      (let ((proj (car entry))
            (val (cdr entry)))
        (if (stringp val)
            (push (cons proj (list :export-code val :rounding 0.5 :round-up nil :active t)) migrated)
          (push entry migrated))))
    (reverse migrated)))

(defun albin/save-timeclock-projects (mapping)
  (with-temp-file albin-timeclock-projects-file
    (let ((print-level nil) (print-length nil))
      (prin1 mapping (current-buffer)))))

(defun albin/get-timelog-sessions ()
  "Parse the timelog file and return a list of sessions."
  (let ((timelog-file (or timeclock-file (expand-file-name "timelog-work" user-emacs-directory)))
        (current-project "")
        (current-start-date nil)
        (current-start-time nil)
        (accumulated-hours 0.0)
        (sessions '()))
    (if (not (file-exists-p timelog-file))
        '()
      (with-temp-buffer
        (insert-file-contents timelog-file)
        (goto-char (point-min))
        (while (not (eobp))
          (let ((line (buffer-substring-no-properties (line-beginning-position) (line-end-position))))
            (when (string-match "^\\([ioO]\\) \\([0-9/]+\\) \\([0-9:]+\\)\\(?: \\(.*\\)\\)?" line)
              (let* ((event (match-string 1 line))
                     (date (replace-regexp-in-string "/" "-" (match-string 2 line)))
                     (time (match-string 3 line))
                     (raw-text (match-string 4 line))
                     (text (if raw-text (string-trim raw-text) "")))
                (cond
                 ((string= event "i")
                  (setq current-project text)
                  (setq current-start-date date current-start-time time))
                 ((and (member event '("o" "O")) current-start-time)
                  (let* ((reason text)
                         (start-str (concat current-start-date " " current-start-time))
                         (end-str (concat date " " time))
                         (t1 (encode-time (parse-time-string start-str)))
                         (t2 (encode-time (parse-time-string end-str)))
                         (diff-hours (/ (float (time-convert (time-subtract t2 t1) 'integer)) 3600.0)))
                    (setq accumulated-hours (+ accumulated-hours diff-hours))
                    (if (string-match-p "---BREAK---" reason)
                        (setq current-start-time nil)
                      (when (> accumulated-hours 0.0)
                        (push (list current-start-date current-project reason accumulated-hours current-start-time time) sessions))
                      (setq accumulated-hours 0.0 current-start-time nil))))))))
          (forward-line 1))
        (when (> accumulated-hours 0.0)
          (push (list current-start-date current-project "Ongoing session" accumulated-hours current-start-time (format-time-string "%H:%M:%S")) sessions))
        (reverse sessions)))))

(defun albin/merge-empty-sessions (sessions)
  "Merges sessions without text with the following session."
  (let ((merged '())
        (active-sessions (make-hash-table :test 'equal)))
    (dolist (s (reverse sessions))
      (let* ((date (nth 0 s))
             (proj (nth 1 s))
             (desc (nth 2 s))
             (hrs  (nth 3 s))
             (key  (concat date "|" proj)))
        (if (or (albin/is-empty desc) (string= desc "Ongoing session"))
            (let ((active (gethash key active-sessions)))
              (if active
                  (setcar (nthcdr 3 active) (+ (nth 3 active) hrs))
                (push (copy-sequence s) merged)))
          (let ((new-s (copy-sequence s)))
            (push new-s merged)
            (puthash key new-s active-sessions)))))
    merged))

(defun albin/merge-sessions-by-description (sessions)
  "Merge same-day sessions that share project and description."
  (let ((merged '())
        (by-key (make-hash-table :test 'equal)))
    (dolist (s sessions)
      (let* ((date (nth 0 s))
             (proj (nth 1 s))
             (desc (string-trim (or (nth 2 s) "")))
             (hrs (nth 3 s))
             (key (concat date "|" proj "|" desc))
             (existing (gethash key by-key)))
        (if (and existing (not (albin/is-empty desc)) (not (string= desc "Ongoing session")))
            (progn
              (setcar (nthcdr 3 existing) (+ (nth 3 existing) hrs))
              (setcar (nthcdr 5 existing) (nth 5 s)))
          (let ((new-s (copy-sequence s)))
            (push new-s merged)
            (when (and (not (albin/is-empty desc)) (not (string= desc "Ongoing session")))
              (puthash key new-s by-key))))))
    (nreverse merged)))

(defun albin/prepare-report-sessions (sessions)
  "Normalize SESSIONS for reports and exports."
  (albin/merge-sessions-by-description
   (albin/merge-empty-sessions sessions)))

(defun albin/timeclock-task-suggestions (&optional project)
  "Return recent unique task descriptions, preferring today's entries.
If PROJECT is non-nil, only include entries from that project."
  (let* ((today (format-time-string "%Y-%m-%d"))
         (seen (make-hash-table :test 'equal))
         (today-suggestions '())
         (older-suggestions '())
         (sessions (reverse (albin/get-timelog-sessions))))
    (dolist (s sessions)
      (let* ((date (nth 0 s))
             (proj (nth 1 s))
             (desc (string-trim (or (nth 2 s) ""))))
        (when (and (not (albin/is-empty desc))
                   (not (string= desc "Ongoing session"))
                   (or (null project) (string= project proj))
                   (not (gethash desc seen)))
          (puthash desc t seen)
          (if (string= date today)
              (push desc today-suggestions)
            (push desc older-suggestions)))))
    (append (nreverse today-suggestions) (nreverse older-suggestions))))

(defun albin/apply-time-carry (sessions)
  "Rounds hours per project config but carries over the remainder."
  (let ((carry 0.0)
        (rounded-sessions '())
        (mapping (albin/load-timeclock-projects)))
    (dolist (s sessions)
      (let* ((proj (nth 1 s))
             (props (cdr (assoc proj mapping)))
             (resolution (if props (plist-get props :rounding) 0.5))
             (round-up (if props (plist-get props :round-up) nil))
             (exact-hours (+ (nth 3 s) carry))
             (rounded-hours (albin/round-hours-custom exact-hours resolution round-up))
             (new-s (copy-sequence s))) 
        (setq carry (- exact-hours rounded-hours))
        (setcar (nthcdr 3 new-s) rounded-hours)
        (push new-s rounded-sessions)))
    (cons (reverse rounded-sessions) carry)))

(defun albin/calculate-flex (sessions &optional start-date end-date)
  (let* ((carry-result (albin/apply-time-carry sessions))
         (rounded-sessions (car carry-result))
         (daily-hours (make-hash-table :test 'equal))
         (total-flex 0.0)
         (period-flex 0.0)
         (period-days 0))
    (dolist (s rounded-sessions)
      (let ((date (nth 0 s))
            (hours (nth 3 s))) 
        (puthash date (+ (gethash date daily-hours 0.0) hours) daily-hours)))
    (maphash (lambda (date hours)
               (let* ((expected (albin/expected-hours-for-date date))
                      (daily-flex (- hours expected)))
                 (setq total-flex (+ total-flex daily-flex))
                 (when (and start-date end-date
                            (not (string< date start-date))
                            (not (string< end-date date)))
                   (setq period-flex (+ period-flex daily-flex))
                   (setq period-days (1+ period-days)))))
             daily-hours)
    (list total-flex period-flex period-days)))

;; ==========================================
;; 3. DIARY & BACKUP SYSTEM
;; ==========================================

(defun albin/append-to-diary (project reason duration-hours)
  (when (and reason (not (albin/is-empty reason)) (not (string-match-p "---BREAK---" reason)))
    (let* ((date-heading (format-time-string "* %Y-%m-%d %A"))
           (time-str (format-time-string "%H:%M"))
           (dur-str (albin/format-hours-to-hm duration-hours))
           (proj-str (if (albin/is-empty project) "Other" project))
           (entry (format "- [%s] *%s* (%s): %s\n" time-str proj-str dur-str reason)))
      (with-current-buffer (find-file-noselect albin-timeclock-diary-file)
        (goto-char (point-max))
        (unless (save-excursion (re-search-backward (concat "^" (regexp-quote date-heading)) nil t))
          (unless (bolp) (insert "\n"))
          (insert "\n" date-heading "\n"))
        (goto-char (point-max))
        (insert entry)
        (save-buffer)))))

(defun albin/timeclock-open-diary ()
  (interactive)
  (find-file albin-timeclock-diary-file)
  (message "📖 Opened diary for: %s" albin-timeclock-current-profile))

(defun albin/timeclock-edit-log ()
  (interactive)
  (find-file timeclock-file)
  (add-hook 'after-save-hook
            (lambda ()
              (timeclock-reread-log)
              (albin/timeclock-update-modeline)
              (message "🔄 Timelog synced to memory!"))
            nil t)
  (message "✏️ Editing raw timelog for: %s. Save when done!" albin-timeclock-current-profile))

(defun albin/timeclock-git-backup ()
  "Automatically commit and push timeclock and diary files to Git."
  (interactive)
  (let ((default-directory user-emacs-directory))
    (call-process-shell-command "git add timelog-* timeclock-projects-*.eld dagbok-*.org timeclock-active-profile.txt timeclock-paused-*.txt" nil nil)
    (call-process-shell-command (format "git commit -m \"⏱ Auto-backup timeclock: %s\"" (format-time-string "%Y-%m-%d %H:%M")) nil nil)
    (call-process-shell-command "git push" nil nil))
  (when (called-interactively-p 'any)
    (message "☁️ Timeclock data committed and pushed to remote!")))

;; ==========================================
;; 4. MAIN FUNCTIONS
;; ==========================================

(defun albin/swedish-red-days (year)
  "Returns a sorted list of (date-string . holiday-name) for a given YEAR."
  (let* ((easter-abs (albin/calculate-easter year))
         ;; Midsummer Eve: the Friday between June 19-25
         (midsommar-abs
          (let* ((june-19 (calendar-absolute-from-gregorian (list 6 19 year)))
                 (dow (calendar-day-of-week (list 6 19 year))))
            (+ june-19 (% (+ 12 (- dow)) 7)))) 
         ;; All Saints' Day: the Saturday between Oct 31 - Nov 6
         (alla-helgons-abs
          (let* ((oct-31 (calendar-absolute-from-gregorian (list 10 31 year)))
                 (dow (calendar-day-of-week (list 10 31 year))))
            (+ oct-31 (% (+ 7 (- 6 dow)) 7))))
         ;; Build the list of pairs: (absolute-day . "Name")
         (holiday-alist
          (list
           (cons (calendar-absolute-from-gregorian (list 1 1 year))   "New Year's Day")
           (cons (calendar-absolute-from-gregorian (list 1 6 year))   "Epiphany")
           (cons (- easter-abs 2)                                    "Good Friday")
           (cons easter-abs                                          "Easter Sunday")
           (cons (+ easter-abs 1)                                    "Easter Monday")
           (cons (calendar-absolute-from-gregorian (list 5 1 year))   "May 1st (Labour Day)")
           (cons (+ easter-abs 39)                                   "Ascension Day")
           (cons (+ easter-abs 49)                                   "Pentecost")
           (cons (calendar-absolute-from-gregorian (list 6 6 year))   "National Day")
           (cons midsommar-abs                                       "Midsummer Eve")
           (cons (+ midsommar-abs 1)                                 "Midsummer Day")
           (cons alla-helgons-abs                                    "All Saints' Day")
           (cons (calendar-absolute-from-gregorian (list 12 24 year)) "Christmas Eve")
           (cons (calendar-absolute-from-gregorian (list 12 25 year)) "Christmas Day")
           (cons (calendar-absolute-from-gregorian (list 12 26 year)) "Boxing Day")
           (cons (calendar-absolute-from-gregorian (list 12 31 year)) "New Year's Eve"))))
    
    ;; Sort by absolute date (car)
    (setq holiday-alist (sort holiday-alist (lambda (a b) (< (car a) (car b)))))
    
    ;; Convert to (YYYY-MM-DD . "Name")
    (mapcar (lambda (pair)
              (let ((greg (calendar-gregorian-from-absolute (car pair))))
                (cons (format "%04d-%02d-%02d" (nth 2 greg) (nth 0 greg) (nth 1 greg))
                      (cdr pair))))
            holiday-alist)))

(defun albin/timeclock-switch-profile ()
  (interactive)
  (timeclock-reread-log)
  (let ((new-profile (completing-read (format "Switch profile (current: %s): " albin-timeclock-current-profile)
                                      albin-timeclock-profiles nil t nil nil albin-timeclock-current-profile)))
    (unless (string= new-profile albin-timeclock-current-profile)
      (when (and timeclock-last-event (string= (car timeclock-last-event) "i"))
        (albin/timeclock-out (format "Auto-clockout (Switched to %s profile)" new-profile)))
      (setq albin-timeclock-current-profile new-profile)
      (albin/save-active-profile)
      (albin/timeclock-update-paths)
      (timeclock-reread-log)
      (setq albin-timeclock-paused-project nil)
      (albin/timeclock-update-modeline)
      (message "🔄 Profile switched to: %s" new-profile))))

(defun albin/timeclock-out (&optional auto-reason)
  (interactive)
  (when (and timeclock-last-event (string= (car timeclock-last-event) "i"))
    (let* ((start-time (nth 1 timeclock-last-event))
           (project (nth 2 timeclock-last-event))
           (diff-sec (float-time (time-subtract (current-time) start-time)))
           (duration-hours (/ diff-sec 3600.0))
           (reason (or auto-reason
                       (read-string "Done for now! What did you do under this session? "
                                    nil
                                    'albin-timeclock-task-history
                                    albin-timeclock-pending-reason))))
      
      (setq reason (if (albin/is-empty reason) "" reason))
      (timeclock-log "o" (if (albin/is-empty reason) nil (substring-no-properties reason)))
      (albin/append-to-diary project reason duration-hours)
      (setq albin-timeclock-pending-reason nil)
      (albin/timeclock-update-modeline)
      (when (called-interactively-p 'any)
        (message "⏱️ Clocked out.%s" (if (albin/is-empty reason) "" (format " Task: %s" reason)))))))

(defun albin/timeclock-break ()
  (interactive)
  (if (not (and timeclock-last-event (string= (car timeclock-last-event) "i")))
      (message "You are not clocked in right now!")
    (setq albin-timeclock-paused-project (nth 2 timeclock-last-event))
    (when albin-timeclock-paused-project
      (write-region albin-timeclock-paused-project nil albin-timeclock-paused-file nil 'silent))
    (timeclock-log "o" "---BREAK---")
    (albin/timeclock-update-modeline)
    (message "☕ Clock paused! Project '%s' saved." albin-timeclock-paused-project)))

(defun albin/timeclock-resume ()
  (interactive)
  (when (and (not albin-timeclock-paused-project)
             albin-timeclock-paused-file
             (file-exists-p albin-timeclock-paused-file))
    (with-temp-buffer
      (insert-file-contents albin-timeclock-paused-file)
      (setq albin-timeclock-paused-project (string-trim (buffer-string)))))
  
  (if (or (albin/is-empty albin-timeclock-paused-project)
          (not (equal (nth 2 timeclock-last-event) "---BREAK---")))
      (message "No valid break found to resume from.")
    (timeclock-log "i" albin-timeclock-paused-project)
    (when (file-exists-p albin-timeclock-paused-file) (delete-file albin-timeclock-paused-file))
    (albin/timeclock-update-modeline)
    (message "▶️ Clock is ticking again on: %s" albin-timeclock-paused-project)
    (setq albin-timeclock-paused-project nil)))

(defun albin/timeclock-in ()
  (interactive)
  (let* ((mapping (albin/load-timeclock-projects))
         (active-projs (delq nil (mapcar (lambda (x) (when (plist-get (cdr x) :active) (car x))) mapping)))
         (suggested-proj (when (derived-mode-p 'org-mode)
                           (or (org-entry-get nil "CATEGORY")
                               (file-name-nondirectory (buffer-file-name)))))
         (selected-proj (completing-read 
                         (format "Clock in on project%s: " 
                                 (if suggested-proj (format " (suggested: %s)" suggested-proj) ""))
                         active-projs nil nil nil nil suggested-proj)))
    (let* ((props (cdr (assoc selected-proj mapping)))
           (export-name nil))
      (if props
          (setq export-name (plist-get props :export-code))
        (let ((new-code (read-string (format "Enter export code for NEW project '%s' (Enter for name): " selected-proj))))
          (setq export-name (if (albin/is-empty new-code) selected-proj new-code))
          (unless (albin/is-empty selected-proj)
            (setq mapping (assq-delete-all selected-proj mapping))
            (push (cons selected-proj (list :export-code export-name :rounding 0.5 :round-up nil :active t)) mapping)
            (albin/save-timeclock-projects mapping))))
      (setq export-name (substring-no-properties export-name))
      (let* ((suggestions (albin/timeclock-task-suggestions selected-proj))
             (suggested-task
              (when suggestions
                (completing-read (format "Task suggestion for '%s' (RET to skip): " selected-proj)
                                 suggestions nil nil nil
                                 'albin-timeclock-task-history
                                 (car suggestions)))))
        (setq albin-timeclock-pending-reason
              (unless (albin/is-empty suggested-task)
                (substring-no-properties suggested-task))))
      (when (and timeclock-last-event (string= (car timeclock-last-event) "i"))
        (albin/timeclock-out (if (albin/is-empty selected-proj) "" (format "Automatically switched to %s" selected-proj))))
      (setq albin-timeclock-paused-project nil)
      (when (and albin-timeclock-paused-file (file-exists-p albin-timeclock-paused-file)) (delete-file albin-timeclock-paused-file))
      (timeclock-log "i" (if (albin/is-empty export-name) nil export-name))
      (albin/timeclock-update-modeline)
      (message "⏱️ Clocked in%s" (if (albin/is-empty selected-proj) "" (format " on: %s" selected-proj))))))

(defun albin/timeclock-change ()
  (interactive)
  (if (not (and timeclock-last-event (string= (car timeclock-last-event) "i")))
      (call-interactively 'albin/timeclock-in)
    (let* ((old-proj (nth 2 timeclock-last-event))
           (reason (read-string (format "🔄 Switching from '%s'. What did you do until now? " old-proj)))
           (mapping (albin/load-timeclock-projects))
           (active-projs (delq nil (mapcar (lambda (x) (when (plist-get (cdr x) :active) (car x))) mapping)))
           (new-proj (completing-read "Clock in on new project: " active-projs nil nil nil nil nil)))
      (setq reason (if (albin/is-empty reason) "" reason))
      (albin/timeclock-out reason)
      (let* ((props (cdr (assoc new-proj mapping)))
             (export-name (if props (plist-get props :export-code) new-proj)))
        (setq albin-timeclock-paused-project nil)
        (when (and albin-timeclock-paused-file (file-exists-p albin-timeclock-paused-file)) (delete-file albin-timeclock-paused-file))
        (timeclock-log "i" (if (albin/is-empty export-name) nil (substring-no-properties export-name)))
        (albin/timeclock-update-modeline)
        (message "⏱️ Switched to '%s'" new-proj)))))

(defun albin/timeclock-adjust-start (minutes)
  "Adjusts the start time of the current session back by MINUTES minutes."
  (interactive "nOops, forgot to clock in! How many minutes ago did you start? ")
  (if (not (and timeclock-last-event (string= (car timeclock-last-event) "i")))
      (message "⚠️ You must be clocked in to adjust the start time!")
    (let* ((file (or timeclock-file (expand-file-name "timelog" user-emacs-directory)))
           (current-start-time (nth 1 timeclock-last-event))
           (new-start-time (time-subtract current-start-time (seconds-to-time (* minutes 60))))
           (new-time-str (format-time-string "%Y/%m/%d %H:%M:%S" new-start-time))
           (project (nth 2 timeclock-last-event)))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-max))
        (when (bolp) (backward-char 1))
        (beginning-of-line)
        (when (looking-at "^i ")
          (delete-region (point) (line-end-position))
          (insert (format "i %s %s" new-time-str (if project project "")))
          (write-region (point-min) (point-max) file nil 'silent)
          (timeclock-reread-log)
          (albin/timeclock-update-modeline)
          (message "⏪ Time machine activated! Start time moved back by %d minutes." minutes))))))

(defun albin/timeclock-edit-project ()
  "Interactively edit properties of an existing project."
  (interactive)
  (let* ((mapping (albin/load-timeclock-projects))
         (proj-names (mapcar #'car mapping))
         (selected-proj (completing-read "Edit project config: " proj-names nil t)))
    (when selected-proj
      (let* ((props (cdr (assoc selected-proj mapping)))
             (code (read-string (format "Export code (%s): " (plist-get props :export-code)) nil nil (plist-get props :export-code)))
             (rounding-str (completing-read "Rounding resolution: " '("0.5" "0.25" "1.0" "None") nil nil (let ((r (plist-get props :rounding))) (if r (number-to-string r) "None"))))
             (rounding (if (string-match-p "^[0-9.]+$" rounding-str) (string-to-number rounding-str) nil))
             (round-up (if rounding (y-or-n-p "Always round UP? ") nil))
             (active (y-or-n-p "Is project ACTIVE? ")))
        (setq mapping (assq-delete-all selected-proj mapping))
        (push (cons selected-proj (list :export-code code :rounding rounding :round-up round-up :active active)) mapping)
        (albin/save-timeclock-projects mapping)
        (message "✅ Project '%s' updated!" selected-proj)))))

(defun albin/timeclock-show-red-days ()
  "Shows the year's public holidays in a neat popup buffer."
  (interactive)
  (let* ((year (string-to-number (format-time-string "%Y")))
         (holiday-data (albin/swedish-red-days year))
         (buf-name "*Public Holidays*"))
    (with-current-buffer (get-buffer-create buf-name)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize (format " 🔴 SWEDISH PUBLIC HOLIDAYS %d\n" year) 'face 'font-lock-type-face))
        (insert " ------------------------------------------------------------\n")
        (dolist (item holiday-data)
          (let* ((date (car item))
                 (name (cdr item))
                 (y (string-to-number (substring date 0 4)))
                 (m (string-to-number (substring date 5 7)))
                 (d (string-to-number (substring date 8 10)))
                 (time (encode-time 0 0 0 d m y))
                 (dow (string-to-number (format-time-string "%u" time)))
                 (dow-name (nth (1- dow) '("Mon" "Tue" "Wed" "Thu" "Fri" "Sat" "Sun"))))
            (insert (format "  %s  %s  %s\n" 
                            (propertize date 'face 'font-lock-keyword-face)
                            (propertize dow-name 'face 'font-lock-comment-face)
                            (propertize name 'face 'font-lock-string-face)))))
        (insert " ------------------------------------------------------------\n")
        (insert (propertize "\n (These days contribute 0h expected time in the flex calculation)\n" 'face 'font-lock-doc-face))
        (insert (propertize " Press 'q' to close.\n" 'face 'font-lock-comment-face))
        (special-mode)
        (goto-char (point-min))))
    (display-buffer buf-name '((display-buffer-reuse-window display-buffer-pop-up-window)
                               (window-height . fit-window-to-buffer)))))

(defun albin/timeclock-show-flex ()
  (interactive)
  (let* ((sessions (albin/get-timelog-sessions))
         (flex-data (albin/calculate-flex sessions))
         (total-flex (nth 0 flex-data)))
    (message "%s  Total flextime (%s): %s%.2f hours" (nerd-icons-faicon "nf-fa-bar_chart") albin-timeclock-current-profile (if (> total-flex 0) "+" "") total-flex)))

(defun albin/timeclock-daily-summary (&optional date)
  "Generate a detailed report for DATE (defaults to today)."
  (interactive)
  (let* ((target-date (or date (org-read-date nil nil nil "Daily summary for date: ")))
         (raw-sessions (albin/get-timelog-sessions))
         (merged-sessions (albin/prepare-report-sessions raw-sessions))
         (rounded-sessions (car (albin/apply-time-carry merged-sessions)))
         (sessions '())
         (total-raw 0.0)
         (total-rounded 0.0)
         (buf-name (format "*Day Summary: %s (%s)*" albin-timeclock-current-profile target-date)))
    (dolist (s merged-sessions)
      (when (string= (nth 0 s) target-date)
        (setq total-raw (+ total-raw (nth 3 s)))))
    (dolist (s rounded-sessions)
      (when (string= (nth 0 s) target-date)
        (push s sessions)
        (setq total-rounded (+ total-rounded (nth 3 s)))))
    (setq sessions (reverse sessions))
    (with-current-buffer (get-buffer-create buf-name)
      (erase-buffer)
      (org-mode)
      (insert (format "#+TITLE: Daily Time Report (%s)\n" albin-timeclock-current-profile))
      (insert (format "#+SUBTITLE: %s\n\n" target-date))
      (insert (format "* %s Summary\n" (nerd-icons-faicon "nf-fa-clock_o")))
      (insert (format "  - Hours worked: %.2f h\n" total-raw))
      (insert (format "  - Billable: %.2f h\n" total-rounded))
      (insert (format "  - Sessions: %d\n\n" (length sessions)))
      (insert (format "* %s Detailed Log\n" (nerd-icons-faicon "nf-fa-list")))
      (if sessions
          (dolist (s sessions)
            (insert (format "  - [%s - %s] *%s* (%.2f h) » %s\n"
                            (nth 4 s)
                            (nth 5 s)
                            (nth 1 s)
                            (nth 3 s)
                            (nth 2 s))))
        (insert "  - No sessions found for this date.\n"))
      (display-buffer (current-buffer)))))

(defun albin/timeclock-weekly-summary ()
  "Generates a detailed weekly report."
  (interactive)
  (let* ((end-date (format-time-string "%Y-%m-%d"))
         (start-date (format-time-string "%Y-%m-%d" (time-subtract (current-time) (days-to-time 7))))
         (raw-sessions (albin/get-timelog-sessions))
         (merged-sessions (albin/prepare-report-sessions raw-sessions))
         (rounded-sessions (car (albin/apply-time-carry merged-sessions)))
         (project-raw-hours (make-hash-table :test 'equal))
         (project-rounded-hours (make-hash-table :test 'equal))
         (daily-sessions (make-hash-table :test 'equal))
         (total-raw 0.0) (total-rounded 0.0) (session-counts 0)
         (buf-name (format "*Summary: %s*" albin-timeclock-current-profile)))
    (dolist (s merged-sessions)
      (let* ((date (nth 0 s)) (proj (nth 1 s)) (raw-hrs (nth 3 s)))
        (when (and (not (string< date start-date)) (not (string< end-date date)))
          (setq total-raw (+ total-raw raw-hrs))
          (setq session-counts (1+ session-counts))
          (puthash proj (+ (gethash proj project-raw-hours 0.0) raw-hrs) project-raw-hours)
          (puthash date (append (gethash date daily-sessions '()) (list s)) daily-sessions))))
    (dolist (s rounded-sessions)
      (let ((date (nth 0 s)) (proj (nth 1 s)) (rnd-hrs (nth 3 s)))
        (when (and (not (string< date start-date)) (not (string< end-date date)))
          (setq total-rounded (+ total-rounded rnd-hrs))
          (puthash proj (+ (gethash proj project-rounded-hours 0.0) rnd-hrs) project-rounded-hours))))
    (with-current-buffer (get-buffer-create buf-name)
      (erase-buffer) (org-mode)
      (insert (format "#+TITLE: Time Report (%s)\n#+SUBTITLE: %s to %s\n\n" albin-timeclock-current-profile start-date end-date))
      (insert (format "* %s Summary\n" (nerd-icons-faicon "nf-fa-bar_chart")) (format "  - Hours worked: %.2f h\n  - Billable: %.2f h\n  - Sessions: %d\n\n" total-raw total-rounded session-counts))
      (insert (format "* %s Project Breakdown\n" (nerd-icons-faicon "nf-fa-folder_open")) "| Project | Worked | Billable | Share |\n|---------+----------+----------+-------|\n")
      (let ((proj-list '())) (maphash (lambda (k v) (push (cons k v) proj-list)) project-rounded-hours)
           (dolist (p (sort proj-list (lambda (a b) (> (cdr a) (cdr b)))))
             (let* ((name (if (albin/is-empty (car p)) "Other" (car p))) (rnd (cdr p)) (raw (gethash (car p) project-raw-hours 0.0))
                    (perc (if (> total-rounded 0) (* (/ rnd total-rounded) 100) 0)))
               (insert (format "| %s | %.2f h | %.2f h | %d%% |\n" name raw rnd perc)))))
      (org-table-align) (insert (format "\n* %s Detailed Log\n" (nerd-icons-faicon "nf-fa-calendar")))
      (let ((dates (sort (let (d) (maphash (lambda (k v) (push k d)) daily-sessions) d) 'string<)))
        (dolist (date dates)
          (let ((day-total 0.0) (sessions (gethash date daily-sessions)))
            (dolist (s sessions) (setq day-total (+ day-total (nth 3 s))))
            (insert (format "** %s (%.2f h)\n" date day-total))
            (dolist (s sessions)
              (insert (format "   - [%s - %s] *%s* (%.2f h) » %s\n" (nth 4 s) (nth 5 s) (nth 1 s) (nth 3 s) (nth 2 s)))))))
      (display-buffer (current-buffer)))))

(defun albin/timeclock-export-csv ()
  (interactive)
  (let* ((start-date (org-read-date nil nil nil "Export from: "))
         (end-date (org-read-date nil nil nil "Export to: "))
         (raw-sessions (albin/get-timelog-sessions))
         (merged (albin/prepare-report-sessions raw-sessions))
         (sessions (car (albin/apply-time-carry merged)))
         (file-path (read-file-name "Save CSV to: " "~/Desktop/" (format "time_%s.csv" (downcase albin-timeclock-current-profile))))
         (content "Project,Description,Date,Duration\n"))
    (dolist (s sessions)
      (let* ((date (nth 0 s)) (proj (nth 1 s)) (desc (nth 2 s)) (hrs (nth 3 s)))
        (when (and (not (string< date start-date)) (not (string< end-date date)))
          (setq content (concat content (format "\"%s\",\"%s\",\"%s\",\"%.2f\"\n" proj desc date hrs))))))
    (with-temp-file file-path (insert (replace-regexp-in-string "\\." "," content)))
    (message "✅ CSV Exported!")))

;; ==========================================
;; 5. TRANSIENT MENU
;; ==========================================

(transient-define-prefix albin-timeclock-menu ()
  "Main menu for Albin Timeclock."
  [:description
   (lambda ()
     (let ((is-in (and timeclock-last-event (string= (car timeclock-last-event) "i"))))
       (format "Albin Timeclock (%s) - %s"
               (propertize albin-timeclock-current-profile 'face 'font-lock-keyword-face)
               (if is-in
                   (propertize (format "CLOCKED IN [%s]" (nth 2 timeclock-last-event)) 'face 'success)
                 (propertize "CLOCKED OUT" 'face 'warning)))))
   ["Actions"
    ("i" "Clock IN" albin/timeclock-in)
    ("o" "Clock OUT" albin/timeclock-out)
    ("b" "Take BREAK" albin/timeclock-break)
    ("r" "Resume" albin/timeclock-resume)
    ("c" "Switch Project" albin/timeclock-change)
    ("a" "Adjust Start Time" albin/timeclock-adjust-start)]
   ["Reports"
    ("t" "Daily Summary" albin/timeclock-daily-summary)
    ("s" "Weekly Summary" albin/timeclock-weekly-summary)
    ("f" "Show Flex" albin/timeclock-show-flex)
    ("h" "Show Public Holidays" albin/timeclock-show-red-days) 
    ("e" "Export CSV" albin/timeclock-export-csv)]
   ["Settings & Files"
    ("p" "Switch Profile" albin/timeclock-switch-profile)
    ("P" "Project Settings" albin/timeclock-edit-project)
    ("d" "Open Diary" albin/timeclock-open-diary)
    ("E" "Edit Raw Log" albin/timeclock-edit-log)]
   ["System"
    ("B" "Git Backup" albin/timeclock-git-backup)]])

;; ==========================================
;; 6. MODE-LINE & TIMERS
;; ==========================================

(defvar albin-timeclock-mode-string "")
(unless (memq 'albin-timeclock-mode-string global-mode-string)
  (setq global-mode-string (append global-mode-string '(albin-timeclock-mode-string))))

(defun albin/timeclock-update-modeline ()
  (let* ((raw (albin/get-timelog-sessions)) (today (format-time-string "%Y-%m-%d")) (hours 0.0) (current-proj nil))
    (dolist (s raw) (when (string= (nth 0 s) today) (setq hours (+ hours (nth 3 s)))))
    (when (and timeclock-last-event (string= (car timeclock-last-event) "i"))
      (setq current-proj (nth 2 timeclock-last-event)
            hours (+ hours (/ (float-time (time-subtract (current-time) (nth 1 timeclock-last-event))) 3600.0))))
    (setq albin-timeclock-mode-string
          (concat (propertize (format " %s " albin-timeclock-current-profile) 'face 'font-lock-keyword-face)
                  (if current-proj (propertize (format " [%s]" current-proj) 'face 'success) " [Paused]")
                  (format " %s " (albin/format-hours-to-hm hours))))
    (force-mode-line-update t)))

(run-at-time t 60 'albin/timeclock-update-modeline)

(use-package timeclock :ensure nil :config (add-hook 'kill-emacs-hook 'albin/timeclock-git-backup))

;; Global Keybinding
(global-set-key (kbd "C-c t") 'albin-timeclock-menu)

(albin/timeclock-update-modeline)
(provide 'albin-timeclock)
