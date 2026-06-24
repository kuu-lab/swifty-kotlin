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

        registerPathConstructor(
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [("pathString", types.stringType)],
            externalLinkName: "kk_path_new",
            symbols: symbols,
            interner: interner
        )

        // MARK: - Path properties

        registerPathMemberProperty(
            named: "name",
            externalLinkName: "kk_path_name",
            ownerSymbol: pathSymbol,
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberProperty(
            named: "fileName",
            externalLinkName: "kk_path_fileName",
            ownerSymbol: pathSymbol,
            returnType: nullablePathType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberProperty(
            named: "nameWithoutExtension",
            externalLinkName: "kk_path_nameWithoutExtension",
            ownerSymbol: pathSymbol,
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberProperty(
            named: "extension",
            externalLinkName: "kk_path_extension",
            ownerSymbol: pathSymbol,
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberProperty(
            named: "parent",
            externalLinkName: "kk_path_parent",
            ownerSymbol: pathSymbol,
            returnType: nullablePathType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberProperty(
            named: "root",
            externalLinkName: "kk_path_root",
            ownerSymbol: pathSymbol,
            returnType: nullablePathType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberProperty(
            named: "nameCount",
            externalLinkName: "kk_path_nameCount",
            ownerSymbol: pathSymbol,
            returnType: types.intType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberProperty(
            named: "isAbsolute",
            externalLinkName: "kk_path_isAbsolute",
            ownerSymbol: pathSymbol,
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionProperty(
            named: "name",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            returnType: types.stringType,
            externalLinkName: "kk_path_name",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionProperty(
            named: "extension",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            returnType: types.stringType,
            externalLinkName: "kk_path_extension",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionProperty(
            named: "nameWithoutExtension",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            returnType: types.stringType,
            externalLinkName: "kk_path_nameWithoutExtension",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "absolute",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [],
            returnType: pathType,
            externalLinkName: "kk_path_toAbsolutePath",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "relativeToOrSelf",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("base", pathType)],
            returnType: pathType,
            externalLinkName: "kk_path_relativeToOrSelf",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "relativeTo",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("base", pathType)],
            returnType: pathType,
            externalLinkName: "kk_path_relativeTo",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "relativeToOrNull",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("base", pathType)],
            returnType: nullablePathType,
            externalLinkName: "kk_path_relativeToOrNull",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "readSymbolicLink",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [],
            returnType: pathType,
            externalLinkName: "kk_path_readSymbolicLink",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "readAttributes",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("attributes", types.stringType), ("options", linkOptionType)],
            returnType: mapOfStringToNullableAnyType,
            externalLinkName: "kk_path_readAttributes_string",
            valueParameterIsVararg: [false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionProperty(
            named: "invariantSeparatorsPath",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            returnType: types.stringType,
            externalLinkName: "kk_path_invariantSeparatorsPath",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionProperty(
            named: "invariantSeparatorsPathString",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            returnType: types.stringType,
            externalLinkName: "kk_path_invariantSeparatorsPathString",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionProperty(
            named: "pathString",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            returnType: types.stringType,
            externalLinkName: "kk_path_pathString",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "appendLines",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("lines", iterableOfCharSequenceType)],
            returnType: pathType,
            externalLinkName: "kk_path_appendLines_iterable_default",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "appendLines",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("lines", iterableOfCharSequenceType), ("charset", charsetType)],
            returnType: pathType,
            externalLinkName: "kk_path_appendLines_iterable",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "writeLines",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [
                ("lines", iterableOfCharSequenceType),
                ("charset", charsetType),
                ("options", openOptionType),
            ],
            returnType: pathType,
            externalLinkName: "kk_path_writeLines_iterable",
            valueParameterHasDefaultValues: [false, true, false],
            valueParameterIsVararg: [false, false, true],
            symbols: symbols,
            interner: interner
        )

        let kotlinSequencesPkg = ensurePackage(path: ["kotlin", "sequences"], symbols: symbols, interner: interner)
        let kotlinSequencesPkgSymbol = symbols.lookup(fqName: kotlinSequencesPkg)
        let sequenceSymbol = ensureInterfaceSymbol(
            named: "Sequence",
            in: kotlinSequencesPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinSequencesPkgSymbol {
            symbols.setParentSymbol(kotlinSequencesPkgSymbol, for: sequenceSymbol)
        }
        let sequenceOfCharSequenceType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(charSequenceType)],
            nullability: .nonNull
        )))
        let sequenceOfStringType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(types.stringType)],
            nullability: .nonNull
        )))
        let sequenceOfPathType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(pathType)],
            nullability: .nonNull
        )))

        registerPathExtensionFunction(
            named: "appendLines",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("lines", sequenceOfCharSequenceType)],
            returnType: pathType,
            externalLinkName: "kk_path_appendLines_sequence_default",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "appendLines",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("lines", sequenceOfCharSequenceType), ("charset", charsetType)],
            returnType: pathType,
            externalLinkName: "kk_path_appendLines_sequence",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "writeLines",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [
                ("lines", sequenceOfCharSequenceType),
                ("charset", charsetType),
                ("options", openOptionType),
            ],
            returnType: pathType,
            externalLinkName: "kk_path_writeLines_sequence",
            valueParameterHasDefaultValues: [false, true, false],
            valueParameterIsVararg: [false, false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "absolutePathString",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [],
            returnType: types.stringType,
            externalLinkName: "kk_path_toAbsolutePathString",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "appendBytes",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("array", byteArrayType)],
            returnType: types.unitType,
            externalLinkName: "kk_path_appendBytes",
            symbols: symbols,
            interner: interner
        )

        registerPathMemberFunction(
            named: "toString",
            externalLinkName: "kk_path_toString",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [],
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberFunction(
            named: "resolve",
            externalLinkName: "kk_path_resolve_string",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [("other", types.stringType)],
            returnType: pathType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberFunction(
            named: "resolve",
            externalLinkName: "kk_path_resolve_path",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [("other", pathType)],
            returnType: pathType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberFunction(
            named: "relativize",
            externalLinkName: "kk_path_relativize",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [("other", pathType)],
            returnType: pathType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberFunction(
            named: "normalize",
            externalLinkName: "kk_path_normalize",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [],
            returnType: pathType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - Path query methods

        registerPathExtensionFunction(
            named: "exists",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("options", linkOptionType)],
            returnType: types.booleanType,
            externalLinkName: "kk_path_exists",
            valueParameterIsVararg: [true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "isDirectory",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("options", linkOptionType)],
            returnType: types.booleanType,
            externalLinkName: "kk_path_isDirectory",
            valueParameterIsVararg: [true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "isRegularFile",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("options", linkOptionType)],
            returnType: types.booleanType,
            externalLinkName: "kk_path_isRegularFile",
            valueParameterIsVararg: [true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "fileStore",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [],
            returnType: fileStoreType,
            externalLinkName: "kk_path_fileStore",
            symbols: symbols,
            interner: interner
        )

        registerPathReadAttributesFunction(
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            optionsType: linkOptionType,
            basicFileAttributesUpperBound: basicFileAttributesType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerPathFileAttributesViewFunction(
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            optionsType: linkOptionType,
            fileAttributeViewUpperBound: fileAttributeViewType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerPathFileAttributesViewOrNullFunction(
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            optionsType: linkOptionType,
            fileAttributeViewUpperBound: fileAttributeViewType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "getAttribute",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("attribute", types.stringType), ("options", linkOptionType)],
            returnType: types.anyType,
            externalLinkName: "kk_path_getAttribute",
            valueParameterIsVararg: [false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "getLastModifiedTime",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("options", linkOptionType)],
            returnType: fileTimeType,
            externalLinkName: "kk_path_getLastModifiedTime",
            valueParameterIsVararg: [true],
            symbols: symbols,
            interner: interner
        )

        for (name, link) in [
            ("isExecutable", "kk_path_isExecutable"),
            ("isHidden", "kk_path_isHidden"),
            ("isReadable", "kk_path_isReadable"),
            ("isSymbolicLink", "kk_path_isSymbolicLink"),
            ("isWritable", "kk_path_isWritable"),
        ] {
            registerPathExtensionFunction(
                named: name,
                packageFQName: kotlinIOPathPkg,
                receiverType: pathType,
                parameters: [],
                returnType: types.booleanType,
                externalLinkName: link,
                symbols: symbols,
                interner: interner
            )
        }

        registerPathExtensionFunction(
            named: "isSameFileAs",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("other", pathType)],
            returnType: types.booleanType,
            externalLinkName: "kk_path_isSameFileAs",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "notExists",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("options", linkOptionType)],
            returnType: types.booleanType,
            externalLinkName: "kk_path_notExists",
            valueParameterIsVararg: [true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "fileSize",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [],
            returnType: types.longType,
            externalLinkName: "kk_path_fileSize",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "forEachDirectoryEntry",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("glob", types.stringType), ("action", pathActionType)],
            returnType: types.unitType,
            externalLinkName: "kk_path_forEachDirectoryEntry",
            valueParameterHasDefaultValues: [true, false],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "forEachDirectoryEntry",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("action", pathActionType)],
            returnType: types.unitType,
            externalLinkName: "kk_path_forEachDirectoryEntry_default",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "forEachLine",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("charset", charsetType), ("action", stringActionType)],
            returnType: types.unitType,
            externalLinkName: "kk_path_forEachLine",
            valueParameterHasDefaultValues: [true, false],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "forEachLine",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("action", stringActionType)],
            returnType: types.unitType,
            externalLinkName: "kk_path_forEachLine_default",
            symbols: symbols,
            interner: interner
        )

        // MARK: - Path comparison methods

        registerPathMemberFunction(
            named: "startsWith",
            externalLinkName: "kk_path_startsWith_path",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [("other", pathType)],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberFunction(
            named: "startsWith",
            externalLinkName: "kk_path_startsWith_string",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [("other", types.stringType)],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberFunction(
            named: "endsWith",
            externalLinkName: "kk_path_endsWith_path",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [("other", pathType)],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberFunction(
            named: "endsWith",
            externalLinkName: "kk_path_endsWith_string",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [("other", types.stringType)],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - Path conversion methods

        registerPathMemberFunction(
            named: "toFile",
            externalLinkName: "kk_path_toFile",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [],
            returnType: fileType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberFunction(
            named: "toUri",
            externalLinkName: "kk_path_toUri",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [],
            returnType: uriType,
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "toPath",
            packageFQName: kotlinIOPathPkg,
            receiverType: uriType,
            parameters: [],
            returnType: pathType,
            externalLinkName: "kk_uri_toPath",
            symbols: symbols,
            interner: interner
        )

        registerPathMemberFunction(
            named: "toAbsolutePath",
            externalLinkName: "kk_path_toAbsolutePath",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [],
            returnType: pathType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberFunction(
            named: "getName",
            externalLinkName: "kk_path_getName",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [("index", types.intType)],
            returnType: pathType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - Path read/write methods

        registerPathExtensionFunction(
            named: "readBytes",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [],
            returnType: byteArrayType,
            externalLinkName: "kk_path_readBytes",
            symbols: symbols,
            interner: interner
        )

        registerPathMemberFunction(
            named: "readText",
            externalLinkName: "kk_path_readText",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [],
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberFunction(
            named: "writeText",
            externalLinkName: "kk_path_writeText",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [("text", types.stringType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberFunction(
            named: "readLines",
            externalLinkName: "kk_path_readLines",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [],
            returnType: listOfStringType,
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "readLines",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("charset", charsetType)],
            returnType: listOfStringType,
            externalLinkName: "kk_path_readLines_charset",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "readText",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("charset", charsetType)],
            returnType: types.stringType,
            externalLinkName: "kk_path_readText_charset",
            symbols: symbols,
            interner: interner
        )

        registerPathUseLinesFunction(
            ownerSymbol: pathSymbol,
            receiverType: pathType,
            sequenceOfStringType: sequenceOfStringType,
            charsetType: charsetType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "writeText",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [
                ("text", charSequenceType),
                ("charset", charsetType),
                ("options", openOptionType),
            ],
            returnType: pathType,
            externalLinkName: "kk_path_writeText_options",
            valueParameterHasDefaultValues: [false, true, false],
            valueParameterIsVararg: [false, false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "writeText",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [
                ("text", charSequenceType),
                ("charset", charsetType),
                ("options", openOptionType),
            ],
            returnType: pathType,
            externalLinkName: "kk_path_writeText_options",
            valueParameterHasDefaultValues: [false, true, false],
            valueParameterIsVararg: [false, false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "appendText",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("text", charSequenceType)],
            returnType: pathType,
            externalLinkName: "kk_path_appendText_default",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "appendText",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("text", charSequenceType), ("charset", charsetType)],
            returnType: pathType,
            externalLinkName: "kk_path_appendText",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "copyTo",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("target", pathType), ("options", copyOptionType)],
            returnType: pathType,
            externalLinkName: "kk_path_copyTo_options",
            valueParameterIsVararg: [false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "copyTo",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("target", pathType), ("overwrite", types.booleanType)],
            returnType: pathType,
            externalLinkName: "kk_path_copyTo_overwrite",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "writeBytes",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("array", byteArrayType), ("options", openOptionType)],
            returnType: types.unitType,
            externalLinkName: "kk_path_writeBytes",
            valueParameterIsVararg: [false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "writer",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [
                ("charset", charsetType),
                ("options", openOptionType),
            ],
            returnType: bufferedWriterType,
            externalLinkName: "kk_path_writer",
            valueParameterHasDefaultValues: [true, false],
            valueParameterIsVararg: [false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "outputStream",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("options", openOptionType)],
            returnType: outputStreamType,
            externalLinkName: "kk_path_outputStream",
            valueParameterIsVararg: [true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "inputStream",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("options", openOptionType)],
            returnType: inputStreamType,
            externalLinkName: "kk_path_inputStream",
            valueParameterIsVararg: [true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "bufferedReader",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [
                ("charset", charsetType),
                ("bufferSize", types.intType),
                ("options", openOptionType),
            ],
            returnType: bufferedReaderType,
            externalLinkName: "kk_path_bufferedReader",
            valueParameterHasDefaultValues: [true, true, false],
            valueParameterIsVararg: [false, false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "reader",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [
                ("charset", charsetType),
                ("options", openOptionType),
            ],
            returnType: bufferedReaderType,
            externalLinkName: "kk_path_reader",
            valueParameterHasDefaultValues: [true, false],
            valueParameterIsVararg: [false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "reader",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [],
            returnType: bufferedReaderType,
            externalLinkName: "kk_path_reader_default",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "bufferedWriter",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [
                ("charset", charsetType),
                ("bufferSize", types.intType),
                ("options", openOptionType),
            ],
            returnType: bufferedWriterType,
            externalLinkName: "kk_path_bufferedWriter",
            valueParameterHasDefaultValues: [true, true, false],
            valueParameterIsVararg: [false, false, true],
            symbols: symbols,
            interner: interner
        )

        // MARK: - Path filesystem operations

        registerPathMemberFunction(
            named: "createDirectories",
            externalLinkName: "kk_path_createDirectories",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [],
            returnType: pathType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberFunction(
            named: "createDirectories",
            externalLinkName: "kk_path_createDirectories_attributes",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [("attributes", fileAttributeStarType)],
            returnType: pathType,
            valueParameterIsVararg: [true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "createDirectories",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("attributes", fileAttributeStarType)],
            returnType: pathType,
            externalLinkName: "kk_path_createDirectories_attributes",
            valueParameterIsVararg: [true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "createSymbolicLinkPointingTo",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [
                ("target", pathType),
                ("attributes", fileAttributeStarType),
            ],
            returnType: pathType,
            externalLinkName: "kk_path_createSymbolicLinkPointingTo_attributes",
            valueParameterIsVararg: [false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "createDirectory",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("attributes", fileAttributeStarType)],
            returnType: pathType,
            externalLinkName: "kk_path_createDirectory_attributes",
            valueParameterIsVararg: [true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "createFile",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("attributes", fileAttributeStarType)],
            returnType: pathType,
            externalLinkName: "kk_path_createFile_attributes",
            valueParameterIsVararg: [true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "createParentDirectories",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("attributes", fileAttributeStarType)],
            returnType: pathType,
            externalLinkName: "kk_path_createParentDirectories_attributes",
            valueParameterIsVararg: [true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "createLinkPointingTo",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("target", pathType)],
            returnType: pathType,
            externalLinkName: "kk_path_createLinkPointingTo",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "deleteExisting",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [],
            returnType: types.unitType,
            externalLinkName: "kk_path_deleteExisting",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "deleteIfExists",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [],
            returnType: types.booleanType,
            externalLinkName: "kk_path_deleteIfExists",
            symbols: symbols,
            interner: interner
        )
        annotatePathExtensionFunction(
            named: "deleteIfExists",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [],
            annotations: pathDeleteIfExistsAnnotations(),
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "setOwner",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("value", userPrincipalType)],
            returnType: pathType,
            externalLinkName: "kk_path_setOwner",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "getOwner",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("options", linkOptionType)],
            returnType: userPrincipalType,
            externalLinkName: "kk_path_getOwner",
            valueParameterIsVararg: [true],
            symbols: symbols,
            interner: interner
        )
        registerPathExtensionFunction(
            named: "setAttribute",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [
                ("attribute", types.stringType),
                ("value", types.stringType),
                ("options", linkOptionType),
            ],
            returnType: pathType,
            externalLinkName: "kk_path_setAttribute",
            valueParameterIsVararg: [false, false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "setPosixFilePermissions",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("value", setOfPosixFilePermissionType)],
            returnType: pathType,
            externalLinkName: "kk_path_setPosixFilePermissions",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "getPosixFilePermissions",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("options", linkOptionType)],
            returnType: setOfPosixFilePermissionType,
            externalLinkName: "kk_path_getPosixFilePermissions",
            valueParameterIsVararg: [true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "deleteRecursively",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [],
            returnType: types.unitType,
            externalLinkName: "kk_path_deleteRecursively",
            symbols: symbols,
            interner: interner
        )

        let copyToRecursivelyOnErrorType = types.make(.functionType(FunctionType(
            params: [pathType, pathType, exceptionType],
            returnType: onErrorResultType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let copyToRecursivelyCopyActionType = types.make(.functionType(FunctionType(
            receiver: copyActionContextType,
            params: [pathType, pathType],
            returnType: copyActionResultType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerPathExtensionFunction(
            named: "copyToRecursively",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [
                ("target", pathType),
                ("onError", copyToRecursivelyOnErrorType),
                ("followLinks", types.booleanType),
                ("overwrite", types.booleanType),
            ],
            returnType: pathType,
            externalLinkName: "kk_path_copyToRecursively_overwrite",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "copyToRecursively",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [
                ("target", pathType),
                ("onError", copyToRecursivelyOnErrorType),
                ("followLinks", types.booleanType),
                ("copyAction", copyToRecursivelyCopyActionType),
            ],
            returnType: pathType,
            externalLinkName: "kk_path_copyToRecursively_copyAction",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "listDirectoryEntries",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("glob", types.stringType)],
            returnType: listOfPathType,
            externalLinkName: "kk_path_listDirectoryEntries",
            valueParameterHasDefaultValues: [true],
            symbols: symbols,
            interner: interner
        )

        registerPathUseDirectoryEntriesFunction(
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            sequenceOfPathType: sequenceOfPathType,
            globType: types.stringType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "walk",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("options", pathWalkOptionType)],
            returnType: sequenceOfPathType,
            externalLinkName: "kk_path_walk",
            valueParameterIsVararg: [true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "div",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("other", pathType)],
            returnType: pathType,
            externalLinkName: "kk_path_div_path",
            isOperator: true,
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "div",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("other", types.stringType)],
            returnType: pathType,
            externalLinkName: "kk_path_div_string",
            isOperator: true,
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "moveTo",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("target", pathType), ("overwrite", types.booleanType)],
            returnType: pathType,
            externalLinkName: "kk_path_moveTo_overwrite",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "moveTo",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("target", pathType), ("options", copyOptionType)],
            returnType: pathType,
            externalLinkName: "kk_path_moveTo_options",
            valueParameterIsVararg: [false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathTopLevelFunction(
            named: "createTempDirectory",
            packageFQName: kotlinIOPathPkg,
            parameters: [
                ("directory", nullablePathType),
                ("prefix", nullableStringType),
                ("attributes", fileAttributeStarType),
            ],
            returnType: pathType,
            externalLinkName: "kk_path_createTempDirectory_directory_prefix_attributes",
            valueParameterHasDefaultValues: [false, true, false],
            valueParameterIsVararg: [false, false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathTopLevelFunction(
            named: "createTempDirectory",
            packageFQName: kotlinIOPathPkg,
            parameters: [
                ("prefix", nullableStringType),
                ("attributes", fileAttributeStarType),
            ],
            returnType: pathType,
            externalLinkName: "kk_path_createTempDirectory_prefix_attributes",
            valueParameterHasDefaultValues: [true, false],
            valueParameterIsVararg: [false, true],
            symbols: symbols,
            interner: interner
        )

        // MARK: - Top-level Path() factory (kotlin.io.path.Path)

        registerPathTopLevelFunction(
            named: "Path",
            packageFQName: kotlinIOPathPkg,
            parameters: [("pathString", types.stringType)],
            returnType: pathType,
            externalLinkName: "kk_path_get",
            symbols: symbols,
            interner: interner
        )

        registerPathTopLevelFunction(
            named: "Path",
            packageFQName: kotlinIOPathPkg,
            parameters: [("base", types.stringType), ("subpaths", types.stringType)],
            returnType: pathType,
            externalLinkName: "kk_path_get_base_subpaths",
            valueParameterIsVararg: [false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathTopLevelFunction(
            named: "fileVisitor",
            packageFQName: kotlinIOPathPkg,
            parameters: [("builderAction", fileVisitorBuilderActionType)],
            returnType: fileVisitorOfPathType,
            externalLinkName: "kk_path_fileVisitor",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "visitFileTree",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [
                ("visitor", fileVisitorOfPathType),
                ("maxDepth", types.intType),
                ("followLinks", types.booleanType),
            ],
            returnType: types.unitType,
            externalLinkName: "kk_path_visitFileTree",
            valueParameterHasDefaultValues: [false, true, true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "visitFileTree",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [
                ("maxDepth", types.intType),
                ("followLinks", types.booleanType),
                ("builderAction", fileVisitorBuilderActionType),
            ],
            returnType: types.unitType,
            externalLinkName: "kk_path_visitFileTree_builder",
            valueParameterHasDefaultValues: [true, true, false],
            symbols: symbols,
            interner: interner
        )

        registerPathTopLevelFunction(
            named: "createTempFile",
            packageFQName: kotlinIOPathPkg,
            parameters: [
                ("directory", nullablePathType),
                ("prefix", nullableStringType),
                ("suffix", nullableStringType),
                ("attributes", fileAttributeStarType),
            ],
            returnType: pathType,
            externalLinkName: "kk_path_createTempFile_directory_prefix_suffix_attributes",
            valueParameterHasDefaultValues: [false, true, true, false],
            valueParameterIsVararg: [false, false, false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathTopLevelFunction(
            named: "createTempFile",
            packageFQName: kotlinIOPathPkg,
            parameters: [
                ("prefix", nullableStringType),
                ("suffix", nullableStringType),
                ("attributes", fileAttributeStarType),
            ],
            returnType: pathType,
            externalLinkName: "kk_path_createTempFile_prefix_suffix_attributes",
            valueParameterHasDefaultValues: [true, true, false],
            valueParameterIsVararg: [false, false, true],
            symbols: symbols,
            interner: interner
        )

        let pathsSymbol = ensureClassSymbol(
            named: "Paths",
            in: javaNioFilePkg,
            symbols: symbols,
            interner: interner
        )
        if let javaNioFilePkgSymbol {
            symbols.setParentSymbol(javaNioFilePkgSymbol, for: pathsSymbol)
        }
        let pathsType = types.make(.classType(ClassType(
            classSymbol: pathsSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(pathsType, for: pathsSymbol)

        registerPathMemberFunction(
            named: "get",
            externalLinkName: "kk_path_get",
            ownerSymbol: pathsSymbol,
            ownerType: pathsType,
            parameters: [("pathString", types.stringType)],
            returnType: pathType,
            symbols: symbols,
            interner: interner
        )
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
