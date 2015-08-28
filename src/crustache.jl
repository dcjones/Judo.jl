

# This does a simplified version of mustache-style templates.
module Crustache
    const crustache_pattern = r"{{(.*?)}}"

    function render(text::UTF8String, tokens::Dict{UTF8String, UTF8String})
        parts = String[]
        lastpos = 1
        for m in eachmatch(crustache_pattern, text)
            if m.offset > lastpos
                push!(parts, text[lastpos:m.offset-1])
            end

            key = m.captures[1]
            if haskey(tokens, key)
                push!(parts, tokens[key])
            else
                warn(string("No docstring found for: ", key))
            end

            lastpos = m.offset + length(m.match)
        end

        return string(parts...)
    end
end
