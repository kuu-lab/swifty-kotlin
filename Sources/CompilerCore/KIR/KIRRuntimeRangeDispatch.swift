extension CallLowerer {
    func appendRuntimeRangeItableRegistrations(
        objectValue: KIRExprID,
        factoryName: InternedString,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        let className: String
        switch interner.resolve(factoryName) {
        case "kk_op_rangeTo", "__kk_op_rangeUntil":
            className = "IntRange"
        case "__kk_long_rangeTo", "__kk_long_rangeUntil":
            className = "LongRange"
        case "__kk_char_rangeTo", "__kk_char_rangeUntil":
            className = "CharRange"
        case "__kk_uint_rangeTo", "__kk_uint_rangeUntil":
            className = "UIntRange"
        case "__kk_ulong_rangeTo", "__kk_op_ulong_rangeUntil":
            className = "ULongRange"
        default:
            return
        }
        let package = [interner.intern("kotlin"), interner.intern("ranges")]
        guard let nominalSymbol = sema.symbols.lookup(fqName: package + [interner.intern(className)]),
            let closedRangeSymbol = sema.symbols.lookup(fqName: package + [interner.intern("ClosedRange")])
        else { return }
        appendObjectItableMethodRegistrations(
            objectValue: objectValue,
            nominalSymbol: nominalSymbol,
            driver: driver,
            sema: sema,
            arena: arena,
            interner: interner,
            interfaceFilter: closedRangeSymbol,
            instructions: &instructions
        )
    }
}
