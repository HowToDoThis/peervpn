/*
 *  OpenVPN -- An application to securely tunnel IP networks
 *             over a single TCP/UDP port, with support for SSL/TLS-based
 *             session authentication and key exchange,
 *             packet encryption, packet authentication, and
 *             packet compression.
 *
 *  Copyright (C) 2002-2010 OpenVPN Technologies, Inc. <sales@openvpn.net>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 2
 *  as published by the Free Software Foundation.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program (see the file COPYING included with this
 *  distribution); if not, write to the Free Software Foundation, Inc.,
 *  59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

/*
 * This program allows one or more OpenVPN processes to be started
 * as a service.  To build, you must get the service sample from the
 * Platform SDK and replace Simple.c with this file.
 *
 * You should also apply service.patch to
 * service.c and service.h from the Platform SDK service sample.
 *
 * This code is designed to be built with the mingw compiler.
 */

#ifdef HAVE_CONFIG_H
#include "config.h"
#elif defined(_MSC_VER)
#include "config-msvc.h"
#endif
#include <windows.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>
#include <process.h>
#include "service.h"

/* bool definitions */
#define bool int
#define true 1
#define false 0

/* These are new for 2000/XP, so they aren't in the mingw headers yet */
#ifndef BELOW_NORMAL_PRIORITY_CLASS
#define BELOW_NORMAL_PRIORITY_CLASS 0x00004000
#endif
#ifndef ABOVE_NORMAL_PRIORITY_CLASS
#define ABOVE_NORMAL_PRIORITY_CLASS 0x00008000
#endif

#define MAIN_NAME peer_vpn_main
#include "peervpn.c"

struct security_attributes
{
  SECURITY_ATTRIBUTES sa;
  SECURITY_DESCRIPTOR sd;
};

/*
 * This event is initially created in the non-signaled
 * state.  It will transition to the signaled state when
 * we have received a terminate signal from the Service
 * Control Manager which will cause an asynchronous call
 * of ServiceStop below.
 */
#define EXIT_EVENT_NAME PACKAGE "_exit_1"

/*
 * Which registry key in HKLM should
 * we get config info from?
 */
#define REG_KEY "SOFTWARE\\" PACKAGE_NAME

static HANDLE exit_event = NULL;

/* clear an object */
#define CLEAR(x) memset(&(x), 0, sizeof(x))

/*
 * Message handling
 */
#define M_INFO    (0)                                  /* informational */
#define M_SYSERR  (MSG_FLAGS_ERROR|MSG_FLAGS_SYS_CODE) /* error + system code */
#define M_ERR     (MSG_FLAGS_ERROR)                    /* error */

/* write error to event log */
#define MSG(flags, ...) \
        { \
           char x_msg[256]; \
           openvpn_snprintf (x_msg, sizeof(x_msg), __VA_ARGS__);      \
           AddToMessageLog ((flags), x_msg); \
        }

/* get a registry string */
#define QUERY_REG_STRING(name, data) \
  { \
    len = sizeof (data); \
    status = RegQueryValueEx(openvpn_key, name, NULL, &type, data, &len); \
    if (status != ERROR_SUCCESS || type != REG_SZ) \
      { \
        SetLastError (status); \
        MSG (M_SYSERR, error_format_str, name); \
	RegCloseKey (openvpn_key); \
	goto finish; \
      } \
  }

/* get a registry string */
#define QUERY_REG_DWORD(name, data) \
  { \
    len = sizeof (DWORD); \
    status = RegQueryValueEx(openvpn_key, name, NULL, &type, (LPBYTE)&data, &len); \
    if (status != ERROR_SUCCESS || type != REG_DWORD || len != sizeof (DWORD)) \
      { \
        SetLastError (status); \
        MSG (M_SYSERR, error_format_dword, name); \
	RegCloseKey (openvpn_key); \
	goto finish; \
      } \
  }

/*
 * This is necessary due to certain buggy implementations of snprintf,
 * that don't guarantee null termination for size > 0.
 * (copied from ../buffer.c, line 217)
 * (git: 100644 blob e2f8caab0a5b2a870092c6cd508a1a50c21c3ba3	buffer.c)
 */

int openvpn_snprintf(char *str, size_t size, const char *format, ...)
{
  va_list arglist;
  int len = -1;
  if (size > 0)
    {
      va_start (arglist, format);
      len = vsnprintf (str, size, format, arglist);
      va_end (arglist);
      str[size - 1] = 0;
    }
  return (len >= 0 && len < size);
}


bool
init_security_attributes_allow_all (struct security_attributes *obj)
{
  CLEAR (*obj);

  obj->sa.nLength = sizeof (SECURITY_ATTRIBUTES);
  obj->sa.lpSecurityDescriptor = &obj->sd;
  obj->sa.bInheritHandle = TRUE;
  if (!InitializeSecurityDescriptor (&obj->sd, SECURITY_DESCRIPTOR_REVISION))
    return false;
  if (!SetSecurityDescriptorDacl (&obj->sd, TRUE, NULL, FALSE))
    return false;
  return true;
}

HANDLE
create_event (const char *name, bool allow_all, bool initial_state, bool manual_reset)
{
  if (allow_all)
    {
      struct security_attributes sa;
      if (!init_security_attributes_allow_all (&sa))
	return NULL;
      return CreateEvent (&sa.sa, (BOOL)manual_reset, (BOOL)initial_state, name);
    }
  else
    return CreateEvent (NULL, (BOOL)manual_reset, (BOOL)initial_state, name);
}

void
close_if_open (HANDLE h)
{
  if (h != NULL)
    CloseHandle (h);
}

