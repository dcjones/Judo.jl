
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


# TODO: I have to figure out how to write method signatures for these
# abominations...
function method_signature_md(io::IO, name, t::Type)
    println(io, "\n```{.julia execute=\"false\"}")
    print(io, name)
    first = true
    print(io, "(")
    for typ in t.types
        if !first
            print(io, ", ")
        end
        print(io, "::", typ)
        first = false
    end
    println(io, ")")
    println(io, "```")
end


"""
Print a method signature in markdown. A variation of the method show function in
Base.
"""
function method_signature_md(io::IO, name, m::Method)
    # TODO: link to package source here
    # TODO: implement code in headers in Markdown so we can say: ## `thing`
    println(io, "\n```{.julia execute=\"false\"}")
    print(io, name)
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


function method_signature_md(io::IO, name, m::Expr)
    println(io, "\n```{.julia execute=\"false\"}")
    println(io, m)
    println(io, "```")
end


"""
Get function docs in a usable format: a dict pointing methods to markdown
plaintext.
"""
function method_doc(f::Union(Function, DataType), modules::Set{Module})
    docs = Dict{Any, UTF8String}()
    for mod in Docs.modules
        if !in(mod, modules)
            continue
        end

        if haskey(Docs.meta(mod), f)
            fd = Docs.meta(mod)[f]

            if isa(fd, Docs.FuncDoc) || isa(fd, Docs.TypeDoc)
                for m in fd.order
                    # delete leading function signature if it exists so we can
                    # actually handly this consistency, unlike base
                    md = fd.meta[m]
                    if isa(fd, Docs.FuncDoc) && length(fd.order) > 1
                        shift!(md.content)
                    end

                    docs[isa(fd, Docs.FuncDoc) ?  fd.source[m].args[1] : m] = utf8(Base.Markdown.plain(md))
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
                        modules_names::Set{UTF8String})
    # TODO: is there a way to do this in a more contained manner?
    modules = Set{Module}()
    for module_name in modules_names
        import_arg = parse_import_arg(module_name)
        eval(:(using $(import_arg...)))
        push!(modules, eval(import_arg[end]))
    end

    docstrings = Dict{UTF8String, UTF8String}()
    for text in substitution_text
        # because docstring handling in julia is currently awful, we have to
        # manually get method signatures.
        ex = parse(text)
        val = Any
        try
            val = eval(ex)
        catch
            warn("Could not evaluate docstring subsect \"$(text)\"")
            continue
        end

        #if isa(val, Function)
            #name = val.env.name
        #else
            #name = val.name.name
        #end
        name = text

        out = IOBuffer()

        if isa(val, Function) || isa(val, DataType)
            ds = method_doc(val, modules)
            println(out, "\n## ", name)
            for (meth, doc) in ds
                method_signature_md(out, name, meth)
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


