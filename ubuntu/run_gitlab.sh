#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
#  GitLab CLI (glab) 管理工具 (Ubuntu / Debian 版)
# ──────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

print_header() {
  echo ""
  echo -e "${CYAN}${BOLD}╔══════════════════════════════════════╗${RESET}"
  echo -e "${CYAN}${BOLD}║      GitLab CLI 管理工具 (Ubuntu)    ║${RESET}"
  echo -e "${CYAN}${BOLD}╚══════════════════════════════════════╝${RESET}"
  echo ""
}

check_apt() {
  if ! command -v apt &>/dev/null; then
    echo -e "${RED}✗ 未偵測到 apt，此腳本專為 Ubuntu / Debian 系統設計。${RESET}"
    exit 1
  fi
}

check_fzf() {
  if ! command -v fzf &>/dev/null; then
    echo -e "${YELLOW}⏳ 未偵測到 fzf，正在透過 apt 安裝...${RESET}"
    sudo apt update
    sudo apt install -y fzf
    echo -e "${GREEN}✓ fzf 安裝完成${RESET}"
  fi
}

install_glab() {
  echo -e "${BOLD}▶ 安裝 GitLab CLI (glab)${RESET}"
  if command -v glab &>/dev/null; then
    echo -e "${GREEN}✓ glab 已安裝，版本：$(glab --version | head -n1)${RESET}"
    echo -e "${YELLOW}🔄 確保版本是最新的，以支援 --device 瀏覽器驗證...${RESET}"
  fi

  if ! command -v curl &>/dev/null; then
    echo -e "${RED}✗ 找不到 curl，請先安裝 curl。${RESET}"
    return 1
  fi

  # packages.gitlab.com 的 apt 官方源在部分 arm 裝置 (如樹莓派) 上常抓不到
  # 真正的最新版，導致裝到的 glab 太舊而不支援 --device。改為直接抓官方
  # Release 頁面對應架構的 .deb 安裝，確保版本與 --device 支援一致。
  local deb_arch
  case "$(uname -m)" in
    x86_64) deb_arch="amd64" ;;
    aarch64|arm64) deb_arch="arm64" ;;
    armv6l|armv7l) deb_arch="armv6" ;;
    i386|i686) deb_arch="386" ;;
    *) echo -e "${RED}✗ 不支援的架構：$(uname -m)${RESET}"; return 1 ;;
  esac

  echo -e "${CYAN}⏳ 查詢 glab 最新版本...${RESET}"
  local latest_tag latest_version deb_url tmp_deb
  latest_tag=$(curl -sL https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/releases/permalink/latest \
    | grep -o '"tag_name":"[^"]*' | head -n1 | cut -d'"' -f4)
  latest_version="${latest_tag#v}"

  if [[ -z "$latest_version" ]]; then
    echo -e "${RED}✗ 無法取得最新版本號，請確認網路連線後再試一次。${RESET}"
    return 1
  fi

  deb_url="https://gitlab.com/gitlab-org/cli/-/releases/${latest_tag}/downloads/glab_${latest_version}_linux_${deb_arch}.deb"
  tmp_deb="$(mktemp --suffix=.deb)"
  echo -e "${CYAN}⏳ 下載 glab ${latest_tag} (${deb_arch})...${RESET}"
  if ! curl -sL --fail "$deb_url" -o "$tmp_deb"; then
    echo -e "${RED}✗ 下載失敗：${deb_url}${RESET}"
    rm -f "$tmp_deb"
    return 1
  fi
  sudo dpkg -i "$tmp_deb"
  rm -f "$tmp_deb"

  echo -e "${GREEN}✓ 安裝/更新完成：$(glab --version | head -n1)${RESET}"
}

login_glab() {
  echo -e "${BOLD}▶ 登入 GitLab 帳號 (--device 驗證)${RESET}"
  if ! command -v glab &>/dev/null; then
    echo -e "${RED}✗ glab 尚未安裝，請先執行 [1] 安裝${RESET}"
    return 1
  fi
  if glab auth status --hostname gitlab.com &>/dev/null; then
    echo -e "${YELLOW}⚠ 已偵測到登入狀態：${RESET}"
    glab auth status || true
    echo ""
    read -rp "是否要重新登入？(y/N): " confirm
    [[ "$(echo "$confirm" | tr '[:upper:]' '[:lower:]')" != "y" ]] && echo "取消。" && return 0
  fi
  
  echo -e "${CYAN}⏳ 開啟瀏覽器進行 GitLab 登入驗證 (Device Token 模式)...${RESET}"
  echo ""

  if glab auth login --help 2>&1 | grep -qw -- '--device'; then
    # 使用 --device 開啟 Device Token 驗證 (會顯示超連結與 Code)
    glab auth login --hostname gitlab.com --device --git-protocol https
  else
    echo -e "${YELLOW}⚠ 目前 glab 版本過舊，不支援 --device 瀏覽器驗證，請先執行 [1] 安裝以更新版本。${RESET}"
    echo -e "${YELLOW}   暫時改用互動式登入（需手動貼上 Personal Access Token）：${RESET}"
    glab auth login --hostname gitlab.com --git-protocol https
  fi

  echo ""
  if glab auth status --hostname gitlab.com &>/dev/null; then
    echo -e "${GREEN}✓ 登入完成：${RESET}"
    glab auth status || true
  else
    echo -e "${RED}✗ 登入失敗或已取消。${RESET}"
  fi
}

