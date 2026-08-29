/// Source/imported-symbol routing for the common Closeable surface.
///
/// The common declarations are collected from bundled Kotlin source or loaded
/// from a precompiled stdlib artifact. Only the JVM `java.io.Closeable` anchor
/// remains synthetic for compatibility with existing Java-oriented IO stubs.
extension DataFlowSemaPhase {
    func initializeSourceBackedCloseableTypes(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPackage = [interner.intern("kotlin")]
        let autoCloseableFQName = kotlinPackage + [interner.intern("AutoCloseable")]
        let ioCloseableFQName = kotlinPackage + [
            interner.intern("io"),
            interner.intern("Closeable"),
        ]

        let autoCloseableSymbol = symbols.lookupAll(fqName: autoCloseableFQName).first {
            guard let symbol = symbols.symbol($0), symbol.kind == .interface else {
                return false
            }
            return !symbol.flags.contains(.synthetic) || symbol.flags.contains(.importedLibrary)
        }
        if let autoCloseableSymbol {
            types.closeableInterfaceSymbol = autoCloseableSymbol
            types.closeableTypeID = types.make(.classType(ClassType(
                classSymbol: autoCloseableSymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        guard let ioCloseableSymbol = symbols.lookupAll(fqName: ioCloseableFQName).first(where: {
            guard let symbol = symbols.symbol($0), symbol.kind == .interface else {
                return false
            }
            return !symbol.flags.contains(.synthetic) || symbol.flags.contains(.importedLibrary)
        }) else {
            return
        }
        types.ioCloseableInterfaceSymbol = ioCloseableSymbol

        let javaIOCloseableFQName = [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("Closeable"),
        ]
        guard let javaIOCloseableSymbol = symbols.lookup(fqName: javaIOCloseableFQName) else {
            return
        }

        var javaSupertypes = symbols.directSupertypes(for: javaIOCloseableSymbol)
        if !javaSupertypes.contains(ioCloseableSymbol) {
            javaSupertypes.append(ioCloseableSymbol)
            javaSupertypes.sort(by: { $0.rawValue < $1.rawValue })
            symbols.setDirectSupertypes(javaSupertypes, for: javaIOCloseableSymbol)
            types.setNominalDirectSupertypes(javaSupertypes, for: javaIOCloseableSymbol)
        }

        // FileIO stubs are registered before bundled headers. They initially
        // use the Java anchor, then switch to the source-backed common symbol.
        let syntheticJavaIOCloseableTypes = [
            "Reader", "BufferedReader", "Writer", "BufferedWriter",
            "InputStream", "OutputStream", "PrintWriter",
        ]
        for name in syntheticJavaIOCloseableTypes {
            let fqName = [
                interner.intern("java"),
                interner.intern("io"),
                interner.intern(name),
            ]
            guard let symbol = symbols.lookup(fqName: fqName),
                  let info = symbols.symbol(symbol),
                  info.flags.contains(.synthetic)
            else {
                continue
            }
            var supertypes = symbols.directSupertypes(for: symbol)
            guard supertypes.contains(javaIOCloseableSymbol) else {
                continue
            }
            supertypes.removeAll(where: { $0 == javaIOCloseableSymbol })
            if !supertypes.contains(ioCloseableSymbol) {
                supertypes.append(ioCloseableSymbol)
            }
            supertypes.sort(by: { $0.rawValue < $1.rawValue })
            symbols.setDirectSupertypes(supertypes, for: symbol)
            types.setNominalDirectSupertypes(supertypes, for: symbol)
        }
    }
}
