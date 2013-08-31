
Judo is a Julia document generator. It takes documents written in
[pandoc markdown](http://johnmacfarlane.net/pandoc/README.html#pandocs-markdown)
and converts them into html, but differs from general purpose markdown tools in
a few ways.

  1. Code blocks can be executed and their results, including graphics, inlined
     in the document.
  2. Metadata can be attached to a document in the form of YAML front-matter
     (similar to Jekyll).
  3. Multiple documents can be compiled and cross-linked.
  4. Function and types comments can be parsed from Julia source code and
     included in a document. (Note: this is not fully implemented yet)

The end goal is to make documenting Julia code, whether it be a package, or some
quick-and-dirty analysis, as painless as possible.


# Status

This is work in progress. I'm using it to generate [documentation for
Gadfly](http://dcjones.github.io/Gadfly.jl/), and figuring out the details as I
go along. Contributions or feedback is welcomed.


