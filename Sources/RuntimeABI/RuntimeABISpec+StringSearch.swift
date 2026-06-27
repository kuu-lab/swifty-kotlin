/// String indexOf, lastIndexOf, find, and related search functions.
public extension RuntimeABISpec {
    static let stringSearchFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_string_indexOf",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_lastIndexOf",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-TEXT-FN-020: CharSequence.indexOf(Char, startIndex, ignoreCase)
        RuntimeABIFunctionSpec(
            name: "kk_string_indexOf_char",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "charRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "ignoreCase", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-TEXT-EDGE-003: indexOf / lastIndexOf with ignoreCase
        RuntimeABIFunctionSpec(
            name: "kk_string_indexOf_ignoreCase",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "ignoreCase", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_lastIndexOf_ignoreCase",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "ignoreCase", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-TEXT-FN-034: CharSequence.lastIndexOf(Char, startIndex, ignoreCase)
        RuntimeABIFunctionSpec(
            name: "kk_string_lastIndexOf_char",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "charRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "ignoreCase", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_indexOf_from",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-TEXT-FN-021: CharSequence.indexOfAny(chars, startIndex=0, ignoreCase=false)
        RuntimeABIFunctionSpec(
            name: "kk_string_indexOfAny_chars",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "charsRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "ignoreCase", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-TEXT-FN-021: CharSequence.indexOfAny(strings, startIndex=0, ignoreCase=false)
        RuntimeABIFunctionSpec(
            name: "kk_string_indexOfAny_strings",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "stringsRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "ignoreCase", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_lastIndexOfAny_chars",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "charsRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "ignoreCase", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_lastIndexOfAny_strings",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "stringsRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "ignoreCase", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_findAnyOf",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "stringsRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "ignoreCase", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_findLastAnyOf",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "stringsRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "ignoreCase", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_indexOfFirst",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_indexOfLast",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_find",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_findLast",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-TEXT-FN-067
        RuntimeABIFunctionSpec(
            name: "kk_string_singleOrNull_predicate",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
    ]
}
