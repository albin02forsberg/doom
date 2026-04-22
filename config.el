;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!


;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets. It is optional.
;; (setq user-full-name "John Doe"
;;       user-mail-address "john@doe.com")

;; Doom exposes five (optional) variables for controlling fonts in Doom:
;;
;; - `doom-font' -- the primary font to use
;; - `doom-variable-pitch-font' -- a non-monospace font (where applicable)
;; - `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;; - `doom-symbol-font' -- for symbols
;; - `doom-serif-font' -- for the `fixed-pitch-serif' face
;;
;; See 'C-h v doom-font' for documentation and more examples of what they
;; accept. For example:
;;
;;(setq doom-font (font-spec :family "Fira Code" :size 12 :weight 'semi-light)
;;      doom-variable-pitch-font (font-spec :family "Fira Sans" :size 13))
;;
;; If you or Emacs can't find your font, use 'M-x describe-font' to look them
;; up, `M-x eval-region' to execute elisp code, and 'M-x doom/reload-font' to
;; refresh your font settings. If Emacs still can't find your font, it likely
;; wasn't installed correctly. Font issues are rarely Doom issues!

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
(setq doom-theme 'doom-one)

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type 'relative)

;; Force line numbers on globally, with relative style.
(setq-default display-line-numbers 'relative)
(global-display-line-numbers-mode 1)

;; Enable current time for Doom modeline's `time` segment.
(setq display-time-24hr-format t
      display-time-default-load-average nil)
(display-time-mode 1)

;; Make which-key appear faster after pressing leader keys.
(after! which-key
  (setq which-key-idle-delay 0.2
	which-key-idle-secondary-delay 0.05))

;; ;; Show Albin timeclock status directly in Doom modeline.
;; (after! doom-modeline
;; 	(doom-modeline-def-segment albin-timeclock
;; 		(when (and (boundp 'albin-timeclock-mode-string)
;; 							 (stringp albin-timeclock-mode-string)
;; 							 (not (string-empty-p (string-trim albin-timeclock-mode-string))))
;; 			(concat (doom-modeline-spc)
;; 							(propertize albin-timeclock-mode-string
;; 													'face (doom-modeline-face 'doom-modeline-info)))))

;; 	;; Add timeclock segment to frequently used modelines.
;; 	(doom-modeline-def-modeline 'main
;; 		'(eldoc bar window-state workspace-name window-number modals matches follow buffer-info remote-host buffer-position word-count parrot selection-info)
;; 		'(compilation objed-state misc-info project-name persp-name battery grip irc mu4e gnus github debug repl lsp minor-modes input-method indent-info buffer-encoding major-mode process vcs check albin-timeclock time))

;; 	(doom-modeline-def-modeline 'dashboard
;; 		'(bar window-number modals buffer-default-directory-simple remote-host)
;; 		'(compilation misc-info battery irc mu4e gnus github debug minor-modes input-method major-mode process albin-timeclock time))

;; 	(doom-modeline-def-modeline 'vcs
;; 		'(bar window-state window-number modals matches buffer-info remote-host buffer-position parrot selection-info)
;; 		'(compilation misc-info battery irc mu4e gnus github debug minor-modes buffer-encoding major-mode process albin-timeclock time))

;; 	(doom-modeline-def-modeline 'special
;; 		'(eldoc bar window-state window-number modals matches buffer-info remote-host buffer-position word-count parrot selection-info)
;; 		'(compilation objed-state misc-info battery irc-buffers debug minor-modes input-method indent-info buffer-encoding major-mode process albin-timeclock time)))

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/org/")

;; Org-roam setup
(use-package! org-roam
  :init
  (setq org-roam-v2-ack t
	;; Use the main org directory as the roam vault.
	org-roam-directory (expand-file-name org-directory))
  :config
  (make-directory org-roam-directory t)
  (org-roam-db-autosync-mode 1)
  (map! :leader
	(:prefix ("n" . "notes")
	 :desc "Agenda" "a" #'org-agenda
	 :desc "Capture" "c" #'org-capture
	 :desc "Today (daily)" "d" #'org-roam-dailies-goto-today
	 :desc "Find node" "f" #'org-roam-node-find
	 :desc "Insert node" "i" #'org-roam-node-insert
	 :desc "Toggle roam buffer" "l" #'org-roam-buffer-toggle
	 :desc "Tomorrow (daily)" "m" #'org-roam-dailies-goto-tomorrow
	 :desc "Find node" "n" #'org-roam-node-find
	 :desc "Capture node" "r" #'org-roam-capture
	 :desc "Sync roam DB" "s" #'org-roam-db-sync
	 :desc "Capture today" "t" #'org-roam-dailies-capture-today
	 :desc "Random node" "x" #'org-roam-node-random
	 :desc "Yesterday (daily)" "y" #'org-roam-dailies-goto-yesterday
	 (:prefix ("R" . "roam-extra")
	  :desc "Add alias" "a" #'org-roam-alias-add
	  :desc "Add tag" "t" #'org-roam-tag-add))))

;; Make Org workflows (agenda/capture/notes) roam-first.
(after! org
  (setq org-default-notes-file (expand-file-name "inbox.org" org-roam-directory)
	org-agenda-files (list org-roam-directory)
	org-agenda-file-regexp "\\`[^.].*\\.org\\'")

  (setq org-capture-templates
	'(("t" "Todo" entry
	   (file+headline org-default-notes-file "Tasks")
	   "* TODO %?\n%U\n")
	  ("n" "Note" entry
	   (file+headline org-default-notes-file "Notes")
	   "* %?\n%U\n"))))

