; fileinfra.nsi - NSIS Installer Script for FileInfra
Unicode true
SetCompressor /SOLID lzma

!define APP_NAME "FileInfra"
!ifndef APP_VERSION
  !error "APP_VERSION is required; pass /DAPP_VERSION=<pubspec version> to makensis"
!endif
!define APP_PUBLISHER "zocs"
!define APP_URL "https://github.com/zocs/fileinfra"
!define APP_EXE "fileinfra.exe"

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"

Name "${APP_NAME} ${APP_VERSION}"
; OutFile 在 !cd ".." 之前定义——当前组合经 CI 实证产物落在调用目录
;（repo 根，v0.5.0 release 已验证）。本地无 makensis 可测，勿凭文档
; 调整定义顺序，改前先在 CI 冒烟。
OutFile "fileinfra-${APP_VERSION}-windows-x64-setup.exe"
; 记住上次安装目录：自定义路径的用户升级时不再装出第二份
InstallDirRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "InstallLocation"
InstallDir "$PROGRAMFILES64\${APP_NAME}"
RequestExecutionLevel admin

; Custom finish page run text
!define MUI_FINISHPAGE_RUN_TEXT "Run ${APP_NAME}"
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"

; Pages
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "SimpChinese"
!insertmacro MUI_LANGUAGE "English"

; Check if fileinfra.exe is running, kill if user confirms
; Uses a fast WMI-based check instead of slow tasklist
!macro CheckAndKillProcess
  nsExec::ExecToStack 'cmd /c tasklist /FI "IMAGENAME eq ${APP_EXE}" /NH 2^>nul ^| findstr /I "${APP_EXE}"'
  Pop $0
  Pop $1
  ${If} $0 == 0
    ; Process found — ask user
    MessageBox MB_YESNO|MB_ICONEXCLAMATION \
      "${APP_NAME} is running. Close it and continue?" \
      IDYES kill IDNO cancel
    cancel:
      Abort
    kill:
      nsExec::ExecToLog 'taskkill /F /IM "${APP_EXE}"'
      ; Wait up to 10 seconds for process to exit
      StrCpy $2 0
      loop:
        Sleep 500
        IntOp $2 $2 + 1
        nsExec::ExecToStack 'cmd /c tasklist /FI "IMAGENAME eq ${APP_EXE}" /NH 2^>nul ^| findstr /I "${APP_EXE}"'
        Pop $0
        Pop $1
        ${If} $0 != 0
          Goto done
        ${EndIf}
        ${If} $2 < 20
          Goto loop
        ${EndIf}
      done:
  ${EndIf}
!macroend

Section "Install"
  !insertmacro CheckAndKillProcess

  SetOutPath "$INSTDIR"
  !cd ".."
  ; 用 * 而非 *.*：无扩展名文件（如 LICENSE）不落在 *.* 的通配里
  File /r "build\windows\x64\runner\Release\*"

  ; Create shortcuts
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"
  CreateShortCut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"

  ; Write uninstaller
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\Uninstall.lnk" "$INSTDIR\Uninstall.exe"

  ; Register in Add/Remove Programs
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "UninstallString" "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "Publisher" "${APP_PUBLISHER}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "URLInfoAbout" "${APP_URL}"

  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "EstimatedSize" $0
SectionEnd

Section "Uninstall"
  !insertmacro CheckAndKillProcess

  RMDir /r "$INSTDIR"
  Delete "$DESKTOP\${APP_NAME}.lnk"
  RMDir /r "$SMPROGRAMS\${APP_NAME}"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}"
SectionEnd
