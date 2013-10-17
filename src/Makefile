
all:frag
	@echo If you want to install frag, please run the following command:
	@echo PREFIX=/path/to/your/prefix make install

# Re will eventually replace Str.

frag.byte:fragment.ml fragment_main.ml
	ocamlfind ocamlc -thread -package str,re,core,mpp -linkpkg -o $@ fragment.ml fragment_main.ml

# Default uses ocamlopt because the Core library makes bytecode binaries too fat and too slow to load.
frag:frag.opt

frag.opt:fragment.ml fragment_main.ml
	ocamlfind ocamlopt -thread -package str,re,core,mpp -linkpkg -o $@ fragment.ml fragment_main.ml

install:frag.opt
	cp frag.opt ${PREFIX}/bin/frag

