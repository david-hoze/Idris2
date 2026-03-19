CC ?= gcc
CFLAGS = -O2 -I../refc -Wall -Wno-unused-label

REFC_SRCS = ../refc/memoryManagement.c ../refc/runtime.c \
            ../refc/casts.c ../refc/stringOps.c ../refc/prim.c \
            ../refc/buffer.c ../refc/mathFunctions.c ../refc/clock.c \
            ../refc/refc_util.c
ZAM_SRCS = zam_vm.c zam_prims.c zam_main.c

idris2-zam: $(ZAM_SRCS) $(REFC_SRCS) zam_vm.h
	$(CC) $(CFLAGS) -o $@ $(ZAM_SRCS) $(REFC_SRCS) -lgmp -lm

clean:
	rm -f idris2-zam

.PHONY: clean
