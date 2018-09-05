#!/bin/sh

CFLAGS=-I/usr/local/include LDFLAGS=-L/usr/local/lib LIBS="-lcrypto -lz -lws2_32 -lgdi32" make $@
