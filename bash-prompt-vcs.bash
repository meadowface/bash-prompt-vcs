# bash-prompt-vcs.bash - Library that exposes bpvcs_bash_prompt() for
#                        showing version control state in the bash prompt.
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
# Usage:
#     In .bashrc do the following:
#         . bash-prompt-vcs.bash
#         PS1="\u@\h:\w\$(bpvcs_bash_prompt)\$ "
#                      ^^^^^^^^^^^^^^^^^^^^^
#     NOTE: The backslash before the $ is required.

# You can set these in .bashrc any time after sourcing this file to control
# the display of the prompt.
BPVCS_UNTRACKED_INDICATOR="…"           # items not in version control
BPVCS_CHANGED_INDICATOR="△"             # items that need to be committed
BPVCS_STAGED_INDICATOR="●"              # items that are staged for commit
BPVCS_CLEAN_INDICATOR="✔"               # used when cwd has none of the above
BPVCS_AHEAD_INDICATOR="⇡"               # used when local is ahead of remote
BPVCS_BEHIND_INDICATOR="⇣"              # used when remote is ahead of local
BPVCS_GIT_COLOR="\033[0;32m"            # git defaults to green
BPVCS_HG_COLOR="\033[0;36m"             # hg defaults to cyan
BPVCS_SVN_COLOR="\033[0;35m"            # svn defaults to purple
BPVCS_ERR_COLOR="\033[0;31m"            # error defaults to red
BPVCS_RESET_COLOR="\033[0m"             # reset
BPVCS_COLORS=1                          # unset to turn off color

declare -g -r BPVCS_VERSION="1.0.0"

