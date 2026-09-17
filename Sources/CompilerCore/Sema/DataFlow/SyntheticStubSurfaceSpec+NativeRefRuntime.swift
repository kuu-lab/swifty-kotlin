enum SyntheticNativeRefRuntimeSurfaceSpec {
    private static let weakReferenceT = SyntheticStubTypeRef.typeParameter("T")
    static let weakReferenceType = SyntheticStubTypeRef.namedClass(
        ["kotlin", "native", "ref", "WeakReference"],
        args: [.invariant(weakReferenceT)]
    )
    static let weakReferenceMembers: [SyntheticFunctionStubSpec] = [
        SyntheticFunctionStubSpec(
            name: "get",
            externalLinkName: "kk_weak_ref_get",
            receiverType: weakReferenceType,
            returnType: .nullable(weakReferenceT),
            typeParameterNames: ["T"],
            classTypeParameterCount: 1
        ),
        SyntheticFunctionStubSpec(
            name: "clear",
            externalLinkName: "kk_weak_ref_clear",
            receiverType: weakReferenceType,
            returnType: .unit,
            typeParameterNames: ["T"],
            classTypeParameterCount: 1
        ),
    ]
}
