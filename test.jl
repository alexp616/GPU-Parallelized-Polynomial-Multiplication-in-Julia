using CUDA
using SparseArrays

function GPUtrivialMultiply!(p1, p2)
    result = CUDA.fill(Tuple, length(p1) * length(p2))

    if !(p1 isa CuArray)
        p1 = CuArray(p1)
    end
    if !(p2 isa CuArray)
        p2 = CuArray(p2)
    end
    
    # Convert mutable types to immutable tuples
    p1 = convert(CuArray{Tuple}, p1)
    p2 = convert(CuArray{Tuple}, p2)

    nthreads = min(CUDA.attribute(
        device(),
        CUDA.DEVICE_ATTRIBUTE_MAX_THREADS_PER_BLOCK
    ), length(p1)*length(p2))

    nblocks = cld(length(p1) * length(p2), nthreads)

    CUDA.@sync @cuda(
        threads = nthreads,
        blocks = nblocks,
        GPUtrivialMultiplyKernel!(result, p1, p2)
    )
    
    return result
end

function GPUtrivialMultiplyKernel!(result, p1, p2)
    idx = threadIdx().x + (blockIdx().x - 1) * blockDim().x - 1
    idx1 = floor(Int, idx / length(p2))
    idx2 = idx - length(p2) * idx1 # idx2 = idx % length(p2)

    # Compute the result and store it in the result array
    result[idx] = (p1[idx1][1] * p2[idx2][1], p1[idx1][2] .+ p2[idx2][2])

    return 
end

p1 = [(1, [1, 0, 0]), (2, [0, 1, 0]), (3, [0, 0, 1])]
p2 = [(1, [2, 0, 0]), (2, [0, 2, 0]), (3, [0, 0, 2])]

println(Array(GPUtrivialMultiply!(p1, p2)))