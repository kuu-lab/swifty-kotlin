/// String find/findLast search functions. `contains`/`indexOf`/`lastIndexOf`/
/// `indexOfAny`/`lastIndexOfAny`/`findAnyOf`/`findLastAnyOf`/`indexOfFirst`/
/// `indexOfLast` are bundled Kotlin source (KSP-408, StringIndexOf.kt); their
/// runtime ABI entries were removed.
public extension RuntimeABISpec {
    static let stringSearchFunctions: [RuntimeABIFunctionSpec] = [
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
    ]
}
