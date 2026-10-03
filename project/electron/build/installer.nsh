; Optional "Command-line tools" component for the Windows NSIS installer.
;
; Adds quki.cmd / quki-mcp.cmd wrapper scripts to the install directory and
; puts that directory on PATH, so `quki` and `quki-mcp` work from any
; terminal. Both wrappers run the CLI/MCP bundles through this app's own
; packaged Electron binary with ELECTRON_RUN_AS_NODE=1 - no separate Node.js
; install is required.
;
; electron-builder auto-includes this file by its default name and location
; (project/electron/build/installer.nsh) - see app-builder-lib's
; platformPackager.js getResource(), read directly from node_modules for this
; electron-builder version rather than assumed. The hook macro names below
; (customHeader, customInit, customPageAfterChangeDir, customInstall,
; customUnInstall) were verified the same way, against the actual templates
; in node_modules/app-builder-lib/templates/nsis/*.nsh, not general NSIS
; knowledge - this project's CLAUDE.md requires reading what executes over
; assuming from memory, and NSIS/electron-builder is exactly the kind of
; unfamiliar domain that rule is aimed at.
;
; NOT verified: this script has not been compiled with makensis or run in a
; real installer anywhere in this change's development - there is no NSIS
; toolchain available in that environment. Only the hook wiring was checked
; against real source.

!macro customHeader
  !include "nsDialogs.nsh"
  !include "WinMessages.nsh"

  Var CliToolsCheckbox
  Var CliToolsSelected

  Function CliToolsPageCreate
    !insertmacro MUI_HEADER_TEXT "Command-line tools" "Optional: use QuKi Notes from a terminal"

    nsDialogs::Create 1018
    Pop $0
    ${If} $0 == error
      Abort
    ${EndIf}

    ${NSD_CreateCheckbox} 0 0 100% 12u "Install command-line tools (quki, quki-mcp) and add them to PATH"
    Pop $CliToolsCheckbox
    ${NSD_SetState} $CliToolsCheckbox $CliToolsSelected

    ${NSD_CreateLabel} 0 20u 100% 40u "Adds 'quki' (read/write QuKis from a shell) and 'quki-mcp' (an MCP server for AI tools) to PATH. Both run through this app's own bundled runtime - no separate Node.js install needed. Uninstalling QuKi Notes removes them too."
    Pop $1

    nsDialogs::Show
  FunctionEnd

  Function CliToolsPageLeave
    ${NSD_GetState} $CliToolsCheckbox $CliToolsSelected
  FunctionEnd
!macroend

!macro customInit
  ; Runs in .onInit, before any page is shown - and before pages are skipped
  ; entirely in a silent install, where CliToolsPageLeave never runs. Default
  ; to "checked" here so a silent/unattended install still gets the CLI
  ; tools, matching "include both by default".
  StrCpy $CliToolsSelected ${BST_CHECKED}
!macroend

!macro customPageAfterChangeDir
  Page custom CliToolsPageCreate CliToolsPageLeave
!macroend

!macro customInstall
  ${If} $CliToolsSelected == ${BST_CHECKED}
    FileOpen $R9 "$INSTDIR\quki.cmd" w
    FileWrite $R9 "@echo off$\r$\n"
    FileWrite $R9 "set ELECTRON_RUN_AS_NODE=1$\r$\n"
    FileWrite $R9 '"%~dp0${APP_EXECUTABLE_FILENAME}" "%~dp0resources\cli\main.mjs" %*$\r$\n'
    FileWrite $R9 "exit /b %ERRORLEVEL%$\r$\n"
    FileClose $R9

    FileOpen $R9 "$INSTDIR\quki-mcp.cmd" w
    FileWrite $R9 "@echo off$\r$\n"
    FileWrite $R9 "set ELECTRON_RUN_AS_NODE=1$\r$\n"
    FileWrite $R9 '"%~dp0${APP_EXECUTABLE_FILENAME}" "%~dp0resources\mcp\server.mjs" %*$\r$\n'
    FileWrite $R9 "exit /b %ERRORLEVEL%$\r$\n"
    FileClose $R9

    ${If} $installMode == "all"
      StrCpy $R8 "Machine"
    ${Else}
      StrCpy $R8 "User"
    ${EndIf}

    ; Do the actual PATH edit in a real PowerShell script file rather than an
    ; inline -Command string, to avoid NSIS-string / cmd-line / PowerShell
    ; triple-quoting. $$ below is NSIS's escape for a literal "$" (so the
    ; written file contains real PowerShell variables, not NSIS ones).
    FileOpen $R9 "$PLUGINSDIR\quki-path-add.ps1" w
    FileWrite $R9 "param([string]$$Dir,[string]$$Scope)$\r$\n"
    FileWrite $R9 "$$p = [Environment]::GetEnvironmentVariable('Path', $$Scope)$\r$\n"
    FileWrite $R9 "$$parts = @()$\r$\n"
    FileWrite $R9 "if ($$p) { $$parts = $$p -split ';' }$\r$\n"
    FileWrite $R9 "if ($$parts -notcontains $$Dir) {$\r$\n"
    FileWrite $R9 "  $$new = if ($$p) { $$p.TrimEnd(';') + ';' + $$Dir } else { $$Dir }$\r$\n"
    FileWrite $R9 "  [Environment]::SetEnvironmentVariable('Path', $$new, $$Scope)$\r$\n"
    FileWrite $R9 "}$\r$\n"
    FileClose $R9

    nsExec::ExecToLog 'powershell -NoProfile -ExecutionPolicy Bypass -File "$PLUGINSDIR\quki-path-add.ps1" -Dir "$INSTDIR" -Scope "$R8"'
  ${EndIf}
!macroend

!macro customUnInstall
  Delete "$INSTDIR\quki.cmd"
  Delete "$INSTDIR\quki-mcp.cmd"

  ${If} $installMode == "all"
    StrCpy $R8 "Machine"
  ${Else}
    StrCpy $R8 "User"
  ${EndIf}

  FileOpen $R9 "$PLUGINSDIR\quki-path-remove.ps1" w
  FileWrite $R9 "param([string]$$Dir,[string]$$Scope)$\r$\n"
  FileWrite $R9 "$$p = [Environment]::GetEnvironmentVariable('Path', $$Scope)$\r$\n"
  FileWrite $R9 "if ($$p) {$\r$\n"
  FileWrite $R9 "  $$new = (($$p -split ';') | Where-Object { $$_ -and ($$_ -ne $$Dir) }) -join ';'$\r$\n"
  FileWrite $R9 "  [Environment]::SetEnvironmentVariable('Path', $$new, $$Scope)$\r$\n"
  FileWrite $R9 "}$\r$\n"
  FileClose $R9

  nsExec::ExecToLog 'powershell -NoProfile -ExecutionPolicy Bypass -File "$PLUGINSDIR\quki-path-remove.ps1" -Dir "$INSTDIR" -Scope "$R8"'
!macroend