logout_glab() {
  echo -e "${BOLD}▶ 登出 GitLab 帳號${RESET}"
  if ! command -v glab &>/dev/null; then
    echo -e "${RED}✗ glab 尚未安裝${RESET}"
    return 1
  fi
  if ! glab auth status --hostname gitlab.com &>/dev/null; then
    echo -e "${YELLOW}⚠ 目前尚未登入任何 GitLab 帳號${RESET}"
    return 0
  fi
  echo -e "${YELLOW}目前登入狀態：${RESET}"
  glab auth status || true
  echo ""
  read -rp "確定要登出？(y/N): " confirm
  if [[ "$(echo "$confirm" | tr '[:upper:]' '[:lower:]')" == "y" ]]; then
    # glab 登出需指定 hostname，預設 gitlab.com
    local host
    host=$(glab auth status 2>&1 | grep "Logged in to" | awk '{print $5}' | head -n1)
    host="${host:-gitlab.com}"
    glab auth logout --hostname "$host"
    echo -e "${GREEN}✓ 已登出 ${host}${RESET}"
  else
    echo "取消。"
  fi
}

show_status() {
  echo -e "${BOLD}▶ 目前 GitLab CLI 狀態${RESET}"
  if ! command -v glab &>/dev/null; then
    echo -e "${RED}✗ glab 尚未安裝${RESET}"
    return 0
  fi
  echo -e "${GREEN}✓ glab 已安裝：$(glab --version | head -n1)${RESET}"
  if glab auth status --hostname gitlab.com &>/dev/null; then
    glab auth status || true
  else
    echo -e "${YELLOW}⚠ 尚未登入任何 GitLab 帳號${RESET}"
  fi
}

main_menu() {
  check_apt
  check_fzf

  local options=(
    "󰮤  安裝 GitLab CLI (glab)"
    "  登入 GitLab 帳號"
    "  登出 GitLab 帳號"
    "  查看目前登入狀態"
    "  離開"
  )

  local descriptions=(
    "透過 apt/snap 安裝或確認 glab 版本"
    "使用瀏覽器 Device Token 驗證登入 GitLab"
    "登出目前已登入的 GitLab 帳號"
    "顯示 glab 安裝版本與登入帳號資訊"
    "結束程式"
  )

  while true; do
    print_header

    # 建立帶 index 的選項清單供 fzf 讀取
    local fzf_input=""
    for i in "${!options[@]}"; do
      fzf_input+="${options[$i]}\n"
    done

    # 使用 fzf 選單，並以 preview 顯示說明
    local choice
    choice=$(printf '%b' "$fzf_input" | fzf \
      --ansi \
      --no-sort \
      --height=45% \
      --border=rounded \
      --prompt="  GitLab CLI ❯ " \
      --pointer="▶" \
      --color="fg:#cdd6f4,bg:#1e1e2e,hl:#89b4fa,fg+:#cdd6f4,bg+:#313244,hl+:#89b4fa,prompt:#cba6f7,pointer:#f38ba8,border:#6c7086,preview-bg:#181825,preview-fg:#a6adc8" \
      --preview='
        case "{}" in
          *安裝*) echo "📦 透過 apt 安裝 glab，已安裝則顯示版本" ;;
          *登入*) echo "🔑 使用瀏覽器 Device Token 驗證登入 GitLab 帳號" ;;
          *登出*) echo "🚪 登出目前已登入的 GitLab 帳號" ;;
          *查看*) echo "📋 顯示 glab 安裝版本與登入帳號資訊" ;;
          *離開*) echo "👋 結束程式" ;;
        esac
      ' \
      --preview-window="bottom:3:wrap" \
    ) || { echo -e "${CYAN}掰掰！${RESET}"; exit 0; }

    echo ""
    case "$choice" in
      *"安裝 GitLab CLI"*) install_glab ;;
      *"登入"*)            login_glab ;;
      *"登出"*)            logout_glab ;;
      *"查看"*)            show_status ;;
      *"離開"*)            echo -e "${CYAN}掰掰！${RESET}"; exit 0 ;;
    esac

    echo ""
    read -rp "按 Enter 返回主選單..."
  done
}

main_menu
