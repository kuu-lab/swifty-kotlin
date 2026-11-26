extension StdlibSurfaceSpec {
    static let listHOFMembers: [StdlibSurfaceSpec] = [
        list("forEach", 1, "kk_list_forEach", returnStrategy: .unit, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .unit)),
        list("firstNotNullOf", 1, "__kk_iterable_firstNotNullOf", returnStrategy: .any, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .nullableAny)),
        list("firstNotNullOfOrNull", 1, "__kk_iterable_firstNotNullOfOrNull", returnStrategy: .nullableAny, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .nullableAny)),
        list("maxOfOrNull", 1, "kk_list_maxOfOrNull", returnStrategy: .nullableAny, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
    ]
}
