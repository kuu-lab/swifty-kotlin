private let abi = RuntimeABISectionBuilder("Delegate")

public extension RuntimeABISpec {
    static let kPropertyStubFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("__kk_kproperty_stub_create", "nameStr returnTypeStr"),
        abi.nt("__kk_kproperty_stub_create_cached", "nameStr returnTypeStr identityStr"),
        abi.nt("__kk_kproperty_stub_create_cached_typed", "nameRaw returnTypeRaw identityRaw returnTypeKTypeRaw arity isMutable"),
        abi.nt("__kk_kproperty_stub_create_local", "nameStr returnTypeStr identityStr isMutable"),
        abi.th("__kk_kproperty0_get", "raw interfaceTypeID methodSlot outThrown"),
        abi.th("__kk_kproperty_stub_create_full", "nameStr returnTypeStr visibilityStr isLateinit isConst"),
        abi.th("__kk_kproperty_stub_visibility", "handle"),
        abi.th("__kk_kproperty_stub_is_lateinit", "handle"),
        abi.th("__kk_kproperty_stub_is_const", "handle"),
    ]
}
