

# Recursively list files under a directory.
#
# Args:
#   root: Path to descend.
#
# Returns:
#   A vector of paths relative to root.
#
function walkdir(root::AbstractString)
    root = abspath(root)
    contents = AbstractString[]
    stack = AbstractString[]
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


