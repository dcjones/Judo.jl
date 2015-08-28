
# Turn a collection of markdown files into a browsable multi-page manual.

# Files to be weaved when generating a packages documentation.
const ext_doc_pat = r"\.(md|txt|rst)$"i


# Pattern for matching github package urls
const pkgurl_pat = r"github.com/(.*)\.git$"


# Generate documentation from the given package.
function collate(package::String; template::String="default")
    # TODO: We need to somehow load the package to make sure docstrings are all
    # there.
    #declarations = harvest(package)
    declarations = Dict()

    pkgver = ""
    try
        pkgver = Pkg.Dir.cd(() -> Pkg.Read.installed()[package][1])
    catch
    end
    pkgver_out = IOBuffer()
    print(pkgver_out, pkgver)
    pkgver = takebuf_string(pkgver_out)

    pkgurl = "#"
    try
        pkgurl_mat = match(pkgurl_pat, Pkg.Dir.cd(() -> Pkg.Read.url(package)))
        if pkgurl_mat != nothing
            pkgurl = string("http://github.com/", pkgurl_mat.captures[1])
        end
    catch
    end

    filenames = UTF8String[]
    for filename in walkdir(joinpath(Pkg.dir(package), "doc"))
        if match(ext_doc_pat, filename) != nothing
            push!(filenames, filename)
        end
    end

    outdir = joinpath(Pkg.dir(package), "doc", "html")
    if !isdir(outdir)
        mkdir(outdir)
    end

    collate(filenames, template=template, outdir=outdir, pkgname=package,
            pkgver=pkgver, pkgurl=pkgurl, declarations=declarations)
end


"""
Table of contents entry containing sections within one document.
"""
immutable TOCEntry
    order::Int
    name::UTF8String
    title::UTF8String
    sections::Vector{Markdown.Header}
end


function Base.isless(a::TOCEntry, b::TOCEntry)
    return a.order < b.order
end


function level{L}(::Markdown.Header{L})
    return L
end


# Generate documentation from multiple files.
function collate(filenames::Vector;
                 template::String="default",
                 outdir::String=".",
                 declarations::Dict=Dict(),
                 pkgname=nothing,
                 pkgver=nothing,
                 pkgurl=nothing)
    toc = Dict{Nullable{UTF8String}, Vector{TOCEntry}}()
    titles = Dict{UTF8String, UTF8String}()

    #declaration_markdown = generate_declaration_markdown(declarations)

    if !isdir(template)
        template = joinpath(Pkg.dir("Judo"), "templates", template)
        if !isdir(template)
            error("Can't find template $(template)")
        end
    end

    # make any expansions necessary in the original document
    # TODO: insert docstrings
    docs = Dict()
    for filename in filenames
        name = choose_document_name(filename)
        docs[name] = readall(filename)
        #docs[name] = expand_declaration_docs(readall(filename),
                                             #declaration_markdown)
    end

    # dry-run to collect the section names in each document
    for (name, doc) in docs
        metadata, sections = process(doc, Nullable{IO}())
        title = get(metadata, "title", name)
        titles[name] = title

        part = haskey(metadata, "part") ?
            Nullable{UTF8String}(metadata["part"]) : Nullable{UTF8String}()
        if !haskey(toc, part)
            toc[part] = TOCEntry[]
        end

        push!(toc[part],
            TOCEntry(get(metadata, "order", 0), name, title, sections))
    end

    for part_content in values(toc)
        sort!(part_content)
    end

    document_template = readall(joinpath(template, "template.html"))

    metadata = Dict{UTF8String, UTF8String}()

    if pkgname != nothing
        metadata["pkgname"] = pkgname
    end

    if pkgver != nothing
        metadata["pkgver"] = pkgver
    end

    if pkgurl != nothing
        metadata["pkgurl"] = pkgurl
    end

    for (name, doc) in docs
        println(STDERR, "processing ", name)
        fmt = :markdown
        title = titles[name]
        outfilename = joinpath(outdir, string(name, ".html"))
        outfile = open(outfilename, "w")
        metadata["table-of-contents"] = table_of_contents(toc, title)
        metadata["name"] = name
        process(doc, Nullable{IO}(outfile),
                template=Nullable{UTF8String}(utf8(document_template)),
                toc=true,
                outdir=outdir,
                metadata=metadata)
        close(outfile)
    end

    # copy template files
    run(`cp -r $(joinpath(template, "js")) $(outdir)`)
    run(`cp -r $(joinpath(template, "css")) $(outdir)`)
end


# pattern for choosing document names
const fileext_pat = r"^(.+)\.([^\.]+)$"


# Choose a documents name from its file name.
function choose_document_name(filename::String)
    filename = basename(filename)
    mat = match(fileext_pat, filename)
    name = filename
    if !is(mat, nothing)
        name = mat.captures[1]
        if mat.captures[2] == "md"
            fmt = :markdown
        elseif mat.captures[2] == "rst"
            fmt = :rst
        elseif mat.captures[2] == "tex"
            fmt = :latex
        elseif mat.captures[2] == "html" || mat.captures[2] == "htm"
            fmt = :html
        else
            name = filename
        end
    end

    name
end


# Generate a table of contents for the given document.
function table_of_contents(toc, selected_title::String)
    parts = collect(keys(toc))
    part_order = [minimum([entry.order for entry in toc[part]])
                  for part in parts]
    out = IOBuffer()
    write(out, "<ul class=\"toc list nav\">")
    for part in parts[sortperm(part_order)]
        if !isnull(part)
            write(out,
                """
                <li>
                    <hr><div class="toc-part">$(get(part))</div>
                </li>
                """)
        end

        for entry in toc[part]
            iscurrent = entry.title == selected_title

            classes = iscurrent ?
                "toc-item toc-current-doc" : "toc-item"

            write(out,
                """
                <li>
                    <a class="$(classes)" href="$(entry.name).html">$(entry.title)</a>
                </li>
                """)

                write(out, table_of_contents_sections(
                    entry.name, entry.sections,iscurrent, maxlevel=iscurrent ? 2 : 0))
        end
    end
    write(out, "</ul>")
    takebuf_string(out)
end


function table_of_contents_sections(parent, sections, iscurrent; maxlevel=2)
    if isempty(sections)
        return ""
    end

    out = IOBuffer()
    current_level = 0
    for section in sections
        if level(section) > maxlevel
            continue
        end

        while level(section) > current_level
            current_level += 1
        end

        while level(section) < current_level
            current_level -= 1
        end

        text = section.text[1]
        href = iscurrent ?
            "#$(section_id(text))" :
            "$(parent).html#$(section_id(text))"

        write(out,
            """
            <li>
                <a style="margin-left: $(0.5 * level(section))em" class="toc-item" href=\"$(href)\">$(text)</a>
            </li>
            """)
    end
    return takebuf_string(out)
end


# Turn a section name into an html id.
function section_id(section::String)
    # Keep only unicode letters, _ and -
    cleaned = replace(section, r"[^\p{L}_\-\s]", "")
    lowercase(replace(cleaned, r"\s+", "-"))
end

