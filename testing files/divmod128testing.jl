using CUDA
using BenchmarkTools
using BitIntegers

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

function div(n::Int256, m::Int256) 
    if n == 0
        return Int256(0)
    end

    sign = 1
    if (n < 0) != (m < 0)
        sign = -1
    end

    n = abs(n)
    m = abs(m)

    quotient = Int256(0)
    remainder = Int256(0)

    for i in 0:255
        remainder = (remainder << 1) | ((n >> (255 - i)) & 1)
        if remainder >= m
            remainder -= m
            quotient |= (Int256(1) << (255 - i))
        end
    end

    return quotient * sign
end


function reduce_mod_m_kernel(arr::CuDeviceVector{Int128, 1}, m::Int128)
    idx = threadIdx().x + (blockIdx().x - 1) * blockDim().x
    arr[idx] = faster_mod(arr[idx], m)

    # using this one gives:
    # ERROR: LLVM error: Undefined external symbol "__modti3"
    # arr[idx] = arr[idx] % m
    return
end

function div_kernel(arr, m)
    idx = threadIdx().x
    arr[idx] = div(arr[idx], m)

    return
end

function test_broken_div()
    # div works for Int128
    arr = CuArray(Int128.([100]))
    m = Int128(7)
    @cuda threads = length(arr) div_kernel(arr, m) 
    display(arr)

    println("testing Int256 stuff: ")
    arr = CuArray(Int256.([10]))
    m = Int256(7)

    display(arr)
    # Addition works
    arr .+= m
    println("arr after addition: ")
    display(arr)
    # Multiplication works
    # arr .*= m
    # println("arr after multiplication: ")
    # display(arr)

    

    # # Division doesn't work
    # @cuda threads = length(arr) div_kernel(arr, m)

    return arr
end

test_broken_div()