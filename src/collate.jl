
# Turn a collection of markdown files into a browsable multi-page manual.


# Recursively list files under a directory.
#
# Args:
#   root: Path to descend.
#
# Returns:
#   A vector of paths relative to root.
#
function walkdir(root::String)
    root = abspath(root)
    contents = String[]
    stack = String[]
    push!(stack, root)
    while !isempty(stack)
        path = pop!(stack)
        for f in readdir(path)
            fullpath = joinpath(path, f)
            if isdir(fullpath)
                push!(stack, fullpath)
            else
                push!(contents, fullpath)
            end
        end
    end
    contents
end


# Files to be weaved when generating a packages documentation.
const ext_doc_pat = r"\.(md|txt|rst)$"i


function collate(package::String)
    filenames = {}
    for filename in walkdir(joinpath(Pkg.dir(package), "doc"))
        if match(ext_doc_pat, filename) != nothing
            push!(filenames, filename)
        end
    end

    outdir = joinpath(Pkg.dir(package), "doc", "html")
    if !isdir(outdir)
        mkdir(outdir)
    end

    collate(filenames, outdir=outdir, pkgname=package)
end


function collate(filenames::Vector;
                 template::String="default",
                 outdir::String=".",
                 pkgname=nothing)
    toc = Dict()
    titles = Dict()
    names = Dict()

    if !isdir(template)
        template = joinpath(Pkg.dir("Judo"), "templates", template)
        if !isdir(template)
            error("Can't find template $(template)")
        end
    end

    # dry-run to collect the section names in each document
    for filename in filenames
        metadata, sections = weave(open(filename), IOBuffer(), dryrun=true)
        name = choose_document_name(filename)
        title = get(metadata, "title", name)
        titles[name] = title
        names[title] = name
        toc[title] = sections
    end

    pandoc_template = joinpath(template, "template.html")

    keyvals = Dict()

    if pkgname != nothing
        keyvals["pkgname"] = pkgname
    end

    for filename in filenames
        fmt = :markdown
        name = choose_document_name(filename)
        title = titles[name]
        outfilename = joinpath(outdir, string(name, ".html"))
        outfile = open(outfilename, "w")
        keyvals["table-of-contents"] = table_of_contents(toc, names, title)
        metadata, sections = weave(open(filename), outfile,
                                   name=name, template=pandoc_template,
                                   toc=true, outdir=outdir,
                                   keyvals=keyvals)
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
function table_of_contents(toc::Dict, names::Dict, selected_title::String)
    out = IOBuffer()
    write(out, "<ul>\n")
    for (title, sections) in toc
        write(out, "<li>")
        if title == selected_title
            write(out,
                """<div class="toc-current-doc">
                     <a href="#title-block">$(title)</a>
                   </div>\n
                """)
            write(out, table_of_contents_sections(sections))
        else
            @printf(out, "<a href=\"%s.html\">%s</a>", names[title], title)
        end
        write(out, "</li>")
    end
    write(out, "</ul>\n")
    takebuf_string(out)
end


function table_of_contents_sections(sections)
    if isempty(sections)
        return ""
    end

    out = IOBuffer()
    write(out, "<ul>\n")
    for (level, section) in sections
        @printf(out, "<li><a href=\"#%s\">%s</a/></li>\n",
                section_id(section), section)
    end
    write(out, "</ul>\n")
    takebuf_string(out)
end


# Turn a section name into an html id.
function section_id(section::String)
    lowercase(replace(section, r"\s+", "-"))
end

