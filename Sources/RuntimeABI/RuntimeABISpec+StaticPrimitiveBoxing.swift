public extension RuntimeABISpec {
    /// ABI entry points emitted when ABILoweringPass has a statically-known
    /// primitive at a boxing boundary. They preserve the canonical Swift ARC
    /// box while using the tagged-handle fast path.
    static let staticPrimitiveBoxingFunctions: [RuntimeABIFunctionSpec] = [
        "kk_box_int_static",
        "kk_box_uint_static",
        "kk_box_ubyte_static",
        "kk_box_ushort_static",
        "kk_box_bool_static",
        "kk_box_long_static",
        "kk_box_long_nonnull_static",
        "kk_box_ulong_static",
        "kk_box_ulong_nonnull_static",
        "kk_box_float_static",
        "kk_box_double_static",
        "kk_box_double_nonnull_static",
        "kk_box_char_static",
        "kk_unbox_int_static",
        "kk_unbox_bool_static",
        "kk_unbox_long_static",
        "kk_unbox_ulong_static",
        "kk_unbox_float_static",
        "kk_unbox_double_static",
        "kk_unbox_char_static",
    ].map { name in
        RuntimeABIFunctionSpec(
            name: name,
            parameters: [RuntimeABIParameter(name: "value", type: .intptr)],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        )
    }
}
