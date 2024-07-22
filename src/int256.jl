import Base.bitstring
import Base.BigInt

struct Int256 <: Integer
    hi::Int128
    lo::Int128
end

function bitstring(n::Int256)
    return Base.bitstring(n.hi) * Base.bitstring(n.lo)
end

Int256(x::Int256) = x
Int256(x::Integer) = Int256((x < 0 ? -1 : 0), Int128(x))

Base.promote_rule(::Type{Int256}, ::Type{T}) where {T<:Integer} = Int256
Base.convert(::Type{Int256}, x::Integer) = Int256(x)

function Base.abs(a::Int256)
    if a < Int256(0)
        return -a
    else
        return a
    end
end

function add_with_carry(a::Int128, b::Integer)
    b = Int128(b)
    sum = a + b
    carry = sum < a ? 1 : 0
    return sum, carry
end

function Base.:+(a::Int256, b::Int256)
    lo, carry = add_with_carry(a.lo, b.lo)
    hi = a.hi + b.hi + carry
    return Int256(hi, lo)
end

function Base.:-(a::Int256, b::Int256)
    return +(a, -b)
end

function Base.:-(a::Int256)
    return a == 0 ? Int256(0) : Int256(~a.hi, ~a.lo) + Int256(1)
end

function Base.:*(a::Int256, b::Int256)
    a1, a0 = a.hi, a.lo
    b1, b0 = b.hi, b.lo

    p0 = a0 * b0
    p1 = a0 * b1
    p2 = a1 * b0
    p3 = a1 * b1

    lo = p0
    mid1, carry1 = add_with_carry(p1, p2)
    hi = p3 + carry1

    lo, carry2 = add_with_carry(lo, mid1 << 64)
    hi += mid1 >> 64 + carry2

    return Int256(hi, lo)
end

function Base.div(a::Int256, b::Int256)
    if a == 0
        return Int256(0)
    end

    sign = 1
    if (a < 0) != (b < 0)
        sign = -1
    end

    a = abs(a)
    b = abs(b)

    quotient = Int256(0)
    remainder = Int256(0)

    for i in 0:255
        remainder = (remainder << 1) | ((a >> (255 - i)) & 1)
        if remainder >= b
            remainder -= b
            quotient |= (Int256(1) << (255 - i))
        end
    end
    return quotient * sign
end

function Base.divrem(a::Int256, b::Int256)
    q = div(a, b)
    r = a - q * b
    r < 0 ? r += b : r
    return q, r
end

function Base.mod(a::Int256, b::Int256)
    q, r = divrem(a, b)
    return r
end

Base.:/(a::Int256, b::Int256) = div(a, b)

Base.:<<(a::Int256, n::Int) = Int256(a.hi << n | a.lo >> (128 - n), a.lo << n)
Base.:>>(a::Int256, n::Int) = Int256(a.hi >> n, a.lo >> n | a.hi << (128 - n))
Base.:&(a::Int256, b::Int256) = Int256(a.hi & b.hi, a.lo & b.lo)
Base.:|(a::Int256, b::Int256) = Int256(a.hi | b.hi, a.lo | b.lo)
Base.:^(a::Int256, b::Int256) = Int256(a.hi ^ b.hi, a.lo ^ b.lo)

Base.:(==)(a::Int256, b::Int256) = a.hi == b.hi && a.lo == b.lo
Base.:<(a::Int256, b::Int256) = a.hi < b.hi || (a.hi == b.hi && a.lo < b.lo)
Base.:<=(a::Int256, b::Int256) = a < b || a == b
Base.:>(a::Int256, b::Int256) = !(a <= b)
Base.:>=(a::Int256, b::Int256) = !(a < b)

function Base.show(io::IO, x::Int256)
    print(io, BigInt(x))
end

function Base.BigInt(x::Int256)
    hi_big = BigInt(x.hi)
    lo_big = BigInt(x.lo)
    result = (hi_big << 128) + lo_big
    return result
end

function Base.Int128(x::Int256)
    if x.hi < 0
        return -(~x.lo + 1)
    else
        return x.lo
    end
end