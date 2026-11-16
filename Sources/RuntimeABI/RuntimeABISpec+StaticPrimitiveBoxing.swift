private let boxingABI = RuntimeABISectionBuilder("Boxing")

public extension RuntimeABISpec {
    /// ABI entry points emitted when ABILoweringPass has a statically-known
    /// primitive at a boxing boundary. They preserve the canonical Swift ARC
    /// box while using the tagged-handle fast path.
    static let staticPrimitiveBoxingFunctions: [RuntimeABIFunctionSpec] = [
        boxingABI.nt("kk_box_int_static", "value"),
        boxingABI.nt("kk_box_byte_static", "value"),
        boxingABI.nt("kk_box_short_static", "value"),
        boxingABI.nt("kk_box_uint_static", "value"),
        boxingABI.nt("kk_box_ubyte_static", "value"),
        boxingABI.nt("kk_box_ushort_static", "value"),
        boxingABI.nt("kk_box_bool_static", "value"),
        boxingABI.nt("kk_box_long_static", "value"),
        boxingABI.nt("kk_box_long_nonnull_static", "value"),
        boxingABI.nt("kk_box_ulong_static", "value"),
        boxingABI.nt("kk_box_ulong_nonnull_static", "value"),
        boxingABI.nt("kk_box_float_static", "value"),
        boxingABI.nt("kk_box_double_static", "value"),
        boxingABI.nt("kk_box_double_nonnull_static", "value"),
        boxingABI.nt("kk_box_char_static", "value"),
        boxingABI.nt("kk_unbox_int_static", "value"),
        boxingABI.nt("kk_unbox_bool_static", "value"),
        boxingABI.nt("kk_unbox_long_static", "value"),
        boxingABI.nt("kk_unbox_ulong_static", "value"),
        boxingABI.nt("kk_unbox_float_static", "value"),
        boxingABI.nt("kk_unbox_double_static", "value"),
        boxingABI.nt("kk_unbox_double_nonnull_static", "value"),
        boxingABI.nt("kk_unbox_char_static", "value"),
    ]
}
