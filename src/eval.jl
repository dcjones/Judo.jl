
# An iterator for the parse function: parsit(source) will iterate over the
# expressiosn in a string.
type ParseIt
    value::String
end


function parseit(value::String)
    ParseIt(value)
end


function Base.start(it::ParseIt)
    1
end


function Base.next(it::ParseIt, pos)
    (ex,newpos) = Base.parse(it.value, pos)
    ((it.value[pos:(newpos-1)], ex), newpos)
end


function Base.done(it::ParseIt, pos)
    pos > length(it.value)
end


# A special dummy module in which a documents code is executed.
module WeaveSandbox
end


# Evaluate an expression and return its result and a string.
function safeeval(ex::Expr)
    eval(WeaveSandbox, ex)
end


