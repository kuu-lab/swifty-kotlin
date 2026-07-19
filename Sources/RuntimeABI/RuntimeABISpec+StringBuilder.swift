public extension RuntimeABISpec {
    /// StringBuilder mutable-buffer bridge.
    static let stringBuilderFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_new",
            parameters: [],
            returnType: .intptr,
            section: "StringBuilder",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_new_with_capacity",
            parameters: [
                RuntimeABIParameter(name: "capacity", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_new_from_string_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_append_obj",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_append_obj_flat",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_toString",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_length_prop",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_clear",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_append_char",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_appendRange_obj_flat",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "endIndex", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder",
            isThrowing: false
        ),
    ]
}
