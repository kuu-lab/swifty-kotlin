extension StdlibSurfaceSpec {
    static func list(
        _ memberName: String,
        _ arity: Int,
        _ runtimeLinkName: String,
        returnStrategy: StdlibSurfaceReturnStrategy,
        lambdaExpectation: StdlibSurfaceLambdaExpectation
    ) -> StdlibSurfaceSpec {
        StdlibSurfaceSpec(
            package: .kotlinCollections,
            ownerKind: .list,
            memberName: memberName,
            arity: StdlibSurfaceArity(arity...arity),
            runtimeLinkName: runtimeLinkName,
            returnStrategy: returnStrategy,
            lambdaExpectation: lambdaExpectation
        )
    }

    static func sequence(
        _ memberName: String,
        _ arity: Int,
        _ runtimeLinkName: String,
        returnStrategy: StdlibSurfaceReturnStrategy,
        lambdaExpectation: StdlibSurfaceLambdaExpectation
    ) -> StdlibSurfaceSpec {
        StdlibSurfaceSpec(
            package: .kotlinSequences,
            ownerKind: .sequence,
            memberName: memberName,
            arity: StdlibSurfaceArity(arity...arity),
            runtimeLinkName: runtimeLinkName,
            returnStrategy: returnStrategy,
            lambdaExpectation: lambdaExpectation
        )
    }
}
