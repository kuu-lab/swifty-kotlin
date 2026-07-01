/// Synthetic Kotlin/JS `JsString` interop surface.
///
/// Covers the `kotlin.js.JsString` external class and the two conversion
/// functions that bridge between Kotlin `String` and the JS-native string type:
///
///   - `String.toJsString(): JsString`
///   - `JsString.toString(): String`
///
/// KSwiftK lowers `String.toJsString()` through a native runtime bridge so the
/// semantic surface is registered even in native builds.
extension DataFlowSemaPhase {
    func registerSyntheticJsStringInteropStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinJsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )

        let jsStringSymbol = ensureJsStringClass(
            packageFQName: kotlinJsPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerStringToJsStringExtension(
            kotlinJsPkg: kotlinJsPkg,
            jsStringSymbol: jsStringSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerJsStringToStringMember(
            kotlinJsPkg: kotlinJsPkg,
            jsStringSymbol: jsStringSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func ensureJsStringClass(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let className = interner.intern("JsString")
        let classFQName = packageFQName + [className]
        let classSymbol = symbols.define(
            kind: .class,
            name: className,
            fqName: classFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .openType]
        )
        symbols.insertFlags([.synthetic, .openType], for: classSymbol)
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: classSymbol)
        }

        let jsAnySymbol = ensureInterfaceSymbol(
            named: "JsAny",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: jsAnySymbol)
        }

        symbols.setDirectSupertypes([jsAnySymbol], for: classSymbol)
        types.setNominalDirectSupertypes([jsAnySymbol], for: classSymbol)

        let classType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(classType, for: classSymbol)
        appendSyntheticMetadataAnnotations(
            [jsStringInteropAnnotation()],
            to: classSymbol,
            symbols: symbols
        )

        return classSymbol
    }

    private func registerStringToJsStringExtension(
        kotlinJsPkg: [InternedString],
        jsStringSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let jsStringType = types.make(.classType(ClassType(
            classSymbol: jsStringSymbol,
            args: [],
            nullability: .nonNull
        )))

        let functionName = interner.intern("toJsString")
        let functionFQName = kotlinJsPkg + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == types.stringType
                && signature.parameterTypes.isEmpty
                && signature.returnType == jsStringType
        }) {
            symbols.setExternalLinkName("kk_string_toJsString_flat", for: existing)
            appendSyntheticMetadataAnnotations(
                [jsStringInteropAnnotation()],
                to: existing,
                symbols: symbols
            )
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: kotlinJsPkg) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: types.stringType,
                parameterTypes: [],
                returnType: jsStringType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: []
            ),
            for: functionSymbol
        )
        symbols.setExternalLinkName("kk_string_toJsString_flat", for: functionSymbol)
        appendSyntheticMetadataAnnotations(
            [jsStringInteropAnnotation()],
            to: functionSymbol,
            symbols: symbols
        )
    }

    private func registerJsStringToStringMember(
        kotlinJsPkg: [InternedString],
        jsStringSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let jsStringFQName = symbols.symbol(jsStringSymbol)?.fqName else { return }

        let jsStringType = types.make(.classType(ClassType(
            classSymbol: jsStringSymbol,
            args: [],
            nullability: .nonNull
        )))

        let memberName = interner.intern("toString")
        let memberFQName = jsStringFQName + [memberName]
        let alreadyRegistered = symbols.lookupAll(fqName: memberFQName).contains { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == jsStringType
                && signature.parameterTypes.isEmpty
                && signature.returnType == types.stringType
        }
        guard !alreadyRegistered else { return }

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(jsStringSymbol, for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: jsStringType,
                parameterTypes: [],
                returnType: types.stringType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: []
            ),
            for: memberSymbol
        )
    }

    private func jsStringInteropAnnotation() -> MetadataAnnotationRecord {
        MetadataAnnotationRecord(annotationFQName: "kotlin.js.ExperimentalWasmJsInterop")
    }
}
