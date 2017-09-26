#=
Abstraction over the GPU thread indexing functions.
Uses CUDA like names
=#
for sym in (:x, :y, :z)
    for f in (:blockidx, :blockdim, :threadidx, :griddim)
        fname = Symbol(string(f, '_', sym))
        @eval $fname(state)::UInt32 = error("Not implemented")
        @eval export $fname
    end
end



"""
in CUDA terms `__synchronize`
"""
function synchronize_threads(state)
    error("Not implemented")
end

"""
linear index in a GPU kernel (equal to  OpenCL.get_global_id)
"""
@inline function linear_index(state)
    UInt32((blockidx_x(state) - UInt32(1)) * blockdim_x(state) + threadidx_x(state))
end

"""
Macro form of `linear_index`, which returns when out of bounds
"""
macro linearidx(A, statesym = :state)
    quote
        x1 = $(esc(A))
        i1 = linear_index($(esc(statesym)))
        i1 > length(x1) && return
        i1
    end
end


"""
Like `@linearidx`, but returns an N-dimensional `NTuple{ndim(A), Cuint}` as index
"""
macro cartesianidx(A, statesym = :state)
    quote
        x = $(esc(A))
        i2 = @linearidx(x, $(esc(statesym)))
        gpu_ind2sub(x, i2)
    end
end

"""
Global size == blockdim * griddim == total number of kernel execution
"""
@inline function global_size(state)
    # TODO nd version
    griddim_x(state) * blockdim_x(state)
end


"""
Gets the device associated to the Array `A`
"""
function device(A::AbstractArray)
    # fallback is a noop, for backends not needing synchronization. This
    # makes it easier to write generic code that also works for AbstractArrays
end
"""
Blocks until all operations are finished on `A`
"""
function synchronize(A::AbstractArray)
    # fallback is a noop, for backends not needing synchronization. This
    # makes it easier to write generic code that also works for AbstractArrays
end
#
# @inline function synchronize_threads(state)
#     CUDAnative.__syncthreads()
# end




"""
Calls function `f` on the GPU.
`A` must be an GPUArray and will help to dispatch to the correct GPU backend
and supplies queues and contexts.
Calls kernel with `kernel(state, args...)`, where state is dependant on the backend
and can be used for e.g getting an index into A with `linear_index(state)`.
Optionally, launch configuration can be supplied in the following way:

    1) A single integer, indicating how many work items (total number of threads) you want to launch.
        in this case `linear_index(state)` will be a number in the range 1:configuration
    2) Pass a tuple of integer tuples to define blocks and threads per blocks!

"""
function gpu_call(f, A::GPUArray, args::Tuple, configuration = length(A))
    ITuple = NTuple{N, Integer} where N
    # If is a single integer, we assume it to be the global size / total number of threads one wants to launch
    thread_blocks = if isa(configuration, Integer)
        thread_blocks_heuristic(configuration)
    elseif isa(configuration, ITuple)
        # if a single integer ntuple, we assume it to configure the blocks
        configuration,  ntuple(x-> x == 1 ? 256 : 1, length(configuration))
    elseif isa(configuration, Tuple{ITuple, ITuple})
        # 2 dim tuple of ints == blocks + threads per block
        if any(x-> length(x) > 3 || length(x) < 1, configuration)
            error("blocks & threads must be 1-3 dimensional. Found: $configuration")
        end
        map(x-> Int.(x), configuration) # make sure it all has the same int type
    else
        error("""Please launch a gpu kernel with a valid configuration.
            Found: $configurations
            Configuration needs to be:
            1) A single integer, indicating how many work items (total number of threads) you want to launch.
                in this case `linear_index(state)` will be a number in the range 1:configuration
            2) Pass a tuple of integer tuples to define blocks and threads per blocks!
                `linear_index` will be inbetween 1:prod((blocks..., threads...))
        """)
    end
    _gpu_call(f, A, args, thread_blocks)
end

# Internal GPU call function, that needs to be overloaded by the backends.
_gpu_call(f, A, args, thread_blocks) = error("Not implemented")
