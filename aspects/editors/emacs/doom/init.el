;;; init.el -*- lexical-binding: t; -*-

(set-frame-parameter (selected-frame) 'alpha '(93 . 93))
;;(set-frame-parameter nil 'alpha-background 93)
;;(add-to-list 'default-frame-alist '(alpha-background . 93))
(add-to-list 'default-frame-alist '(inhibit-double-buffering . t))
(add-to-list 'default-frame-alist '(undecorated . t))
(doom!
 :completion
 (corfu +icons +orderless +dabbrev)
 (vertico +icons +childframe)

 :ui
 doom                    ; what makes DOOM look the way it does
 dashboard               ; a nifty splash screen for Emacs
 (emoji +ascii +github +unicode)
 hl-todo                 ; highlight TODO/FIXME/NOTE/DEPRECATED/HACK/REVIEW
 indent-guides           ; highlighted indent columns
 ligatures               ; ligatures and symbols to make your code pretty again
 minimap                 ; show a map of the code on the side
 modeline                ; snazzy, Atom-inspired modeline, plus API
 nav-flash               ; blink cursor line after big motions
 ophints                 ; highlight the region an operation acts on
 (popup +defaults)       ; tame sudden yet inevitable temporary windows
 smooth-scroll
 treemacs                ; a project drawer, like neotree but cooler
 unicode                 ; extended unicode support for various languages
 vc-gutter               ; vcs diff in the fringe
 vi-tilde-fringe         ; fringe tildes to mark beyond EOB
 (window-select +switch-window) ; visually switch windows
 workspaces              ; tab emulation, persistence & separate workspaces
 ;; deft                 ; notational velocity for Emacs
 ;; doom-quit            ; DOOM quit-message prompts when you quit Emacs
 ;; tabs                    ; a tab bar for Emacs
 ;; zen                  ; distraction-free coding or writing

 :editor
 (evil +everywhere)      ; come to the dark side, we have cookies
 fold                    ; (nigh) universal code folding
 (format +onsave +lsp)   ; automated prettiness
 multiple-cursors        ; editing in many places at once
 rotate-text             ; cycle region at point between text candidates
 snippets                ; my elves. They type so I don't have to
 (whitespace +trim +guess)
 word-wrap               ; soft wrapping with language-aware indent
 ;; file-templates       ; auto-snippets for empty files
 ;; objed                ; text object editing for the innocent

 :emacs
 (dired +icons +dirvish) ; making dired pretty [functional]
 electric                ; smarter, keyword-based electric-indent
 ibuffer                 ; interactive buffer management
 (undo +tree)            ; persistent, smarter undo for your inevitable mistakes
 vc                      ; version-control and Emacs, sitting in a tree
 tramp

 :term
 vterm                   ; the best terminal emulation in Emacs

 :checkers
 syntax                  ; tasing you for every semicolon you forget
 ;; grammar              ; tasing grammar mistake every you make
 ;; (spell +flyspell)    ; tasing you for misspelling mispelling

 :tools
 debugger                ; FIXME stepping through code, to help you add bugs
 direnv
 (docker +lsp +tree-sitter)
 (eval +overlay)         ; run code, run (also, repls)
 llm
 (lookup +dictionary +offline +docsets ) ; navigate your code and its documentation
 (lsp +peek +eglot +booster)
 (magit +forge)          ; a git porcelain for Emacs
 make                    ; run make tasks from Emacs
 pdf                     ; pdf enhancements
 (terraform +lsp)        ; taskrunner for all your projects
 tree-sitter
 upload
 ;; tmux                 ; an API for interacting with tmux
 ;; editorconfig         ; let someone else argue about tabs vs spaces
 ;; biblio
 ;; ansible
 ;; ein                  ; tame Jupyter notebooks with emacs

 :os
 macos
 (tty +osc)

 :lang
 (cc +lsp +tree-sitter)
 data
 emacs-lisp
 (go +lsp +tree-sitter)
 graphviz
 (javascript +lsp +tree-sitter)
 (json +lsp +tree-sitter)
 (latex +cdlatex +fold +lsp)
 (lua +lsp +tree-sitter)
 (markdown +lsp +tree-sitter +grip)
 (nix +lsp +tree-sitter)
 (org +pretty +roam2 +journal);; +gnuplot +jupyter +pandoc +pomodoro +hugo +brain +noter +snippets-dir +dragndrop +present)
 (python +conda +uv +cython +lsp +pyright +tree-sitter)
 rest
 (rust +lsp +tree-sitter)
 (sh +lsp)
 (web +lsp +tree-sitter)
 (yaml +lsp +tree-sitter)
 ;; beancount
 ;; julia
 ;; plantuml
 ;; (scheme +guile)
 ;; (swift +lsp)
 ;; solidity

 :email
 ;; (mu4e +org +gmail)
 ;; notmuch
 ;; (wanderlust +gmail)

 :app
 irc
 ;; calendar
 ;; emms
 ;; everywhere        ; *leave* Emacs!? You must be joking
 ;; (rss +org)        ; emacs as an RSS reader

 :config
 ;; literate
 (default +bindings +smartparens))
