public extension RuntimeABISpec {
    static let kPropertyStubFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "__kk_kproperty_stub_create",
            parameters: [
                RuntimeABIParameter(name: "nameStr", type: .intptr),
                RuntimeABIParameter(name: "returnTypeStr", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kproperty_stub_create_cached",
            parameters: [
                RuntimeABIParameter(name: "nameStr", type: .intptr),
                RuntimeABIParameter(name: "returnTypeStr", type: .intptr),
                RuntimeABIParameter(name: "identityStr", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kproperty_stub_create_cached_typed",
            parameters: [
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
                RuntimeABIParameter(name: "returnTypeRaw", type: .intptr),
                RuntimeABIParameter(name: "identityRaw", type: .intptr),
                RuntimeABIParameter(name: "returnTypeKTypeRaw", type: .intptr),
                RuntimeABIParameter(name: "arity", type: .intptr),
                RuntimeABIParameter(name: "isMutable", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kproperty_stub_create_local",
            parameters: [
                RuntimeABIParameter(name: "nameStr", type: .intptr),
                RuntimeABIParameter(name: "returnTypeStr", type: .intptr),
                RuntimeABIParameter(name: "identityStr", type: .intptr),
                RuntimeABIParameter(name: "isMutable", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kproperty0_get",
            parameters: [
                RuntimeABIParameter(name: "raw", type: .intptr),
                RuntimeABIParameter(name: "interfaceTypeID", type: .intptr),
                RuntimeABIParameter(name: "methodSlot", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Delegate",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kproperty_stub_create_full",
            parameters: [
                RuntimeABIParameter(name: "nameStr", type: .intptr),
                RuntimeABIParameter(name: "returnTypeStr", type: .intptr),
                RuntimeABIParameter(name: "visibilityStr", type: .intptr),
                RuntimeABIParameter(name: "isLateinit", type: .intptr),
                RuntimeABIParameter(name: "isConst", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kproperty_stub_visibility",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kproperty_stub_is_lateinit",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kproperty_stub_is_const",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
    ]
}
