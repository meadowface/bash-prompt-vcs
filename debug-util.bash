#!/usr/bin/env bash
# Bash debugging helpers.
#
# WARNING: These functions are tested to work within this project, and are
#          pretty robust, but they don't have dedicated tests of their own
#          yet.
#
#
# Copyright (c) 2016 Marc Meadows
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.
#

# Dump the call stack that bash keeps in various variables to stdout doing
# no interpretation of it.
dump_callstack() {
    local -i i

    for ((i=0 ; i < ${#BASH_SOURCE[@]} ; i++)); do
        printf "[%d] %s:%d %s\n" \
               $i \
               "${BASH_SOURCE[$i]}" \
               "${BASH_LINENO[$i]}" \
               "${FUNCNAME[$i]}"
    done
}

# Needed so code-extraction works even when the script is in a different
# directory.  Used in traceback().
readonly _traceback_source_dir=$(pwd)

# Print a python-style traceback to stdout.  Uses bash's call stack variables
# and extracts source lines using sed.
#
# Accepts two parameters:
#   $1 - Top frame to show.  Set to 1 to skip the frame that represents the
#        traceback() call itself.  Set higher if the ERR trap calls multiple
#        levels of functions to get to traceback().
#   $2 - Whether to embed the frame number in the traceback output.
#        Any non-empty string will be interpreted as True.
#
# Intended to be called from an ERR trap:
#   traceback 1 >&2
traceback() {
    # The top of the stack is the most recent call and frame 0.
    local traceback_show_frame=${2:-}
    local -i top_frame=${1:-0}
    local -i bottom_frame=$((${#FUNCNAME[@]} - 2))

    # Start with the bottom of the stack and walk back up, printing each frame.
    # Using FUNCNAME, BASH_SOURCE, and BASH_LINENO arrays because parsing
    # the output of the caller builtin is more trouble than it's worth when
    # there can be spaces in filenames.
    printf "\nTraceback (most recent call last):\n"
    for ((frame=bottom_frame ; frame >= top_frame ; frame--)); do
        local calling_frame=$((frame + 1))
        local called_from="${FUNCNAME[${calling_frame}]}()"
        local source_file="${BASH_SOURCE[${calling_frame}]}"
        local source_linenum="${BASH_LINENO[${frame}]}"
        local source_line

        # Extract the source line, stripping out any leading whitespace.
        source_line=$(sed -n "s/^\s*//;${source_linenum}p;" \
                             "${_traceback_source_dir}/${source_file}")

        # Need to special-case the module frame as FUNCNAME reports it as
        # 'main', which is confusing if you also have a function named main.
        if [[ "${BASH_LINENO[${calling_frame}]}" -eq 0 ]]; then
            called_from="<module>"
        fi

        if [[ -n "${traceback_show_frame}" ]]; then
            printf "  [%d] " "${frame}"
        else
            printf "  " "${frame}"
        fi

        printf "File \"%s\", line %s, in %s\n    %s\n" \
               "${source_file}" \
               "${source_linenum}" \
               "${called_from}" \
               "${source_line}"
    done
}
