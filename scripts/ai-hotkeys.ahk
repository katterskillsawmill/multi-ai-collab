; Multi-AI Collaboration Hotkeys
; ================================
; Ctrl+Alt+C = Claude
; Ctrl+Alt+G = GPT-4
; Ctrl+Alt+M = Gemini
; Ctrl+Alt+K = Grok
; Ctrl+Alt+A = All AIs
; Ctrl+Alt+N = Check Notes (fetch latest comments)
; Ctrl+Alt+P = Post response to GitHub

#Requires AutoHotkey v2.0
#SingleInstance Force

; Configuration - Set your repo here
global GITHUB_REPO := "katterskillsawmill/multi-ai-collab"
global SCRIPTS_DIR := A_ScriptDir

; Show tooltip helper
ShowTip(msg, duration := 2000) {
    ToolTip(msg)
    SetTimer(() => ToolTip(), -duration)
}

; Ctrl+Alt+C = Ask Claude
^!c:: {
    ShowTip("🧠 Asking Claude...")
    RunWait('powershell.exe -ExecutionPolicy Bypass -File "' SCRIPTS_DIR '\ai-query.ps1" -AI claude', , "Hide")
}

; Ctrl+Alt+G = Ask GPT-4
^!g:: {
    ShowTip("💻 Asking GPT-4...")
    RunWait('powershell.exe -ExecutionPolicy Bypass -File "' SCRIPTS_DIR '\ai-query.ps1" -AI gpt4', , "Hide")
}

; Ctrl+Alt+M = Ask Gemini
^!m:: {
    ShowTip("🔒 Asking Gemini...")
    RunWait('powershell.exe -ExecutionPolicy Bypass -File "' SCRIPTS_DIR '\ai-query.ps1" -AI gemini', , "Hide")
}

; Ctrl+Alt+K = Ask Grok
^!k:: {
    ShowTip("🚀 Asking Grok...")
    RunWait('powershell.exe -ExecutionPolicy Bypass -File "' SCRIPTS_DIR '\ai-query.ps1" -AI grok', , "Hide")
}

; Ctrl+Alt+A = Ask All AIs
^!a:: {
    ShowTip("🤖 Asking All AIs...")
    RunWait('powershell.exe -ExecutionPolicy Bypass -File "' SCRIPTS_DIR '\ai-query.ps1" -AI all', , "Hide")
}

; Ctrl+Alt+N = Check Notes (fetch latest GitHub comments)
^!n:: {
    ShowTip("📋 Fetching notes...")
    RunWait('powershell.exe -ExecutionPolicy Bypass -File "' SCRIPTS_DIR '\ai-query.ps1" -CheckNotes', , "Hide")
}

; Ctrl+Alt+P = Post to GitHub
^!p:: {
    ShowTip("📤 Posting to GitHub...")
    RunWait('powershell.exe -ExecutionPolicy Bypass -File "' SCRIPTS_DIR '\ai-query.ps1" -PostToGitHub', , "Hide")
}

; Ctrl+Alt+H = Show help
^!h:: {
    helpText := "
    (
    Multi-AI Collaboration Hotkeys
    ==============================

    Ctrl+Alt+C  →  Ask Claude (Architecture)
    Ctrl+Alt+G  →  Ask GPT-4 (Code Quality)
    Ctrl+Alt+M  →  Ask Gemini (Security)
    Ctrl+Alt+K  →  Ask Grok (Edge Cases)
    Ctrl+Alt+A  →  Ask All AIs

    Ctrl+Alt+N  →  Check Notes (fetch comments)
    Ctrl+Alt+P  →  Post response to GitHub
    Ctrl+Alt+H  →  Show this help

    Usage:
    1. Copy code/question to clipboard
    2. Press hotkey for desired AI
    3. Response appears in popup
    4. Press Ctrl+Alt+P to post to GitHub
    )"
    MsgBox(helpText, "AI Hotkeys Help", "Iconi")
}

; Startup notification
ShowTip("✅ AI Hotkeys Active (Ctrl+Alt+H for help)", 3000)
