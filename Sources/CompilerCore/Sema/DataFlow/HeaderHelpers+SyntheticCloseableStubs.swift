/// Synthetic residuals for Closeable / AutoCloseable and the .use {} extension (STDLIB-520).
///
/// KSP-721: `kotlin.AutoCloseable` (interface + factory + `kotlin.use`) is now
/// Kotlin source (Stdlib/kotlin/AutoCloseable.kt). `kotlin.io.Closeable` extends
/// `AutoCloseable` and provides `kotlin.io.use` (Stdlib/kotlin/io/Closeable.kt).
///
/// What remains here is the `java.io.Closeable` compatibility anchor and the
/// `TypeSystem.closeable*` cache pointing at `kotlin.AutoCloseable` for the `.use {}`
/// inline lowering and `isCloseableReceiver` checks.
///
/// The .use extension is inline-expanded by CallLowerer: no runtime call is needed.
extension DataFlowSemaPhase {
    func registerSyntheticCloseableStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        if symbols.lookup(fqName: kotlinPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("kotlin"),
                fqName: kotlinPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let kotlinIOPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("io")]
        if symbols.lookup(fqName: kotlinIOPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("io"),
                fqName: kotlinIOPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let bundledIndex = BundledSyntheticStubRegistration.bundledIndex
        let closeName = interner.intern("close")

        // --- AutoCloseable interface (source-backed) ---
        // KSP-721: `kotlin.AutoCloseable` is the root closeable interface. The compiler
        // caches its symbol / TypeID so `.use {}` lowering and type checking treat both
        // `AutoCloseable` and `Closeable` (which extends it) as closeable receivers.
        let autoCloseableName = interner.intern("AutoCloseable")
        let autoCloseableFQName = kotlinPkg + [autoCloseableName]
        let hasSourceAutoCloseableClose = bundledIndex.contains(
            owner: autoCloseableFQName,
            name: closeName,
            arity: 0
        )
        let hasSourceAutoCloseableFactory = bundledIndex.contains(
            owner: kotlinPkg,
            name: autoCloseableName,
            arity: 1
        )
        let autoCloseableSymbol: SymbolID
        if let existing = symbols.lookupAll(fqName: autoCloseableFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .interface
        }) {
            autoCloseableSymbol = existing
        } else {
            let symbol = symbols.define(
                kind: .interface,
                name: autoCloseableName,
                fqName: autoCloseableFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            let autoCloseableType = types.make(.classType(ClassType(
                classSymbol: symbol, args: [], nullability: .nonNull
            )))
            // When the bundled source declaration is present it provides the
            // `close()` member; do not register a second copy.
            if !hasSourceAutoCloseableClose {
                let closeSymbol = symbols.define(
                    kind: .function,
                    name: closeName,
                    fqName: autoCloseableFQName + [closeName],
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(symbol, for: closeSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: autoCloseableType,
                        parameterTypes: [],
                        returnType: types.unitType
                    ),
                    for: closeSymbol
                )
            }
            autoCloseableSymbol = symbol
        }

        types.closeableInterfaceSymbol = autoCloseableSymbol

        let autoCloseableType = types.make(.classType(ClassType(
            classSymbol: autoCloseableSymbol, args: [], nullability: .nonNull
        )))
        types.closeableTypeID = autoCloseableType

        // --- Closeable interface ---
        let closeableName = interner.intern("Closeable")
        let closeableFQName = kotlinIOPkg + [closeableName]
        let closeableSymbol: SymbolID
        if let existing = symbols.lookupAll(fqName: closeableFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .interface
        }) {
            closeableSymbol = existing
        } else {
            let symbol = symbols.define(
                kind: .interface,
                name: closeableName,
                fqName: closeableFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setDirectSupertypes([autoCloseableSymbol], for: symbol)
            types.setNominalDirectSupertypes([autoCloseableSymbol], for: symbol)
            closeableSymbol = symbol
        }

        types.ioCloseableInterfaceSymbol = closeableSymbol

        let closeableType = types.make(.classType(ClassType(
            classSymbol: closeableSymbol, args: [], nullability: .nonNull
        )))

        let closeFQName = closeableFQName + [closeName]
        let hasSourceCloseableClose = bundledIndex.contains(
            owner: closeableFQName,
            name: closeName,
            arity: 0
        )
        if !hasSourceCloseableClose, symbols.lookup(fqName: closeFQName) == nil {
            let closeSymbol = symbols.define(
                kind: .function,
                name: closeName,
                fqName: closeFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(closeableSymbol, for: closeSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: closeableType,
                    parameterTypes: [],
                    returnType: types.unitType
                ),
                for: closeSymbol
            )
        }

        // KSP-721: the `AutoCloseable { closeAction }` factory and `kotlin.use` are
        // Kotlin source (Stdlib/kotlin/AutoCloseable.kt); `kotlin.io.use` is Kotlin
        // source (Stdlib/kotlin/io/Closeable.kt). No synthetic factory or type alias
        // is registered here.

        // --- java.io.Closeable interface (mirrors kotlin.io.Closeable) ---
        // On Kotlin/JVM java.io.Closeable is the canonical type; kswiftc maps it
        // to the synthetic kotlin.io.Closeable so that `import java.io.Closeable`
        // works in user code.
        let javaPkg: [InternedString] = [interner.intern("java")]
        if symbols.lookup(fqName: javaPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("java"),
                fqName: javaPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let javaIOPkg: [InternedString] = javaPkg + [interner.intern("io")]
        if symbols.lookup(fqName: javaIOPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("io"),
                fqName: javaIOPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let javaCloseableFQName = javaIOPkg + [closeableName]
        if symbols.lookup(fqName: javaCloseableFQName) == nil {
            let javaCloseableSymbol = symbols.define(
                kind: .interface,
                name: closeableName,
                fqName: javaCloseableFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            // Register java.io.Closeable → kotlin.io.Closeable supertype chain
            // so that isNominalSubtypeSymbol traversal finds kotlin.io.Closeable.
            symbols.setDirectSupertypes([closeableSymbol], for: javaCloseableSymbol)
            types.setNominalDirectSupertypes([closeableSymbol], for: javaCloseableSymbol)
        } else if let javaCloseableSymbol = symbols.lookup(fqName: javaCloseableFQName) {
            // STDLIB-SHARED-008: When java.io.Closeable is imported as a synthetic
            // nominal anchor from a prebuilt stdlib artifact, its direct supertype
            // is not serialized in metadata. Patch the supertype chain here so that
            // user classes implementing java.io.Closeable are also subtypes of
            // kotlin.io.Closeable, which lets `isCloseableReceiver` recognise them
            // and resolve `.use {}`.
            var supertypes = symbols.directSupertypes(for: javaCloseableSymbol)
            if !supertypes.contains(closeableSymbol) {
                supertypes.append(closeableSymbol)
                supertypes.sort(by: { $0.rawValue < $1.rawValue })
                symbols.setDirectSupertypes(supertypes, for: javaCloseableSymbol)
                types.setNominalDirectSupertypes(supertypes, for: javaCloseableSymbol)
            }
        }

        // --- T.use(block: (T) -> R): R ---
        // Synthetic fallback only runs when the bundled source declaration is absent.
        let useName = interner.intern("use")
        let nullableAutoCloseableType = types.makeNullable(autoCloseableType)
        let nullableCloseableType = types.makeNullable(closeableType)

        func registerUseFunction(in packageFQName: [InternedString], boundType: TypeID) {
            let useFQName = packageFQName + [useName]
            if symbols.lookup(fqName: useFQName) != nil {
                return
            }

            let tName = interner.intern("T")
            let rName = interner.intern("R")
            let tFQName = useFQName + [tName]
            let rFQName = useFQName + [rName]

            let tSymbol = symbols.define(
                kind: .typeParameter,
                name: tName,
                fqName: tFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: rFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )

            symbols.setTypeParameterUpperBounds([boundType], for: tSymbol)

            let tType = types.make(.typeParam(TypeParamType(symbol: tSymbol, nullability: .nonNull)))
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))

            let blockType = types.make(.functionType(FunctionType(
                params: [tType],
                returnType: rType,
                isSuspend: false,
                nullability: .nonNull
            )))

            let blockParamName = interner.intern("block")
            let blockParamSymbol = symbols.define(
                kind: .valueParameter,
                name: blockParamName,
                fqName: useFQName + [blockParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )

            let useSymbol = symbols.define(
                kind: .function,
                name: useName,
                fqName: useFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            if let packageSymbol = symbols.lookup(fqName: packageFQName) {
                symbols.setParentSymbol(packageSymbol, for: useSymbol)
            }
            symbols.setParentSymbol(useSymbol, for: tSymbol)
            symbols.setParentSymbol(useSymbol, for: rSymbol)
            symbols.setParentSymbol(useSymbol, for: blockParamSymbol)

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: tType,
                    parameterTypes: [blockType],
                    returnType: rType,
                    isSuspend: false,
                    valueParameterSymbols: [blockParamSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: [tSymbol, rSymbol],
                    typeParameterUpperBoundsList: [[boundType], []],
                    classTypeParameterCount: 0
                ),
                for: useSymbol
            )
        }

        if !hasSourceAutoCloseableClose && !hasSourceAutoCloseableFactory {
            registerUseFunction(in: kotlinPkg, boundType: nullableAutoCloseableType)
        }
        if !hasSourceCloseableClose {
            registerUseFunction(in: kotlinIOPkg, boundType: nullableCloseableType)
        }
    }
}
