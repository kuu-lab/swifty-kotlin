import RuntimeABI

extension ABILoweringPass {
    func rawBooleanReturnCallees(interner: StringInterner) -> Set<InternedString> {
        Set(RuntimeABISpec.rawBooleanReturnCalleeNames.map { interner.intern($0) })
    }
}
