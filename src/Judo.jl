
module Judo

import Base: start, next, done, display, writemime
import JSON
import Mustache

include("walkdir.jl")
include("harvest.jl")
include("collate.jl")

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


# A special dummy module in which a documents code is executed.
module WeaveSandbox
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
    for arg in args
        push!(cmd, arg)
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
            push!(out, {"t" => "Space", "c" => {}})
        end
        push!(out, {"t" => "Str", "c" => mat.match})
    end
    out
end


# A Display implementation that renders multimedia into the document currently
# being processed.
type WeaveDoc <: Display
    # JSON respresentation of the document being built up.
    blocks::Array

    # Queued output from display calls
    display_blocks::Array

    # Document name (used for naming any external files generated)
    name::String

    # Output formal
    outfmt::Symbol

    # Current figure number
    fignum::Int

    # Redirected stdout
    stdout_read
    stdout_write

    # Output directory
    outdir::String

    function WeaveDoc(name::String, outfmt::Symbol, stdout_read, stdout_write,
                      outdir::String)
        new({}, {}, name, outfmt, 1, stdout_read, stdout_write, outdir)
    end
end


# Display functions that render output and insert them into the document.

const supported_mime_types =
    { MIME"text/html",
      MIME"image/svg+xml",
      MIME"image/png",
      MIME"text/latex",
      MIME"text/vnd.graphviz",
      MIME"text/plain" }


function display(doc::WeaveDoc, data)
    for m in supported_mime_types
        if mimewritable(m(), data)
            display(doc, m(), data)
            break
        end
    end
end


function display(doc::WeaveDoc, m::MIME"text/plain", data)
    block =
        {"t" => "CodeBlock",
         "c" => {{"", {"output"}, {}}, stringmime(m, data)}}
    push!(doc.display_blocks, block)
end


function display(doc::WeaveDoc, m::MIME"text/latex", data)
    # latex to dvi
    input_path, input = mktemp()
    writemime(input, m, data)
    flush(input)
    seek(input, 0)
    latexout_dir = mktempdir()
    run(`latex -output-format=dvi -output-directory=$(latexout_dir) $(input_path)` |> SpawnNullStream())
    rm(input_path)

    # dvi to svg
    latexout_path = "$(latexout_dir)/$(basename(input_path)).dvi"
    output = readall(`dvisvgm --stdout --no-fonts $(latexout_path)` .> SpawnNullStream())
    run(`rm -rf $(latexout_dir)`)

    display(doc, MIME("image/svg+xml"), output)
end


function display(doc::WeaveDoc, m::MIME"image/svg+xml", data)
    filename = @sprintf("%s_figure_%d.svg", doc.name, doc.fignum)
    out = open(joinpath(doc.outdir, filename), "w")
    writemime(out, m, data)
    close(out)

    alttext = @sprintf("Figure %d", doc.fignum)
    figurl = filename
    caption = ""

    if doc.outfmt == :html || doc.outfmt == :html5
        block =
            {"t" => "RawBlock",
             "c" => {"html",
               """
               <figure>
                 <object alt="$(alttext)" data="$(figurl)" type="image/svg+xml">
                 </object>
                 <figcaption>
                   $(caption)
                 </figcaption>
               </figure>
               """}}
    else
        block =
            {"t" => "Para",
             "c" => {
                {"t" => "Image",
                 "c" => {{{"Str" => alttext}},
                 {figurl, ""}}}}}
    end

    doc.fignum += 1
    push!(doc.display_blocks, block)
end


function display(doc::WeaveDoc, m::MIME"image/png", data)
    filename = @sprintf("%s_figure_%d.png", doc.name, doc.fignum)
    out = open(joinpath(doc.outdir, filename), "w")
    writemime(out, m, data)
    close(out)

    alttext = @sprintf("Figure %d", doc.fignum)
    figurl = filename
    caption = ""

    block =
        {"t" => "Para",
         "c" => {
            {"t" => "Image",
             "c" => {{{"t" => "Str", "c" => alttext}},
                     {figurl, ""}}}}}

    doc.fignum += 1
    push!(doc.display_blocks, block)
end


function display(doc::WeaveDoc, m::MIME"text/vnd.graphviz", data)
    output, input, proc = readandwrite(`dot -Tsvg`)
    writemime(input, m, data)
    close(input)
    display(doc, MIME("image/svg+xml"), readall(output))