static bool
match (const WIN32_FIND_DATA *find, const char *ext)
{
  int i;

  if (find->dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
    return false;

  if (!strlen (ext))
    return true;

  i = strlen (find->cFileName) - strlen (ext) - 1;
  if (i < 1)
    return false;

  return find->cFileName[i] == '.' && !_stricmp (find->cFileName + i + 1, ext);
}

/*
 * Modify the extension on a filename.
 */
static bool
modext (char *dest, int size, const char *src, const char *newext)
{
  int i;

  if (size > 0 && (strlen (src) + 1) <= size)
    {
      strcpy (dest, src);
      dest [size - 1] = '\0';
      i = strlen (dest);
      while (--i >= 0)
	{
	  if (dest[i] == '\\')
	    break;
	  if (dest[i] == '.')
	    {
	      dest[i] = '\0';
	      break;
	    }
	}
      if (strlen (dest) + strlen(newext) + 2 <= size)
	{
	  strcat (dest, ".");
	  strcat (dest, newext);
	  return true;
	}
      dest [0] = '\0';
    }
  return false;
}

void startLoopThreadProc(void *pdata)
{
	MAIN_NAME(2, (char **)pdata);
}

int startLoop(char **pargs)
{
	return (_beginthread(&startLoopThreadProc, 0, pargs) != -1);
}

VOID ServiceStart (DWORD dwArgc, LPTSTR *lpszArgv)
{
  char exe_path[MAX_PATH];
  char config_dir[MAX_PATH];
  char ext_string[16];
  char log_dir[MAX_PATH];
  char priority_string[64];
  char append_string[2];

  DWORD priority;
  bool append;

  ResetError ();

  if (!ReportStatusToSCMgr(SERVICE_START_PENDING, NO_ERROR, 3000))
    {
      MSG (M_ERR, "ReportStatusToSCMgr #1 failed");
      goto finish;
    }

  /*
   * Create our exit event
   */
  exit_event = create_event (EXIT_EVENT_NAME, false, false, true);
  if (!exit_event)
    {
      MSG (M_ERR, "CreateEvent failed");
      goto finish;
    }

  /*
   * If exit event is already signaled, it means we were not
   * shut down properly.
   */
  if (WaitForSingleObject (exit_event, 0) != WAIT_TIMEOUT)
    {
      MSG (M_ERR, "Exit event is already signaled -- we were not shut down properly");
      goto finish;
    }

  if (!ReportStatusToSCMgr(SERVICE_START_PENDING, NO_ERROR, 3000))
    {
      MSG (M_ERR, "ReportStatusToSCMgr #2 failed");
      goto finish;
    }

  /*
   * Read info from registry in key HKLM\SOFTWARE\OpenVPN
   */
  {
    HKEY openvpn_key;
    LONG status;
    DWORD len;
    DWORD type;

    static const char error_format_str[] =
      "Error querying registry key of type REG_SZ: HKLM\\" REG_KEY "\\%s";

    static const char error_format_dword[] =
      "Error querying registry key of type REG_DWORD: HKLM\\" REG_KEY "\\%s";

    status = RegOpenKeyEx(
			  HKEY_LOCAL_MACHINE,
			  REG_KEY,
			  0,
			  KEY_READ,
			  &openvpn_key);

    if (status != ERROR_SUCCESS)
      {
	SetLastError (status);
	MSG (M_SYSERR, "Registry key HKLM\\" REG_KEY " not found");
	goto finish;
      }

    /* get path to openvpn.exe */
    QUERY_REG_STRING ("exe_path", exe_path);

    /* get path to configuration directory */
    QUERY_REG_STRING ("config_dir", config_dir);

    /* get extension on configuration files */
    QUERY_REG_STRING ("config_ext", ext_string);

    /* get priority for spawned OpenVPN subprocesses */
    QUERY_REG_STRING ("priority", priority_string);

    RegCloseKey (openvpn_key);
  }

  /* set process priority */
  priority = NORMAL_PRIORITY_CLASS;
  if (!_stricmp (priority_string, "IDLE_PRIORITY_CLASS"))
    priority = IDLE_PRIORITY_CLASS;
  else if (!_stricmp (priority_string, "BELOW_NORMAL_PRIORITY_CLASS"))
    priority = BELOW_NORMAL_PRIORITY_CLASS;
  else if (!_stricmp (priority_string, "NORMAL_PRIORITY_CLASS"))
    priority = NORMAL_PRIORITY_CLASS;
  else if (!_stricmp (priority_string, "ABOVE_NORMAL_PRIORITY_CLASS"))
    priority = ABOVE_NORMAL_PRIORITY_CLASS;
  else if (!_stricmp (priority_string, "HIGH_PRIORITY_CLASS"))
    priority = HIGH_PRIORITY_CLASS;
  else
    {
      MSG (M_ERR, "Unknown priority name: %s", priority_string);
      goto finish;
    }


	char configFile[MAX_PATH];
	char *arg1 = "peervpnservice.exe";
	char *arg2 = &configFile[0];
	char *peerargs[] = {arg1, arg2, NULL};

	openvpn_snprintf (configFile, MAX_PATH, "%s\\%s.%s", config_dir, "node", ext_string);

    if(startLoop(&peerargs[0]))
    {
	Sleep(1000);
	if(!ReportStatusToSCMgr(SERVICE_RUNNING, NO_ERROR, 0))
		MSG(M_ERR, "ReportStatusToSCMgr SERVICE_RUNNING failed")
	else if(WaitForSingleObject(exit_event, INFINITE) != WAIT_OBJECT_0)
		MSG(M_ERR, "wait for shutdown signal failed");
    }
    else
    	MSG(M_ERR, "Unable to start proccess thread");

 finish:
  ServiceStop ();
  if (exit_event)
    CloseHandle (exit_event);
}

VOID ServiceStop()
{
  if (exit_event)
    SetEvent(exit_event);
}
