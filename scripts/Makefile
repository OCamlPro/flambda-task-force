WARN=+1..45-4-44-42

all:
	ocamlbuild main.native -j 100 -tag debug -tag principal -tag bin_annot -tag "warn($(WARN))" -package str -package unix

filter:
	ocamlbuild filter.native -j 100 -tag debug -tag principal -tag bin_annot -tag "warn($(WARN))" -package str -package unix

table:
	ocamlbuild table.native -j 100 -tag debug -tag principal -tag bin_annot -tag "warn($(WARN))" -package str -package unix

clean:
	ocamlbuild -clean
