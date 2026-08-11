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
        list("groupBy", 1, "kk_list_groupBy", returnStrategy: .map, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        list("associateBy", 1, "kk_list_associateBy", returnStrategy: .map, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        list("associateWith", 1, "kk_list_associateWith", returnStrategy: .map, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        list("associate", 1, "kk_list_associate", returnStrategy: .map, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        list("sumOf", 1, "kk_list_sumOf", returnStrategy: .int, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .int)),
        list("sumBy", 1, "kk_list_sumBy", returnStrategy: .int, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .int)),
        list("sumByDouble", 1, "kk_list_sumByDouble", returnStrategy: .double, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .double)),
        list("firstNotNullOf", 1, "__kk_iterable_firstNotNullOf", returnStrategy: .any, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .nullableAny)),
        list("firstNotNullOfOrNull", 1, "__kk_iterable_firstNotNullOfOrNull", returnStrategy: .nullableAny, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .nullableAny)),
        list("maxOfOrNull", 1, "kk_list_maxOfOrNull", returnStrategy: .nullableAny, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        list("onEach", 1, "kk_list_onEach", returnStrategy: .list, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .unit)),
        list("onEachIndexed", 1, "kk_list_onEachIndexed", returnStrategy: .list, lambdaExpectation: .indexedReceiverElement(argumentIndex: 0, returnStrategy: .unit)),
        list("takeWhile", 1, "kk_list_takeWhile", returnStrategy: .list, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        list("dropWhile", 1, "kk_list_dropWhile", returnStrategy: .list, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        list("takeLastWhile", 1, "kk_list_takeLastWhile", returnStrategy: .list, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        list("dropLastWhile", 1, "kk_list_dropLastWhile", returnStrategy: .list, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        list("associateTo", 2, "kk_list_associateTo", returnStrategy: .destinationArgument, lambdaExpectation: .destinationElement(argumentIndex: 1, returnStrategy: .pairOfDestinationKeyValue)),
        list("associateByTo", 2, "kk_list_associateByTo", returnStrategy: .destinationArgument, lambdaExpectation: .destinationElement(argumentIndex: 1, returnStrategy: .any)),
        list("associateWithTo", 2, "kk_list_associateWithTo", returnStrategy: .destinationArgument, lambdaExpectation: .destinationElement(argumentIndex: 1, returnStrategy: .any)),
        list("groupByTo", 2, "kk_list_groupByTo", returnStrategy: .destinationArgument, lambdaExpectation: .destinationElement(argumentIndex: 1, returnStrategy: .any)),
    ]
}
