include("../src/int256.jl")

@inline function faster_mod(x::T, m::Integer)::T where T<:Integer
    m = T(m)
    r = x - div(x, m) * m
    return r < 0 ? r + m : r
end

function test_crt()
    pregen = Int256.([
        12666374363021314 12020569859740413094537576
        -12666374363021313 -12020569859740413094537575
        63331870305157121 29750909161552864427900929
    ])

    arr = Int256.([121196, 84296324, 201782258])

    x = arr[1]
    for i in axes(pregen, 2)
        a = x * pregen[2, i] + arr[i + 1] * pregen[1, i]
        x = faster_mod(a, pregen[3, i])
        println("a: $a")
        println("x: $x")
    end
    println("x: $x")
end

test_crt()


