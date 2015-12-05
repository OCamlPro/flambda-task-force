WARN=+1..45-4-44-42

all:
	ocamlbuild main.native -j 100 -tag debug -tag principal -tag bin_annot -tag "warn($(WARN))" -package str -package unix

filter:
	ocamlbuild filter.native -j 100 -tag debug -tag principal -tag bin_annot -tag "warn($(WARN))" -package str -package unix

table:
	ocamlbuild table.native -j 100 -tag debug -tag principal -tag bin_annot -tag "warn($(WARN))" -package str -package unix

clean:
	ocamlbuild -clean
	rm bench2html bench2html.cm* becn2html.o

bench2html: bench2html.ml
	ocamlfind ocamlopt -package cow,cow.syntax,operf-macro -linkpkg -syntax camlp4o $^ -o $@

benchwww: benchwww.ml
	ocamlfind ocamlopt -package cow,cow.syntax,lwt,cohttp.lwt,operf-macro -linkpkg -syntax camlp4o $^ -o $@

opamjson2html: opamjson2html.ml
	ocamlfind ocamlopt -package yojson,re -linkpkg $< -o $@
