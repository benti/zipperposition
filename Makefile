# OASIS_START
# DO NOT EDIT (digest: 9a60866e2fa295c5e33a3fe33b8f3a32)

SETUP = ./setup.exe

build: setup.data $(SETUP)
	$(SETUP) -build $(BUILDFLAGS)

doc: setup.data $(SETUP) build
	$(SETUP) -doc $(DOCFLAGS)

test: setup.data $(SETUP) build
	$(SETUP) -test $(TESTFLAGS)

all: $(SETUP)
	$(SETUP) -all $(ALLFLAGS)

install: setup.data $(SETUP)
	$(SETUP) -install $(INSTALLFLAGS)

uninstall: setup.data $(SETUP)
	$(SETUP) -uninstall $(UNINSTALLFLAGS)

reinstall: setup.data $(SETUP)
	$(SETUP) -reinstall $(REINSTALLFLAGS)

clean: $(SETUP)
	$(SETUP) -clean $(CLEANFLAGS)

distclean: $(SETUP)
	$(SETUP) -distclean $(DISTCLEANFLAGS)
	$(RM) $(SETUP)

setup.data: $(SETUP)
	$(SETUP) -configure $(CONFIGUREFLAGS)

configure: $(SETUP)
	$(SETUP) -configure $(CONFIGUREFLAGS)

setup.exe: setup.ml
	ocamlfind ocamlopt -o $@ -linkpkg -package oasis.dynrun $< || ocamlfind ocamlc -o $@ -linkpkg -package oasis.dynrun $< || true
	$(RM) setup.cmi setup.cmo setup.cmx setup.o

.PHONY: build doc test all install uninstall reinstall clean distclean configure

# OASIS_STOP

INTERFACE_FILES = $(shell find src -name '*.mli')
IMPLEMENTATION_FILES = $(shell find src -name '*.ml')

tags:
	otags $(IMPLEMENTATION_FILES) $(INTERFACE_FILES)

dot:
	for i in *.dot; do dot -Tsvg "$$i" > "$$( basename $$i .dot )".svg; done

TARBALL=zipperposition.tar.gz

package: clean
	rm $(TARBALL) || true
	oasis setup
	tar cavf $(TARBALL) _oasis setup.ml configure myocamlbuild.ml _tags \
		Makefile pelletier_problems README.md src/ tests/ utils/

.PHONY: tags dot package

watch:
	while find src/ -name '*.ml*' -print0 | xargs -0 inotifywait -e delete_self -e modify ; do \
		echo "============ at `date` ==========" ; \
		make ; \
	done
