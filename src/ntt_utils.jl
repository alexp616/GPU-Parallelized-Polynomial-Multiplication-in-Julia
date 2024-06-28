using CUDA
using Test
using Primes
using BenchmarkTools
using Dates

import Base.div

# Also exists to guarantee positive mod numbers so my chinese remainder theorem
# doesn't get messed up
@inline function faster_mod(x::Int, m::Int)::Int
    r = Int(x - div(x, m) * m)
    return r < 0 ? r + m : r
end

function faster_mod(a::Int128, b::Int128)::Int128
    # Handle edge cases
    if b == 0
        return a # Division by zero should not happen in kernel, return a for safety
    elseif a == 0
        return 0
    end

    abs_a = abs(a)
    abs_b = abs(b)
    
    if abs_a < abs_b
        return a
    end

    remainder = abs_a
    b_bits = sizeof(Int128) * 8 - leading_zeros(abs_b)

    for i in (sizeof(Int128) * 8 - leading_zeros(abs_a)):-1:b_bits
        if remainder >= (abs_b << (i - b_bits))
            remainder -= abs_b << (i - b_bits)
        end
    end

    return a < 0 ? -remainder + b : remainder
end

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

function chinese_remainder_two(a::T, n::T, b::Integer, m::Integer) where T<:Integer

    b = T(b)
    m = T(m)

    n0, m0 = n, m
    x0, x1 = T(1), T(0)
    y0, y1 = T(0), T(1)
    while m != 0
        q = div(n, m)
        n, m = m, faster_mod(n, m)
        x0, x1 = x1, x0 - q * x1
        y0, y1 = y1, y0 - q * y1
    end

    return faster_mod(a * m0 * y0 + b * n0 * x0, T(n0 * m0))

end


"""
    find_ntt_primes(n)

Find primes of form k * n + 1 for 5 seconds
isprime() method is probabilistic, actually test for primality using
another method when using a prime from here
"""
function find_ntt_primes(n)
    start_time = now()
    prime_list = []
    k = 1

    while (now() - start_time) < Second(5)
        candidate = k * n + 1
        if isprime(candidate)
            push!(prime_list, candidate)
        end
        k += 1
    end

    return prime_list
end

function get_ntt_length(numVars, prime)
    step1HomogeneousDegree = numVars * (prime - 1)
    step1Length = nextpow(2, (step1HomogeneousDegree) * (step1HomogeneousDegree + 1) ^ (numVars - 2))
    step2HomogeneousDegree = step1HomogeneousDegree * prime 
    step2Length = nextpow(2, (step2HomogeneousDegree) * (step2HomogeneousDegree + 1) ^ (numVars - 2))
    return step1Length, step2Length
end


function npruarray_generator(primearray::Array{T}, n::T) where T<:Integer
    return map(p -> nth_principal_root_of_unity(n, p), primearray)
end

function inverse_generator(npruarray::Array, primearray::Array)
    @assert length(npruarray) == length(primearray)
    return mod_inverse.(npruarray, primearray)
end


"""
    power_mod(n, p, m)

Return n ^ p mod m. Only gives accurate results when
m is prime, since uses fermat's little theorem
"""
function power_mod(n::T, p::Integer, m::Integer) where T<:Integer
    result = 1
    p = faster_mod(p, m - 1)
    base = faster_mod(n, m)

    while p > 0
        if p & 1 == 1
            result = faster_mod((result * base), m)
        end
        base = faster_mod(base * base, m)
        p = p >> 1
    end

    return result
end


"""
    mod_inverse(n, p)

Return n^-1 mod p. Assumes n is actually invertible mod p
"""
function mod_inverse(n::Integer, p::Integer)
    n = faster_mod(n, p)

    t, new_t = 0, 1
    r, new_r = p, n

    while new_r != 0
        quotient = r ÷ new_r
        t, new_t = new_t, t - quotient * new_t
        r, new_r = new_r, r - quotient * new_r
    end

    return t < 0 ? t + p : t
end

function nth_principal_root_of_unity(n::Integer, p::Integer)
    @assert faster_mod(p - 1, n) == 0 "n must divide p-1"

    order = (p - 1) ÷ n

    function is_primitive_root(g, p, order)
        for i in 1:(n-1)
            if power_mod(g, i * order, p) == 1
                return false
            end
        end
        return true
    end
    
    g = 2
    while !is_primitive_root(g, p, order)
        g += 1
    end

    root_of_unity = power_mod(g, order, p)
    return typeof(n)(root_of_unity)
end

function parallelBitReverseCopy(p)
    @assert ispow2(length(p)) "p must be an array with length of a power of 2"
    len = length(p)
    result = CUDA.zeros(eltype(p), len)
    nthreads = min(512, len ÷ 2)
    nblocks = cld(len ÷ 2, nthreads)
    log2n = Int(log2(len))

    function kernel(p, dest, len, log2n)
        idx1 = threadIdx().x + (blockIdx().x - 1) * blockDim().x - 1
        idx2 = idx1 + Int(len / 2)
    
        rev1 = bit_reverse(idx1, log2n)
        rev2 = bit_reverse(idx2, log2n)
    
        dest[idx1 + 1] = p[rev1 + 1]
        dest[idx2 + 1] = p[rev2 + 1]
        return nothing
    end

    @cuda(
        threads = nthreads,
        blocks = nblocks,
        kernel(p, result, len, log2n)
    )
    
    return result
end