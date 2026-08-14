// MARK: - List higher-order function surface
//
// Split from `StdlibSurfaceSpec.swift` so that parallel branches adding
// `kotlin.collections.List` member entries do not collide on the same
// central array. New `list(...)` entries go here.

extension StdlibSurfaceSpec {
    // KSP-421: List transform higher-order functions (map, mapIndexed,
    // mapNotNull, flatMap, flatMapIndexed, flatten, and their *To variants)
    // are now source-backed in
    // Sources/CompilerCore/Stdlib/kotlin/collections/ListHOF.kt.
    // The runtime bridge entries have been removed, so no list transform HOF
    // surface specs remain here.
    static let listHOFMembers: [StdlibSurfaceSpec] = [
        list("forEach", 1, "kk_list_forEach", returnStrategy: .unit, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .unit)),
        list("sumOf", 1, "kk_list_sumOf", returnStrategy: .int, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .int)),
        list("sumBy", 1, "kk_list_sumBy", returnStrategy: .int, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .int)),
        list("sumByDouble", 1, "kk_list_sumByDouble", returnStrategy: .double, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .double)),
        list("firstNotNullOf", 1, "__kk_iterable_firstNotNullOf", returnStrategy: .any, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .nullableAny)),
        list("firstNotNullOfOrNull", 1, "__kk_iterable_firstNotNullOfOrNull", returnStrategy: .nullableAny, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .nullableAny)),
        list("maxOfOrNull", 1, "kk_list_maxOfOrNull", returnStrategy: .nullableAny, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
    ]
}