end


function display(doc::WeaveDoc, m::MIME"text/html", data)
    block = {"t" => "RawBlock",
             "c" =>  {"html",
                string("<div class=\"judo-result\">\n", stringmime(m, data), "\n</div>")}}
    push!(doc.display_blocks, block)
end


# This is maybe an abuse. TODO: This is going to be a problem.
writemime(io, m::MIME"text/vnd.graphviz", data::String) = write(io, data)
writemime(io, m::MIME"image/vnd.graphviz", data::String) = write(io, data)
writemime(io, m::MIME"image/svg+xml", data::String) = write(io, data)
writemime(io, m::MIME"text/latex", data::String) = write(io, data)


# Turn YAML frontmatter parsed by pandoc into simplified julia structure.
#
# Args:
#   pandoc_metadata: YAML fontmatter parsed by pandoc then by JSON
#
# Returns:
#   A (String => String) dictionary with key value pairs.
#
function flatten_pandoc_metadata(pandoc_metadata::Dict)
    metadata = Dict{String, String}()
    for (key, val) in pandoc_metadata["unMeta"]
        if val["t"] == "MetaInlines"
            metadata[key] = flatten_pandoc_metainlines(val["c"])
        elseif val["t"] == "MetaString"
            metadata[key] = val["c"]
        end
    end
    return metadata
end


function flatten_pandoc_metainlines(pandoc_metainlines::Vector)
    buf = IOBuffer()
    for val in pandoc_metainlines
        if val["t"] == "Str"
            write(buf, val["c"])
        elseif val["t"] == "Space"
            write(buf, " ")
        end
    end
    return takebuf_string(buf)
end


# Strip parsed pandoc JSON to a plain text representation.
function plaintext(blocks::Array)
    buf = IOBuffer()
    atstart = true
    for block in blocks
        if block["t"] == "Space"
            write(buf, " ")
        elseif block["t"] == "Str"
            write(buf, block["c"])
        elseif block["t"] == "Cite"
            write(buf, plaintext(block["c"][2]))
        end
        atstart = false
    end
    return takebuf_string(buf)
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
#   name: A short name for the document used for naming output files.
#
# Returns:
#   A pair (metadata, sections) where
#   `metadata` is metadata parsed from the YAML front matter if any, and
#   `sections` is an array of section/subsection names in the order in which
#   they occur. Each section name is a pair (level, name) where `level` an
#   integer giving the section level (1 is a section, 2 a sub-section, etc).
#
function weave(input::IO, output::IO;
               outfmt=:html5, name="judo", template=nothing,
               toc::Bool=false, outdir::String=".", dryrun::Bool=false,
               keyvals::Dict=Dict(),
               pandocargs=nothing)
    input_text = readall(input)

    # first pandoc pass
    pandoc_metadata, document =
        JSON.parse(pandoc(input_text, :markdown, :json))
    metadata = flatten_pandoc_metadata(pandoc_metadata)
    pandoc_metadata = pandoc_metadata["unMeta"]
    prev_stdout = STDOUT
    stdout_read, stdout_write = redirect_stdout()
    doc = WeaveDoc(name, outfmt, stdout_read, stdout_write, outdir)
    pushdisplay(doc)

    sections = {}

    for block in document
        if block["t"] == "Header"
            level = block["c"][1]
            headername = plaintext(block["c"][3])
            push!(sections, (level, headername))
            if !dryrun
                push!(doc.blocks, process_block(block))
            end
        elseif dryrun
            continue
        elseif block["t"] == "CodeBlock"
            try
                process_code_block(doc, block)
            catch err
                error("Error processing codeblock in document $(name):\n$(string(err))")
            end
        else
            push!(doc.blocks, process_block(block))
        end
    end

    if dryrun
        return metadata, sections
    end

    popdisplay(doc)
    redirect_stdout(prev_stdout)
    #Base.reinit_stdio()

    # second pandoc pass
    buf = IOBuffer()

    # splice the document's creation date into pandoc's metadata
    pandoc_metadata["today"] =
        {"t" => "MetaInlines",
         "c" => {{"t" => "Str",
                  "c" => strip(readall(`date`))}}}

    JSON.print(buf, {{"unMeta" => pandoc_metadata}, doc.blocks})

    args = {}
    for (k, v) in keyvals
        push!(args, "--variable=$(k):$(v)")
    end

    if template != nothing
        push!(args, "--template=$(template)")
    end

    if toc
        push!(args, "--toc")
    end

    if pandocargs != nothing
        push!(args, pandocargs)
    end

    write(output, pandoc(takebuf_string(buf), :json, outfmt, args...))

    metadata, sections
