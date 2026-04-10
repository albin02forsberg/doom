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
(setq display-line-numbers-type t)

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
