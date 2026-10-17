public extension RuntimeABISpec {
    static var rawBooleanReturnCalleeNames: Set<String> {
        Set(allFunctions.lazy.filter(\.returnsRawBoolean).map(\.name))
    }
}
