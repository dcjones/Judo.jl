
# Parse function and type documentation from julia source files.


# pattern to extract comments immediately preceeding declarations:
const decl_comment_pat =
    r"
    (\h*\#[^\n]*\n)+
    \h*(function|immutable|type)\s+([A-Za-z_][A-Za-z0-9_?]*)
    "xm


# pattern to strip leading whitespace and '#' characters from comments.
const comment_strip_pat = r"\h*\#+\h*"


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
    for mat in eachmatch(decl_comment_pat, input)
        push!(mats, (mat.captures[3],
                     replace(mat.captures[1], comment_strip_pat, "")))
    end
    mats
end


# pattern to parse function documentation
const func_doc_pat =
    r"
    \s*
    (?:Args:
       ()+\s*:
    )?
    "xm


# Extract and parse decleration-preceeding comments from a set of files.
function harvest(filenames::Vector)
    for filename in filenames
        declarations = extract_declaration_comments(readall(filename))

    end
end



