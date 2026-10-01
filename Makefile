CLANG ?= clang
CC = $(CLANG)
GENESIS ?= $(CURDIR)/genesis/rolangc
PREFIX ?= $(HOME)/.local
VERSION ?= 0.1.0
SOURCES := $(wildcard compiler/*.rl compiler/codegen/*.rl std/*.rl std/*.c std/*.h runtime/*.c runtime/*.h)

.PHONY: all rebuild release install clean
all: bin/rolangc

bin/rolangc: $(SOURCES) scripts/build.sh
	GENESIS="$(GENESIS)" CLANG="$(CLANG)" CC="$(CC)" ./scripts/build.sh

rebuild:
	GENESIS="$(GENESIS)" CLANG="$(CLANG)" CC="$(CC)" ./scripts/build.sh

release: bin/rolangc
	GENESIS="$(GENESIS)" VERSION="$(VERSION)" ./scripts/release.sh

install: bin/rolangc
	./scripts/install.sh "$(DESTDIR)$(PREFIX)"

clean:
	rm -rf build bin
