
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
Extract docstring text.
"""
function docstring_text(substitution_text::Set{UTF8String},
                        modules::Set{UTF8String})
    # TODO: is there a way to do this in a more contained manner?
    for mod in modules
        eval(:(import $(parse_import_arg(mod)...)))
    end

    docstrings = Dict{UTF8String, UTF8String}()
    for ex in substitution_text
        # TODO: We have clashing Markdown definitions here. We need to use
        # Base.Markdown because that's what doc will give us. Probably we
        md = eval(:(@doc $(parse(ex))))
        docstrings[ex] = Base.Markdown.plain(md)
    end

    return docstrings
end


