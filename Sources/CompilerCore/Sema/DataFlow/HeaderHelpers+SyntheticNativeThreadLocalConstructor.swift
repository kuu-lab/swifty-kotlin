/// Registers the native `kotlin.native.concurrent.ThreadLocal` annotation constructor.
extension DataFlowSemaPhase {
    func registerNativeThreadLocalAnnotationConstructor(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let annotationSymbol = symbols.lookup(
            fqName: packageFQName + [interner.intern("ThreadLocal")]
        ) else {
            return
        }

        let annotationType = types.make(.classType(ClassType(
            classSymbol: annotationSymbol,
            args: [],
            nullability: .nonNull
        )))
        registerNativeConcurrentConstructor(
            ownerSymbol: annotationSymbol,
            ownerType: annotationType,
            parameters: [],
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )
    }
}
