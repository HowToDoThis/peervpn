/***************************************************************************
 *   Copyright (C) 2016 by Tobias Volk                                     *
 *   mail@tobiasvolk.de                                                    *
 *                                                                         *
 *   This program is free software: you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation, either version 3 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 *   This program is distributed in the hope that it will be useful,       *
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of        *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *
 *   GNU General Public License for more details.                          *
 *                                                                         *
 *   You should have received a copy of the GNU General Public License     *
 *   along with this program.  If not, see <http://www.gnu.org/licenses/>. *
 ***************************************************************************/


#include <signal.h>
#include <stdio.h>
#include <openssl/engine.h>


#include "ethernet/switch.c"
#include "ethernet/ndp6.c"
#include "ethernet/virtserv.c"
#include "libp2psec/p2psec.c"
#include "platform/io.c"
#include "platform/ifconfig.c"
#include "platform/seccomp.c"
#include "globals.ic"
#include "console.ic"
#include "mainloop.ic"
#include "config.ic"
#include "pwd.ic"
#include "init.ic"

#ifndef MAIN_NAME
#define MAIN_NAME main
#endif

static char bufThrowError[4096];

// commandline parser
int MAIN_NAME(int argc, char **argv) {
	int confok;
	int conffd;
	int arglen;
	int i;
	struct s_initconfig config;

	// default configuration
	strcpy(config.tapname,"");
	strcpy(config.ifconfig4,"");
	strcpy(config.ifconfig6,"");
	strcpy(config.upcmd,"");
	strcpy(config.sourceip,"");
	strcpy(config.sourceport,"");
	strcpy(config.userstr,"");
	strcpy(config.groupstr,"");
	strcpy(config.chrootstr,"");
	strcpy(config.networkname,"PEERVPN");
	strcpy(config.initpeers,"");
	strcpy(config.engines,"");
	config.password_len = 0;
	config.enableeth = 1;
	config.enablendpcache = 0;
	config.enablevirtserv = 0;
	config.enablerelay = 0;
	config.enableindirect = 0;
	config.enableconsole = 0;
	config.enableseccomp = 0;
	config.forceseccomp = 0;
	config.enableprivdrop = 1;
	config.enableipv4 = 1;
	config.enableipv6 = 1;
	config.enablenat64clat = 0;
	config.sockmark = 0;

	setbuf(stdout,NULL);
	printf("PeerVPN v%d.%03d\n"
		"(c)2016 Tobias Volk <mail@tobiasvolk.de>\n"
		"\n"
		, PEERVPN_VERSION_MAJOR, PEERVPN_VERSION_MINOR
		);

	confok = 0;
	if(argc == 2) {
		arglen = 0;
		for(i=0; i<3; i++) {
			if(argv[1][i] == '\0') break;
			arglen++;
		}
		if(arglen > 0) {
			if(argv[1][0] == '-') {
				if(!((arglen > 1) && (argv[1][1] >= '!') && (argv[1][1] <= '~'))) {
					conffd = STDIN_FILENO;
					parseConfigFile(conffd,&config);
					confok = 1;
				}
			}
			else {
				memset(bufThrowError, 0, sizeof(bufThrowError));
				snprintf(bufThrowError, sizeof(bufThrowError)-1, "could not open config file! '%s'", argv[1]);

				if((conffd = (open(argv[1],O_RDONLY))) < 0) throwError(bufThrowError);
				parseConfigFile(conffd,&config);
				close(conffd);
				confok = 1;
			}
		}
	}

	if(confok > 0) {
		// start vpn node
		init(&config);
	}
	else {
		printf("usage: %s <configfile>\n", argv[0]);
	}

	return 0;
}
