-- =======================================================================
-- Hammerspoon Configuration (Supplementary Helpers)
-- Managed by Chezmoi dotfiles (Private Orchestration Layer)
-- =======================================================================

require("hs.ipc")
local window = require("hs.window")
local hotkey = require("hs.hotkey")

-- 禁用窗口移动动画，实现即时响应
window.animationDuration = 0

-- -----------------------------------------------------------------------
-- Option(Alt) + F: 像素级记忆坐标与尺寸的 窗口最大化 / 还原
-- -----------------------------------------------------------------------
local savedFrames = {}

hotkey.bind({"alt"}, "f", function()
    local win = window.focusedWindow()
    if not win then return end
    local id = win:id()
    local scr = win:screen()
    if not scr then return end

    local maxF = scr:frame()
    local curF = win:frame()

    -- 容差判定当前窗口是否已处于最大化状态
    local isMaximized = (math.abs(curF.x - maxF.x) < 5 and
                         math.abs(curF.y - maxF.y) < 5 and
                         math.abs(curF.w - maxF.w) < 10 and
                         math.abs(curF.h - maxF.h) < 10)

    if isMaximized and savedFrames[id] then
        -- 还原回原本精确的坐标 (X, Y) 与尺寸 (W, H)
        win:setFrame(savedFrames[id])
        savedFrames[id] = nil
    else
        -- 记录当前浮动位置与大小，并铺满屏幕
        savedFrames[id] = curF
        win:setFrame(maxF)
    end
end)
