
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


# pattern used to find fileds in a function declaration comment
const func_field_pat = r"^\h*(Args|Returns|Modifies|Throws)\s*:\h*\r?\n"im


# Parse a function declaration comment
#
# Args:
#   input: Comment preceeding a funciton declaration, stripped of the leading
#          '#' characters.
#
# Returns:
#   A four-tuple of the form (description, args, returns, modifies, throws)
#
function parse_function_comment(input::String)
    mat = match(func_field_pat, input)
    if mat == nothing
        return (strip(input), nothing, nothing, nothing, nothing, nothing)
    end

    description = input[1:mat.offset-1]
    args = nothing
    returns = nothing
    modifies = nothing
    throws = nothing

    while mat != nothing
        typ = mat.captures[1]
        if typ == "Args"
            args = get_indented_block(input, mat.offset + length(mat.match))
            offset = mat.offset + length(args)
            args = parse_function_comment_args(args)
        elseif typ == "Returns"
            returns = strip(get_indented_block(input, mat.offset + length(mat.match)))
            offset = mat.offset + length(returns)
        elseif typ == "Modifies"
            modifies = strip(get_indented_block(input, mat.offset + length(mat.match)))
            offset = mat.offset + length(modifies)
        elseif typ == "Throws"
            throws = strip(get_indented_block(input, mat.offset + length(mat.match)))
            offset = mat.offset + length(throws)
        end

        mat = match(func_field_pat, input, offset)
    end

    (strip(description), args, returns, modifies, throws)
end


# pattern to match argument names/descriptions.
const arg_desc_pat = r"^(\h*)([\w_][\w\d_\!]*)\h*:\h*(.*)\r?"m


# Parse the "Args" section of a function declaration comment.
#
# Args:
#   input: Everything under the "Args" block.
#
# Returns:
#   A dictionary mapping arugment names to their descriptions.
#
function parse_function_comment_args(input::String)
    args = Dict()
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
            println(STDERR, (next_line_indent, indent))
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

