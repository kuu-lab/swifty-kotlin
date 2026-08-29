public extension RuntimeABISpec {
    /// StringBuilder mutable-buffer bridge.
    static let stringBuilderFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "__kk_string_builder_new",
            parameters: [],
            returnType: .intptr,
            section: "StringBuilder",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_builder_new_from_string_flat",
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
            name: "__kk_string_builder_new_capacity_checked",
            parameters: [
                RuntimeABIParameter(name: "capacity", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "StringBuilder"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_builder_append_obj",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_builder_append_char",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
                RuntimeABIParameter(name: "charRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_builder_append_char_array",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "endIndex", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "StringBuilder"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_builder_insert_obj",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "StringBuilder"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_builder_insert_char_sequence",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "StringBuilder"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_builder_insert_char_array",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "endIndex", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "StringBuilder"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_builder_index_of",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
                RuntimeABIParameter(name: "stringRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_builder_last_index_of",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
                RuntimeABIParameter(name: "stringRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_builder_set_length",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
                RuntimeABIParameter(name: "newLength", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "StringBuilder"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_builder_substring",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "endIndex", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "StringBuilder"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_builder_to_char_array",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
                RuntimeABIParameter(name: "destinationRaw", type: .intptr),
                RuntimeABIParameter(name: "destinationOffset", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "endIndex", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "StringBuilder"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_builder_length_utf16",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_builder_append_range",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "endIndex", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "StringBuilder"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_builder_append_obj_flat",
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
            name: "__kk_string_builder_toString",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_builder_length_prop",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_builder_clear",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder",
            isThrowing: false
        ),
    ]
}
