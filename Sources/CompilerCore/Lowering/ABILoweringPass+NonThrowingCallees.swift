import RuntimeABI

extension ABILoweringPass {
    func nonThrowingCallees(interner: StringInterner) -> Set<InternedString> {
        Set(RuntimeABISpec.nonThrowingRuntimeCalleeNames.map { interner.intern($0) })
    }
}
