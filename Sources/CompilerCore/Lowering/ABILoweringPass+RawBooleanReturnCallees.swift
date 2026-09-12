import RuntimeABI

extension ABILoweringPass {
    /// Callees that return a raw 0/1 Boolean instead of a boxed Boolean handle.
    ///
    /// Derived from `RuntimeABISpec.rawBooleanReturnCalleeNames` so the
    /// raw-Boolean metadata is maintained in a single place.
    func rawBooleanReturnCallees(interner: StringInterner) -> Set<InternedString> {
        Set(RuntimeABISpec.rawBooleanReturnCalleeNames.map { interner.intern($0) })
    }
}