end


# Evaluate the truthiness of a code block attribute.
function codeblock_keyval_bool(keyvals::Dict, key, default::Bool)
    if haskey(keyvals, key)
        val = lowercase(strip(keyvals[key]))
        @assert val == "true" || val == "false"
        val == "true"
    else
        default
    end
end


# Process a text paragraph.
#
# Args:
#   block: Block parsed from the json document representation.
#
# Modifies:
#    block, prior to inserting it into doc
#
# Returns:
#   block
#
#function process_block(block::Dict)
    #if block["t"] == "Code"
        #(id, classes, keyvals), text = block["c"]
        #if "julia" in classes
            #out = eval(WeaveSandbox, parse(text))
            #block["c"] = string(out)
        #end
    #else
        #block["c"] = process_block(block["c"])
    #end
    #return block
#end


#function process_block(block::Array)
    #for i in 1:length(block)
        #block[i] = process_block(block[i])
    #end
    #block
#end


function process_block(block::Any)
    block
end



# Code block classes supported.
const code_block_classes = Set(
    ["julia",
     "graphviz",
     "latex",
     "svg"])



# Process code blocks.
#
# This consists of (optioclasses =ally) executing code and inserting the results into
# the document.
#
# Args:
#   doc: Document being generated.
#   block:: Code block.
#
function process_code_block(doc::WeaveDoc, block::Dict)
    (id, classes, keyvals_array), text = block["c"]
    keyvals = [k => v for (k, v) in keyvals_array]

    # Options are:
    #
    #  hide: Don't show the code block. (defaut: false)
    #  execute: Do excute the code block. (default: true)
    #  display: Do display output. (default: true)
    #  results:
    #    none (default)
    #    block
    #    expression

    keyvals["hide"]    = codeblock_keyval_bool(keyvals, "hide",    false)
    keyvals["execute"] = codeblock_keyval_bool(keyvals, "execute", true)
    keyvals["display"] = codeblock_keyval_bool(keyvals, "display", true)
    keyvals["results"] = get(keyvals, "results", "block")

    if isempty(classes) || classes[1] == "julia" ||
        !in(classes[1], code_block_classes)

        if keyvals["results"] == "none" || keyvals["results"] == "block"
            result = nothing
            if keyvals["execute"]
                for (cmd, ex) in parseit(strip(text))
                    result = safeeval(ex)
                end
            end

            if keyvals["results"] == "block" && result != nothing
                display(result)
            end
            output_text = text
        elseif keyvals["results"] == "expression"
            if keyvals["execute"]
                output_text = IOBuffer()
                for (cmd, ex) in parseit(strip(text))
                    println(output_text, cmd)
                    println(output_text, "## ", string(safeeval(ex)), "\n")
                end
            else
                output_text = text
            end
        end

        if !keyvals["hide"]
            push!(doc.blocks,
            {"t" => "CodeBlock", "c" => {{id, {"julia", classes...}, keyvals_array}, output_text}})
        end

        if keyvals["display"]
            flush(doc.stdout_read)
            flush(doc.stdout_write)
            if nb_available(doc.stdout_read) > 0
                stdout_output = readavailable(doc.stdout_read)
                if !isempty(stdout_output)
                    display("text/plain", stdout_output)
                end
            end
            append!(doc.blocks, doc.display_blocks)
        end
        empty!(doc.display_blocks)
    else
        if !keyvals["hide"]
            push!(doc.blocks, block)
        end

        class = classes[1]
        if keyvals["display"]
            if class == "graphviz"
                display("text/vnd.graphviz", text)
            elseif class == "latex"
                display("text/latex", text)
            elseif class == "svg"
                display("image/svg+xml", text)
            end
            append!(doc.blocks, doc.display_blocks)
        end
    end
end


# Evaluate an expression and return its result and a string.
function safeeval(ex::Expr)
    eval(WeaveSandbox, ex)
end


end
