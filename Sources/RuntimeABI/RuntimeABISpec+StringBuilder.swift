private let abi = RuntimeABISectionBuilder("StringBuilder")

public extension RuntimeABISpec {
    static let stringBuilderFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("__kk_string_builder_capacity", "sbRaw"),
        abi.nt("__kk_string_builder_ensure_capacity", "sbRaw minimumCapacity"),
        abi.nt("__kk_string_builder_trim_to_size", "sbRaw"),
        abi.nt("__kk_string_builder_new"),
        abi.nt("__kk_string_builder_new_from_string_flat", "data:nullableConstUInt8Pointer length byteCount hash"),
        abi.nt("__kk_string_builder_new_from_char_sequence", "valueRaw"),
        abi.th("__kk_string_builder_new_capacity_checked", "capacity outThrown"),
        abi.nt("__kk_string_builder_append_obj", "sbRaw valueRaw"),
        abi.nt("__kk_string_builder_append_char", "sbRaw charRaw"),
        abi.th("__kk_string_builder_append_char_array", "sbRaw arrayRaw startIndex endIndex outThrown"),
        abi.th("__kk_string_builder_insert_obj", "sbRaw index valueRaw outThrown"),
        abi.th("__kk_string_builder_insert_char_sequence", "sbRaw index valueRaw outThrown"),
        abi.th("__kk_string_builder_insert_char_array", "sbRaw index arrayRaw startIndex endIndex outThrown"),
        abi.nt("__kk_string_builder_index_of", "sbRaw stringRaw startIndex"),
        abi.nt("__kk_string_builder_last_index_of", "sbRaw stringRaw startIndex"),
        abi.th("__kk_string_builder_set_length", "sbRaw newLength outThrown"),
        abi.th("__kk_string_builder_substring", "sbRaw startIndex endIndex outThrown"),
        abi.th("__kk_string_builder_to_char_array", "sbRaw destinationRaw destinationOffset startIndex endIndex outThrown"),
        abi.nt("__kk_string_builder_length_utf16", "sbRaw"),
        abi.nt("__kk_string_builder_append_obj_flat", "sbRaw data:nullableConstUInt8Pointer length byteCount hash"),
        abi.nt("__kk_string_builder_toString", "sbRaw"),
        abi.th("__kk_string_builder_get", "sbRaw index outThrown"),
        abi.nt("__kk_string_builder_length_prop", "sbRaw"),
        abi.nt("__kk_string_builder_clear", "sbRaw"),
    ]
}
