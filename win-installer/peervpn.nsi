; ****************************************************************************
; * Copyright (C) 2015 Christian Wick <c.wick@mail.de>
; * Copyright (C) 2002-2010 OpenVPN Technologies, Inc.                       *
; * Copyright (C)      2012 Alon Bar-Lev <alon.barlev@gmail.com>             *
; *  This program is free software; you can redistribute it and/or modify    *
; *  it under the terms of the GNU General Public License version 2          *
; *  as published by the Free Software Foundation.                           *
; ****************************************************************************

; peervpn install script for Windows, using NSIS
; based on OpenVPN install script "openvpn.nsi" 

SetCompressor lzma

; Modern user interface
!include "MUI2.nsh"

; Install for all users. MultiUser.nsh also calls SetShellVarContext to point 
; the installer to global directories (e.g. Start menu, desktop, etc.)
!define MULTIUSER_EXECUTIONLEVEL Admin
!include "MultiUser.nsh"

; EnvVarUpdate.nsh is needed to update the PATH environment variable
!include "EnvVarUpdate.nsh"

; WinMessages.nsh is needed to send WM_CLOSE to the GUI if it is still running
!include "WinMessages.nsh"

; nsProcess.nsh to detect whether peervpn process is running ( http://nsis.sourceforge.net/NsProcess_plugin )
!addplugindir .
!include "nsProcess.nsh"

; x64.nsh for architecture detection
!include "x64.nsh"

; Read the command-line parameters
!insertmacro GetParameters
!insertmacro GetOptions

; Default service settings
!define PEERVPN_CONFIG_EXT "pvpn"

;--------------------------------
;Configuration

;General

; Package name as shown in the installer GUI
Name "${PACKAGE_NAME} ${VERSION_STRING}"

; On 64-bit Windows the constant $PROGRAMFILES defaults to
; C:\Program Files (x86) and on 32-bit Windows to C:\Program Files. However,
; the .onInit function (see below) takes care of changing this for 64-bit 
; Windows.
InstallDir "$PROGRAMFILES\${PACKAGE_NAME}"

; Installer filename
OutFile "${OUTPUT}"

ShowInstDetails show
ShowUninstDetails show

;Remember install folder
InstallDirRegKey HKLM "SOFTWARE\${PACKAGE_NAME}" ""

;--------------------------------
;Modern UI Configuration

; Compile-time constants which we'll need during install
!define MUI_WELCOMEPAGE_TEXT "This wizard will guide you through the installation of ${PACKAGE_NAME}, an Open Source VPN package by Tobias Volk.$\r$\n$\r$\nNote that the Windows version of ${PACKAGE_NAME} will only run on Windows XP, or higher.$\r$\n$\r$\n$\r$\n"

!define MUI_COMPONENTSPAGE_TEXT_TOP "Select the components to install/upgrade.  Stop any ${PACKAGE_NAME} processes or the ${PACKAGE_NAME} service if it is running.  All DLLs are installed locally."

!define MUI_COMPONENTSPAGE_SMALLDESC
!define MUI_FINISHPAGE_SHOWREADME "$INSTDIR\doc\INSTALL-win32.txt"
!define MUI_FINISHPAGE_RUN_TEXT "Start peervpn GUI"
!define MUI_FINISHPAGE_RUN "$INSTDIR\bin\peervpn-gui.exe"
!define MUI_FINISHPAGE_RUN_NOTCHECKED

!define MUI_FINISHPAGE_NOAUTOCLOSE
!define MUI_ABORTWARNING
!define MUI_ICON "icon.ico"
!define MUI_UNICON "icon.ico"
!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_BITMAP "install-whirl.bmp"
!define MUI_UNFINISHPAGE_NOAUTOCLOSE

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${PEERVPN_ROOT}\license.txt"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_PAGE_CUSTOMFUNCTION_SHOW StartGUI.show
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

Var /Global strGuiKilled ; Track if GUI was killed so we can tick the checkbox to start it upon installer finish

;--------------------------------
;Languages
 
!insertmacro MUI_LANGUAGE "English"
  
;--------------------------------
;Language Strings

LangString DESC_SecPeerVpnUserSpace ${LANG_ENGLISH} "Install ${PACKAGE_NAME} user-space components, including peervpn.exe."

!ifdef USE_PEERVPN_GUI
	LangString DESC_SecPeerVpnGUI ${LANG_ENGLISH} "Install ${PACKAGE_NAME} GUI."
!endif

!ifdef USE_TAP_WINDOWS
	LangString DESC_SecTAP ${LANG_ENGLISH} "Install/upgrade the TAP virtual device driver."
!endif

LangString DESC_SecService ${LANG_ENGLISH} "Install the ${PACKAGE_NAME} service wrapper (peervpnserv.exe)"

LangString DESC_SecAddPath ${LANG_ENGLISH} "Add ${PACKAGE_NAME} executable directory to the current user's PATH."

LangString DESC_SecAddShortcuts ${LANG_ENGLISH} "Add ${PACKAGE_NAME} shortcuts to the current user's Start Menu."

LangString DESC_SecFileAssociation ${LANG_ENGLISH} "Register ${PACKAGE_NAME} config file association (*.${PEERVPN_CONFIG_EXT})"

;--------------------------------
;Reserve Files
  
;Things that need to be extracted on first (keep these lines before any File command!)
;Only useful for BZIP2 compression

ReserveFile "install-whirl.bmp"

;--------------------------------
;Macros

!macro SelectByParameter SECT PARAMETER DEFAULT
	${GetOptions} $R0 "/${PARAMETER}=" $0
	${If} ${DEFAULT} == 0
		${If} $0 == 1
			!insertmacro SelectSection ${SECT}
		${EndIf}
	${Else}
		${If} $0 != 0
			!insertmacro SelectSection ${SECT}
		${EndIf}
	${EndIf}
!macroend

!macro WriteRegStringIfUndef ROOT SUBKEY KEY VALUE
	Push $R0
	ReadRegStr $R0 "${ROOT}" "${SUBKEY}" "${KEY}"
	${If} $R0 == ""
		WriteRegStr "${ROOT}" "${SUBKEY}" "${KEY}" '${VALUE}'
	${EndIf}
	Pop $R0
!macroend

!macro DelRegKeyIfUnchanged ROOT SUBKEY VALUE
	Push $R0
	ReadRegStr $R0 "${ROOT}" "${SUBKEY}" ""
	${If} $R0 == '${VALUE}'
		DeleteRegKey "${ROOT}" "${SUBKEY}"
	${EndIf}
	Pop $R0
!macroend

;--------------------
;Pre-install section

Section -pre
	Push $0 ; for FindWindow
	FindWindow $0 "peervpn-GUI"
	StrCmp $0 0 guiNotRunning

	MessageBox MB_YESNO|MB_ICONEXCLAMATION "To perform the specified operation, peervpn-GUI needs to be closed. Shall I close it?" /SD IDYES IDNO guiEndNo
	DetailPrint "Closing peervpn-GUI..."
	Goto guiEndYes

	guiEndNo:
		Quit

	guiEndYes:
		; user wants to close GUI as part of install/upgrade
		FindWindow $0 "peervpn-GUI"
		IntCmp $0 0 guiClosed
		SendMessage $0 ${WM_CLOSE} 0 0
		Sleep 100
		Goto guiEndYes

	guiClosed:
		; Keep track that we closed the GUI so we can offer to auto (re)start it later
		StrCpy $strGuiKilled "1"

	guiNotRunning:
		; check for running peervpn.exe processes
		${nsProcess::FindProcess} "peervpn.exe" $R0
		${If} $R0 == 0
			MessageBox MB_OK|MB_ICONEXCLAMATION "The installation cannot continue as peervpn is currently running. Please close all peervpn instances and re-run the installer."
			Quit
		${EndIf}

		; peervpn.exe + GUI not running/closed successfully, carry on with install/upgrade
	
		; Delete previous start menu folder
		RMDir /r "$SMPROGRAMS\${PACKAGE_NAME}"

		; Stop & Remove previous peervpn service
		DetailPrint "Removing any previous peervpn service..."
		nsExec::ExecToLog '"$INSTDIR\bin\peervpnserv.exe" -remove'
		Pop $R0 # return value/error/timeout

		Sleep 3000
	Pop $0 ; for FindWindow

SectionEnd

Section /o "-workaround" SecAddShortcutsWorkaround
	; this section should be selected as SecAddShortcuts
	; as we don't want to move SecAddShortcuts to top of selection
SectionEnd

Section /o "${PACKAGE_NAME} User-Space Components" SecPeerVpnUserSpace

	SetOverwrite on

	SetOutPath "$INSTDIR\bin"
	File "${PEERVPN_ROOT}\peervpn.exe"

;	SetOutPath "$INSTDIR\doc"
;	File "${PEERVPN_ROOT}\share\doc\openvpn\INSTALL-win32.txt"

	${If} ${SectionIsSelected} ${SecAddShortcutsWorkaround}
		CreateDirectory "$SMPROGRAMS\${PACKAGE_NAME}\Documentation"
;		CreateShortCut "$SMPROGRAMS\${PACKAGE_NAME}\Documentation\${PACKAGE_NAME} Windows Notes.lnk" "$INSTDIR\doc\INSTALL-win32.txt"
	${EndIf}

SectionEnd

Section /o "${PACKAGE_NAME} Service" SecService

	SetOverwrite on

	SetOutPath "$INSTDIR\bin"
	File "${PEERVPN_ROOT}\peervpnserv.exe"

	SetOutPath "$INSTDIR\config"

	FileOpen $R0 "$INSTDIR\config\README.txt" w
	FileWrite $R0 "This directory should contain ${PACKAGE_NAME} configuration files$\r$\n"
	FileWrite $R0 "each having an extension of .${PEERVPN_CONFIG_EXT}$\r$\n"
	FileWrite $R0 "$\r$\n"
	FileWrite $R0 "When ${PACKAGE_NAME} is started as a service, a separate ${PACKAGE_NAME}$\r$\n"
	FileWrite $R0 "process will be instantiated for each configuration file.$\r$\n"
	FileClose $R0

	CreateDirectory "$INSTDIR\log"
	FileOpen $R0 "$INSTDIR\log\README.txt" w
	FileWrite $R0 "This directory will contain the log files for ${PACKAGE_NAME}$\r$\n"
	FileWrite $R0 "sessions which are being run as a service.$\r$\n"
	FileClose $R0

	${If} ${SectionIsSelected} ${SecAddShortcutsWorkaround}
		CreateDirectory "$SMPROGRAMS\${PACKAGE_NAME}\Utilities"
		CreateDirectory "$SMPROGRAMS\${PACKAGE_NAME}\Shortcuts"
		CreateShortCut "$SMPROGRAMS\${PACKAGE_NAME}\Shortcuts\${PACKAGE_NAME} log file directory.lnk" "$INSTDIR\log" ""
		CreateShortCut "$SMPROGRAMS\${PACKAGE_NAME}\Shortcuts\${PACKAGE_NAME} configuration file directory.lnk" "$INSTDIR\config" ""
	${EndIf}

	; set registry parameters for peervpnserv	
	!insertmacro WriteRegStringIfUndef HKLM "SOFTWARE\${PACKAGE_NAME}" "config_dir" "$INSTDIR\config" 
	!insertmacro WriteRegStringIfUndef HKLM "SOFTWARE\${PACKAGE_NAME}" "config_ext"  "${PEERVPN_CONFIG_EXT}"
	!insertmacro WriteRegStringIfUndef HKLM "SOFTWARE\${PACKAGE_NAME}" "exe_path"    "$INSTDIR\bin\peervpn.exe"
	!insertmacro WriteRegStringIfUndef HKLM "SOFTWARE\${PACKAGE_NAME}" "log_dir"     "$INSTDIR\log"
	!insertmacro WriteRegStringIfUndef HKLM "SOFTWARE\${PACKAGE_NAME}" "priority"    "NORMAL_PRIORITY_CLASS"
	!insertmacro WriteRegStringIfUndef HKLM "SOFTWARE\${PACKAGE_NAME}" "log_append"  "0"

	; install peervpnserv as a service (to be started manually from service control manager)
	DetailPrint "Installing PeerVPN Service..."
	nsExec::ExecToLog '"$INSTDIR\bin\peervpnserv.exe" -install'
	Pop $R0 # return value/error/timeout

SectionEnd

!ifdef USE_TAP_WINDOWS
Section /o "TAP Virtual Ethernet Adapter" SecTAP

	SetOverwrite on
	SetOutPath "$TEMP"

	File /oname=tap-windows.exe "${TAP_WINDOWS_INSTALLER}"

	DetailPrint "Installing TAP (may need confirmation)..."
	nsExec::ExecToLog '"$TEMP\tap-windows.exe" /S /SELECT_UTILITIES=1'
	Pop $R0 # return value/error/timeout

	Delete "$TEMP\tap-windows.exe"

	WriteRegStr HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\${PACKAGE_NAME}" "tap" "installed"
SectionEnd
!endif

!ifdef USE_PEERVPN_GUI
Section /o "${PACKAGE_NAME} GUI" SecPeerVPNGUI

	SetOverwrite on
	SetOutPath "$INSTDIR\bin"

	File "${PEERVPN_ROOT}\bin\peervpn-gui.exe"

	${If} ${SectionIsSelected} ${SecAddShortcutsWorkaround}
		CreateDirectory "$SMPROGRAMS\${PACKAGE_NAME}"
		CreateShortCut "$SMPROGRAMS\${PACKAGE_NAME}\${PACKAGE_NAME} GUI.lnk" "$INSTDIR\bin\peervpn-gui.exe" ""
		CreateShortcut "$DESKTOP\${PACKAGE_NAME} GUI.lnk" "$INSTDIR\bin\peervpn-gui.exe"
	${EndIf}
SectionEnd
!endif

Section /o "${PACKAGE_NAME} File Associations" SecFileAssociation
	WriteRegStr HKCR ".${PEERVPN_CONFIG_EXT}" "" "${PACKAGE_NAME}File"
	WriteRegStr HKCR "${PACKAGE_NAME}File" "" "${PACKAGE_NAME} Config File"
	WriteRegStr HKCR "${PACKAGE_NAME}File\shell" "" "open"
	WriteRegStr HKCR "${PACKAGE_NAME}File\DefaultIcon" "" "$INSTDIR\icon.ico,0"
	WriteRegStr HKCR "${PACKAGE_NAME}File\shell\open\command" "" 'notepad.exe "%1"'
	WriteRegStr HKCR "${PACKAGE_NAME}File\shell\run" "" "Start ${PACKAGE_NAME} on this config file"
	WriteRegStr HKCR "${PACKAGE_NAME}File\shell\run\command" "" '"$INSTDIR\bin\peervpn.exe" --pause-exit --config "%1"'
SectionEnd

Section /o "Add ${PACKAGE_NAME} to PATH" SecAddPath

	; append our bin directory to end of current user path
	${EnvVarUpdate} $R0 "PATH" "A" "HKLM" "$INSTDIR\bin"

SectionEnd

Section /o "Add Shortcuts to Start Menu" SecAddShortcuts

	SetOverwrite on
	CreateDirectory "$SMPROGRAMS\${PACKAGE_NAME}\Documentation"
	WriteINIStr "$SMPROGRAMS\${PACKAGE_NAME}\Documentation\${PACKAGE_NAME} Web Site.url" "InternetShortcut" "URL" "http://peervpn.net/"

	CreateShortCut "$SMPROGRAMS\${PACKAGE_NAME}\Uninstall ${PACKAGE_NAME}.lnk" "$INSTDIR\Uninstall.exe"
SectionEnd

;--------------------------------
;Installer Sections

Function .onInit
	${GetParameters} $R0
	ClearErrors

	!insertmacro SelectByParameter ${SecAddShortcutsWorkaround} SELECT_SHORTCUTS 1
	!insertmacro SelectByParameter ${SecPeerVpnUserSpace} SELECT_PEERVPN 1
	!insertmacro SelectByParameter ${SecService} SELECT_SERVICE 1
!ifdef USE_TAP_WINDOWS
	!insertmacro SelectByParameter ${SecTAP} SELECT_TAP 1
!endif
!ifdef USE_PEERVPN_GUI
	!insertmacro SelectByParameter ${SecPeerVpnGUI} SELECT_PEERVPNGUI 1
!endif
	!insertmacro SelectByParameter ${SecFileAssociation} SELECT_ASSOCIATIONS 1
	!insertmacro SelectByParameter ${SecAddPath} SELECT_PATH 1
	!insertmacro SelectByParameter ${SecAddShortcuts} SELECT_SHORTCUTS 1

	!insertmacro MULTIUSER_INIT
	SetShellVarContext all

	; Check if the installer was built for x86_64
	${If} "${ARCH}" == "x86_64"

		${IfNot} ${RunningX64}
			; User is running 64 bit installer on 32 bit OS
			MessageBox MB_OK|MB_ICONEXCLAMATION "This installer is designed to run only on 64-bit systems."
			Quit
		${EndIf}
	
		SetRegView 64

		; Change the installation directory to C:\Program Files, but only if the
		; user has not provided a custom install location.
		${If} "$INSTDIR" == "$PROGRAMFILES\${PACKAGE_NAME}"
			StrCpy $INSTDIR "$PROGRAMFILES64\${PACKAGE_NAME}"
		${EndIf}
	${EndIf}

FunctionEnd

;--------------------------------
;Dependencies

Function .onSelChange
	${If} ${SectionIsSelected} ${SecService}
		!insertmacro SelectSection ${SecPeerVpnUserSpace}
	${EndIf}
	${If} ${SectionIsSelected} ${SecAddShortcuts}
		!insertmacro SelectSection ${SecAddShortcutsWorkaround}
	${Else}
		!insertmacro UnselectSection ${SecAddShortcutsWorkaround}
	${EndIf}
FunctionEnd

Function StartGUI.show
	; if the user chooses not to install the GUI, do not offer to start it
	${IfNot} ${SectionIsSelected} ${SecPeerVpnGUI}
		SendMessage $mui.FinishPage.Run ${BM_SETCHECK} ${BST_CHECKED} 0
		ShowWindow $mui.FinishPage.Run 0
	${EndIf}

	; if we killed the GUI to do the install/upgrade, automatically tick the "Start peervpn GUI" option
	${If} $strGuiKilled == "1"
		SendMessage $mui.FinishPage.Run ${BM_SETCHECK} ${BST_CHECKED} 1
	${EndIf}
FunctionEnd

;--------------------
;Post-install section

Section -post

	SetOverwrite on
	SetOutPath "$INSTDIR"
	File "icon.ico"
	SetOutPath "$INSTDIR\doc"
	File "${PEERVPN_ROOT}\license.txt"

	; Store install folder in registry
	WriteRegStr HKLM "SOFTWARE\${PACKAGE_NAME}" "" "$INSTDIR"

	; Create uninstaller
	WriteUninstaller "$INSTDIR\Uninstall.exe"

	; Show up in Add/Remove programs
	WriteRegStr HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\${PACKAGE_NAME}" "DisplayName" "${PACKAGE_NAME} ${VERSION_STRING}"
	WriteRegExpandStr HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\${PACKAGE_NAME}" "UninstallString" "$INSTDIR\Uninstall.exe"
	WriteRegStr HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\${PACKAGE_NAME}" "DisplayIcon" "$INSTDIR\icon.ico"
	WriteRegStr HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\${PACKAGE_NAME}" "DisplayVersion" "${VERSION_STRING}"

SectionEnd

;--------------------------------
;Descriptions

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
	!insertmacro MUI_DESCRIPTION_TEXT ${SecPeerVpnUserSpace} $(DESC_SecPeerVpnUserSpace)
	!insertmacro MUI_DESCRIPTION_TEXT ${SecService} $(DESC_SecService)
	!ifdef USE_PEERVPN_GUI
		!insertmacro MUI_DESCRIPTION_TEXT ${SecPeerVpnGUI} $(DESC_SecPeerVpnGUI)
	!endif
	!ifdef USE_TAP_WINDOWS
		!insertmacro MUI_DESCRIPTION_TEXT ${SecTAP} $(DESC_SecTAP)
	!endif
	!insertmacro MUI_DESCRIPTION_TEXT ${SecAddPath} $(DESC_SecAddPath)
	!insertmacro MUI_DESCRIPTION_TEXT ${SecAddShortcuts} $(DESC_SecAddShortcuts)
	!insertmacro MUI_DESCRIPTION_TEXT ${SecFileAssociation} $(DESC_SecFileAssociation)
!insertmacro MUI_FUNCTION_DESCRIPTION_END

;--------------------------------
;Uninstaller Section

Function un.onInit
	ClearErrors
	!insertmacro MULTIUSER_UNINIT
	SetShellVarContext all
	${If} "${ARCH}" == "x86_64"
		SetRegView 64
	${EndIf}
FunctionEnd

Section "Uninstall"

	; Stop peervpn-GUI if currently running
	DetailPrint "Stopping peervpn-GUI..."
	StopGUI:

	FindWindow $0 "peervpn-GUI"
	IntCmp $0 0 guiClosed
	SendMessage $0 ${WM_CLOSE} 0 0
	Sleep 100
	Goto StopGUI

	guiClosed:

	; Stop peervpn if currently running
	DetailPrint "Removing peervpn Service..."
	nsExec::ExecToLog '"$INSTDIR\bin\peervpnserv.exe" -remove'
	Pop $R0 # return value/error/timeout

	Sleep 3000

	!ifdef USE_TAP_WINDOWS
		ReadRegStr $R0 HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\${PACKAGE_NAME}" "tap"
		${If} $R0 == "installed"
			ReadRegStr $R0 HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\TAP-Windows" "UninstallString"
			${If} $R0 != ""
				DetailPrint "Uninstalling TAP..."
				nsExec::ExecToLog '"$R0" /S'
				Pop $R0 # return value/error/timeout
			${EndIf}
		${EndIf}
	!endif

	${un.EnvVarUpdate} $R0 "PATH" "R" "HKLM" "$INSTDIR\bin"

	!ifdef USE_PEERVPN_GUI
		Delete "$INSTDIR\bin\peervpn-gui.exe"
		Delete "$DESKTOP\${PACKAGE_NAME} GUI.lnk"
	!endif

	Delete "$INSTDIR\bin\peervpn.exe"
	Delete "$INSTDIR\bin\peervpnserv.exe"

	Delete "$INSTDIR\config\README.txt"

	Delete "$INSTDIR\log\README.txt"

	Delete "$INSTDIR\doc\license.txt"
;	Delete "$INSTDIR\doc\INSTALL-win32.txt"
	Delete "$INSTDIR\icon.ico"
	Delete "$INSTDIR\Uninstall.exe"

	RMDir "$INSTDIR\bin"
	RMDir "$INSTDIR\doc"
	RMDir "$INSTDIR\config"
	RMDir /r "$INSTDIR\log"
	RMDir "$INSTDIR"
	RMDir /r "$SMPROGRAMS\${PACKAGE_NAME}"

	!insertmacro DelRegKeyIfUnchanged HKCR ".${PEERVPN_CONFIG_EXT}" "${PACKAGE_NAME}File"
	DeleteRegKey HKCR "${PACKAGE_NAME}File"
	DeleteRegKey HKLM "SOFTWARE\${PACKAGE_NAME}"
	DeleteRegKey HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\${PACKAGE_NAME}"

SectionEnd

