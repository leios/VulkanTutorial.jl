struct ShaderPushConsts
    val::Float32
    n::UInt32
end

struct ShaderSpecConsts
    local_size_x::UInt32
end

function simple_compute()
    instance = Instance([],[])
    physical_device = first(unwrap(enumerate_physical_devices(instance)))
    qfam_idx = 1
    device = Device(physical_device, [DeviceQueueCreateInfo(qfam_idx, [1.0])], [], [])
    memorytype_idx = 3

    data_items = 100
    mem_size = sizeof(Float32) * data_items
    mem = DeviceMemory(device, mem_size, memorytype_idx)
    buffer = Buffer(
        device,
        mem_size,
        BUFFER_USAGE_STORAGE_BUFFER_BIT,
        SHARING_MODE_EXCLUSIVE,
        [qfam_idx],
    )

    bind_buffer_memory(device, buffer, mem, 0)

    memptr = unwrap(map_memory(device, mem, 0, mem_size))

    data = unsafe_wrap(Vector{Float32}, convert(Ptr{Float32}, memptr), data_item

    data .= 0
    unwrap(flush_mapped_memory_ranges(device, [MappedMemoryRange(mem, 0, mem_size)]))

    shader_code = """
        #version 430

        layout(local_size_x_id = 0) in;
        layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

        layout(constant_id = 0) const uint blocksize = 1; // manual way to capture the specialization constants
    
        layout(push_constant) uniform Params
        {
            float val;
            uint n;
        } params;

        layout(std430, binding=0) buffer databuf
        {
            float data[];
        };

        void
        main()
        {
            uint i = gl_GlobalInvocationID.x;
            if(i < params.n) data[i] = params.val * i;
        }
    """

    glslang = glslangValidator(identity)
    shader_bcode = mktempdir() do dir
        inpath = joinpath(dir, "shader.comp")
        outpath = joinpath(dir, "shader.spv")
        open(f -> write(f, shader_code), inpath, "w")
        status = run(`$glslang -V -S comp -o $outpath $inpath`)
        @assert status.exitcode == 0
        reinterpret(UInt32, read(outpath))
    end

    shader = ShaderModule(device, sizeof(UInt32) * length(shader_bcode), shader_bcode)

    dsl = DescriptorSetLayout(
        device,
        [
            DescriptorSetLayoutBinding(
                0,
                DESCRIPTOR_TYPE_STORAGE_BUFFER,
                SHADER_STAGE_COMPUTE_BIT;
                descriptor_count = 1,
            ),
        ],
    )

    pl = PipelineLayout(
        device,
        [dsl],
        [PushConstantRange(SHADER_STAGE_COMPUTE_BIT, 0, sizeof(ShaderPushConsts))],
    )

    const_local_size_x = 32
    spec_consts = [ShaderSpecConsts(const_local_size_x)]

    pipeline_info = ComputePipelineCreateInfo(
        PipelineShaderStageCreateInfo(
            SHADER_STAGE_COMPUTE_BIT,
            shader,
            "main", # this needs to match the function name in the shader
            specialization_info = SpecializationInfo(
                [SpecializationMapEntry(0, 0, 4)],
                UInt64(4),
                Ptr{Nothing}(pointer(spec_consts)),
            ),
        ),
        pl,
        -1,
    )
    ps, _ = unwrap(create_compute_pipelines(device, [pipeline_info]))
    p = first(ps)

    dpool = DescriptorPool(device, 1, [DescriptorPoolSize(DESCRIPTOR_TYPE_STORAGE_BUFFER, 1)],
                           flags=DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT)

   dsets = unwrap(allocate_descriptor_sets(device, DescriptorSetAllocateInfo(dpool, [dsl])))
    dset = first(dsets)

    update_descriptor_sets(
        device,
        [
            WriteDescriptorSet(
                dset,
                0,
                0,
                DESCRIPTOR_TYPE_STORAGE_BUFFER,
                [],
                [DescriptorBufferInfo(buffer, 0, WHOLE_SIZE)],
                [],
            ),
        ],
        [],
    )

    cmdpool = CommandPool(device, qfam_idx)
    cbufs = unwrap(
        allocate_command_buffers(
            device,
            CommandBufferAllocateInfo(cmdpool, COMMAND_BUFFER_LEVEL_PRIMARY, 1),
        ),
    )
    cbuf = first(cbufs)

    begin_command_buffer(
        cbuf,
        CommandBufferBeginInfo(flags = COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT),
    )

    cmd_bind_pipeline(cbuf, PIPELINE_BIND_POINT_COMPUTE, p)

    const_buf = [ShaderPushConsts(1.234, data_items)]
    cmd_push_constants(
        cbuf,
        pl,
        SHADER_STAGE_COMPUTE_BIT,
        0,
        sizeof(ShaderPushConsts),
        Ptr{Nothing}(pointer(const_buf)),
    )

    cmd_bind_descriptor_sets(cbuf, PIPELINE_BIND_POINT_COMPUTE, pl, 0, [dset], [])

    cmd_dispatch(cbuf, div(data_items, const_local_size_x, RoundUp), 1, 1)

    end_command_buffer(cbuf)

    compute_q = get_device_queue(device, qfam_idx, 0)
    unwrap(queue_submit(compute_q, [SubmitInfo([], [], [cbuf], [])]))

    free_command_buffers(device, cmdpool, cbufs)
    free_descriptor_sets(device, dpool, dsets)

    unwrap(invalidate_mapped_memory_ranges(device, [MappedMemoryRange(mem, 0, mem_size)]))

    data
end
