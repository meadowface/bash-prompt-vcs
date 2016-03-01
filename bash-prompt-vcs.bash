# bash-prompt-vcs.bash - Library that exposes bpvcs_bash_prompt() for
#                        showing version control state in the bash prompt.
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
BPVCS_GIT_COLOR="\033[0;32m"            # git defaults to green
BPVCS_HG_COLOR="\033[0;36m"             # hg defaults to cyan
BPVCS_SVN_COLOR="\033[0;35m"            # svn defaults to purple
BPVCS_COLORS=1                          # unset to turn off color

bpvcs_bash_prompt() {
    local vcs               # name of VCS
    local -i changed        # count of items that need to be committed
    local -i untracked      # count of items not in version control
    local -i staged         # count of items staged for commit
    local branch            # name of current branch or "" if not gathered

    # *_state functions are called to gather state from each VCS.
    # Each function must return 1 on error and 0 on success, with success
    # also setting appropriate values for the variables above.
    _reset_state() {
        vcs=""
        changed=0
        untracked=0
        staged=0
        branch=""
    }

    _git_state() {
        _reset_state

        local line
        while IFS= read -r line ; do
            if [[ "${line:0:2}" = "xx" ]]; then
                return 1
            fi

            if [[ "${line:2:1}" != " " ]]; then
                return 1;
            fi

            # https://git-scm.com/docs/git-status
            local x=${line:0:1}
            local y=${line:1:1}

            if [[ "${x}${y}" = "??" ]]; then
                ((untracked++))
            elif [[ "${x}${y}" = "##" ]]; then
                branch=${line:3}
            elif [[ "${y}" = "M" ]]; then
                ((changed++))
            else
                ((staged++))
            fi
            #NOTE: -z would complicate parsing dramatically because of renames
            #      and it's not worth it since git escapes pretty well.
        done < <(git status --porcelain --branch 2>/dev/null || echo -e "xx $?")

        vcs="git"
        return 0
    }

    _hg_state() {
        _reset_state

        local line
        while IFS= read -r line ; do
            if [[ "${line:0:2}" = "xx" ]]; then
                return 1
            fi

            #Note: Commit message is indented so it won't ever match a field.

            local field="${line%%: *}"   # remove everything after first ': '
            local value="${line#*: }"    # remove everything before first ': '
            if [[ "${field}" = "branch" ]]; then
                branch="${value}"
            elif [[ "${field}" = "commit" ]]; then
                # commit: 1 modified, 1 added, 2 unknown (info)
                # +----+  +-----------------------------------+ field value
                #         +--------+ +------+ +---------------+ chunks
                #         + +------+  + +---+  + +-----+ +----+ parts
                local chunks chunk
                IFS="," read -r -a chunks <<< "${value}"
                for chunk in "${chunks[@]}"; do
                    local parts count kind
                    IFS=" " read -r -a parts <<< "${chunk}"
                    count="${parts[0]:-0}"
                    kind="${parts[1]:-""}"
                    case "${kind}" in
                        modified|added|renamed) ((changed += count)) ;;
                        unknown)  ((untracked += count)) ;;
                    esac
                done
            fi
        done < <(hg summary 2>/dev/null || echo -e "xx: $?")

        # branch: should *always* be present, if not assume bad output
        if [[ -z "${branch}" ]]; then
            return 1
        fi

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

            case "${line:0:1}" in
                A|M|R) ((changed++)) ;;
                \?)    ((untracked++)) ;;
                " ")   if [[ "${line:1:1}" = "M" ]]; then ((changed++)); fi ;;
                # The following are all valid but ignored.
                # Prase them to be able to detect bad output in the *) case.
                C|D|I|X|!|~) ;;
                *) return 1 ;;
            esac
        #svn status doesn't return anything but 0, but keep the mechanism in place
        done < <(svn status --depth immediates 2>&1 || echo -e "xx: $?")

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

    #TODO: have an errors flag too incase vc returns something unparsable.
    local vcstate=""
    (( untracked )) && vcstate+="${BPVCS_UNTRACKED_INDICATOR}${untracked}"
    (( changed ))   && vcstate+="${BPVCS_CHANGED_INDICATOR}${changed}"
    (( staged ))    && vcstate+="${BPVCS_STAGED_INDICATOR}${staged}"
    if [[ -z "${vcstate}" ]]; then
        vcstate="${BPVCS_CLEAN_INDICATOR}"
    fi

    local prefix
    case "${vcs}" in
        git)  prefix="${BPVCS_GIT_COLOR} "; vcstate="(${branch}|${vcstate})" ;;
        hg)   prefix="${BPVCS_HG_COLOR} ";  vcstate="(${branch}|${vcstate})" ;;
        svn)  prefix="${BPVCS_SVN_COLOR} "; vcstate="(${vcstate})" ;;
        *)    return ;;
    esac
    local suffix="\033[0m"      # reset colors

    if [[ -z "${BPVCS_COLORS:-}" ]]; then
        prefix=" ${vcs}:"
        suffix=""
    fi

    echo -e "${prefix}${vcstate}${suffix}"
}
