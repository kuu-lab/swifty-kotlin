/// Synthetic stubs for `kotlin.io.path.Path` and related types.
extension DataFlowSemaPhase {
    func registerSyntheticPathStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinIOPathPkg = ensureKotlinIOPathPackage(symbols: symbols, interner: interner)
        let kotlinIOPathPkgSymbol = symbols.lookup(fqName: kotlinIOPathPkg)

        let pathSymbol = ensureClassSymbol(
            named: "Path",
            in: kotlinIOPathPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinIOPathPkgSymbol {
            symbols.setParentSymbol(kotlinIOPathPkgSymbol, for: pathSymbol)
        }
        let pathType = types.make(.classType(ClassType(
            classSymbol: pathSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(pathType, for: pathSymbol)

        let nullablePathType = types.makeNullable(pathType)
        let pathActionType = types.make(.functionType(FunctionType(
            params: [pathType],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let kotlinPkg = ensurePackage(path: ["kotlin"], symbols: symbols, interner: interner)
        let kotlinCollectionsPkg = ensurePackage(path: ["kotlin", "collections"], symbols: symbols, interner: interner)
        let kotlinTextPkg = ensurePackage(path: ["kotlin", "text"], symbols: symbols, interner: interner)
        let kotlinPkgSymbol = symbols.lookup(fqName: kotlinPkg)
        let kotlinTextPkgSymbol = symbols.lookup(fqName: kotlinTextPkg)
        let javaNioFilePkg = ensurePackage(
            path: ["java", "nio", "file"],
            symbols: symbols,
            interner: interner
        )
        let javaNioFilePkgSymbol = symbols.lookup(fqName: javaNioFilePkg)

        let charSequenceSymbol = ensureInterfaceSymbol(
            named: "CharSequence",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinPkgSymbol {
            symbols.setParentSymbol(kotlinPkgSymbol, for: charSequenceSymbol)
        }
        let charSequenceType = types.make(.classType(ClassType(
            classSymbol: charSequenceSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(charSequenceType, for: charSequenceSymbol)

        let byteArraySymbol = ensureClassSymbol(
            named: "ByteArray",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinPkgSymbol {
            symbols.setParentSymbol(kotlinPkgSymbol, for: byteArraySymbol)
        }
        let byteArrayType = types.make(.classType(ClassType(
            classSymbol: byteArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(byteArrayType, for: byteArraySymbol)

        let charsetSymbol = ensureClassSymbol(
            named: "Charset",
            in: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinTextPkgSymbol {
            symbols.setParentSymbol(kotlinTextPkgSymbol, for: charsetSymbol)
        }
        let charsetType = types.make(.classType(ClassType(
            classSymbol: charsetSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(charsetType, for: charsetSymbol)
        let stringActionType = types.make(.functionType(FunctionType(
            params: [types.stringType],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let nullableStringType = types.makeNullable(types.stringType)

        let copyOptionPkg = ensurePackage(path: ["java", "nio", "file"], symbols: symbols, interner: interner)
        let copyOptionPkgSymbol = symbols.lookup(fqName: copyOptionPkg)
        let copyOptionSymbol = ensureInterfaceSymbol(
            named: "CopyOption",
            in: copyOptionPkg,
            symbols: symbols,
            interner: interner
        )
        if let copyOptionPkgSymbol {
            symbols.setParentSymbol(copyOptionPkgSymbol, for: copyOptionSymbol)
        }
        let copyOptionType = types.make(.classType(ClassType(
            classSymbol: copyOptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(copyOptionType, for: copyOptionSymbol)

        let openOptionSymbol = ensureInterfaceSymbol(
            named: "OpenOption",
            in: javaNioFilePkg,
            symbols: symbols,
            interner: interner
        )
        if let javaNioFilePkgSymbol {
            symbols.setParentSymbol(javaNioFilePkgSymbol, for: openOptionSymbol)
        }
        let openOptionType = types.make(.classType(ClassType(
            classSymbol: openOptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(openOptionType, for: openOptionSymbol)

        let linkOptionSymbol = ensureInterfaceSymbol(
            named: "LinkOption",
            in: javaNioFilePkg,
            symbols: symbols,
            interner: interner
        )
        if let javaNioFilePkgSymbol {
            symbols.setParentSymbol(javaNioFilePkgSymbol, for: linkOptionSymbol)
        }
        let linkOptionType = types.make(.classType(ClassType(
            classSymbol: linkOptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(linkOptionType, for: linkOptionSymbol)

        let standardOpenOptionFQName = javaNioFilePkg + [interner.intern("StandardOpenOption")]
        let standardOpenOptionSymbol: SymbolID
        if let existing = symbols.lookup(fqName: standardOpenOptionFQName) {
            standardOpenOptionSymbol = existing
        } else {
            let soName = interner.intern("StandardOpenOption")
            standardOpenOptionSymbol = symbols.define(
                kind: .enumClass,
                name: soName,
                fqName: standardOpenOptionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let javaNioFilePkgSymbol {
                symbols.setParentSymbol(javaNioFilePkgSymbol, for: standardOpenOptionSymbol)
            }
            symbols.setPropertyType(openOptionType, for: standardOpenOptionSymbol)
            types.setNominalDirectSupertypes(
                types.directNominalSupertypes(for: standardOpenOptionSymbol) + [openOptionSymbol],
                for: standardOpenOptionSymbol
            )
            for constantName in ["READ", "WRITE", "APPEND", "TRUNCATE_EXISTING", "CREATE",
                                  "CREATE_NEW", "DELETE_ON_CLOSE", "SPARSE", "SYNC", "DSYNC"] {
                let entryName = interner.intern(constantName)
                let entryFQName = standardOpenOptionFQName + [entryName]
                if symbols.lookup(fqName: entryFQName) == nil {
                    let entrySymbol = symbols.define(
                        kind: .field,
                        name: entryName,
                        fqName: entryFQName,
                        declSite: nil,
                        visibility: .public,
                        flags: [.synthetic]
                    )
                    symbols.setParentSymbol(standardOpenOptionSymbol, for: entrySymbol)
                    symbols.setPropertyType(openOptionType, for: entrySymbol)
                }
            }
        }

        registerPathCopyActionContextSurface(
            packageFQName: kotlinIOPathPkg,
            packageSymbol: kotlinIOPathPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerPathExperimentalPathApiAnnotation(
            packageFQName: kotlinIOPathPkg,
            packageSymbol: kotlinIOPathPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerPathFileVisitorBuilderSurface(
            packageFQName: kotlinIOPathPkg,
            packageSymbol: kotlinIOPathPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let fileVisitorBuilderSymbol = ensureInterfaceSymbol(
            named: "FileVisitorBuilder",
            in: kotlinIOPathPkg,
            symbols: symbols,
            interner: interner
        )
        let fileVisitorBuilderType = types.make(.classType(ClassType(
            classSymbol: fileVisitorBuilderSymbol,
            args: [],
            nullability: .nonNull
        )))
        let fileVisitorBuilderActionType = types.make(.functionType(FunctionType(
            receiver: fileVisitorBuilderType,
            params: [],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let onErrorResultSymbol = ensurePathOnErrorResultEnum(
            in: kotlinIOPathPkg,
            packageSymbol: kotlinIOPathPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        let onErrorResultType = types.make(.classType(ClassType(
            classSymbol: onErrorResultSymbol,
            args: [],
            nullability: .nonNull
        )))
        setPathEnumEntryTypes(
            enumSymbol: onErrorResultSymbol,
            enumType: onErrorResultType,
            symbols: symbols
        )

        let pathWalkOptionSymbol = ensurePathWalkOptionEnum(
            in: kotlinIOPathPkg,
            packageSymbol: kotlinIOPathPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        let pathWalkOptionType = types.make(.classType(ClassType(
            classSymbol: pathWalkOptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(pathWalkOptionType, for: pathWalkOptionSymbol)
        setPathEnumEntryTypes(
            enumSymbol: pathWalkOptionSymbol,
            enumType: pathWalkOptionType,
            symbols: symbols
        )

        let copyActionResultSymbol = ensurePathCopyActionResultEnum(
            in: kotlinIOPathPkg,
            packageSymbol: kotlinIOPathPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        let copyActionResultType = types.make(.classType(ClassType(
            classSymbol: copyActionResultSymbol,
            args: [],
            nullability: .nonNull
        )))
        setPathEnumEntryTypes(
            enumSymbol: copyActionResultSymbol,
            enumType: copyActionResultType,
            symbols: symbols
        )

        let exceptionSymbol = ensureClassSymbol(
            named: "Exception",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinPkgSymbol {
            symbols.setParentSymbol(kotlinPkgSymbol, for: exceptionSymbol)
        }
        let exceptionType = types.make(.classType(ClassType(
            classSymbol: exceptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(exceptionType, for: exceptionSymbol)

        let copyActionContextSymbol = ensureInterfaceSymbol(
            named: "CopyActionContext",
            in: kotlinIOPathPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinIOPathPkgSymbol {
            symbols.setParentSymbol(kotlinIOPathPkgSymbol, for: copyActionContextSymbol)
        }
        let copyActionContextType = types.make(.classType(ClassType(
            classSymbol: copyActionContextSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(copyActionContextType, for: copyActionContextSymbol)

        let listSymbol = resolvePathListSymbol(symbols: symbols, interner: interner)
        if listSymbol == nil {
            assertionFailure("kotlin.collections.List symbol not found; Path stubs will use Any as fallback")
        }
        let listOfPathType: TypeID = if let listSym = listSymbol {
            types.make(.classType(ClassType(
                classSymbol: listSym,
                args: [.out(pathType)],
                nullability: .nonNull
            )))
        } else {
            types.anyType
        }

        let iterableFQName = kotlinCollectionsPkg + [interner.intern("Iterable")]
        let iterableSymbol = symbols.lookup(fqName: iterableFQName) ?? registerSyntheticIterableStub(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )
        let iterableOfCharSequenceType = types.make(.classType(ClassType(
            classSymbol: iterableSymbol,
            args: [.invariant(charSequenceType)],
            nullability: .nonNull
        )))

        let mapSymbol = symbols.lookup(
            fqName: kotlinCollectionsPkg + [interner.intern("Map")]
        ) ?? registerSyntheticMapStub(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        ).mapSymbol
        let mapOfStringToNullableAnyType = types.make(.classType(ClassType(
            classSymbol: mapSymbol,
            args: [.invariant(types.stringType), .out(types.nullableAnyType)],
            nullability: .nonNull
        )))

        let listOfStringType: TypeID = if let listSym = listSymbol {
            types.make(.classType(ClassType(
                classSymbol: listSym,
                args: [.out(types.stringType)],
                nullability: .nonNull
            )))
        } else {
            types.anyType
        }
        let javaIOPkg = ensurePackage(path: ["java", "io"], symbols: symbols, interner: interner)
        let javaIOPkgSymbol = symbols.lookup(fqName: javaIOPkg)
        let fileSymbol = symbols.lookup(fqName: javaIOPkg + [interner.intern("File")])
        let fileType: TypeID = if let fileSym = fileSymbol {
            types.make(.classType(ClassType(
                classSymbol: fileSym, args: [], nullability: .nonNull
            )))
        } else {
            types.anyType
        }

        let bufferedReaderSymbol = ensureClassSymbol(
            named: "BufferedReader",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaIOPkgSymbol {
            symbols.setParentSymbol(javaIOPkgSymbol, for: bufferedReaderSymbol)
        }
        let bufferedReaderType = types.make(.classType(ClassType(
            classSymbol: bufferedReaderSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(bufferedReaderType, for: bufferedReaderSymbol)

        let bufferedWriterSymbol = ensureClassSymbol(
            named: "BufferedWriter",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaIOPkgSymbol {
            symbols.setParentSymbol(javaIOPkgSymbol, for: bufferedWriterSymbol)
        }
        let bufferedWriterType = types.make(.classType(ClassType(
            classSymbol: bufferedWriterSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(bufferedWriterType, for: bufferedWriterSymbol)

        let outputStreamSymbol = ensureClassSymbol(
            named: "OutputStream",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaIOPkgSymbol {
            symbols.setParentSymbol(javaIOPkgSymbol, for: outputStreamSymbol)
        }
        let outputStreamType = types.make(.classType(ClassType(
            classSymbol: outputStreamSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(outputStreamType, for: outputStreamSymbol)

        let inputStreamSymbol = ensureClassSymbol(
            named: "InputStream",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaIOPkgSymbol {
            symbols.setParentSymbol(javaIOPkgSymbol, for: inputStreamSymbol)
        }
        let inputStreamType = types.make(.classType(ClassType(
            classSymbol: inputStreamSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(inputStreamType, for: inputStreamSymbol)

        let javaNetPkg = ensurePackage(
            path: ["java", "net"],
            symbols: symbols,
            interner: interner
        )
        let javaNetPkgSymbol = symbols.lookup(fqName: javaNetPkg)
        let uriSymbol = ensureClassSymbol(
            named: "URI",
            in: javaNetPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaNetPkgSymbol {
            symbols.setParentSymbol(javaNetPkgSymbol, for: uriSymbol)
        }
        let uriType = types.make(.classType(ClassType(
            classSymbol: uriSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(uriType, for: uriSymbol)

        let javaNioFilePackage = ensurePackage(
            path: ["java", "nio", "file"],
            symbols: symbols,
            interner: interner
        )
        let javaNioFilePackageSymbol = symbols.lookup(fqName: javaNioFilePackage)
        let fileStoreSymbol = ensureClassSymbol(
            named: "FileStore",
            in: javaNioFilePackage,
            symbols: symbols,
            interner: interner
        )
        if let javaNioFilePackageSymbol {
            symbols.setParentSymbol(javaNioFilePackageSymbol, for: fileStoreSymbol)
        }
        let fileStoreType = types.make(.classType(ClassType(
            classSymbol: fileStoreSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(fileStoreType, for: fileStoreSymbol)

        let fileVisitorSymbol = ensureGenericPathFileVisitorSymbol(
            in: javaNioFilePackage,
            packageSymbol: javaNioFilePackageSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let fileVisitorOfPathType = types.make(.classType(ClassType(
            classSymbol: fileVisitorSymbol,
            args: [.invariant(pathType)],
            nullability: .nonNull
        )))

        let javaNioFileAttributePkg = ensurePackage(
            path: ["java", "nio", "file", "attribute"],
            symbols: symbols,
            interner: interner
        )
        let javaNioFileAttributePkgSymbol = symbols.lookup(fqName: javaNioFileAttributePkg)
        let userPrincipalSymbol = ensureInterfaceSymbol(
            named: "UserPrincipal",
            in: javaNioFileAttributePkg,
            symbols: symbols,
            interner: interner
        )
        if let javaNioFileAttributePkgSymbol {
            symbols.setParentSymbol(javaNioFileAttributePkgSymbol, for: userPrincipalSymbol)
        }
        let userPrincipalType = types.make(.classType(ClassType(
            classSymbol: userPrincipalSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(userPrincipalType, for: userPrincipalSymbol)

        let fileAttributeViewSymbol = ensureInterfaceSymbol(
            named: "FileAttributeView",
            in: javaNioFileAttributePkg,
            symbols: symbols,
            interner: interner
        )
        if let javaNioFileAttributePkgSymbol {
            symbols.setParentSymbol(javaNioFileAttributePkgSymbol, for: fileAttributeViewSymbol)
        }
        let fileAttributeViewType = types.make(.classType(ClassType(
            classSymbol: fileAttributeViewSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(fileAttributeViewType, for: fileAttributeViewSymbol)

        let fileAttributeSymbol = ensureGenericFileAttributeSymbol(
            in: javaNioFileAttributePkg,
            packageSymbol: javaNioFileAttributePkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let fileAttributeStarType = types.make(.classType(ClassType(
            classSymbol: fileAttributeSymbol,
            args: [.star],
            nullability: .nonNull
        )))

        let basicFileAttributesSymbol = ensureInterfaceSymbol(
            named: "BasicFileAttributes",
            in: javaNioFileAttributePkg,
            symbols: symbols,
            interner: interner
        )
        if let javaNioFileAttributePkgSymbol {
            symbols.setParentSymbol(javaNioFileAttributePkgSymbol, for: basicFileAttributesSymbol)
        }
        let basicFileAttributesType = types.make(.classType(ClassType(
            classSymbol: basicFileAttributesSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(basicFileAttributesType, for: basicFileAttributesSymbol)

        let fileTimeSymbol = ensureClassSymbol(
            named: "FileTime",
            in: javaNioFileAttributePkg,
            symbols: symbols,
            interner: interner
        )
        if let javaNioFileAttributePkgSymbol {
            symbols.setParentSymbol(javaNioFileAttributePkgSymbol, for: fileTimeSymbol)
        }
        let fileTimeType = types.make(.classType(ClassType(
            classSymbol: fileTimeSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(fileTimeType, for: fileTimeSymbol)

        let posixFilePermissionName = interner.intern("PosixFilePermission")
        let posixFilePermissionFQName = javaNioFileAttributePkg + [posixFilePermissionName]
        let posixFilePermissionSymbol = symbols.lookup(fqName: posixFilePermissionFQName) ?? symbols.define(
            kind: .enumClass,
            name: posixFilePermissionName,
            fqName: posixFilePermissionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let javaNioFileAttributePkgSymbol {
            symbols.setParentSymbol(javaNioFileAttributePkgSymbol, for: posixFilePermissionSymbol)
        }
        let posixFilePermissionType = types.make(.classType(ClassType(
            classSymbol: posixFilePermissionSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(posixFilePermissionType, for: posixFilePermissionSymbol)

        let setOfPosixFilePermissionType: TypeID = if let setSymbol = symbols.lookup(
            fqName: [interner.intern("kotlin"), interner.intern("collections"), interner.intern("Set")]
        ) {
            types.make(.classType(ClassType(
                classSymbol: setSymbol,
                args: [.out(posixFilePermissionType)],
                nullability: .nonNull
            )))
        } else {
            types.anyType
        }

    }

    // MARK: - Package Utilities

    private func resolvePathListSymbol(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID? {
        let listFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]
        return symbols.lookup(fqName: listFQName)
    }

    private func ensureKotlinIOPathPackage(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
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
        let kotlinIOPkg: [InternedString] = kotlinPkg + [interner.intern("io")]
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
        let kotlinIOPathPkg: [InternedString] = kotlinIOPkg + [interner.intern("path")]
        if symbols.lookup(fqName: kotlinIOPathPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("path"),
                fqName: kotlinIOPathPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        return kotlinIOPathPkg
    }
}
