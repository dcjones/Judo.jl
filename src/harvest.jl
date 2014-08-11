
using DataStructures

# Parse function and type documentation from julia source files.


# Metadata parsed from a declarations's preceeding comment.
type DeclarationComment
    decltype::String
    description::String
    args::Union(OrderedDict, Nothing)
    sections::Dict

    function DeclarationComment(decltype, description)
        new(decltype, description, nothing, Dict())
    end
end


# pattern to extract comments immediately preceeding declarations:
const decl_comment_pat =
    r"
    ((?:\h*\#[^\n]*\n)+)
    \h*(function|macro|immutable|abstract|type|const)\s+([A-Za-z_][A-Za-z0-9_?!]*)
    "xm

# pattern to extract comments immediately preceeding
# assignment style function declarations.
const compact_decl_comment_pat =
    r"
    ((?:\h*\#[^\n]*\n)+)              # comments
    \h*([A-Za-z_][A-Za-z0-9_?!]*)     # function name
    \h*((?:\{(?:[^{}]++|(?-1))*+\})?) # type parameters (balanced braces)
    \h*(\((?:[^()]++|(?-1))*+\))      # balanced parenthesis
    \h*=[^=]                          # assignment and not ==
    "xm

# pattern to strip leading whitespace and '#' characters from comments.
const comment_strip_pat = r"\h*\#+"


# Extract comments immediately preceeding declarations.
#
# Args:
#   input: Text which is expected to be julia source code.
#
# Returns:
#   A three-tuple of the form (decltype, name, comment), where
#   decltype is one of "function", "immutable", "type".
#
function extract_declaration_comments(input::String)
    mats = {}
    comment_strip(txt) = replace(txt, comment_strip_pat, "")

    for mat in eachmatch(decl_comment_pat, input)
        push!(mats, (mat.captures[2], mat.captures[3], comment_strip(mat.captures[1])))
    end

    for mat in eachmatch(compact_decl_comment_pat, input)
        push!(mats, ("function", mat.captures[2], comment_strip(mat.captures[1])))
    end
    mats
end


# Harvest declaration comments from a package
#
# Args:
#   package: Name of a currently installed package.
#
# Returns:
#   A dictionary mapping declared identifiers to DeclarationComment objects.
#
function harvest(package::String)
    srcdir = joinpath(Pkg.dir(package), "src")
    filenames = {}
    for filename in walkdir(srcdir)
        if match(r"\.jl$", filename) != nothing
            push!(filenames, filename)
        end
    end
    harvest(filenames)
end


# Extract and parse decleration-preceeding comments from a set of files.
#
# Args:
#   filename: Names of julia source files to harvest from.
#
# Returns:
#   A dictionary mapping declared identifiers to DeclarationComment objects.
#
function harvest(filenames::Vector)
    declarations = Dict()
    for filename in filenames
        for (decltype, name, comment) in extract_declaration_comments(readall(filename))
            if decltype == "macro"
                name = string("@", name)
            end
            declarations[name] = parse_comment(decltype, comment)
        end
    end
    declarations
end


# Return a substring of input that is of equal or greater indentation than the
# line starting at i.
function get_indented_block(input::String, i::Integer=1)
    output = IOBuffer()
    n = length(input)
    block_indent = 0
    while i < n && (input[i] == ' ' || input[i] == '\t')
        block_indent += 1
        write(output, input[i])
        i = nextind(input, i)
    end

    j = search(input, '\n', i)
    if j == 0
        j = n
    end

    write(output, input[i:j])
    i = nextind(input, j)

    while i < n
        j = i
        line_indent = 0
        while j < n && (input[j] == ' ' || input[j] == '\t')
            line_indent += 1
            j = nextind(input, j)
        end

        k = search(input, '\n', j)
        if k == 0
            k = n
        end

        if line_indent < block_indent && j < k
            break
        end

        write(output, input[i:k])
        i = nextind(input, k)
    end
    takebuf_string(output)
end


# TODO: We should not just take fixed section names. Anything should be allowed.
# pattern used to find fileds in a function declaration comment
const func_field_pat = r"^\h*(Args|Returns|Modifies|Throws)\s*:\h*\r?\n"im


# Parse a function declaration comment
#
# Args:
#   input: Comment preceeding a funciton declaration, stripped of the leading
#          '#' characters.
#
# Returns:
#   A DeclarationComment object.
#
function parse_comment(decltype, input::String)
    mat = match(func_field_pat, input)
    if mat == nothing
        return DeclarationComment(decltype, strip(input))
    end

    metadata = DeclarationComment(decltype, input[1:mat.offset-1])
    while mat != nothing
        typ = mat.captures[1]
        if typ == "Args"
            args = get_indented_block(input, mat.offset + length(mat.match))
            offset = mat.offset + length(args)
            metadata.args = parse_comment_args(args)
        else
            section = strip(get_indented_block(input, mat.offset + length(mat.match)))
            metadata.sections[typ] = section
            offset = mat.offset + length(section)
        end

        mat = match(func_field_pat, input, offset)
    end

    metadata
end


# pattern to match argument names/descriptions.
const arg_desc_pat = r"^(\h*)([\w_][\w\d_\!]*(?:\.\.\.)?)\h*:\h*(.*)\r?"m


# Parse the "Args" section of a function declaration comment.
#
# Args:
#   input: Everything under the "Args" block.
#
# Returns:
#   A dictionary mapping arugment names to their descriptions.
#
function parse_comment_args(input::String)
    args = OrderedDict()
    mat = match(arg_desc_pat, input)
    while mat != nothing
        indent = length(mat.captures[1])
        name = mat.captures[2]
        desc = IOBuffer()
        write(desc, mat.captures[3])

        offset = mat.offset + length(mat.match)
        if offset < length(input) && input[offset] == '\n'
            offset = nextind(input, offset)
            next_line_indent = 0
            i = offset
            while i < length(input) && (input[i] == ' ' || input[i] == '\t')
                next_line_indent += 1
                i = nextind(input, i)
            end
            if next_line_indent > indent
                desc_rest = get_indented_block(input, offset)
                write(desc, desc_rest)
                offset += length(desc_rest)
            end
        end

        args[name] = takebuf_string(desc)
        mat = match(arg_desc_pat, input, offset)
    end

    args
end


# Generate markdown for each declaration comment.
function generate_declaration_markdown(declarations::Dict)
    declaration_markdown = Dict()
    for (name, comment) in declarations
        out = IOBuffer()

        # TODO: in pandoc > 1.10 we can apply a class directly to a header
        println(out, "<div class=\"api-doc\">")

        println(out, comment.description)

        if comment.args != nothing
            println(out, "\n#### Args")
            for (arg_name, arg_desc) in comment.args
                @printf(out, "  * `%s`: %s\n", arg_name, arg_desc)
            end
        end

        for (section_name, section_content) in comment.sections
            println(out, "\n#### ", section_name)
            println(out, section_content)
        end

        println(out, "</div>")

        declaration_markdown[name] = takebuf_string(out)
    end
    declaration_markdown
end


# Insert function declaration comments into a markdown document.
function expand_declaration_docs(input::String, declaration_markdown::Dict)
    Mustache.render(input, declaration_markdown)
end




