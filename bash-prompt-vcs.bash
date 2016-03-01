function bpvcs_git_state() {
    vcs=""
    changed=0
    untracked=0
    staged=0
    branch=""
    local line
    while IFS= read -r line ; do
        if [ "${line:0:2}" = "xx" ]; then
            return 0
        fi

        if [ "${line:2:1}" != " " ]; then
            return 0;
        fi

        # https://git-scm.com/docs/git-status
        local x=${line:0:1}
        local y=${line:1:1}

        if [ "$x$y" = "??" ]; then
            ((untracked++))
        elif [ "$x$y" = "##" ]; then
            branch=${line:3}
        elif [ "$y" = "M" ]; then
            ((changed++))
        else
            ((staged++))
        fi
        #NOTE: -z would complicate parsing dramatically because of renames
        #      and it's not worth it since git escapes pretty well.
    done < <(git status --porcelain --branch 2>/dev/null || echo -e "xx $?")

    vcs="git"
    return 1
}

function bpvcs_hg_state() {
    vcs=""
    changed=0
    untracked=0
    staged=0
    branch=""
    local line
    while IFS= read -r line ; do
        if [ "${line:0:2}" = "xx" ]; then
            return 0
        fi

        # commit messages start with " " so it won't ever match a field.
        local field="${line/:*/}"
        if [ "$field" = "branch" ]; then
            branch="${line/*: /}"
        elif [ "$field" = "commit" ]; then
            local item
            while IFS= read -r -d ',' item; do
                item="${item## }"
                item="${item% (clean)}"
                local count="${item/ */}"
                local kind="${item/* /}"
                case $kind in
                    modified|added) ((changed += count)) ;;
                    unknown)  ((untracked += count)) ;;
                esac
            done  <<< "${line/*?: /},"  #NOTE: need the trailing comma for read
        fi
    done < <(hg summary 2>/dev/null || echo -e "xx: $?")

    vcs="hg"
    return 1
}

function bpvcs_svn_state() {
    vcs=""
    changed=0
    untracked=0
    staged=0
    branch=""
    local line
    while IFS= read -r line ; do
        if [ "${line:0:22}" = "svn: warning: W155007:" ]; then
            return 0
        fi

        case "${line:0:1}" in
            A|M|R) ((changed++)) ;;
            \?)    ((untracked++)) ;;
        esac
    #svn status doesn't return anything but 0, but keep the mechanism in place
    done < <(svn status --depth immediates 2>&1 || echo -e "xx: $?")

    vcs="svn"
    return 1
}

function bpvcs_bash_prompt() {
    bpvcs_git_state && bpvcs_hg_state && bpvcs_svn_state

    #TODO: have an errors flag too incase vc returns something unparsable.
    vcstate=""
    (( untracked )) && vcstate="$vcstate…$untracked"
    (( changed ))   && vcstate="$vcstate△$changed"
    (( staged ))    && vcstate="$vcstate●$staged"
    if [ -z $vcstate ]; then
        vcstate="✔"
    fi

    case "$vcs" in
        git)  color="\033[0;32m "; vcstate="($branch|$vcstate)" ;;
        hg)   color="\033[0;36m "; vcstate="($branch|$vcstate)" ;;
        svn)  color="\033[0;35m "; vcstate="($vcstate)" ;;
        *)    color=''; vcstate=''; return ;;
    esac
    resetcolor="\033[0m"

    if [ -z "$color_vcs_bash_prompt" ]; then
        color=" $vcs:"
        resetcolor=""
    fi

    echo -e "${color}${vcstate}${resetcolor}"
}

function install_vcs_bash_prompt() {
    local cmd="vcs_bash_prompt"
    IFS=';' read -r -a cmds <<< "$PROMPT_COMMAND"
    found=0
    for ((i=0; i < ${#cmds[@]}; ++i)); do
        if [ "${cmds[$i]}" = "$cmd" ]; then
            found=1
        fi
    done

    if [ "$found" -eq 0 ]; then
        PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}$cmd"
    fi
}

color_vcs_bash_prompt=1
#install_vcs_bash_prompt

PS1="\[\e]0;\u@\h: \w\a\]${debian_chroot:+($debian_chroot)}\u@\h:\w\$(vcs_bash_prompt)\$ "
