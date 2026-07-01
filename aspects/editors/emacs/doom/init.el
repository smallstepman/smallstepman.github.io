;;; init.el -*- lexical-binding: t; -*-

;; This file controls what Doom modules are enabled and what order they load
;; in. Remember to run 'doom sync' after modifying it!

;; NOTE Press 'SPC h d h' (or 'C-h d h' for non-vim users) to access Doom's
;;      documentation. There you'll find a "Module Index" link where you'll find
;;      a comprehensive list of Doom's modules and what flags they support.

;; NOTE Move your cursor over a module's name (or its flags) and press 'K' (or
;;      'C-c c k' for non-vim users) to view its documentation. This works on
;;      flags as well (those symbols that start with a plus).
;;
;;      Alternatively, press 'gd' (or 'C-c c d') on a module to browse its
;;      directory (for easy access to its source code).

(doom! :input
       ;;layout            ; auie,ctsrnm is the superior home row

       :completion
       (corfu +icons +orderless +dabbrev)             ; the ultimate code completion backend
       (vertico +icons +childframe)             ; the search engine of the future
       ;;helm              ; the *other* search engine for love and life
       ;;ido               ; the other *other* search engine...
       ;;ivy               ; a search engine for love and life

       :ui
       ;;   deft              ; notational velocity for Emacs
       doom                ; what makes DOOM look the way it does
       dashboard      ; a nifty splash screen for Emacs
       (emoji +ascii +github +unicode)
       hl-todo             ; highlight TODO/FIXME/NOTE/DEPRECATED/HACK/REVIEW
       indent-guides     ; highlighted indent columns
       ligatures         ; ligatures and symbols to make your code pretty again
       minimap           ; show a map of the code on the side
       modeline            ; snazzy, Atom-inspired modeline, plus API
       nav-flash           ; blink cursor line after big motions
       ophints             ; highlight the region an operation acts on
       (popup +defaults)   ; tame sudden yet inevitable temporary windows
       smooth-scroll
       tabs              ; a tab bar for Emacs
       treemacs            ; a project drawer, like neotree but cooler
       unicode             ; extended unicode support for various languages
       vc-gutter           ; vcs diff in the fringe
       vi-tilde-fringe     ; fringe tildes to mark beyond EOB
       (window-select +switch-window)     ; visually switch windows
       workspaces          ; tab emulation, persistence & separate workspaces
       ;;zen                 ; distraction-free coding or writing
       ;; doom-quit           ; DOOM quit-message prompts when you quit Emacs

       :editor
       (evil +everywhere)  ; come to the dark side, we have cookies
       ;; file-templates      ; auto-snippets for empty files
       fold                ; (nigh) universal code folding
       (format +onsave +lsp)    ; automated prettiness
       multiple-cursors    ; editing in many places at once
       snippets            ; my elves. They type so I don't have to
       objed             ; text object editing for the innocent
       rotate-text       ; cycle region at point between text candidates
       (whitespace +trim +guess)
       word-wrap         ; soft wrapping with language-aware indent

       :emacs
       (dired +icons +dirvish) ; making dired pretty [functional]
       electric            ; smarter, keyword-based electric-indent
       ibuffer             ; interactive buffer management
       (undo +tree)       ; persistent, smarter undo for your inevitable mistakes
       vc                  ; version-control and Emacs, sitting in a tree
       tramp

       :term
       vterm               ; the best terminal emulation in Emacs

       :checkers
       syntax              ; tasing you for every semicolon you forget
       ;; (spell +flyspell) ; tasing you for misspelling mispelling
       ;; grammar           ; tasing grammar mistake every you make

       :tools
       llm
       debugger      ; FIXME stepping through code, to help you add bugs
       (eval +overlay)     ; run code, run (also, repls)
       (lookup +dictionary +offline +docsets )              ; navigate your code and its documentation
       (lsp +peek +eglot +booster)         ; M-x vscode
       (magit +forge)      ; a git porcelain for Emacs
       make                ; run make tasks from Emacs
       pdf                 ; pdf enhancements
       tmux                ; an API for interacting with tmux
       tree-sitter
       direnv
       upload
       (docker +lsp +tree-sitter)
       (terraform +lsp)       ; taskrunner for all your projects
       ;;editorconfig      ; let someone else argue about tabs vs spaces
       ;;   biblio
       ;;ansible
       ;; ein                 ; tame Jupyter notebooks with emacs

       :os
       macos
       (tty +osc)

       :lang
       (cc +lsp +tree-sitter)
       emacs-lisp
       (javascript +lsp +tree-sitter)
       (nix +lsp +tree-sitter)
       (python +conda +uv +cython +lsp +pyright +tree-sitter)
       (rust +lsp +tree-sitter)
       (sh +lsp)
       (go +lsp +tree-sitter)
       (web +lsp +tree-sitter)
       (latex +cdlatex +fold +lsp)
       graphviz
       (markdown +lsp +tree-sitter +grip)
       (yaml +lsp +tree-sitter)
       rest
       data
       (json +lsp +tree-sitter)
       ;; beancount
       (lua +lsp +tree-sitter)
       ;; (org
       ;;  +pretty
       ;;  +roam2
       ;;  +gnuplot
       ;;  +jupyter
       ;;  +pandoc
       ;;  +pomodoro
       ;;  +hugo
       ;;  +brain
       ;;  +noter
       ;;  +snippets-dir
       ;;  +dragndrop
       ;;  +journal
       ;;  +present)
       ;;   plantuml
       ;;   (scheme +guile)
       ;;   solidity
       ;;   julia
       ;;    (swift +lsp)

       :email
       ;;(mu4e +org +gmail)
       ;;notmuch
       ;;(wanderlust +gmail)

       :app
       ;;  calendar
       ;;emms
       ;;    everywhere        ; *leave* Emacs!? You must be joking
       irc               ; how neckbeards socialize
       ;;    (rss +org)        ; emacs as an RSS reader
       ;;    twitter           ; twitter client https://twitter.com/vnought

       :config
       literate
       (default +bindings +smartparens))
