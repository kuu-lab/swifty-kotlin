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

    static let gcType = nativeRuntimeClass("GC")
    static let gcFunctions: [SyntheticFunctionStubSpec] = [
        SyntheticFunctionStubSpec(
            name: "collect",
            externalLinkName: "kk_gc_collect",
            receiverType: gcType,
            returnType: .unit
        ),
        SyntheticFunctionStubSpec(
            name: "schedule",
            externalLinkName: "kk_gc_schedule",
            receiverType: gcType,
            returnType: .unit
        ),
    ]
    static let gcProperties: [SyntheticPropertyStubSpec] = [
        SyntheticPropertyStubSpec(
            name: "targetHeapBytes",
            propertyType: .long,
            externalLinkName: "kk_gc_target_heap_bytes"
        ),
        SyntheticPropertyStubSpec(
            name: "targetHeapUtilization",
            propertyType: .double,
            externalLinkName: "kk_gc_target_heap_utilization"
        ),
        SyntheticPropertyStubSpec(
            name: "maxHeapBytes",
            propertyType: .long,
            externalLinkName: "kk_gc_max_heap_bytes"
        ),
    ]

    static let rootSetStatisticsType = nativeRuntimeClass("RootSetStatistics")
    static let rootSetStatisticsProperties: [SyntheticPropertyStubSpec] = [
        SyntheticPropertyStubSpec(name: "threadLocalReferences", propertyType: .long),
        SyntheticPropertyStubSpec(name: "stackReferences", propertyType: .long),
        SyntheticPropertyStubSpec(name: "globalReferences", propertyType: .long),
        SyntheticPropertyStubSpec(name: "stableReferences", propertyType: .long),
    ]
    static let rootSetStatisticsConstructor = constructor(from: rootSetStatisticsProperties)

    private static func nativeRuntimeClass(_ name: String) -> SyntheticStubTypeRef {
        .namedClass(["kotlin", "native", "runtime", name])
    }

    private static func constructor(
        from properties: [SyntheticPropertyStubSpec]
    ) -> SyntheticConstructorStubSpec {
        SyntheticConstructorStubSpec(
            parameters: properties.map {
                SyntheticStubParameterSpec(name: $0.name, type: $0.propertyType)
            }
        )
    }
}
