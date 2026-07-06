 ;;; config.el -*- no-byte-compile: t; -*-
(setq doom-font (font-spec :family (if (eq system-type 'darwin) "Menlo" "DejaVu Sans Mono")
                           :size 14 :weight 'medium)
      ;; themes that work well in:
      ;; - tty: old-hope vivendi challenger-deep homage-black bluloco-dark city-lights acario-dark
      ;; - and in gui: old-hope challenger-deep homage-black bluloco-dark city-ligths acario-dark
      ;; - from blackest to lightest: acario-dark homage-black old-hope challenger-deep bluloco-dark city-ligths
      doom-theme 'doom-old-hope
      fancy-splash-image (concat doom-private-dir "themes/splash.png")
      evil-snipe-scope 'buffer
      evil-escape-key-sequence "ii"
      evil-escape-delay 0.0
      avy-timeout-seconds 0.15
      confirm-kill-emacs nil)
(defvar toggle-window-maximization t)

;; (with-eval-after-load 'eglot
;;   (require 'browse-url)
;;   (require 'map)
;;   (require 'seq)
;;   (require 'subr-x))
(after! eglot
  (setq eldoc-idle-delay 0.2) ; Speed up documentation appearance
  (setq eglot-extend-to-xref t)
  (add-hook 'eglot-managed-mode-hook #'sideline-mode)
  (defun my-eglot-rust--seq (x)
    (cond
     ((null x) nil)
     ((vectorp x) (append x nil))
     ((listp x) x)
     (t (list x))))

  (defun my-eglot-rust--env-alist (env)
    "Convert rust-analyzer env object ENV to process-environment entries."
    (cond
     ((null env) nil)
     ((hash-table-p env)
      (let (out)
        (maphash (lambda (k v)
                   (push (format "%s=%s" k v) out))
                 env)
        out))
     ((listp env)
      (cl-loop for (k v) on env by #'cddr
               collect (format "%s=%s"
                               (string-remove-prefix ":" (symbol-name k))
                               v)))))

  (defun my-eglot-rust--run-runnable (runnable)
    "Run a rust-analyzer RUNNABLE in a compilation buffer."
    (let* ((kind (map-elt runnable :kind))
           (label (or (map-elt runnable :label) "rust-analyzer runnable"))
           (args (map-elt runnable :args))
           (cargo-args (my-eglot-rust--seq (map-elt args :cargoArgs)))
           (executable-args (my-eglot-rust--seq (map-elt args :executableArgs)))
           (workspace-root (map-elt args :workspaceRoot))
           (expect-test (map-elt args :expectTest))
           (environment (map-elt args :environment))
           (default-directory
            (file-name-as-directory
             (or workspace-root default-directory))))
      (unless (string= kind "cargo")
        (user-error "Unsupported rust-analyzer runnable kind: %s" kind))
      (let ((process-environment
             (append
              (when expect-test '("UPDATE_EXPECT=1"))
              (my-eglot-rust--env-alist environment)
              process-environment))
            (cmd (mapconcat
                  #'shell-quote-argument
                  (append '("cargo")
                          cargo-args
                          (when executable-args '("--"))
                          executable-args)
                  " ")))
        (compilation-start
         cmd
         (when (fboundp 'cargo-process-mode) 'cargo-process-mode)
         (lambda (_) (format "*%s*" label))))))

  (defun lsp-find-related-rust-tests ()
    "Find and run tests related to the Rust symbol at point."
    (interactive)
    (unless (eglot-current-server)
      (user-error "No Eglot server running"))
    (let* ((resp (jsonrpc-request
                  (eglot-current-server)
                  :rust-analyzer/relatedTests
                  (eglot--TextDocumentPositionParams)))
           (tests (my-eglot-rust--seq resp))
           (runnables
            (delq nil
                  (mapcar (lambda (test)
                            (map-elt test :runnable))
                          tests))))
      (unless runnables
        (user-error "No related tests found"))
      (let* ((choices
              (mapcar (lambda (r)
                        (cons (or (map-elt r :label) "<unnamed test>") r))
                      runnables))
             (choice (completing-read "Related test: " choices nil t)))
        (my-eglot-rust--run-runnable (cdr (assoc choice choices))))))

  (defun lsp-find-parent-module ()
    "Jump to the Rust parent module using rust-analyzer via Eglot."
    (interactive)
    (unless (eglot-current-server)
      (user-error "No Eglot server running"))
    (let* ((locs (jsonrpc-request
                  (eglot-current-server)
                  :experimental/parentModule
                  (eglot--TextDocumentPositionParams)))
           (locs (and locs (seq-into locs 'list))))
      (unless locs
        (user-error "No parent module found"))
      (let* ((loc
              (if (= (length locs) 1)
                  (car locs)
                (let* ((choices
                        (mapcar
                         (lambda (loc)
                           (let* ((uri (or (map-elt loc :targetUri)
                                           (map-elt loc :uri)))
                                  (path (eglot--uri-to-path uri)))
                             (cons (abbreviate-file-name path) loc)))
                         locs))
                       (choice (completing-read "Parent module: " choices nil t)))
                  (cdr (assoc choice choices)))))
             (uri (or (map-elt loc :targetUri)
                      (map-elt loc :uri)))
             (range (or (map-elt loc :targetSelectionRange)
                        (map-elt loc :targetRange)
                        (map-elt loc :range))))
        (find-file (eglot--uri-to-path uri))
        (goto-char (car (eglot--range-region range))))))

  (defun lsp-rust-analyzer-open-external-docs ()
    "Open external Rust docs for the symbol at point using rust-analyzer."
    (interactive)
    (unless (eglot-current-server)
      (user-error "No Eglot server running"))
    (let* ((res (jsonrpc-request
                 (eglot-current-server)
                 :experimental/externalDocs
                 (eglot--TextDocumentPositionParams)))
           (url
            (cond
             ;; Older/common response: plain URL string.
             ((stringp res) res)
             ;; Newer response when local docs are supported:
             ;; { web?: string, local?: string }
             ((hash-table-p res)
              (or (gethash "local" res)
                  (gethash "web" res)
                  (gethash :local res)
                  (gethash :web res)))
             ((listp res)
              (or (map-elt res :local)
                  (map-elt res :web)
                  (map-elt res "local")
                  (map-elt res "web"))))))
      (unless url
        (user-error "No external docs found"))
      (browse-url url))))
(use-package sideline-eglot
  :hook (eglot-managed-mode . sideline-mode)
  :init
  (setq sideline-backends-right '(sideline-eglot))
  :config
  (setq sideline-eglot-code-actions-prefix ""))
(use-package! eldoc-box
  :hook (eglot-managed-mode . eldoc-box-hover-at-point-mode)
  :config
  (setq eldoc-box-max-pixel-width 600
        eldoc-box-max-pixel-height 400))

;; Noctalia theme (generated by noctalia-shell user template)
;; (add-to-list 'custom-theme-load-path "~/.local/share/noctalia/emacs-themes/")
;; (add-hook 'after-init-hook (lambda () (ignore-errors (load-theme 'noctalia t))))

(map! :nv "C-M-d"        #'+multiple-cursors/evil-mc-toggle-cursor-here) ;; dumb, but it is what it is
(map! :gnv
      ;; num row
      "M-s-1"            #'+workspace/switch-to-0
      "M-s-2"            #'+workspace/switch-to-1
      "M-s-3"            #'+workspace/switch-to-2
      "M-s-4"            #'+workspace/switch-to-3
      "M-s-5"            #'+workspace/switch-to-4
      "M-s-6"            #'+workspace/switch-to-5
      "M-s-7"            #'+workspace/switch-to-6
      "M-s-8"            #'+workspace:switch-previous
      "M-s-9"            #'+workspace:switch-next
      "M-s-0"            #'+workspace/kill

      "C-M-w"            #'+goto-previous-function.outer
      "C-M-S-w"          #'+goto-previous-class.outer
      "C-M-f"            #'save-buffer
      "C-M-S-f"          #'evil-avy-goto-char-timer
      ;; "C-M-p"            #'scroll-other-window
      "C-M-g"            #'magit-status ;; g
      "C-M-r"            #'+goto-function.outer
      "C-M-S-r"          #'+goto-class.outer
      "C-M-S-s"          #'gptel-send
      ;; "C-M-S-s"          #'gptel-menu
      ;; "C-M-t"            #'scroll-other-window-down
      "C-M-d"            #'+multiple-cursors/evil-mc-toggle-cursor-here
      "C-M-v"            #'lsp-extend-selection
      "C-s-v"            #'popterm-toggle-cd

      "C-M-j"            #'+default/diagnostics
      "C-M-S-j"          #'eglot-code-actions
      "C-M-l"            #'+lookup/definition
      "C-M-S-l"          #'lsp-find-parent-module
      "C-M-u"            #'+lookup/references
      "C-M-S-u"          #'lsp-find-related-rust-tests
      "C-M-y"            #'consult-imenu
      "C-M-S-y"          #'consult-imenu-multi
      "C-M-s-y"          #'consult-eglot-symbols
      "C-M-;"            #'lsp-ui-peek--goto-xref-other-window
      "C-M-:"            #'lsp-rust-analyzer-open-external-docs
      "C-M-k"            #'kill-current-buffer
      "M-RET"            (λ! (if toggle-window-maximization ;; C-M-m, for some reason registered as M-RET
                                 (progn (evil-resize-window (- (frame-width) 1) t)
                                        (evil-resize-window (- (frame-width) 1) nil))
                               (balance-windows))
                             (setq toggle-window-maximization (not toggle-window-maximization)))

      "C-M-,"            #'previous-buffer
      "C-M-/"            #'next-buffer
      )
(use-package! uv)
(use-package! combobulate)
(map! :map smerge-mode-map :nv
      "n"             #'smerge-prev
      "e"             #'smerge-keep-lower
      "i"             #'smerge-keep-upper
      "o"             #'smerge-next)

(use-package! popterm
  :config
  (setq popterm-backend        'ghostel     ; or 'ghostel, 'eat, 'shell, 'eshell
        popterm-display-method 'window  ; or 'posframe, 'fullscreen
        popterm-scope          'project   ; or 'frame, 'dedicated, nil
        popterm-auto-cd        t)
  (popterm-global-mode 1))
(use-package! ghostel
  :defer t
  :ensure t)
(after! projectile
  (setq projectile-project-search-path '("~/Desktop/")))

(use-package! rustic
  :config
  (setq lsp-rust-server 'rust-analyzer)
  (setq rustic-clippy-arguments "--verbose --tests --benches -- -D clippy::all")
  (setq rustic-lsp-server 'rust-analyzer))
(after! lsp-mode
  (setq lsp-rust-analyzer-inlay-hints-mode t)
  (setq lsp-rust-analyzer-server-display-inlay-hints t)
  (setq lsp-ui-sideline-enable nil)
  (setq lsp-ui-sideline-show-hover nil)
  (setq lsp-ui-peek-always-show t)
  (setq lsp-inlay-hint-enable t)
  (setq lsp-auto-guess-root nil))
(add-hook 'python-mode-hook 'ruff-format-on-save-mode)
(add-hook 'python-mode-hook #'flymake-ruff-load)
(add-hook 'python-ts-mode-hook 'ruff-format-on-save-mode)
(add-hook 'python-ts-mode-hook #'flymake-ruff-load)
(use-package! which-key
  :config
  (setq which-key-idle-delay 0))

(define-prefix-command 'uv-command-prefix)

(defvar uv-command-map uv-command-prefix
  "Prefix command map for uv and Python workflow commands.")

(use-package! python-pytest
  :defer t)

(map! :map uv-command-map
      :desc "Repeat uv run"        "C-c" #'uv-repeat-run
      :desc "Run pytest"           "C-t" #'python-pytest
      :desc "Pytest dispatch"      "C-d" #'python-pytest-dispatch
      :desc "Run uv"               "C-u" #'uv
      :desc "Format with Ruff"     "C-f" #'ruff-format-buffer
      :desc "Add dependency"       "C-a" #'uv-add
      :desc "Remove dependency"    "C-<delete>" #'uv-remove
      :desc "Lock dependencies"    "C-l" #'uv-lock
      :desc "Sync environment"     "C-s" #'uv-sync
      :desc "Create venv"          "C-v" #'uv-venv
      :desc "Run command"          "C-r" #'uv-run)

(after! python
  (map! :map python-mode-map
        "C-c C-c" #'uv-command-prefix
        "C-c C-w" #'python-shell-send-buffer)
  (map! :map python-ts-mode-map
        "C-c C-c" #'uv-command-prefix
        "C-c C-w" #'python-shell-send-buffer))

(use-package! agent-shell
  :commands (agent-shell))
(use-package! gptel
  :defer t
  :config
  (setq  gptel-directives '((default . "You are a large language model living in Emacs and a helpful coding assistant. Respond concisely.")
                            (arbitrage . "As Arbitrage Expert, you specialize in advanced strategies, including cross-exchange trades, in financial markets. Your expertise encompasses risk, spatial, statistical, and triangular arbitrage, with a keen focus on exploiting price discrepancies across different exchanges. Tailored for professionals deeply versed in financial markets, you offer nuanced, data-driven insights into identifying and capitalizing on these opportunities. Your knowledge extends to sophisticated trading algorithms and the latest technologies facilitating efficient cross-exchange arbitrage. Your interactions are analytical and precise, essential for successful arbitrage trading.")
                            (crypto . "As Crypto Commander, you are a specialized GPT model dedicated to advanced and professional-level discourse in the realm of cryptocurrency trading. Your role is to provide high-level, expert insights into cryptocurrency markets, trading strategies, and technological advancements. You cater to users with a deep understanding of cryptocurrency trading, ensuring that interactions remain sophisticated and professional. Your expertise includes detailed analysis of trading indicators, algorithms, and dashboards, tailored for professionals deeply ingrained in the cryptocurrency industry. Your responses are designed to be nuanced and in-depth, suitable for the complex and dynamic world of cryptocurrencies.")
                            (programming . "You are a large language model and a careful programmer. Provide code and only code as output without any additional text, prompt or note.")
                            (writing . "You are a large language model and a writing assistant. Respond concisely.")
                            (chat . "You are a large language model and a conversation partner. Respond concisely.")
                            (rust . "You are expert coder, staff software engineer in fintech company. You are expert at rust, concurrency, multithreading, and async code.")
                            )))
(setq magit-todos-mode -1)
(use-package! kanata-kbd-mode
  :mode ("\\.kbd\\'" . kanata-kbd-mode))

;; (setq! +lookup--last-provider '((fundamental-mode . "Google") (org-mode . "Google") (rust-mode . "Google") (rustic-mode . "Google")))
;; (custom-set-variables
;; '(ns-control-modifier 'meta)
;; '(ns-command-modifier 'control)
;; '(ns-alternate-modifier 'option)
;; '(ns-option-modifier 'option)
;; )
;; (setq aw-keys '(?n ?e ?i ?o ?m ?u ?y))
;; (defhydra +hydra/window-nav (:hint nil) "resize window: _o_:increase width  _n_:decrease width  _i_:increase height  _e_:decrease height _q_:quit"
;;     ("o" evil-window-increase-width)
;;     ("n" evil-window-decrease-width)
;;     ("i" evil-window-increase-height)
;;     ("e" evil-window-decrease-height)
;;     ("q" nil))
;; we recommend using use-package to organize your init.el
;; (use-package! codeium
;;     ;; if you use straight
;;     ;; :straight '(:type git :host github :repo "Exafunction/codeium.el")
;;     ;; otherwise, make sure that the codeium.el file is on load-path

;;     :init
;;     ;; use globally
;;     (add-to-list 'completion-at-point-functions #'codeium-completion-at-point)
;;     ;; or on a hook
;;     ;; (add-hook 'python-mode-hook
;;     ;;     (lambda ()
;;     ;;         (setq-local completion-at-point-functions '(codeium-completion-at-point))))

;;     ;; if you want multiple completion backends, use cape (https://github.com/minad/cape):
;;     ;; (add-hook 'python-mode-hook
;;     ;;     (lambda ()
;;     ;;         (setq-local completion-at-point-functions
;;     ;;             (list (cape-super-capf #'codeium-completion-at-point #'lsp-completion-at-point)))))
;;     ;; an async company-backend is coming soon!

;;     ;; codeium-completion-at-point is autoloaded, but you can
;;     ;; optionally set a timer, which might speed up things as the
;;     ;; codeium local language server takes ~0.2s to start up
;;     ;; (add-hook 'emacs-startup-hook
;;     ;;  (lambda () (run-with-timer 0.1 nil #'codeium-init)))

;;     ;; :defer t ;; lazy loading, if you want
;;     :config
;;     (setq use-dialog-box nil) ;; do not use popup boxes

;;     ;; if you don't want to use customize to save the api-key

;;     ;; get codeium status in the modeline
;;     (setq codeium-mode-line-enable
;;         (lambda (api) (not (memq api '(CancelRequest Heartbeat AcceptCompletion)))))
;;     (add-to-list 'mode-line-format '(:eval (car-safe codeium-mode-line)) t)
;;     ;; alternatively for a more extensive mode-line
;;     ;; (add-to-list 'mode-line-format '(-50 "" codeium-mode-line) t)

;;     ;; use M-x codeium-diagnose to see apis/fields that would be sent to the local language server
;;     (setq codeium-api-enabled
;;         (lambda (api)
;;             (memq api '(GetCompletions Heartbeat CancelRequest GetAuthToken RegisterUser auth-redirect AcceptCompletion))))
;;     ;; you can also set a config for a single buffer like this:
;;     ;; (add-hook 'python-mode-hook
;;     ;;     (lambda ()
;;     ;;         (setq-local codeium/editor_options/tab_size 4)))

;;     ;; You can overwrite all the codeium configs!
;;     ;; for example, we recommend limiting the string sent to codeium for better performance
;;     (defun my-codeium/document/text ()
;;         (buffer-substring-no-properties (max (- (point) 3000) (point-min)) (min (+ (point) 1000) (point-max))))
;;     ;; if you change the text, you should also change the cursor_offset
;;     ;; warning: this is measured by UTF-8 encoded bytes
;;     (defun my-codeium/document/cursor_offset ()
;;         (codeium-utf8-byte-length
;;             (buffer-substring-no-properties (max (- (point) 3000) (point-min)) (point))))
;;     (setq codeium/document/text 'my-codeium/document/text)
;;     (setq codeium/document/cursor_offset 'my-codeium/document/cursor_offset))
;; accept completion from copilot and fallback to company
;;(use-package! copilot
;;:hook (prog-mode . copilot-mode)
;; :bind (("C-TAB" . 'copilot-accept-completion-by-word)
;;        ("C-<tab>" . 'copilot-accept-completion-by-word)
;;       :map copilot-completion-map
;;      ("<tab>" . 'copilot-accept-completion)
;;     ("TAB" . 'copilot-accept-completion)))
;; (use-package! git-link)
;; (use-package! mermaid-mode)
;; (use-package! mini-modeline
;;   :after smart-mode-line
;;   :config
;;   (mini-modeline-mode t))
;; (use-package! nyan-mode
;;   :config
;;   (nyan-mode 1)
;;   (nyan-start-animation))
;; (use-package! ob-mermaid
;;   :config
;;   (org-babel-do-load-languages 'org-babel-load-languages
;;                               (append org-babel-load-languages
;;                               '((mermaid . t)))))
;; (use-package! org-roam
;;   :after org
;;   :config
;;   (setq org-roam-dailies-directory "Journal/")
;;   (setq org-roam-capture-templates
;;         '(("n" "default" plain "%?"
;;            :target (file+head "pkms/${slug}.org" "${title}\n\n")
;;            :unnarrowed t)
;;           ("j" "new jira ticket" entry "* %?"
;;            :target (file+head+olp "pkms/${slug}.org" "${title}\n#+filetags: ${title}\n\n" ("Inbox"))
;;            :unnarrowed t)
;;           ("q" "question" entry "* [[id:66d7d310-3832-4bf9-9be2-df6e1aeccd61][QUESTION]] %?"
;;            :target (file+head+olp "pkms/${slug}.org" "${title}\n\n" ("Inbox"))
;;            :unnarrowed t)
;;           ("t" "todo" entry "* TODO %?"
;;            :target (file+head+olp "pkms/${slug}.org" "${title}\n\n" ("Inbox"))
;;            :unnarrowed t)))
;; )
;; (use-package! md-roam
;;   :after org-roam
;;   :config
;;   (set-company-backend! 'markdown-mode 'company-capf) ; add company-capf as company backend in markdown buffers
;;   (setq org-roam-file-extensions '("org" "md")) ; enable Org-roam for a markdown files
;;   (md-roam-mode 1) ; md-roam-mode needs to be active before org-roam-db-sync
;;   (org-roam-db-autosync-mode 1)
;;   (add-to-list 'org-roam-capture-templates
;;                '("m" "Markdown" plain "" :target
;;                  (file+head "%<%Y-%m-%dT%H%M%S>-${slug}.md"
;;                             "---\ntitle: ${title}\nid: %<%Y-%m-%dT%H%M%S>\ncategory: \n---\n")
;;                  :unnarrowed t)))

;; (use-package! powerthesaurus)
;; (after! rustic
;;   (setq lsp-rust-server 'rust-analyzer)
;;   (setq rustic-lsp-server 'rust-analyzer))
;; (use-package! string-inflection
;;   :config
;;   (map! :n "g C" #'string-inflection-all-cycle)
;; )
                                        ; (use-package! switch-window
;;   :config
;;   (setq switch-window-qwerty-shortcuts '("n" "e" "i" "o" "m" "u" "r")))
;; (use-package! vc-msg)
;; Start server in daemon mode — Doom only does this for GUI displays
;; (when (and (daemonp) (not (display-graphic-p)))
;;   (require 'server)
;;   (unless (server-running-p)
;;     (server-start)))
