; =====================================================================
; RDP Mega Toolkit v9.0.0 — NSIS Installer Script
; Requires: NSIS 3.x (https://nsis.sourceforge.io/)
; Build:    makensis installer.nsi
; =====================================================================

!define APP_NAME        "RDP Mega Toolkit"
!define APP_VERSION     "9.0.0"
!define APP_PUBLISHER   "usekarne"
!define APP_URL         "https://github.com/usekarne/github-rdp-mega-toolkit"
!define APP_REGKEY      "Software\usekarne\RDPToolkit"
!define APP_UNINSTKEY   "Software\Microsoft\Windows\CurrentVersion\Uninstall\RDPToolkit"

Name "${APP_NAME} ${APP_VERSION}"
OutFile "rdp-toolkit-setup-9.0.0.exe"
InstallDir "$PROGRAMFILES\RDPToolkit"
InstallDirRegKey HKLM "${APP_REGKEY}" "InstallDir"
ShowInstDetails show
ShowUnInstDetails show
SetOverwrite on
Unicode true
RequestExecutionLevel admin

; ----- Modern UI ------------------------------------------------------
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "EnvVarUpdate.nsh"

!define MUI_ABORTWARNING
!define MUI_ICON "installer.ico"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "..\..\LICENSE"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

!insertmacro MUI_LANGUAGE "English"

; =====================================================================
; Section: Main files
; =====================================================================
Section "Main Application (required)" SecMain
    SectionIn RO
    SetOutPath "$INSTDIR"
    File /r "..\..\rdp_toolkit\*.*"
    File "..\..\README.md"
    File "..\..\LICENSE"

    ; Write install dir + uninstaller to registry
    WriteRegStr HKLM "${APP_REGKEY}" "InstallDir" "$INSTDIR"
    WriteRegStr HKLM "${APP_REGKEY}" "Version"    "${APP_VERSION}"

    WriteRegStr   HKLM "${APP_UNINSTKEY}" "DisplayName"     "${APP_NAME}"
    WriteRegStr   HKLM "${APP_UNINSTKEY}" "DisplayVersion"  "${APP_VERSION}"
    WriteRegStr   HKLM "${APP_UNINSTKEY}" "Publisher"       "${APP_PUBLISHER}"
    WriteRegStr   HKLM "${APP_UNINSTKEY}" "DisplayIcon"     "$INSTDIR\rdp-toolkit.exe,0"
    WriteRegStr   HKLM "${APP_UNINSTKEY}" "URLInfoAbout"    "${APP_URL}"
    WriteRegStr   HKLM "${APP_UNINSTKEY}" "InstallLocation" "$INSTDIR"
    WriteRegStr   HKLM "${APP_UNINSTKEY}" "Uninstaller"     "$INSTDIR\uninstall.exe"
    WriteRegDWORD HKLM "${APP_UNINSTKEY}" "NoModify" 1
    WriteRegDWORD HKLM "${APP_UNINSTKEY}" "NoRepair" 1

    ; Create the uninstaller
    WriteUninstaller "$INSTDIR\uninstall.exe"

    ; Estimate install size for Add/Remove Programs
    ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
    IntFmt $0 "0x%08X" $0
    WriteRegDWORD HKLM "${APP_UNINSTKEY}" "EstimatedSize" "$0"
SectionEnd

; =====================================================================
; Section: Shortcuts
; =====================================================================
Section "Start Menu + Desktop Shortcuts" SecShortcuts
    CreateDirectory "$SMPROGRAMS\${APP_NAME}"
    CreateShortcut  "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" \
                    "$INSTDIR\rdp-toolkit.exe" "" \
                    "$INSTDIR\rdp-toolkit.exe" 0 \
                    "" "" "" "Cross-platform RDP automation toolkit"
    CreateShortcut  "$SMPROGRAMS\${APP_NAME}\Uninstall.lnk" \
                    "$INSTDIR\uninstall.exe"
    CreateShortcut  "$DESKTOP\${APP_NAME}.lnk" \
                    "$INSTDIR\rdp-toolkit.exe" "" \
                    "$INSTDIR\rdp-toolkit.exe" 0
SectionEnd

; =====================================================================
; Section: PATH
; =====================================================================
Section "Add to System PATH" SecPath
    ; EnvVarUpdate (courtesy of the NSIS wiki) handles PATH safely.
    ${EnvVarUpdate} $0 "PATH" "A" "HKLM" "$INSTDIR"
    DetailPrint "Added $INSTDIR to system PATH (restart shell to apply)."
SectionEnd

; =====================================================================
; Descriptions
; =====================================================================
!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
    !insertmacro MUI_DESCRIPTION_TEXT ${SecMain}     "Installs core ${APP_NAME} files (required)."
    !insertmacro MUI_DESCRIPTION_TEXT ${SecShortcuts} "Creates Start Menu and Desktop shortcuts."
    !insertmacro MUI_DESCRIPTION_TEXT ${SecPath}     "Adds the install directory to the system PATH."
!insertmacro MUI_FUNCTION_DESCRIPTION_END

; =====================================================================
; Uninstaller
; =====================================================================
Section "Uninstall"
    Delete "$INSTDIR\uninstall.exe"
    Delete "$INSTDIR\README.md"
    Delete "$INSTDIR\LICENSE"
    RMDir /r "$INSTDIR\rdp_toolkit"
    RMDir /r "$INSTDIR"
    RMDir /r "$SMPROGRAMS\${APP_NAME}"
    Delete "$DESKTOP\${APP_NAME}.lnk"

    ; Remove from PATH
    ${un.EnvVarUpdate} $0 "PATH" "R" "HKLM" "$INSTDIR"

    DeleteRegKey HKLM "${APP_UNINSTKEY}"
    DeleteRegKey HKLM "${APP_REGKEY}"
SectionEnd

Function .onInstSuccess
    MessageBox MB_YESNO|MB_ICONQUESTION \
        "${APP_NAME} installed successfully!$\r$\n$\r$\nRun 'rdp-toolkit doctor' now?" \
        /SD IDNO IDNO NoRun
        Exec '"$INSTDIR\rdp-toolkit.exe" doctor'
    NoRun:
FunctionEnd
