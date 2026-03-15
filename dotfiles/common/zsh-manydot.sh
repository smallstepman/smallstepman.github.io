# -*- mode: sh -*-
#
# manydots-magic - zle tweak for emulating "..."=="../.." etc.
#
# Copyright (c) 2011, 2012 Akinori MUSHA
# Licensed under the 2-clause BSD license.
#
# This tweek helps input ancestor directories beyond the parent (`..')
# in a handy way.  You can just type triple dots to input `../..',
# quadruple dots to `../../..', etc..
#
#     % .. [Hit <.>]
#     % ../.. [Hit <.>]
#     % ../../.. [Hit <^H>]
#     % ../.. [Hit <^H>]
#     % ..
#
# As you see above, each of the `/..' parts complemented by this tweak
# can be deleted by a single invocation of the backward-delete-char
# command, only if invoked right after the magic happens.
#
#     % .. [Hit </><.><.>]
#     % ../.. [Hit <^H>]
#     % ../.
#
# Usage:
#     autoload -Uz manydots-magic
#     manydots-magic
#

manydots-magic.self-insert() {
    emulate -L zsh
    local self_insert_function magic_count
    zstyle -s ':manydots-magic' self-insert-function self_insert_function

    if [[ "$KEYS" == .* && "$LBUFFER" != *...* && "$LBUFFER" == *.. ]] && {
        local -a words
        words=("${(@Q)${(z)LBUFFER}}")
        # `...` is a wildcard operator in go
        [[ ${${(@)words[1,-2]}[(I)go]} = 0 ]] &&
        [[ $words[-1] == (|*[/=]|[\<\>=]\().. ]]
    }
    then
        [[ "$LASTWIDGET" == (self-insert|backward-delete-char) ]] &&
        zstyle -s ':manydots-magic' magic-count magic_count
        zstyle ':manydots-magic' magic-count $((magic_count+1))
        if [[ "$LBUFFER" == .. ]]; then
            LBUFFER="cd $LBUFFER/."
        else
            LBUFFER="$LBUFFER/."
        fi
        zle "$self_insert_function"
        return
    fi

    # cancel expansion if it does not seem right
    if [[ "$KEYS" != [=/,:\;\|\&\<\>\(\)\[\]{}^~\'\"\`[:space:]]* &&
        "$LASTWIDGET" == (self-insert|backward-delete-char) && "$LBUFFER" == *../.. ]] && {
        zstyle -s ':manydots-magic' magic-count magic_count
        [[ "$magic_count" -gt 0 ]]
    }
    then
        repeat $magic_count LBUFFER="${LBUFFER%/..}"
        repeat $magic_count LBUFFER="$LBUFFER."
        [[ "$LBUFFER" == "cd "..* ]] && LBUFFER="${LBUFFER#cd }"
    fi

    zstyle ':manydots-magic' magic-count 0

    zle "$self_insert_function"
}

manydots-magic.backward-delete-char() {
    emulate -L zsh
    local backward_delete_char_function
    zstyle -s ':manydots-magic' backward-delete-char-function backward_delete_char_function

    if [[ "$LASTWIDGET" == (self-insert|backward-delete-char) && "$LBUFFER" == *../.. ]] && {
        local magic_count
        zstyle -s ':manydots-magic' magic-count magic_count
        [[ "$magic_count" -gt 0 ]]
    }
    then
        zstyle ':manydots-magic' magic-count $((magic_count-1))
        LBUFFER="${LBUFFER%..}"
    else
        zstyle ':manydots-magic' magic-count 0
    fi

    zle "$backward_delete_char_function"
}

manydots-magic.rewrite-buffer() {
    emulate -L zsh
    local -a words
    local path

    [[ -n "$BUFFER" && "$BUFFER" != [[:space:]]* && "$BUFFER" != *[[:space:]] ]] ||
        return 0

    words=("${(@Q)${(z)BUFFER}}")
    (( ${#words} == 1 )) || return 0

    path="$words[1]"

    if [[ "$path" == .. ]]; then
        BUFFER='cd ..'
    elif [[ -d "$path" ]]; then
        BUFFER="cd -- $BUFFER"
    fi
}

manydots-magic.accept-line() {
    emulate -L zsh
    local accept_line_function
    zstyle -s ':manydots-magic' accept-line-function accept_line_function

    manydots-magic.rewrite-buffer
    zle "$accept_line_function"
}

manydots-magic.on() {
    emulate -L zsh
    local self_insert_function="${$(zle -lL | awk \
        '$1=="zle"&&$2=="-N"&&$3=="self-insert"{print $4;exit}'):-.self-insert}"

    [[ "$self_insert_function" == manydots-magic.self-insert ]] &&
        return 0

    # For url-quote-magic which does not zle -N itself
    zle -la "$self_insert_function" || zle -N "$self_insert_function"

    zstyle ':manydots-magic' self-insert-function "$self_insert_function"

    zle -A manydots-magic.self-insert self-insert

    local backward_delete_char_function="$(zle -lL | awk \
        '$1=="zle"&&$2=="-N"&&$3=="backward-delete-char"{print $4;exit}')"

    if [[ -n "$backward_delete_char_function" ]]
    then
        zle -la "$backward_delete_char_function" || zle -N "$backward_delete_char_function"
    else
        zle -A backward-delete-char manydots-magic.orig.backward-delete-char
        backward_delete_char_function=manydots-magic.orig.backward-delete-char
    fi

    zstyle ':manydots-magic' backward-delete-char-function "$backward_delete_char_function"

    zle -A manydots-magic.backward-delete-char backward-delete-char

    local accept_line_function="$(zle -lL | awk \
        '$1=="zle"&&$2=="-N"&&$3=="accept-line"{print $4;exit}')"

    if [[ -n "$accept_line_function" ]]
    then
        zle -la "$accept_line_function" || zle -N "$accept_line_function"
    else
        zle -A accept-line manydots-magic.orig.accept-line
        accept_line_function=manydots-magic.orig.accept-line
    fi

    zstyle ':manydots-magic' accept-line-function "$accept_line_function"

    zle -A manydots-magic.accept-line accept-line

    zstyle ':manydots-magic' magic-count 0

    return 0
}

manydots-magic.off() {
    emulate -L zsh
    local self_insert_function backward_delete_char_function accept_line_function
    zstyle -s ':manydots-magic' self-insert-function self_insert_function

    [[ -n "$self_insert_function" ]] &&
        zle -A "$self_insert_function" self-insert

    zstyle -s ':manydots-magic' backward-delete-char-function backward_delete_char_function

    [[ -n "$backward_delete_char_function" ]] &&
        zle -A "$backward_delete_char_function" backward-delete-char

    zstyle -s ':manydots-magic' accept-line-function accept_line_function

    [[ -n "$accept_line_function" ]] &&
        zle -A "$accept_line_function" accept-line

    zstyle ':manydots-magic' magic-count 0

    return 0
}

zle -N manydots-magic.self-insert
zle -N manydots-magic.backward-delete-char
zle -N manydots-magic.accept-line
zle -N manydots-magic.on
zle -N manydots-magic.off

manydots-magic() {
    manydots-magic.on
}

[[ -o kshautoload ]] || manydots-magic "$@"
