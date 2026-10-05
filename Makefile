CLANG ?= clang
CC = $(CLANG)
GENESIS ?= $(CURDIR)/genesis/rolangc
PREFIX ?= $(HOME)/.local
VERSION ?= 0.5.2
SOURCES := $(wildcard compiler/*.rl compiler/codegen/*.rl std/*.rl std/*.c std/*.h runtime/*.c runtime/*.h)

.PHONY: all rebuild release install clean bootstrap test check-selfhost
all: bin/rolangc

bin/rolangc: $(SOURCES) scripts/build.sh
	GENESIS="$(GENESIS)" CLANG="$(CLANG)" CC="$(CC)" ./scripts/build.sh

rebuild:
	GENESIS="$(GENESIS)" CLANG="$(CLANG)" CC="$(CC)" ./scripts/build.sh

release: bin/rolangc
	VERSION="$(VERSION)" ./scripts/release.sh

bootstrap:
	./scripts/bootstrap.sh

test: bin/rolangc
	ROLANGC="$(CURDIR)/bin/rolangc" ./scripts/test.sh

check-selfhost: bin/rolangc
	CLANG="$(CLANG)" ./scripts/check-selfhost.sh

install: bin/rolangc
	./scripts/install.sh "$(DESTDIR)$(PREFIX)"

clean:
	rm -rf build bin
