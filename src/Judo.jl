
module Judo

import JSON
import YAML


# Pattern used to extract YAML metadata from the front on input documents.
const frontmatter_pattern = r"\A\s*^---$.*^\.\.\.$"sm

# An iterator for the parse function: parsit(source) will iterate over the
# expressiosn in a string.
type ParseIt
    value::String
end


function parseit(value::String)
    ParseIt(value)
end


function start(it::ParseIt)
    1
end


function next(it::ParseIt, pos)
    (ex,newpos) = Base.parse(it.value, pos)
    ((it.value[pos:(newpos-1)], ex), newpos)
end


function done(it::ParseIt, pos)
    pos > length(it.value)
end


# A super-simple pandoc interface.
#
# Args:
#   input: Input string.
#   infmt: Input format.
#   outfmt: Output format.
#   args: Additional arguments appended to the pandoc command.
#
# Returns:
#   A string containing the output from pandoc.
#
function pandoc(input::String, infmt::Symbol, outfmt::Symbol, args::String...)
    cmd = ByteString["pandoc",
                     "--from=$(string(infmt))",
                     "--to=$(string(outfmt))"]
    if !isempty(args)
        append!(cmd, args)
    end
    pandoc_out, pandoc_in, proc = readandwrite(Cmd(cmd))
    write(pandoc_in, input)
    close(pandoc_in)
    readall(pandoc_out)
end


# Convert a string to a structure interpretable by pandoc json parser.
function string_to_pandoc_json(s::String)
    out = {}
    for mat in eachmatch(r"\S+", s)
        if !isempty(out)
            push!(out, "Space")
        end
        push!(out, ["Str" => mat.match])
    end
    out
end


# Transform a annotated markdown file into a variety of formats.
#
# This reads markdown input, optionally prefixed with a YAML metadata document,
# and transforms in into a document in the desired output format, while
# executing code blocks and inserting results into the document.
#
# Args:
#   input: An input source.
#   output: Where the resulting document should be written.
#   outfmt: One of the output formats supported by pandoc:
#       Eg. markdown, rst, html, json, latex.
#
function weave(input::IO, output::IO; outfmt=:html5)
    input_text = readall(input)

    # parse yaml front matter
    mat = match(frontmatter_pattern, input_text)
    metadata = nothing
    if !is(mat, nothing)
        metadata = YAML.load(mat.match)
        input_text = input_text[1+length(mat.match):]
    end


    # first pandoc pass
    pandoc_metadata, document = JSON.parse(pandoc(input_text, :markdown, :json))
    processed_document = {}

    for block in document
        # TODO: everything
        push!(processed_document, block)
    end

    # splice in metadata fields that pandoc supports
    pandoc_metadata_keys = ["title"   => "docTitle",
                            "authors" => "docAuthors",
                            "author"  => "docAuthors",
                            "date"    => "docDate"]

    for (key, pandoc_key) in pandoc_metadata_keys
        if haskey(metadata, key)
            if key == "author"
                pandoc_metadata[pandoc_key] =
                    {string_to_pandoc_json(metadata[key])}
            elseif key == "authors"
                if typeof(metadata[key]) <: AbstractArray
                    pandoc_metadata[pandoc_key] =
                        {string_to_pandoc_json(author)
                         for author in metadata[key]}
                else
                    pandoc_metadata[pandoc_key] =
                        {string_to_pandoc_json(metadata[key])}
                end
            else
                pandoc_metadata[pandoc_key] =
                    string_to_pandoc_json(metadata[key])
            end
        end
    end

    # second pandoc pass
    buf = IOBuffer()
    JSON.print(buf, {pandoc_metadata, processed_document})
    write(output, pandoc(takebuf_string(buf), :json, outfmt))
end


end


