
TARGET= peervpn
CFLAGS+=-O2
LIBS+=-lcrypto -lz

ifeq (,$(findstring mingw, $(CC)))
	TARGET=peervpn.exe
	LIBS+=-lgdi32 -lws2_32 -lcrypt32
	ifeq (,$(findstring i686, $(CC)))
		CFLAGS+=-I/opt/mingw32/include
	else ifneq (,$(findstring x86_64, $(CC)))
		CFLAGS+=-I/opt/mingw64/include
	endif
endif

all: $(TARGET)

$(TARGET): peervpn.o
	$(CC) $(LDFLAGS) peervpn.o -o $@ $(LIBS)

peervpn.o: peervpn.c

install:
	install peervpn /usr/local/sbin/peervpn
clean:
	rm -f $(TARGET) peervpn.o
