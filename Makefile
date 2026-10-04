# Build both helper projects:
#   x11hook - LD_PRELOAD library that blocks deskflow's DPMS/screen-saver calls
#   tracer  - helper that logs exec calls to trace the real culprit binary

CC ?= gcc
GO ?= go

HOOK_SRC := x11hook/hook.c
HOOK_BIN := x11hook/x11hook.so

TRACER_DIR := tracer
TRACER_BIN := $(TRACER_DIR)/main
TRACER_SRC := $(TRACER_DIR)/main.go $(TRACER_DIR)/go.mod

X11_CFLAGS := -shared -fPIC
X11_LIBS := -ldl -lX11 -lXext

.PHONY: all x11hook tracer clean install

all: x11hook tracer

x11hook: $(HOOK_BIN)

$(HOOK_BIN): $(HOOK_SRC)
	$(CC) $(X11_CFLAGS) -o $@ $< $(X11_LIBS)

tracer: $(TRACER_BIN)

$(TRACER_BIN): $(TRACER_SRC)
	cd $(TRACER_DIR) && $(GO) build -o main .

clean:
	rm -f $(HOOK_BIN) $(TRACER_BIN)

install:
	./x11hook/install.sh
