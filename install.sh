#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then
  echo "Running in dry run mode. No actual changes will be made."
  DRY_RUN=1
fi

# run_command: receives a single string command
run_command() {
  local cmd="$*"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[DRY RUN] $cmd"
  else
    echo "+ $cmd"
    eval "$cmd"
  fi
}

error_exit() {
  echo "ERROR: $1" >&2
  exit 1
}

trap 'error_exit "Script failed at line $LINENO"' ERR

package_manager=""

set_package_manager() {
  # /etc/os-release is expected to exist
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
  else
    error_exit "/etc/os-release not found"
  fi

  case "${ID:-}" in
    fedora)
      package_manager="dnf"
      ;;
    rhel|centos)
      package_manager="yum"
      ;;
    ubuntu|debian)
      package_manager="apt-get"
      ;;
    *)
      error_exit "(Maybe) your distro is not supported: ${ID:-unknown}"
      ;;
  esac
}

update_system() {
  echo "Updating system (using $package_manager)..."
  if [ "$package_manager" = "apt-get" ]; then
    run_command "sudo $package_manager update -qq"
    run_command "sudo $package_manager upgrade -qq -y"
    run_command "sudo $package_manager autoremove -qq -y || true"
  else
    run_command "sudo $package_manager upgrade -y"
    run_command "sudo $package_manager autoremove -y || true"
  fi
}

install_apps() {
  echo "Installing common software packages..."
  # --- ALTERAÇÃO AQUI ---
  # Adicionado 'unzip' à lista para garantir que 'install_fonts' funcione.
  local common_apps=(curl flatpak openssh-server zenity git vim neovim btop zsh shellcheck wget wine unzip)

  for app in "${common_apps[@]}"; do
    if ! command -v "$app" >/dev/null 2>&1; then
      run_command "sudo $package_manager install -y $app"
    else
      echo "$app is already installed."
    fi
  done
}

install_dev_tools() {
  echo "Installing Development Tools..."
  if [ "$package_manager" = "dnf" ] || [ "$package_manager" = "yum" ]; then
    # prefer groupinstall, fallback to @development-tools
    run_command "sudo $package_manager groupinstall -y 'Development Tools' || sudo $package_manager install -y @development-tools || true"

  elif [ "$package_manager" = "apt-get" ]; then
    run_command "sudo $package_manager install -y build-essential"
  else
    echo "(Maybe) your distro is not supported"
    exit 1
  fi
}

setup_java_and_nvm() {
  echo "Installing SDKMan and NVM (non-interactive)..."
  run_command "curl -s https://get.sdkman.io | bash"
  
  sleep 1
  
  run_command "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.4/install.sh | bash"
}

add_flathub() {
  if command -v flatpak >/dev/null 2>&1; then
    run_command "sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"
  else
    echo "flatpak not installed; skipping add_flathub"
  fi
}

flatpak_packages() {
  if command -v flatpak >/dev/null 2>&1; then
    echo "Installing Flatpak packages..."
    run_command "flatpak update --appstream -y || true"
    sleep 1
    run_command "flatpak install -y flathub \
      com.protonvpn.www \
      org.standardnotes.standardnotes \
      io.github.peazip.PeaZip \
      com.spotify.Client \
      org.telegram.desktop \
      org.torproject.torbrowser-launcher \
      io.github.flattool.Warehouse \
      com.github.tchx84.Flatseal"
  else
    echo "flatpak not available; skipping flatpak_packages"
  fi
}

download_fonts() {
  run_command "mkdir -p \"$HOME/.local/share/fonts\""
  echo "Downloading JetBrains Mono Nerd Font..."
  run_command "wget -c https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip -P \"$HOME/.local/share/fonts/\""
  
  sleep 1
  
  echo "Downloading Noto Nerd Font..."
  run_command "wget -c https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/Noto.zip -P \"$HOME/.local/share/fonts/\""
}

install_fonts() {
  echo "Installing fonts..."
  run_command "unzip -q -o \"$HOME/.local/share/fonts/JetBrainsMono.zip\" -d \"$HOME/.local/share/fonts/\""
  run_command "unzip -q -o \"$HOME/.local/share/fonts/Noto.zip\" -d \"$HOME/.local/share/fonts/\""
  run_command "fc-cache -f -v || true"
}

install_zsh() {
  run_command "chsh -s $(which zsh)"
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "Installing Oh-My-Zsh (non-interactive)..."
    run_command "RUNZSH=no CHSH=no sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\""
  else
    echo "Oh-My-Zsh already installed."
  fi
}

set_ohmyzsh() {
  echo "Configuring Oh-My-Zsh (plugins/themes)..."
  run_command "mkdir -p \"$HOME/.oh-my-zsh/custom/plugins\" \"$HOME/.oh-my-zsh/completions\""
  run_command "git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git \"$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting\" || true"
  sleep 1
  run_command "git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \"$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions\" || true"
  sleep 1
  run_command "curl -sS https://starship.rs/install.sh | sh -s -- -y || true"

  # Backup existing .zshrc instead of removing
  run_command "mv \"$HOME/.zshrc\" \"$HOME/.zshrc.backup\" 2>/dev/null || true"
  run_command "wget -c https://raw.githubusercontent.com/emanoelhenrick/MESS/main/files/.zshrc -O \"$HOME/.zshrc\""
}

sysctl_set() {
  echo "Applying sysctl configuration..."
  run_command "sudo cp /etc/sysctl.conf /etc/sysctl.conf.backup 2>/dev/null || true"
  run_command "sudo curl -fsSL https://raw.githubusercontent.com/emanoelhenrick/MESS/main/files/sysctl.conf -o /etc/sysctl.conf"
  run_command "sudo sysctl -p || true"
}

create_dev_and_studies_folders() {
  echo "Creating Dev and Studies folders..."
  run_command "mkdir -p \"$HOME/Documents/dev\" \"$HOME/Documents/studies\""
}

configure_git() {
  echo "Configuring Git..."
  run_command "curl -fsS https://raw.githubusercontent.com/emanoelhenrick/MESS/main/files/.gitconfig -o \"$HOME/.gitconfig\" || true"
}

main() {
  echo "MANEL'S ENVIRONMENT SETUP SCRIPT"
  echo "Initializing the environment setup..."

  set_package_manager
  update_system
  install_apps
  install_dev_tools
  setup_java_and_nvm
  add_flathub
  flatpak_packages
  download_fonts
  install_fonts
  install_zsh
  set_ohmyzsh
  sysctl_set
  create_dev_and_studies_folders
  configure_git

  echo "The environment was successfully configured. See $LOGFILE for details."
}

main "$@"
