
module Judo

import Markdown, YAML


"""
Parse YAML frontmatter. Returns a `(metadata, position)` pair where `position`
is the first position following the metadata and `metadata` is `nothing` if
there was no metadata to parse.
"""
function parse_frontmatter(data::String)
    mat = match(r"\s*^---"xm, data)
    if mat == nothing
        return (nothing, 1)
    end
    yaml_start = mat.offset

    mat = match(r"\s*^\.\.\."xm, data)
    if mat == nothing
        return (nothing, 1)
    end
    yaml_end = mat.offset + length(mat.match) - 1

    metadata = YAML.load(data[yaml_start:yaml_end])
    if !isa(metadata, Dict)
        error("YAML frontmatter must be a mapping")
    end

    return (metadata, yaml_end + 1)
end


const attribute_pattern =
    r"(#\S+)|(\.\S+)|((\S+)=\"([^\"]*)\")"

"""
Loose, permissive parsing of pandoc-style code block attributes.
"""
function parse_codeblock_attributes(data::String)
    id = Nullable{UTF8String}()
    classes = UTF8String[]
    keyvals = Dict{UTF8String, UTF8String}()

    position = 1
    data = strip(data)
    if !isempty(data) && data[1] == '{'
        while true
            mat = match(attribute_pattern, data, position)
            if mat === nothing
                break
            end

            if mat.captures[1] != nothing
                if !isnull(id)
                    warn("Multiple ids in code black attributes: ", data)
                end
                id = Nullable{UTF8String}(convert(UTF8String, mat.captures[1]))
            elseif mat.captures[2] != nothing
                push!(classes, mat.captures[2])
            elseif mat.captures[3] != nothing
                keyvals[mat.captures[4]] = mat.captures[5]
            end

            position = mat.offset + length(mat.match)
        end
    else
        push!(classes, data)
    end

    return (id, classes, keyvals)
end


"""
Parse a markdown file with optional YAML frontmatter.
"""
function parse_markdown(data::String)
    metadata, position = parse_frontmatter(data)
    md = Markdown.parse(data[position:end])
    return metadata, md
end


function keyvals_bool(keyvals::Dict, key::String, default::Bool)
    val = get(keyvals, key, default ? "true" : "false")
    if val == "true"
        return true
    elseif val == "false"
        return false
    else
        error("Invalid value for $(key) attribute. Must be true or false.")
    end
end


function process(block::Markdown.Code, id::Nullable{UTF8String}, classes::Dict,
                 keyvals::Dict, doc_metadata::Dict)
    hide    = keyvals_bool(keyvals, "hide",    false)
    execute = keyvals_bool(keyvals, "execute", true)
    display = keyvals_bool(keyvals, "display", true)
    results = get(keyvals, "results", "block")

    if isempty(classes) || in("julia", classes)

    end
end


function process_code_block(::Type{MIME"text/x-julia"}, id::Nullable{UTF8String},
                            classes::Vector{UTF8String},
                            keyvals::Dict{UTF8String, UTF8String},
                            text::UTF8String)
    
end



# Supported code block classes.
const code_block_classes = Dict{ASCIIString, Type{MIME}}(
    "julia"    => MIME"text/x-julia",
    "svg"      => MIME"image/svg+xml",
    "graphviz" => MIME"text/vnd.graphviz",
    "latex"    => MIME"text/x-latex",
)


"""
A simple display to collect displayed values and convert markdown blocks.
"""
type ProcessedDoc <: Display
    blocks::Any[]

    function ProcessedDoc()
        return new(Any[])
    end
end


function Base.display(doc::ProcessedDoc, m::MIME"text/svg+xml", data)

end


"""
Take as input parsed markdown, process code blocks, and modify the document
representation in place.
"""
function process(doc::Markdown.MD, metadata::Dict)
    processed = ProcessedDoc()
    content = doc.content
    for block in content
        if isa(block, Markdown.Code)
            id, classes, keyvals = parse_codeblock_attributes(block.language)
            language = "julia"
            for class in classes
                if haskey(code_block_classes, class)
                    language = class
                    break
                end
            end

            hide    = keyvals_bool(keyvals, "hide",    false)
            execute = keyvals_bool(keyvals, "execute", true)
            display = keyvals_bool(keyvals, "display", true)

            if !hide
                push!(processed.blocks, Markdown.Code(language, block.code))
            end

            if execute
                block_result = process_code_block(code_block_classes[language], id,
                                                  classes, keyvals, block.code)

                # TODO: Super secret stdout/stderr capture technology

                push!(processed.blocks, block_result)
            end
        else
            push!(processed.blocks, block)
        end
    end

    return Markdown.MD(processed.blocks, doc.meta)
end


function process(filename::String)
    metadata, md = parse_markdown(readall(filename))
    md = process(md, metadata)

    # TODO: Now what? Output HTML?
    return md
end


end # module Judo