;; GitHub Copilot setup
(use-package! copilot
  :hook (prog-mode . copilot-mode)
  :config
  (map! :map copilot-completion-map
	  "<tab>" #'copilot-accept-completion
	  "TAB" #'copilot-accept-completion
	  "C-<tab>" #'copilot-accept-completion-by-word)
  (map! :leader
	  (:prefix ("t c" . "copilot")
	   :desc "Toggle Copilot" "t" #'copilot-mode
	   :desc "Login" "l" #'copilot-login
	   :desc "Panel" "p" #'copilot-panel-complete)))

;; Force .tsx to web-mode to avoid tree-sitter grammar issues.
(add-to-list 'auto-mode-alist '("\\.tsx\\'" . web-mode))

;; Make eglot-ensure callable from hooks before Eglot itself is loaded.
(autoload 'eglot-ensure "eglot")

;; Start Eglot automatically in programming buffers.
(add-hook 'prog-mode-hook #'eglot-ensure)

;; If .tsx opens in web-mode, still attach Eglot.
(defun +eglot-ensure-for-tsx-in-web-mode-h ()
  (when (and buffer-file-name
             (string-match-p "\\.tsx\\'" buffer-file-name))
    (eglot-ensure)))
(add-hook 'web-mode-hook #'+eglot-ensure-for-tsx-in-web-mode-h)

;; Auto-start Eglot for programming buffers.
(after! eglot
  ;; Ensure TS/TSX major modes use the TypeScript language server.
  (add-to-list 'eglot-server-programs
	       '((typescript-mode typescript-ts-mode typescript-tsx-mode
		  tsx-ts-mode js-mode js-ts-mode js2-mode rjsx-mode web-mode)
		 . ("typescript-language-server" "--stdio")))
  )

;; -----------------------------
;; Phase 2: workflow upgrades
;; -----------------------------

;; Better structure for org-roam notes.
(after! org-roam
	(setq org-roam-capture-templates
				'(("p" "project" plain
					 "* Goals\n%?\n\n* Tasks\n** TODO First task\n\n* Notes\n"
					 :if-new (file+head "projects/%<%Y%m%d%H%M%S>-${slug}.org"
															"#+title: ${title}\n#+filetags: :project:\n#+created: %U\n")
					 :unnarrowed t)
					("a" "area" plain
					 "* Why this matters\n%?\n\n* Ongoing\n"
					 :if-new (file+head "areas/%<%Y%m%d%H%M%S>-${slug}.org"
															"#+title: ${title}\n#+filetags: :area:\n#+created: %U\n")
					 :unnarrowed t)
					("i" "idea" plain
					 "%?"
					 :if-new (file+head "ideas/%<%Y%m%d%H%M%S>-${slug}.org"
															"#+title: ${title}\n#+filetags: :idea:\n#+created: %U\n")
					 :unnarrowed t)
					("m" "meeting" plain
					 "* Attendees\n- \n\n* Notes\n%?\n\n* Actions\n** TODO "
					 :if-new (file+head "meetings/%<%Y%m%d%H%M%S>-${slug}.org"
															"#+title: ${title}\n#+filetags: :meeting:\n#+created: %U\n")
					 :unnarrowed t)))

	(setq org-roam-dailies-capture-templates
				'(("d" "default" entry
					 "* %<%H:%M> %?"
					 :if-new (file+head "daily/%<%Y-%m-%d>.org"
															"#+title: %<%A, %d %B %Y>\n")))))

