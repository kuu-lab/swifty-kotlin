private let abi = RuntimeABISectionBuilder("Array")

public extension RuntimeABISpec {
    static let arrayFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("__kk_array_new_same_component", "sourceRaw size"),
        abi.nt("__kk_array_component_type", "classifier element"),
        abi.nt("__kk_array_tag_component", "arrayRaw component"),
        abi.nt("kk_array_new", "length"),
        abi.th("kk_array_new_checked", "length outThrown"),
        abi.nt("kk_array_tag_type", "arrayRaw typeID"),
        abi.th("kk_array_of_nulls", "length outThrown"),
        abi.nt("kk_object_new", "length classId"),
        abi.nt("kk_runtime_register_data_class", "classID"),
        abi.nt("kk_runtime_register_data_class_fields", "classID mask"),
        abi.nt("kk_object_type_id", "objectRaw"),
        abi.th("kk_array_get", "arrayRaw index outThrown"),
        abi.nt("kk_array_get_inbounds", "arrayRaw index"),
        abi.th("kk_array_set", "arrayRaw index value outThrown"),
        abi.nt("kk_array_set_typed", "arrayRaw index value anyFallbackTag"),
        abi.nt("kk_vararg_spread_concat", "pairsArrayRaw pairCount"),
    ]
}
