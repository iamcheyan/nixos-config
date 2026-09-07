#!/usr/bin/env bash
# =======================================================================
# macOS 极速零动画 (Zero Animation) 系统调优脚本
# 彻底关闭系统各层级的窗口缩放、淡入淡出、Dock延迟与预览过渡动画
# =======================================================================

set -euo pipefail

if [[ "$(uname)" != "Darwin" ]]; then
    echo "This script is only applicable to macOS (Darwin)."
    exit 0
fi

echo ">> 正在应用 macOS 极速零动画系统设置..."

# 1. 消除窗口尺寸变化、缩放与对齐动画 (解决窗口切换微小缩放感)
defaults write -g NSWindowResizeTime -float 0.001

# 2. 禁用所有窗口打开/关闭时的缩放淡入淡出
defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false

# 3. 禁用 Finder 的所有动画
defaults write com.apple.finder DisableAllAnimations -bool true

# 4. 禁用快速预览 (QuickLook) 窗口淡入动画
defaults write -g QLPanelAnimationDuration -float 0

# 5. 消除 Dock 栏弹出和隐藏的所有过渡延迟与动画
defaults write com.apple.dock autohide-time-modifier -float 0
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock expose-animation-duration -float 0.001
defaults write com.apple.dock springboard-show-duration -float 0.001
defaults write com.apple.dock springboard-hide-duration -float 0.001
defaults write com.apple.dock springboard-page-duration -float 0.001
defaults write com.apple.dock launchanim -bool false

# 6. 隐藏菜单栏无用的 Spotlight 放大镜搜索图标 (节省顶部空间)
defaults write com.apple.controlcenter "NSStatusItem Visible Spotlight" -bool false
defaults write com.apple.controlcenter "Spotlight" -int 8
defaults -currentHost write com.apple.Spotlight MenuItemHidden -int 1

# 7. 重载 Dock、Finder 与 ControlCenter 使设置立即生效
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true
killall ControlCenter 2>/dev/null || true

echo "✓ macOS 极速零动画系统设置已全部生效！"
