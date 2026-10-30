/// The common declarations are collected from bundled Kotlin source or loaded
/// from a precompiled stdlib artifact. The JVM `java.io.Closeable` and
/// `java.lang.AutoCloseable` compatibility anchors remain synthetic for Java IO
/// types while inheriting the source-backed Kotlin contracts.
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
        guard let autoCloseableSymbol else {
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

        let javaLangAutoCloseableFQName = [
            interner.intern("java"),
            interner.intern("lang"),
            interner.intern("AutoCloseable"),
        ]
        if let javaLangAutoCloseableSymbol = symbols.lookup(fqName: javaLangAutoCloseableFQName) {
            var javaLangSupertypes = symbols.directSupertypes(for: javaLangAutoCloseableSymbol)
            if !javaLangSupertypes.contains(autoCloseableSymbol) {
                javaLangSupertypes.append(autoCloseableSymbol)
                javaLangSupertypes.sort(by: { $0.rawValue < $1.rawValue })
                symbols.setDirectSupertypes(javaLangSupertypes, for: javaLangAutoCloseableSymbol)
                types.setNominalDirectSupertypes(javaLangSupertypes, for: javaLangAutoCloseableSymbol)
            }
        }

        var javaSupertypes = symbols.directSupertypes(for: javaIOCloseableSymbol)
        if !javaSupertypes.contains(ioCloseableSymbol) {
            javaSupertypes.append(ioCloseableSymbol)
        }
        if let javaLangAutoCloseableSymbol = symbols.lookup(fqName: javaLangAutoCloseableFQName),
           !javaSupertypes.contains(javaLangAutoCloseableSymbol)
        {
            javaSupertypes.append(javaLangAutoCloseableSymbol)
        }
        javaSupertypes.sort(by: { $0.rawValue < $1.rawValue })
        symbols.setDirectSupertypes(javaSupertypes, for: javaIOCloseableSymbol)
        types.setNominalDirectSupertypes(javaSupertypes, for: javaIOCloseableSymbol)

        // java.io stream stubs are registered before bundled headers. They
        // initially use the Java anchor, then add the source-backed common
        // symbol while retaining the Java nominal edges. `PrintWriter` was
        // removed by CLEANUP-STUB-107 (it was reachable only via the
        // now-deleted `File.printWriter()` factory).
        let syntheticJavaIOCloseableTypes = [
            "Reader", "BufferedReader", "Writer", "BufferedWriter",
            "InputStream", "OutputStream",
        ]
        let javaCloseableSupertypes = [javaIOCloseableSymbol]
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
            if !supertypes.contains(ioCloseableSymbol) {
                supertypes.append(ioCloseableSymbol)
            }
            for javaCloseableSupertype in javaCloseableSupertypes where !supertypes.contains(javaCloseableSupertype) {
                supertypes.append(javaCloseableSupertype)
            }
            supertypes.sort(by: { $0.rawValue < $1.rawValue })
            symbols.setDirectSupertypes(supertypes, for: symbol)
            types.setNominalDirectSupertypes(supertypes, for: symbol)
        }
    }
}
