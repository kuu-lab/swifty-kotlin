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

    static let rootSetStatisticsType = nativeRuntimeClass("RootSetStatistics")
    static let rootSetStatisticsProperties: [SyntheticPropertyStubSpec] = [
        SyntheticPropertyStubSpec(name: "threadLocalReferences", propertyType: .long),
        SyntheticPropertyStubSpec(name: "stackReferences", propertyType: .long),
        SyntheticPropertyStubSpec(name: "globalReferences", propertyType: .long),
        SyntheticPropertyStubSpec(name: "stableReferences", propertyType: .long),
    ]
    static let rootSetStatisticsConstructor = constructor(from: rootSetStatisticsProperties)

    static let sweepStatisticsType = nativeRuntimeClass("SweepStatistics")

    static let memoryUsageType = nativeRuntimeClass("MemoryUsage")
    static let gcInfoProperties: [SyntheticPropertyStubSpec] = [
        SyntheticPropertyStubSpec(name: "epoch", propertyType: .long),
        SyntheticPropertyStubSpec(name: "startTimeNs", propertyType: .long),
        SyntheticPropertyStubSpec(name: "endTimeNs", propertyType: .long),
        SyntheticPropertyStubSpec(name: "firstPauseRequestTimeNs", propertyType: .long),
        SyntheticPropertyStubSpec(name: "firstPauseStartTimeNs", propertyType: .long),
        SyntheticPropertyStubSpec(name: "firstPauseEndTimeNs", propertyType: .long),
        SyntheticPropertyStubSpec(name: "secondPauseRequestTimeNs", propertyType: .nullable(.long)),
        SyntheticPropertyStubSpec(name: "secondPauseStartTimeNs", propertyType: .nullable(.long)),
        SyntheticPropertyStubSpec(name: "secondPauseEndTimeNs", propertyType: .nullable(.long)),
        SyntheticPropertyStubSpec(name: "postGcCleanupTimeNs", propertyType: .nullable(.long)),
        SyntheticPropertyStubSpec(name: "rootSet", propertyType: rootSetStatisticsType),
        SyntheticPropertyStubSpec(name: "markedCount", propertyType: .long),
        SyntheticPropertyStubSpec(name: "sweepStatistics", propertyType: mapOfString(to: sweepStatisticsType)),
        SyntheticPropertyStubSpec(name: "memoryUsageBefore", propertyType: mapOfString(to: memoryUsageType)),
        SyntheticPropertyStubSpec(name: "memoryUsageAfter", propertyType: mapOfString(to: memoryUsageType)),
    ]

    private static func nativeRuntimeClass(_ name: String) -> SyntheticStubTypeRef {
        .namedClass(["kotlin", "native", "runtime", name])
    }

    private static func mapOfString(to valueType: SyntheticStubTypeRef) -> SyntheticStubTypeRef {
        .fallback(
            primary: .namedClass(
                ["kotlin", "collections", "Map"],
                args: [.out(.string), .out(valueType)]
            ),
            fallback: .any
        )
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
