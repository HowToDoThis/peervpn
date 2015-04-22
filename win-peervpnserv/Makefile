CFLAGS+=-DHAVE_CONFIG_H

ifneq (,$(findstring i686, $(CC)))
	CFLAGS+=-O2 -I/opt/mingw32/include
	LIBS+=
	RC=i686-w64-mingw32-windres
else ifneq (,$(findstring x86_64, $(CC)))
	CFLAGS+=-O2 -I/opt/mingw64/include 
	LIBS+=
	RC=x86_64-w64-mingw32-windres
endif

# Windows resource compiler: windres
INCLUDES=-I.
DEFS=-DHAVE_CONFIG_H
RCCOMPILE = $(RC) $(DEFS) $(DEFAULT_INCLUDES) $(INCLUDES) $(AM_CPPFLAGS) $(CPPFLAGS)

all: peervpnserv.exe

peervpnserv.exe: peervpnserv.o service.o peervpnserv_resources.rc.o
	$(CC) $(LDFLAGS) peervpnserv.o service.o peervpnserv_resources.rc.o $(LIBS) -o $@

peervpnserv.o: peervpnserv.c
service.o: service.c service.h

# Prevent circular dependency: %rc: ; <- override built-in rule for .o
%.rc: ;
%.rc.o: %.rc
	$(RCCOMPILE) -i "$<" -o "$@"	

clean:
	rm -f peervpnserv.exe peervpnserv.o peervpnserv_resources.rc.o service.o
