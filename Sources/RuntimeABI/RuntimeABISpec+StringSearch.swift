/// String find/findLast search functions. `contains`/`indexOf`/`lastIndexOf`/
/// `indexOfAny`/`lastIndexOfAny`/`findAnyOf`/`findLastAnyOf`/`indexOfFirst`/
/// `indexOfLast` are bundled Kotlin source (KSP-408, StringIndexOf.kt); `find`/
/// `findLast` are bundled Kotlin source (KSP-410, StringHOF.kt). Their runtime
/// ABI entries were removed.
public extension RuntimeABISpec {
    static let stringSearchFunctions: [RuntimeABIFunctionSpec] = []
}
