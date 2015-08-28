
# Code to perform docstring subtitutions.


"""
Extract all text within '{{' '}}' template pairs.
"""
function extract_substitution_text(text::UTF8String)
    substitution_text = Set{UTF8String}()
    substitution_pattern = r"{{(.*?)}}"
    for mat in eachmatch(substitution_pattern, text)
        push!(substitution_text, mat.captures[1])
    end
    return substitution_text
end


"""
Parse an expression that looks like 'A.B.C' into an array of symbols.
"""
function parse_import_arg(arg::UTF8String)
    symbols = Symbol[]
    ex = parse(arg)
    while true
        if isa(ex, Symbol)
            push!(symbols, ex)
            break
        elseif ex.head == :.
            push!(symbols, ex.args[2].value)
            ex = ex.args[1]
        else
            error(string("Invalid module: ", arg))
        end
    end
    reverse!(symbols)
    return symbols
end


"""
Print a method signature in markdown. A variation of the method show function in
Base.
"""
function method_signature_md(io::IO, m::Method)
    # TODO: link to package source here
    # TODO: implement code in headers in Markdown so we can say: ## `thing`
    println(io, "## ", m.func.code.name)
    println(io, "```{.julia execute=\"false\"}")
    print(io, m.func.code.name)
    tv, decls, file, line = Base.arg_decl_parts(m)
    if !isempty(tv)
        Base.show_delim_array(io, tv, '{', ',', '}', false)
    end
    print(io, "(")
    print_joined(io, [isempty(d[2]) ? d[1] : d[1]*"::"*d[2] for d in decls],
                 ", ", ", ")
    println(io, ")")
    println(io, "```")
end


"""
Get function docs in a usable format: a dict pointing methods to markdown
plaintext.
"""
function method_doc(f::Function)
    docs = Dict{Method, UTF8String}()
    for mod in Docs.modules
        if haskey(Docs.meta(mod), f)
            fd = Docs.meta(mod)[f]
            if isa(fd, Docs.FuncDoc)
                for m in fd.order
                    # delete leading function signature if it exists so we can
                    # actually handly this consistency, unlike base
                    md = fd.meta[m]
                    if length(fd.order) > 1
                        shift!(md.content)
                    end

                    docs[m] = utf8(Base.Markdown.plain(md))
                end
            end
        end
    end

    return docs
end


"""
Extract docstring text.
"""
function docstring_text(substitution_text::Set{UTF8String},
                        modules::Set{UTF8String})
    # TODO: is there a way to do this in a more contained manner?
    for mod in modules
        eval(:(import $(parse_import_arg(mod)...)))
    end

    docstrings = Dict{UTF8String, UTF8String}()
    for text in substitution_text
        # because docstring handling in julia is currently awful, we have to
        # manually get method signatures.
        ex = parse(text)
        val = eval(ex)
        out = IOBuffer()
        if isa(val, Function)
            ds = method_doc(val)
            for (meth, doc) in ds
                method_signature_md(out, meth)
                print(out, doc)
            end

            docstrings[text] = utf8(takebuf_string(out))
        else
            md = eval(:(@doc $(ex)))
            docstrings[text] = Base.Markdown.plain(md)
        end
    end

    return docstrings
end


