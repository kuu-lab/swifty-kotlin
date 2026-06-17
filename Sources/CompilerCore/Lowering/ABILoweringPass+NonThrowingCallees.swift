import RuntimeABI

extension ABILoweringPass {
    /// Runtime callees that omit the `outThrown` ABI lowering path.
    ///
    /// Derived from `RuntimeABISpec.nonThrowingRuntimeCalleeNames` so throwing
    /// metadata is maintained in a single place (DEBT-KIR-003).
    func nonThrowingCallees(interner: StringInterner) -> Set<InternedString> {
        Set(RuntimeABISpec.nonThrowingRuntimeCalleeNames.map { interner.intern($0) })

    }
}
