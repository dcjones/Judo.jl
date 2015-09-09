
# Turn a section name into an html id.
function section_id(section::String)
    # Keep only unicode letters, _ and -
    cleaned = replace(section, r"[^\p{L}_\-\s]", "")
    return lowercase(replace(cleaned, r"\s+", "-"))
end


"""
Convert a Markdown.Header with an id property to allow section links.
"""
function header_html{L}(header::Markdown.Header{L})
    text = string(header.text...)
    return Markdown.HTML(@sprintf("<h%d id=\"%s\">%s</h%d>", L, section_id(text), text, L))
end


"""
Parse YAML frontmatter. Returns a `(metadata, position)` pair where `position`
is the first position following the metadata and `metadata` is `nothing` if
there was no metadata to parse.
"""
function parse_frontmatter(data::String)
    mat = match(r"\s*^---"xm, data)
    if mat == nothing
        return (Dict(), 1)
    end
    yaml_start = mat.offset

    mat = match(r"\s*^\.\.\."xm, data)
    if mat == nothing
        return (Dict(), 1)
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
    sections = Markdown.Header[]
    for block in md.content
        if isa(block, Markdown.Header)
            push!(sections, block)
        end
    end
    return metadata, sections, md
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


"""
A simple display to collect displayed values and convert markdown blocks.
"""
type ProcessedDoc <: Display
    blocks::Vector{Any}

    function ProcessedDoc()
        return new(Any[])
    end
end


"""
Execude and display output from julia code blocks.
"""
function process_code_block(doc::ProcessedDoc,
                            ::Type{MIME"text/x-julia"},
                            display_result::Bool,
                            id::Nullable{UTF8String},
                            classes::Vector{UTF8String},
                            keyvals::Dict{UTF8String, UTF8String},
                            text::UTF8String)

    result = nothing
    for (cmd, ex) in parseit(strip(text))
        result = safeeval(ex)
    end

    if display_result && result != nothing
        display(doc, result)
    end
end


const supported_mime_types =
    [ MIME"text/html",
      MIME"image/svg+xml",
      MIME"image/png",
      MIME"text/latex",
      MIME"text/vnd.graphviz",
      MIME"text/plain" ]


# Supported code block classes.
const code_block_classes = Dict{ASCIIString, Type{MIME}}(
    "julia"    => MIME"text/x-julia",
    "svg"      => MIME"image/svg+xml",
    "graphviz" => MIME"text/vnd.graphviz",
    "latex"    => MIME"text/x-latex",
)


function Base.display(doc::ProcessedDoc, data)
    for m in supported_mime_types
        if mimewritable(m(), data)
            display(doc, m(), data)
            break
        end
    end
end


function Base.display(doc::ProcessedDoc, m::MIME"text/html", data)
    push!(doc.blocks, Markdown.HTML(stringmime(m, data)))
end


function Base.display(doc::ProcessedDoc, m::MIME"text/plain", data)
    push!(doc.blocks, Markdown.Paragraph(stringmime(m, data)))
end


const html_paragraph_pat = r"^<"



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
                process_code_block(processed,
                                   code_block_classes[language],
                                   !hide && display,
                                   id, classes, keyvals, block.code)
                # TODO: capture stdout/stderr ???
            end
        # manually convert headers to html so we can use header id's
        elseif isa(block, Markdown.Header)
            push!(processed.blocks, header_html(block))
        # treat paragraphs that start with an html tag as html
        elseif isa(block, Markdown.Paragraph) &&
               isa(block.content[1], String) &&
               match(html_paragraph_pat, block.content[1]) != nothing
            push!(processed.blocks, Markdown.HTML(string(block.content...)))
        else
            push!(processed.blocks, block)
        end
    end

    return Markdown.MD(processed.blocks, doc.meta)
end


function process(data::String, out::Nullable{IO};
                 template::Nullable{UTF8String}=Nullable{UTF8String}(),
                 toc::Bool=false,
                 outdir::UTF8String=utf8("."),
                 metadata::Dict{UTF8String, UTF8String}=Dict{UTF8String, UTF8String}())

    document_metadata, sections, md = parse_markdown(data)
    for (k, v) in metadata
        if !haskey(document_metadata, k)
            document_metadata[k] = v
        end
    end

    if !isnull(out)
        body = Markdown.html(process(md, metadata))
        if !isnull(template)
            document_metadata["body"] = body
            print(get(out), Mustache.render(get(template), document_metadata))
        else
            print(get(out), body)
        end
    end

    return document_metadata, sections
end

