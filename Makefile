ifneq (,$(findstring mingw, $(CC)))
	TARGET := peervpn.exe
	ifneq (,$(findstring i686, $(CC)))
		CFLAGS+=-O2 -I/opt/mingw32/include
		LIBS+=-lcrypto -lz -lgdi32 -lws2_32 -lcrypt32
	else ifneq (,$(findstring x86_64, $(CC)))
		CFLAGS+=-O2 -I/opt/mingw64/include
		LIBS+=-lcrypto -lz -lgdi32 -lws2_32 -lcrypt32
	endif
else
	TARGET := peervpn
	CFLAGS+=-O2
	LIBS+=-lcrypto -lz
endif

all: $(TARGET)
$(TARGET): peervpn.o
	$(CC) $(LDFLAGS) peervpn.o $(LIBS) -o $@
peervpn.o: peervpn.c

clean:
	rm -f $(TARGET) peervpn.o