bpvcs_bash_prompt() {
    local vcs               # name of VCS
    local -i changed        # count of items that need to be committed
    local -i untracked      # count of items not in version control
    local -i staged         # count of items staged for commit
    local branch            # name of current branch or "" if not gathered
    local error             # if set, show error to user

    # *_state functions are called to gather state from each VCS.
    # Each function must return 1 if it's not a sandbox, 0 if it is.
    # Must also setting appropriate values for the variables above.
    # If it's a sandbox but there's an error, error must be set.
    _reset_state() {
        vcs=""
        changed=0
        untracked=0
        staged=0
        branch=""
        error=""
    }

    _git_state() {
        _reset_state

        local line
        while IFS= read -r line ; do
            if [[ "${line:0:2}" = "xx" ]]; then
                return 1
            fi

            if [[ "${line:2:1}" != " " ]]; then
                error="unexpected git status output"
                return 0;
            fi

            # https://git-scm.com/docs/git-status
            local x=${line:0:1}
            local y=${line:1:1}

            if [[ "${x}${y}" = "??" ]]; then
                ((untracked++))
            elif [[ "${x}${y}" = "##" ]]; then
                branch=${line:3}

                # Decorate branch name with a remote branch status indicator.
                # Rendered in wt_shortstatus_print_tracking()
                # in https://github.com/git/git/blob/master/wt-status.c
                # Branch names won't contain '...'
                # (https://git-scm.com/docs/git-check-ref-format)
                local remote="${branch#*...}"  # grab everything after ...
                branch="${branch%%...*}"       # grab everything before ...
                if [[ $remote =~ .*\[.*ahead.*\] ]]; then
                    branch="${branch}${BPVCS_AHEAD_INDICATOR}"
                fi
                if [[ $remote =~ .*\[.*behind.*\] ]]; then
                    branch="${branch}${BPVCS_BEHIND_INDICATOR}"
                fi
            elif [[ "${y}" = "M" ]]; then
                ((changed++))
            else
                ((staged++))
            fi
            #NOTE: -z would complicate parsing dramatically because of renames
            #      and it's not worth it since git escapes pretty well.
            # Set locale so things like ahead/behind are in English and match the above.
        done < <(LC_ALL=C git status --porcelain --branch 2>/dev/null || echo -e "xx $?")

        vcs="git"
        return 0
    }

    _hg_state() {
        _reset_state

        local line
        local commit=""
        while IFS= read -r line ; do
            if [[ "${line:0:2}" = "xx" ]]; then
                return 1
            fi

            local field="${line%%: *}"   # remove everything after first ': '
            local value="${line#*: }"    # remove everything before first ': '
            if [[ "${field}" = "branch" ]]; then
                branch="${value}"
            elif [[ "${field}" = "commit" ]]; then
                commit="${value}"
            fi
            #Note: Commit message is indented so it won't ever match a field.
        done < <(hg summary 2>/dev/null || echo -e "xx: $?")


        # both should *always* be present, if not assume bad output
        if [[ -z "${branch}" || -z "${commit}" ]]; then
            error="unexpected hg summary output"
            return 0
        fi

        # commit: 1 modified, 1 added, 2 unknown (info)
        # +----+  +-----------------------------------+ field value
        #         +--------+ +------+ +---------------+ chunks
        #         + +------+  + +---+  + +-----+ +----+ parts
        local chunks chunk
        IFS="," read -r -a chunks <<< "${commit}"
        for chunk in "${chunks[@]}"; do
            local parts count kind
            IFS=" " read -r -a parts <<< "${chunk}"
            count="${parts[0]:-0}"
            kind="${parts[1]:-""}"
            case "${kind}" in
                modified|added|renamed|removed) ((changed += count)) ;;
                unknown|deleted)  ((untracked += count)) ;;
            esac
        done

        vcs="hg"
        return 0
    }

    _svn_state() {
        _reset_state

        local line
        while IFS= read -r line ; do
            # Not an svn sandbox.
            if [[ "${line:0:22}" = "svn: warning: W155007:" ]]; then
                return 1
            fi

            # svn upgrade needed
            if [[ "${line:0:13}" = "svn: E155036:" ]]; then
                error="'svn upgrade' needed"
                return 0
            fi

            case "${line:0:1}" in
                A|M|R|D) ((changed++)) ;;
                \?|!)    ((untracked++)) ;;
                " ")   if [[ "${line:1:1}" = "M" ]]; then ((changed++)); fi ;;
                # The following are all valid but ignored.
                # Parse them to be able to detect bad output in the *) case.
                C|I|X|~) ;;
                *) error="unexpected svn status output"; return 0 ;;
            esac
        # svn status returns 0 even if not a sandbox so parse error messages
        done < <(svn status --depth immediates 2>&1)

        vcs="svn"
        return 0
    }

    # Get vcs state, checking them all in order, first one wins.
    _git_state || _hg_state || _svn_state || true

    # Functions are always global, so unset these so they don't leak.
    unset _reset_state
    unset _git_state
    unset _hg_state
    unset _svn_state

    local vcstate prefix suffix
    if [[ -n "${error}" ]]; then
        vcs="ERR"
        vcstate="(${error})"
        prefix="${BPVCS_ERR_COLOR}"
    else
        vcstate=""
        (( untracked )) && vcstate+="${BPVCS_UNTRACKED_INDICATOR}${untracked}"
        (( changed ))   && vcstate+="${BPVCS_CHANGED_INDICATOR}${changed}"
        (( staged ))    && vcstate+="${BPVCS_STAGED_INDICATOR}${staged}"
        if [[ -z "${vcstate}" ]]; then
            vcstate="${BPVCS_CLEAN_INDICATOR}"
        fi

        case "${vcs}" in
            git)  prefix="${BPVCS_GIT_COLOR}"; vcstate="(${branch}|${vcstate})" ;;
            hg)   prefix="${BPVCS_HG_COLOR}";  vcstate="(${branch}|${vcstate})" ;;
            svn)  prefix="${BPVCS_SVN_COLOR}"; vcstate="(${vcstate})" ;;
            *)    return ;;
        esac
    fi

    # Wrap the prefix in the chars that tell bash/readline that those
    # are non-printing characters, also add a space to make it look nice.
    prefix="\x01${prefix}\x02 "

    if [[ -n "${BPVCS_COLORS:-}" ]]; then
        # Reset colors to normal with the suffix, again wrapping with chars
        # to indicate non-printing characters to bash/readline.
        suffix="\x01${BPVCS_RESET_COLOR}\x02"
    else
        prefix=" ${vcs}:"     # explicitly show vcs for monochrome
        suffix=""
    fi

    echo -e "${prefix}${vcstate}${suffix}"
}
