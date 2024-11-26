#!/bin/bash

# Detect shell configuration file
if [[ $SHELL == *"zsh"* ]]; then
    CONFIG_FILE="$HOME/.zshrc"
elif [[ $SHELL == *"bash"* ]]; then
    CONFIG_FILE="$HOME/.bashrc"
else
    echo "unsupported shell - failed these aliases manually to your shell config file."
    exit 1
fi

# Aliases to add
ALIASES=$(cat << 'EOF'
# Git shortcuts
alias g='git'
alias gst='git status'
alias gcm='git commit -m'
alias gco='git checkout'
alias gb='git branch'
alias gd='git diff'
alias gpl='git pull'
alias gps='git push'
alias gra='git remote add'

# Python shortcuts
alias p='poetry'
alias p-r='poetry run'
alias p-i='poetry install'
alias p-a='poetry add'
alias py='python'
alias pip='python -m pip'
alias pipr='python -m pip install -r requirements.txt'
alias pyt='pytest'
alias jnb='jupyter notebook'

# Elixir shortcuts
alias mx='mix'
alias mxc='mix compile'
alias mxt='mix test'
alias iex='iex -S mix'
alias mxd='mix deps.get'
alias mxb='mix build'

# JavaScript/Node.js shortcuts
alias npmr='npm run'
alias npmi='npm install'
alias npms='npm start'
alias npmt='npm test'
alias yarnr='yarn run'
alias yarni='yarn install'
alias nod='node'
alias npmb='npm build'

# Shell productivity
alias cls='clear'
alias ll='ls -alh'
alias ..='cd ..'
alias c='cd'
alias v='vim'
alias t='tmux'
alias k='kubectl'

EOF
)

# Add aliases to shell configuration file
echo -e "\n# Custom Aliases\n$ALIASES" >> "$CONFIG_FILE"

# Apply the changes
if [[ $SHELL == *"zsh"* ]]; then
    source "$HOME/.zshrc"
elif [[ $SHELL == *"bash"* ]]; then
    source "$HOME/.bashrc"
fi

echo "Aliases have been added $CONFIG_FILE and applied"
