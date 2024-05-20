using CUDA

# Segmented_scan that doesn't assume length(data) and length(flags) are a power of 2 plus 1
# function segmented_scan(data, flags)
#     @assert length(data) == length(flags) "data and flags not same length"

#     cu_data = CuArray(pad_to_next_power_of_2(data))
#     cu_flags_original = CuArray(pad_to_next_power_of_2(flags))
#     cu_flags_tmp = copy(cu_flags_original)
#     n = length(cu_data)
#     log2n = Int(floor(log2(n)))
    
#     # Launch configuration
#     threads_per_block = min(length(cu_data), 256)
#     blocks = cld(n, threads_per_block)

#     for d in 0:(log2n - 1)
#         CUDA.@sync @cuda threads = div(threads_per_block, 2^(d+1)) blocks = blocks segmented_scan_upsweep_kernel(cu_data, cu_flags_tmp, d)
#     end

#     CUDA.@sync @cuda threads = 1 blocks = 1 set_value(cu_data, n, 0)

#     @assert Array(cu_flags_original) != Array(cu_flags_tmp) "tmp array never changed, no flags present"

#     for d in (log2n - 1):-1:0
#         CUDA.@sync @cuda threads = div(threads_per_block, 2^(d+1)) blocks = blocks segmented_scan_downsweep_kernel(cu_data, cu_flags_original, cu_flags_tmp, d)
#     end

#     cu_copy_data = CuArray(data)
#     cu_data .+= cu_copy_data

#     CUDA.unsafe_free!(cu_copy_data)
#     CUDA.unsafe_free!(cu_flags_original)
#     CUDA.unsafe_free!(cu_flags_tmp)
#     return cu_data
# end

# Returns padded array to next power of 2
function pad_to_next_power_of_2_plus_1(arr::Vector{T}) where T
    current_length = length(arr)
    next_power_of_2 = 2^ceil(Int, log2(current_length))
    padding_length = next_power_of_2 - current_length + 1
    padded_array = vcat(arr, zeros(T, padding_length))
    
    return padded_array
end

function segmented_scan_upsweep_kernel(data, flags_tmp, d)
    i = threadIdx().x + (blockIdx().x - 1) * blockDim().x - 1
    k = i * 2^(d + 1)

    if flags_tmp[k + 2^(d + 1)] == 0
        data[k + 2^(d + 1)] = data[k + 2^(d)] + data[k + 2^(d + 1)]
    end
    flags_tmp[k + 2^(d + 1)] = flags_tmp[k + 2^d] | flags_tmp[k + 2^(d + 1)]

    return
end

function segmented_scan_downsweep_kernel(data, flags_original, flags_tmp, d)
    i = threadIdx().x + (blockIdx().x - 1) * blockDim().x - 1
    k = i * 2^(d + 1)

    temp = data[k + 2^d]
    data[k + 2^d] = data[k + 2^(d + 1)]
    if (flags_original[k + 2^d + 1] != 0)
        data[k + 2^(d + 1)] = 0
    elseif (flags_tmp[k + 2^d] != 0)
        data[k + 2^(d + 1)] = temp
    else
        data[k + 2^(d + 1)] += temp
    end
    flags_tmp[k + 2^d] = 0

    return nothing
end

# idk any better way to do this
function set_value(arr, idx, num)
    arr[idx] = num
    return
end





function generate_start_flags_kernel(keys, flags)
    tid = threadIdx().x + (blockIdx().x - 1) * blockDim().x

    if keys[tid + 1] != keys[tid]
        flags[tid + 1] = true
    end

    return nothing
end

function reduce_by_key(keys, values)
    @assert length(keys) == length(values) "Keys and values cannot be different lengths"
    cu_keys = CuArray(pad_to_next_power_of_2_plus_1(keys))
    cu_values = CuArray(pad_to_next_power_of_2_plus_1(values))
    flags = CUDA.fill(Int32(0), length(cu_keys))

    nthreads = min(512, length(cu_keys) - 1)
    nblocks = cld(length(cu_keys) - 1, nthreads)

    CUDA.@sync @cuda(
        threads = nthreads,
        blocks = nblocks,
        generate_start_flags_kernel(cu_keys, flags)
    )

    CUDA.@sync @cuda threads = 1 blocks = 1 set_value(flags, 1, 1)
    
    key_indices = accumulate(+, flags)

    length_of_reduced_keys = Array(key_indices)[end]

    cu_seg_reduced = segmented_scan(cu_values, flags)

    reduced_keys = CUDA.fill(0, length_of_reduced_keys)
    reduced_values = CUDA.fill(0, length_of_reduced_keys)
    
    CUDA.@sync @cuda(
        threads = nthreads,
        blocks = nblocks,
        reduce_by_key_kernel(flags, key_indices, cu_keys, reduced_keys, reduced_values, cu_seg_reduced)
    )

    return (reduced_keys, reduced_values)
end

function reduce_by_key_kernel(flags, key_indices, cu_keys, reduced_keys, reduced_values, cu_seg_reduced)
    tid = threadIdx().x + (blockIdx().x - 1) * blockDim().x

    if flags[tid + 1] != 0
        reduced_keys[key_indices[tid]] = cu_keys[tid]
        reduced_values[key_indices[tid]] = cu_seg_reduced[tid]
    end

    return nothing
end

function segmented_scan(cu_data, cu_flags_original)
    @assert length(cu_data) == length(cu_flags_original) "data and flags not same length"
    copy_original_data = copy(cu_data)
    cu_flags_tmp = copy(cu_flags_original)
    n = length(cu_data) - 1
    log2n = Int(floor(log2(n)))
    
    threads_per_block = min(length(cu_data) - 1, 512)
    blocks = cld(n, threads_per_block)

    for d in 0:(log2n - 1)
        CUDA.@sync @cuda threads = div(threads_per_block, 2^(d+1)) blocks = blocks segmented_scan_upsweep_kernel(cu_data, cu_flags_tmp, d)
    end

    CUDA.@sync @cuda threads = 1 blocks = 1 set_value(cu_data, n, 0)

    for d in (log2n - 1):-1:0
        CUDA.@sync @cuda threads = div(threads_per_block, 2^(d+1)) blocks = blocks segmented_scan_downsweep_kernel(cu_data, cu_flags_original, cu_flags_tmp, d)
    end

    cu_data .+= copy_original_data

    CUDA.unsafe_free!(copy_original_data)
    CUDA.unsafe_free!(cu_flags_tmp)
    return cu_data
end

keys = [3, 3, 3, 4, 4, 5, 5, 5, 5, 6, 7, 8, 9]
values = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]

result = reduce_by_key(keys, values)

println(result[1])
println(result[2])
# println(result)


