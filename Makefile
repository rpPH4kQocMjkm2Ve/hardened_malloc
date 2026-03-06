TAG      := 2026020600
NPROC    := $(shell nproc)
DESTDIR  ?=
SRCDIR   := hardened_malloc
PREFIX   := /usr/local
SYSCONFDIR := /etc

.PHONY: build install uninstall clean

build:
	git clone --depth 1 --branch $(TAG) \
		https://github.com/GrapheneOS/hardened_malloc.git $(SRCDIR)
	$(MAKE) -C $(SRCDIR) -j$(NPROC)
	$(MAKE) -C $(SRCDIR) -j$(NPROC) VARIANT=light
	gcc -shared -fPIC -O2 -o libfake_rlimit.so fake_rlimit.c -ldl

install:
	install -Dm644 $(SRCDIR)/out/libhardened_malloc.so \
		$(DESTDIR)$(PREFIX)/lib/libhardened_malloc.so
	install -Dm644 $(SRCDIR)/out-light/libhardened_malloc-light.so \
		$(DESTDIR)$(PREFIX)/lib/libhardened_malloc-light.so
	install -Dm644 libfake_rlimit.so \
		$(DESTDIR)$(PREFIX)/lib/libfake_rlimit.so
	install -Dm644 ld.so.preload \
		$(DESTDIR)$(SYSCONFDIR)/ld.so.preload

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/lib/libhardened_malloc.so
	rm -f $(DESTDIR)$(PREFIX)/lib/libhardened_malloc-light.so
	rm -f $(DESTDIR)$(PREFIX)/lib/libfake_rlimit.so
	rm -f $(DESTDIR)$(SYSCONFDIR)/ld.so.preload
	@echo "Note: run 'ldconfig' if needed."

clean:
	rm -rf $(SRCDIR) libfake_rlimit.so
