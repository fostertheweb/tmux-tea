#!/usr/bin/env bash

fzf_tmux_options=${FZF_TMUX_OPTS:-"-p 60%"}
home_replacer="s|^${HOME}/|~/|"

preview_position_option=$(tmux show-option -gqv "@tea-preview-position")
preview_position=${preview_position_option:-"right"}

layout_option=$(tmux show-option -gqv "@tea-layout")
layout=${layout_option:-"reverse"}

session_preview_cmd="tmux capture-pane -ep -t"
dir_preview_cmd="eza --oneline --icons --git --git-ignore --no-user --color=always --color-scale=all --color-scale-mode=gradient"
preview="$session_preview_cmd {} 2&>/dev/null || eval $dir_preview_cmd {}"

prompt=' : '
marker='*'
border_label=' Session Picker '
header="C-f   C-j   C-s   C-w "

t_bind="ctrl-t:abort"
tab_bind="tab:down,btab:up"
find_bind="ctrl-f:change-prompt( : )+reload(fd -H -t d -d 4 '.git' $HOME/Developer --exec dirname | sed -e \"$home_replacer\")+change-preview(eval $dir_preview_cmd {})"
session_bind="ctrl-s:change-prompt( : )+reload(tmux list-sessions -F '#S')"
zoxide_bind="ctrl-j:change-prompt( : )+reload(zoxide query -l | sed -e \"$home_replacer\")+change-preview(eval $dir_preview_cmd {})"
window_bind="ctrl-w:change-prompt( : )+reload(tmux list-windows -a -F '#{session_name}:#{window_index}')+change-preview($session_preview_cmd {})"

# determine if the tmux server is running
tmux_running=1
tmux list-sessions &>/dev/null && tmux_running=0

# determine the user's current position relative tmux:
run_type="serverless"
[[ "$tmux_running" -eq 0 ]] && run_type=$([[ "$TMUX" ]] && echo "attached" || echo "detached")

get_sessions_by_last_used() {
    tmux list-sessions -F '#{session_last_attached} #{session_name}' |
        sort --numeric-sort --reverse | awk '{print $2}' | grep -v -E "^$(tmux display-message -p '#S')$"
}

get_zoxide_results() {
    zoxide query -l | sed -e "$home_replacer"
}

get_fzf_results() {
    if [[ "$tmux_running" -eq 0 ]]; then
        sessions=$(get_sessions_by_last_used)
        [[ "$sessions" ]] && echo "$sessions" && get_zoxide_results || get_zoxide_results
    else
        get_zoxide_results
    fi
}

# if started with single argument
if [[ $# -eq 1 ]]; then
    if [[ -d "$1" ]]; then
        result=$1
    else
        zoxide query "$1" &>/dev/null
        zoxide_result_exit_code=$?
        if [[ $zoxide_result_exit_code -eq 0 ]]; then
            result=$(zoxide query "$1")
        else
            echo "No directory found."
            exit 1
        fi
    fi
else
    case $run_type in
    attached)
        result=$(get_fzf_results | fzf-tmux \
            --bind "$session_bind" --bind "$tab_bind" --bind "$window_bind" --bind "$t_bind" \
            --bind "$zoxide_bind" --bind "$find_bind" --border-label "$border_label" --header "$header" \
            --no-sort --prompt "$prompt" --marker "$marker" --preview "$preview" \
            --preview-window="$preview_position",60% "$fzf_tmux_options" --layout="$layout")
        ;;
    detached)
        result=$(get_fzf_results | fzf \
            --bind "$session_bind" --bind "$tab_bind" --bind "$window_bind" --bind "$t_bind" \
            --bind "$zoxide_bind" --bind "$find_bind" --border-label "$border_label" --header "$header" \
            --no-sort --prompt "$prompt" --marker "$marker" --preview "$preview" \
            --preview-window=top,60%)
        ;;
    serverless)
        result=$(get_fzf_results | fzf \
            --bind "$tab_bind" --bind "$zoxide_bind" --bind "$find_bind" --bind "$t_bind" \
            --border-label "$border_label" --header "$header" --no-sort --prompt "$prompt" --marker "$marker" \
            --preview "$dir_preview_cmd {}")
        ;;
    esac
fi

[[ "$result" ]] || exit 0

[[ $home_replacer ]] && result=$(echo "$result" | sed -e "s|^~/|$HOME/|")

zoxide add "$result" &>/dev/null

if [[ $result != /* ]]; then # not a dir path
    session_name=$result
else
    session_name_option=$(tmux show-option -gqv "@tea-session-name")
    if [[ "$session_name_option" = "full-path" ]]; then
        session_name="${result/$HOME/\~}"
    else
        session_name=$(basename "$result")
    fi
    session_name=$(echo "$session_name" | tr ' .:' '_')
fi

if [[ "$run_type" = "serverless" ]] || ! tmux has-session -t="$session_name" &>/dev/null; then
    if [[ -e "$result"/.tmuxinator.yml ]] && command -v tmuxinator &>/dev/null; then
        cd "$result" && tmuxinator local
    elif [[ -e "$HOME/.config/tmuxinator/$session_name.yml" ]] && command -v tmuxinator &>/dev/null; then
        tmuxinator "$session_name"
    else
        default_cmd=$(tmux show-option -gqv "@tea-default-command")
        if [[ -n "$default_cmd" ]]; then
            tmux new-session -d -s "$session_name" -c "$result" "$default_cmd"
        else
            tmux new-session -d -s "$session_name" -c "$result"
        fi
    fi
fi

case $run_type in
attached) tmux switch-client -t "$session_name" ;;
detached | serverless) tmux attach -t "$session_name" ;;
esac
