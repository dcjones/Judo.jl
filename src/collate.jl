
# Turn a collection of markdown files into a browsable multi-page manual.


function collate(package::String)

end


function collate(filenames::Vector;
                 template::String="default",
                 outdir::String=".")
    fileext_pat = r"^(.+)\.([^\.]+)$"

    # map topics to document names
    topics = Dict{String, Vector{String}}

    # map document names to section names
    sections = Dict{String, Vector{String}}

    if !isdir(template)
        template = joinpath(Pkg.dir("Judo"), "templates", template)
        if !isdir(template)
            error("Can't find template $(template)")
        end
    end

    pandoc_template = joinpath(template, "template.html")

    for filename in filenames
        mat = match(fileext_pat, filename)
        fmt = :markdown
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

        outfilename = joinpath(outdir, string(name, ".html"))
        outfile = open(outfilename, "w")
        metadata, sections = weave(open(filename), outfile,
                                   name=name, template=pandoc_template,
                                   toc=true, outdir=outdir)
        close(outfile)
    end

    # copy template files
    run(`cp -r $(joinpath(template, "js")) $(outdir)`)
    run(`cp -r $(joinpath(template, "css")) $(outdir)`)
end


