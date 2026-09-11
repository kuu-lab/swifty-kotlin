public extension RuntimeABISpec {
    /// All runtime callee symbol names that return a raw 0/1 Boolean instead of
    /// a boxed Boolean handle.
    static var rawBooleanReturnCalleeNames: Set<String> {
        Set(allFunctions.lazy.filter(\.returnsRawBoolean).map(\.name))
    }
}
