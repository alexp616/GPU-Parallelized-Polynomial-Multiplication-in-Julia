using CUDA
using BenchmarkTools

import Base.div
import Base.bitstring

@inline function faster_mod(x::T, m::Integer)::T where T<:Integer
    m = T(m)
    r = x - div(x, m) * m
    return r < 0 ? r + m : r
end
"""
    div(n::Int128, m::Int128)::Int128

div function for Int128's that can be called inside CUDA kernels, since Base.div can't
"""
function div(n::Int128, m::Int128)
    if n == 0
        return Int128(0)
    end

    sign = 1
    if (n < 0) != (m < 0)
        sign = -1
    end

    n = abs(n)
    m = abs(m)

    quotient = Int128(0)
    remainder = Int128(0)

    for i in 0:127
        remainder = (remainder << 1) | ((n >> (127 - i)) & 1)
        if remainder >= m
            remainder -= m
            quotient |= (Int128(1) << (127 - i))
        end
    end

    return quotient * sign
end

function mod_kernel(arr::CuDeviceVector{Int128}, m::Int128)
    tid = threadIdx().x + (blockIdx().x - 1) * blockDim().x

    arr[tid] = mod(arr[tid], m)

    return
end

function test_broken_div()
    arr = CuArray(Int128.([10, 20, 30, 40]))
    mod = Int128(7)

    @cuda threads=length(arr) blocks = 1 mod_kernel(arr, mod)

    display(arr)
end

test_broken_div()