;; Agenda grouping for a clean "today" command.
(use-package! org-super-agenda
	:after org-agenda
	:config
	(org-super-agenda-mode 1)
	(setq org-agenda-custom-commands
				'(("z" "Today"
					 ((agenda ""
										((org-agenda-span 1)
										 (org-super-agenda-groups
											'((:name "Overdue" :deadline past)
												(:name "Due Today" :deadline today)
												(:name "Important" :priority "A")
												(:name "Next Actions" :todo "NEXT")
												(:name "Inbox" :file-path "inbox")
												(:discard (:anything t)))))))))))

;; Coding quality-of-life defaults.
(setq-default fill-column 100)
(add-hook 'prog-mode-hook #'display-fill-column-indicator-mode)
(add-hook 'prog-mode-hook #'hl-line-mode)
(after! apheleia
	(setq apheleia-log-only-errors t))
(after! flycheck
	(setq flycheck-display-errors-delay 0.2
				flycheck-indication-mode 'right-fringe))

;; Workspace persistence and bootstrap helpers.
(after! persp-mode
	(setq persp-auto-save-opt 1
				persp-set-last-persp-for-new-frames t)
	(add-hook 'kill-emacs-hook #'persp-state-save))

(defun albin/workspaces-bootstrap ()
	"Create a practical default workspace layout."
	(interactive)
	(+workspace-switch "main" t)
	(+workspace/new "notes")
	(+workspace/new "code")
	(+workspace-switch "main" t)
	(message "Workspaces ready: main, notes, code"))

;; Maintenance helpers: Doom diagnostics and keybinding cheatsheet.
(defun albin/doom-health-check ()
	"Run Doom diagnostics in a compile buffer."
	(interactive)
	(let ((doom-bin (if (file-executable-p (expand-file-name "~/.config/emacs/bin/doom"))
											(expand-file-name "~/.config/emacs/bin/doom")
										"doom")))
		(compile (format "%s doctor && %s profile"
										 (shell-quote-argument doom-bin)
										 (shell-quote-argument doom-bin)))))

(defun albin/show-keymap-cheatsheet ()
	"Show personal keybindings in one place."
	(interactive)
	(with-current-buffer (get-buffer-create "*Albin Keys*")
		(let ((inhibit-read-only t))
			(erase-buffer)
			(insert "Albin Keymap Cheatsheet\n")
			(insert "======================\n\n")
			(insert "Notes / Roam (SPC n)\n")
			(insert "  SPC n a  agenda       SPC n c  capture\n")
			(insert "  SPC n d  daily today  SPC n f  find node\n")
			(insert "  SPC n i  insert node  SPC n r  capture node\n")
			(insert "  SPC n t  capture daily SPC n x random node\n\n")
			(insert "Copilot (SPC t c)\n")
			(insert "  SPC t c t  toggle   SPC t c l  login   SPC t c p  panel\n\n")
			(insert "Dashboard\n")
			(insert "  i in  o out  b break  r resume  p profile  g refresh  q quit\n\n")
			(insert "Maintenance\n")
			(insert "  SPC h D  Doom health check   SPC h K  this cheatsheet\n")
			(special-mode)
			(goto-char (point-min))))
	(pop-to-buffer "*Albin Keys*"))

;; Lightweight git backups for notes/timeclock repos.
(defcustom albin/backup-interval-seconds 1800
	"Automatic backup interval for notes and timeclock in seconds."
	:type 'integer)

(defvar albin/backup-timer nil
	"Timer for automatic notes/timeclock backups.")

(defun albin/git-root (dir)
	"Return git root for DIR, or nil when DIR is not inside a git repository."
	(let ((default-directory (expand-file-name dir)))
		(condition-case nil
				(car (process-lines "git" "rev-parse" "--show-toplevel"))
			(error nil))))

(defun albin/git-backup-path (path label)
	"Commit PATH changes to its git repo with LABEL.
Returns non-nil if a commit was made."
	(let* ((full-path (expand-file-name path))
				 (repo (albin/git-root full-path)))
		(when repo
			(let* ((default-directory repo)
						 (rel (file-relative-name full-path repo))
						 (stamp (format-time-string "%Y-%m-%d %H:%M"))
						 (changed nil))
				(with-temp-buffer
					(call-process "git" nil (current-buffer) nil "status" "--porcelain" "--" rel)
					(setq changed (> (buffer-size) 0)))
				(when changed
					(call-process "git" nil nil nil "add" "--" rel)
					(when (eq 0 (call-process "git" nil nil nil "commit" "-m" (format "backup(%s): %s" label stamp)))
						t))))))

(defun albin/backup-notes-and-timeclock ()
	"Commit local note/timeclock changes when their repos are dirty."
	(interactive)
	(let ((notes-done (albin/git-backup-path org-directory "org"))
				(time-done (and (boundp 'albin-timeclock-data-directory)
												albin-timeclock-data-directory
												(albin/git-backup-path albin-timeclock-data-directory "timeclock"))))
		(message "Backup complete: notes=%s timeclock=%s"
						 (if notes-done "committed" "clean/no-repo")
						 (if time-done "committed" "clean/no-repo"))))

(defun albin/start-backup-timer ()
	"Start automatic notes/timeclock backup timer."
	(interactive)
	(when albin/backup-timer
		(cancel-timer albin/backup-timer))
	(setq albin/backup-timer
				(run-at-time 120 albin/backup-interval-seconds #'albin/backup-notes-and-timeclock))
	(message "Backup timer started (%ss interval)" albin/backup-interval-seconds))

(defun albin/stop-backup-timer ()
	"Stop automatic notes/timeclock backup timer."
	(interactive)
	(when albin/backup-timer
		(cancel-timer albin/backup-timer)
		(setq albin/backup-timer nil))
	(message "Backup timer stopped"))

(albin/start-backup-timer)

;; Custom keybindings for workflow helpers.
(map! :leader
			:desc "Doom health check" "h D" #'albin/doom-health-check
			:desc "My key cheatsheet" "h K" #'albin/show-keymap-cheatsheet)

(map! :leader
			(:prefix ("w" . "workspace")
			 :desc "Bootstrap workspaces" "B" #'albin/workspaces-bootstrap
			 :desc "Save workspace state" "S" #'persp-state-save
			 :desc "Load workspace state" "L" #'persp-state-load))

(map! :leader
			(:prefix ("n b" . "backup")
			 :desc "Backup now" "b" #'albin/backup-notes-and-timeclock
			 :desc "Start backup timer" "s" #'albin/start-backup-timer
			 :desc "Stop backup timer" "x" #'albin/stop-backup-timer))



;; Whenever you reconfigure a package, make sure to wrap your config in an
;; `with-eval-after-load' block, otherwise Doom's defaults may override your
;; settings. E.g.
;;
;;   (with-eval-after-load 'PACKAGE
;;     (setq x y))
;;
;; The exceptions to this rule:
;;
;;   - Setting file/directory variables (like `org-directory')
;;   - Setting variables which explicitly tell you to set them before their
;;     package is loaded (see 'C-h v VARIABLE' to look them up).
;;   - Setting doom variables (which start with 'doom-' or '+').
;;
;; Here are some additional functions/macros that will help you configure Doom.
;;
;; - `load!' for loading external *.el files relative to this one
;; - `add-load-path!' for adding directories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; To get information about any of these functions/macros, move the cursor over
;; the highlighted symbol at press 'K' (non-evil users must press 'C-c c k').
;; This will open documentation for it, including demos of how they are used.
;; Alternatively, use `C-h o' to look up a symbol (functions, variables, faces,
;; etc).
;;
;; You can also try 'gd' (or 'C-c c d') to jump to their definition and see how
;; they are implemented.

;; Load local modules from ~/.config/doom/lisp.
(add-load-path! "lisp")

;; Store all timeclock data files under ~/timeclock/.
(setq albin-timeclock-data-directory (expand-file-name "~/timeclock/"))
(make-directory albin-timeclock-data-directory t)

;; Albin custom modules.
(require 'albin-timeclock)
(require 'albin-dashboard)

;; Replace Doom's default startup dashboard with Albin's dashboard.
(add-hook 'emacs-startup-hook #'albin/dashboard)

(defun albin/use-dashboard-overrides-h ()
  "Ensure Doom dashboard commands open Albin dashboard."
  (when (and (fboundp '+dashboard/open)
	     (not (advice-member-p #'albin/dashboard-open-for-doom #'+dashboard/open)))
    (advice-add #'+dashboard/open :override #'albin/dashboard-open-for-doom)))

(add-hook 'doom-init-ui-hook #'albin/use-dashboard-overrides-h)
(add-hook 'emacs-startup-hook #'albin/use-dashboard-overrides-h)
