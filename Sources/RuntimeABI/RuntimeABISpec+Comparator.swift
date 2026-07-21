public extension RuntimeABISpec {
    static let comparatorFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_comparator_from_multi_selectors",
            parameters: [
                RuntimeABIParameter(name: "sel1Fnptr", type: .intptr),
                RuntimeABIParameter(name: "sel1Closure", type: .intptr),
                RuntimeABIParameter(name: "sel2Fnptr", type: .intptr),
                RuntimeABIParameter(name: "sel2Closure", type: .intptr),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_from_multi_selectors3",
            parameters: [
                RuntimeABIParameter(name: "sel1Fnptr", type: .intptr),
                RuntimeABIParameter(name: "sel1Closure", type: .intptr),
                RuntimeABIParameter(name: "sel2Fnptr", type: .intptr),
                RuntimeABIParameter(name: "sel2Closure", type: .intptr),
                RuntimeABIParameter(name: "sel3Fnptr", type: .intptr),
                RuntimeABIParameter(name: "sel3Closure", type: .intptr),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_from_multi_selectors_vararg",
            parameters: [
                RuntimeABIParameter(name: "selectors", type: .intptr),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_from_multi_selectors_trampoline",
            parameters: [
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_nulls_first",
            parameters: [
                RuntimeABIParameter(name: "cFn", type: .intptr),
                RuntimeABIParameter(name: "cClosure", type: .intptr),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_nulls_first_of",
            parameters: [
                RuntimeABIParameter(name: "cFn", type: .intptr),
                RuntimeABIParameter(name: "cClosure", type: .intptr),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_nulls_first_trampoline",
            parameters: [
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_nulls_last",
            parameters: [
                RuntimeABIParameter(name: "cFn", type: .intptr),
                RuntimeABIParameter(name: "cClosure", type: .intptr),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_nulls_last_of",
            parameters: [
                RuntimeABIParameter(name: "cFn", type: .intptr),
                RuntimeABIParameter(name: "cClosure", type: .intptr),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_nulls_last_trampoline",
            parameters: [
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_nulls_last_natural",
            parameters: [],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_nulls_last_natural_trampoline",
            parameters: [
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_nulls_first_comparable",
            parameters: [],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_nulls_first_comparable_trampoline",
            parameters: [
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_case_insensitive_order_trampoline",
            parameters: [
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_case_insensitive_order",
            parameters: [],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_compareValues",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_compareValuesBy1",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "selectorFnptr", type: .intptr),
                RuntimeABIParameter(name: "selectorClosure", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_compareValuesBy",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "sel1Fnptr", type: .intptr),
                RuntimeABIParameter(name: "sel1Closure", type: .intptr),
                RuntimeABIParameter(name: "sel2Fnptr", type: .intptr),
                RuntimeABIParameter(name: "sel2Closure", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_compareValuesBy3",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "sel1Fnptr", type: .intptr),
                RuntimeABIParameter(name: "sel1Closure", type: .intptr),
                RuntimeABIParameter(name: "sel2Fnptr", type: .intptr),
                RuntimeABIParameter(name: "sel2Closure", type: .intptr),
                RuntimeABIParameter(name: "sel3Fnptr", type: .intptr),
                RuntimeABIParameter(name: "sel3Closure", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_compareValuesByVararg",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "selectors", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_compareValuesByComparator",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "comparator", type: .intptr),
                RuntimeABIParameter(name: "selectorFnptr", type: .intptr),
                RuntimeABIParameter(name: "selectorClosure", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_compare_with_comparator",
            parameters: [
                RuntimeABIParameter(name: "comparator", type: .intptr),
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparable_compareTo",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Comparator",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_primitive_compareTo",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
                RuntimeABIParameter(name: "kindRaw", type: .int32),
            ],
            returnType: .intptr,
            section: "Comparator",
            isThrowing: false
        ),
    ]
}
