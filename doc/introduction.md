---
title: Getting Started
author: Daniel Jones
...

Judo is a Julia document generator. It takes documents written in
[pandoc markdown](http://johnmacfarlane.net/pandoc/README.html#pandocs-markdown)
and converts them into html, but differs from general purpose markdown tools in
a few ways.

  1. Code blocks can be executed and their results inlined in the document,
     including plots and graphics.
  2. Metadata can be attached to a document in the form of YAML front-matter
     (similar to Jekyll).
  3. Multiple documents can be compiled and cross-linked.
  4. Function and types comments can be parsed from Julia source code and
     included in a document.

The end goal is to make documenting Julia code, whether it be a package, or some
quick-and-dirty analysis, as painless as possible.


# Installing

Judo can be installed like a regular Julia package, but is used somewhat
differently.

```{.julia execute="false"}
Pkg.add("Judo")
```

An executable `judo` script is now installed to
`joinpath(Pkg.dir("Judo"), "bin")` (typically `~/.julia/Judo/bin/judo`), which
you may want to add to your `PATH` variable.


# Using

`judo -h` will give you some idea of how Judo is invoked.




