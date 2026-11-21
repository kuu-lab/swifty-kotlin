extension DataFlowSemaPhase {

    func registerSyntheticSystemMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        registerSyntheticFunctionStub(
            named: name,
            ownerFQName: ownerInfo.fqName,
            parentSymbol: ownerSymbol,
            receiverType: ownerType,
            parameters: syntheticFunctionParameters(parameters),
            returnType: returnType,
            externalLinkName: externalLinkName,
            matchReturnType: true,
            symbols: symbols,
            interner: interner
        )
    }

    func registerSyntheticTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        annotations: [MetadataAnnotationRecord] = [],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionFQName = packageFQName + [interner.intern(name)]
        if symbols.deferWorkUntilImportedMemberMaterializes(at: functionFQName, work: { [self] in
            registerSyntheticTopLevelFunction(
                named: name,
                packageFQName: packageFQName,
                parameters: parameters,
                returnType: returnType,
                externalLinkName: externalLinkName,
                annotations: annotations,
                symbols: symbols,
                interner: interner
            )
        }) {
            return
        }
        _ = registerSyntheticFunctionStub(
            named: name,
            ownerFQName: packageFQName,
            parentSymbol: symbols.lookup(fqName: packageFQName),
            parameters: syntheticFunctionParameters(parameters),
            returnType: returnType,
            externalLinkName: externalLinkName,
            annotations: annotations,
            matchReturnType: true,
            symbols: symbols,
            interner: interner
        )
    }

    func registerSyntheticJavaIOStreamStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let javaIOPkg = ensureJavaIOPackage(symbols: symbols, interner: interner)
        let javaIOCloseableSymbol = ensureJavaIOCloseableCompatibilityAnchor(
            symbols: symbols,
            interner: interner
        )
        _ = ensureJavaLangAutoCloseableCompatibilityAnchor(
            symbols: symbols,
            interner: interner
        )
        let javaIOPkgSymbol = symbols.lookup(fqName: javaIOPkg)

        let fileSymbol = ensureClassSymbol(
            named: "File",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaIOPkgSymbol {
            symbols.setParentSymbol(javaIOPkgSymbol, for: fileSymbol)
        }
        let fileType = types.make(.classType(ClassType(
            classSymbol: fileSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(fileType, for: fileSymbol)
        let hasSourceBackedFileContract = symbols.symbol(fileSymbol).map { symbol in
            symbol.declSite != nil || !symbol.flags.contains(.synthetic)
        } ?? false

        let listSymbol = resolveListSymbol(symbols: symbols, interner: interner)
        if listSymbol == nil {
            assertionFailure("kotlin.collections.List symbol not found; java.io stream stubs will use Any as fallback")
        }

        let listOfStringType: TypeID = if let listSym = listSymbol {
            types.make(.classType(ClassType(
                classSymbol: listSym,
                args: [.out(types.stringType)],
                nullability: .nonNull
            )))
        } else {
            types.anyType
        }

        let stringToUnitType = types.make(.functionType(FunctionType(
            params: [types.stringType],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))

        if !hasSourceBackedFileContract {
            _ = ensureSyntheticCompanionSymbol(
                ownerSymbol: fileSymbol,
                symbols: symbols,
                interner: interner
            )

            // KSP-483: `path` reads File's internal state, so it stays a direct
            // synthetic member (not migrated to Kotlin source). A Kotlin-source
            // extension property named `path` would collide with the
            // `kotlin.io.path` package FQName in this compiler's symbol table.
            // Consumed by `Stdlib/kotlin/io/Files.kt`'s pure-logic extension
            // properties, `FileIO.kt`'s line-iteration helpers, and by
            // `kotlin.io.FileSystemException.file`/`.other` (KSP-619).
            registerFileMemberProperty(
                named: "path",
                externalLinkName: "__kk_file_path",
                ownerSymbol: fileSymbol,
                returnType: types.stringType,
                symbols: symbols,
                interner: interner
            )

            // File must stay constructible even though its own member facade
            // (readText/exists/bufferedReader/etc., STDLIB-320/321) was removed:
            // `kotlin.io.FileSystemException` and friends (KSP-619) take `File`
            // parameters, and `Files.kt`'s `resolveSibling`/`normalize` (KSP-483)
            // build new `File` values from a path. Without a constructor, none
            // of that source-backed surface could ever be exercised.
            registerFileConstructor(
                ownerSymbol: fileSymbol,
                ownerType: fileType,
                parameters: [("path", types.stringType)],
                externalLinkName: "__kk_file_new",
                symbols: symbols,
                interner: interner
            )
            registerFileConstructor(
                ownerSymbol: fileSymbol,
                ownerType: fileType,
                parameters: [("parent", types.stringType), ("child", types.stringType)],
                externalLinkName: "__kk_file_new_parent_child",
                symbols: symbols,
                interner: interner
            )
        }

        let createTempKotlinIOPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("io")],
            symbols: symbols
        )
        let deprecatedCreateTempDirAnnotations = [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: [
                    "message = \"Avoid creating temporary directories in the default temp location with this function due to too wide permissions on the newly created directory. Use kotlin.io.path.createTempDirectory instead.\"",
                    "replaceWith = ReplaceWith(\"kotlin.io.path.createTempDirectory(prefix)\")",
                    "level = DeprecationLevel.ERROR",
                ]
            ),
        ]
        let deprecatedCreateTempFileAnnotations = [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: [
                    "message = \"Avoid creating temporary files in the default temp location with this function due to too wide permissions on the newly created file. Use kotlin.io.path.createTempFile instead or resort to java.io.File.createTempFile.\"",
                    "replaceWith = ReplaceWith(\"kotlin.io.path.createTempFile(prefix, suffix)\")",
                    "level = DeprecationLevel.ERROR",
                ]
            ),
        ]
        registerSyntheticTopLevelFunction(
            named: "createTempDir",
            packageFQName: createTempKotlinIOPkg,
            parameters: [],
            returnType: fileType,
            externalLinkName: "__kk_io_createTempDir_default",
            annotations: deprecatedCreateTempDirAnnotations,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "createTempDir",
            packageFQName: createTempKotlinIOPkg,
            parameters: [(name: "prefix", type: types.stringType)],
            returnType: fileType,
            externalLinkName: "__kk_io_createTempDir_prefix",
            annotations: deprecatedCreateTempDirAnnotations,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "createTempDir",
            packageFQName: createTempKotlinIOPkg,
            parameters: [
                (name: "prefix", type: types.stringType),
                (name: "suffix", type: types.makeNullable(types.stringType)),
            ],
            returnType: fileType,
            externalLinkName: "__kk_io_createTempDir_prefix_suffix",
            annotations: deprecatedCreateTempDirAnnotations,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "createTempDir",
            packageFQName: createTempKotlinIOPkg,
            parameters: [
                (name: "prefix", type: types.stringType),
                (name: "suffix", type: types.makeNullable(types.stringType)),
                (name: "directory", type: types.makeNullable(fileType)),
            ],
            returnType: fileType,
            externalLinkName: "__kk_io_createTempDir",
            annotations: deprecatedCreateTempDirAnnotations,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "createTempFile",
            packageFQName: createTempKotlinIOPkg,
            parameters: [],
            returnType: fileType,
            externalLinkName: "__kk_io_createTempFile_default",
            annotations: deprecatedCreateTempFileAnnotations,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "createTempFile",
            packageFQName: createTempKotlinIOPkg,
            parameters: [(name: "prefix", type: types.stringType)],
            returnType: fileType,
            externalLinkName: "__kk_io_createTempFile_prefix",
            annotations: deprecatedCreateTempFileAnnotations,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "createTempFile",
            packageFQName: createTempKotlinIOPkg,
            parameters: [
                (name: "prefix", type: types.stringType),
                (name: "suffix", type: types.makeNullable(types.stringType)),
            ],
            returnType: fileType,
            externalLinkName: "__kk_io_createTempFile_prefix_suffix",
            annotations: deprecatedCreateTempFileAnnotations,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "createTempFile",
            packageFQName: createTempKotlinIOPkg,
            parameters: [
                (name: "prefix", type: types.stringType),
                (name: "suffix", type: types.makeNullable(types.stringType)),
                (name: "directory", type: types.makeNullable(fileType)),
            ],
            returnType: fileType,
            externalLinkName: "__kk_io_createTempFile",
            annotations: deprecatedCreateTempFileAnnotations,
            symbols: symbols,
            interner: interner
        )

        let nullableStringType = types.makeNullable(types.stringType)
        let intType = types.intType

        let listOfIntType: TypeID = if let listSym = listSymbol {
            types.make(.classType(ClassType(
                classSymbol: listSym,
                args: [.out(intType)],
                nullability: .nonNull
            )))
        } else {
            types.anyType
        }
        let byteArrayFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("ByteArray")]
        // `readAllBytes`/`readBytes` bridges return real ByteArray storage
        // (`RuntimeArrayBox`); declaring the Kotlin ByteArray type keeps
        // `.size`/indexed access dispatching to array, not list, semantics.
        let byteArrayReturnType: TypeID = if let byteArraySymbol = symbols.lookup(fqName: byteArrayFQName) {
            types.make(.classType(ClassType(
                classSymbol: byteArraySymbol, args: [], nullability: .nonNull
            )))
        } else {
            listOfIntType
        }

        let readerSymbol = ensureClassSymbol(
            named: "Reader",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        symbols.insertFlags([.abstractType, .openType], for: readerSymbol)
        let bufferedReaderSymbol = ensureClassSymbol(
            named: "BufferedReader",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaIOPkgSymbol {
            symbols.setParentSymbol(javaIOPkgSymbol, for: readerSymbol)
            symbols.setParentSymbol(javaIOPkgSymbol, for: bufferedReaderSymbol)
        }
        let readerType = types.make(.classType(ClassType(
            classSymbol: readerSymbol, args: [], nullability: .nonNull
        )))
        let bufferedReaderType = types.make(.classType(ClassType(
            classSymbol: bufferedReaderSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(readerType, for: readerSymbol)
        symbols.setPropertyType(bufferedReaderType, for: bufferedReaderSymbol)

        let bufferedReaderMembers = fileMemberRows(of: bufferedReaderSymbol, type: bufferedReaderType, symbols: symbols, interner: interner)
        bufferedReaderMembers.fn("readLine", "__kk_buffered_reader_readLine", ret: nullableStringType)
        bufferedReaderMembers.fn("readLines", "__kk_buffered_reader_readLines", ret: listOfStringType)

        bufferedReaderMembers.fn("close", "__kk_buffered_reader_close", ret: types.unitType)

        let readerCloseableSymbol = types.ioCloseableInterfaceSymbol ?? javaIOCloseableSymbol
        symbols.setDirectSupertypes([readerCloseableSymbol], for: readerSymbol)
        types.setNominalDirectSupertypes([readerCloseableSymbol], for: readerSymbol)
        symbols.setDirectSupertypes([readerSymbol, readerCloseableSymbol], for: bufferedReaderSymbol)
        types.setNominalDirectSupertypes([readerSymbol, readerCloseableSymbol], for: bufferedReaderSymbol)

        // `java.io.Reader` declares `read(CharArray, Int, Int)` abstract — the
        // char-source contract every concrete reader implements (JVM parity).
        // It is the class's sole virtual member, so every subclass override
        // lands in vtable slot 0 — `RuntimeIoStreamVTableSlot.readerReadChars`
        // on box handles and the slot `RuntimeKotlinReaderCharSource` uses to
        // pull chars from Kotlin-source Reader objects (StringReader, user
        // subclasses — KUU-4031).
        let charArrayFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("CharArray")]
        if let charArraySymbol = symbols.lookup(fqName: charArrayFQName) {
            let charArrayType = types.make(.classType(ClassType(
                classSymbol: charArraySymbol, args: [], nullability: .nonNull
            )))
            let readerMembers = fileMemberRows(of: readerSymbol, type: readerType, symbols: symbols, interner: interner)
            readerMembers.fn(
                "read",
                "__kk_reader_read_range",
                [("buffer", charArrayType), ("offset", intType), ("length", intType)],
                ret: intType
            )
            let readRangeFQName: [InternedString] = (symbols.symbol(readerSymbol)?.fqName ?? [])
                + [interner.intern("read")]
            for candidate in symbols.lookupAll(fqName: readRangeFQName)
            where symbols.externalLinkName(for: candidate) == "__kk_reader_read_range" {
                symbols.insertFlags([.abstractType, .openType], for: candidate)
            }
            // `Reader.read(CharArray)` (KUU-4044) — JVM models it as a
            // concrete method that delegates to `read(cbuf, 0, cbuf.length)`.
            // The `__kk_reader_read` bridge forwards to
            // `__kk_reader_read_range`, so the virtual 3-arg implementation
            // (box fast path or Kotlin-reader vtable source) still supplies
            // the chars. Registered as a concrete member so calls on any
            // `Reader`/`BufferedReader`/`StringReader` receiver resolve the
            // inherited overload directly.
            readerMembers.fn(
                "read",
                "__kk_reader_read",
                [("buffer", charArrayType)],
                ret: intType
            )
        }

        bufferedReaderMembers.fn("read", "__kk_buffered_reader_read", ret: intType)
        bufferedReaderMembers.fn("ready", "__kk_buffered_reader_ready", ret: types.booleanType)

        let iteratorOfStringType = syntheticIteratorType(
            elementType: types.stringType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        bufferedReaderMembers.fn("iterator", "__kk_buffered_reader_iterator", ret: iteratorOfStringType)
        let iteratorFQName: [InternedString] = (symbols.symbol(bufferedReaderSymbol)?.fqName ?? [])
            + [interner.intern("iterator")]
        let promoteIteratorToOperator = {
            for candidate in symbols.lookupAll(fqName: iteratorFQName) {
                guard let info = symbols.symbol(candidate),
                      info.flags.contains(.synthetic),
                      let signature = symbols.functionSignature(for: candidate),
                      signature.receiverType == bufferedReaderType,
                      signature.parameterTypes.isEmpty
                else { continue }
                symbols.insertFlags(.operatorFunction, for: candidate)
            }
        }
        if !symbols.deferWorkUntilImportedMemberMaterializes(at: iteratorFQName, work: promoteIteratorToOperator) {
            promoteIteratorToOperator()
        }

        // BufferedReader.useLines { lines: Sequence<String> -> T } (STDLIB-IO-FN-040)
        //
        // Kotlin declares `useLines` as an extension function on `kotlin.io.Reader`
        // (which `BufferedReader` extends). The lambda is invoked with the receiver's
        // remaining lines as a `Sequence<String>`, and the reader is closed before
        // the function returns. The runtime hands the block a lazy pull-source
        // sequence, matching Kotlin's real `(Sequence<String>) -> T` signature —
        // so a block that only scans a prefix never drains the whole reader.
        let sequenceSymbol = resolveSequenceSymbol(symbols: symbols, interner: interner)
        if sequenceSymbol == nil {
            assertionFailure("kotlin.sequences.Sequence symbol not found; BufferedReader.useLines will use Any as fallback")
        }
        let sequenceOfStringType: TypeID = if let seqSym = sequenceSymbol {
            types.make(.classType(ClassType(
                classSymbol: seqSym,
                args: [.out(types.stringType)],
                nullability: .nonNull
            )))
        } else {
            types.anyType
        }
        let sequenceOfStringToAnyTypeBR = types.make(.functionType(FunctionType(
            params: [sequenceOfStringType],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        bufferedReaderMembers.fn("useLines", "__kk_buffered_reader_useLines", [("block", sequenceOfStringToAnyTypeBR)], ret: types.anyType)

        bufferedReaderMembers.fn("forEachLine", "__kk_buffered_reader_forEachLine", [("action", stringToUnitType)], ret: types.unitType)

        let writerSymbol = ensureClassSymbol(
            named: "Writer",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        symbols.insertFlags([.abstractType], for: writerSymbol)
        let bufferedWriterSymbol = ensureClassSymbol(
            named: "BufferedWriter",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaIOPkgSymbol {
            symbols.setParentSymbol(javaIOPkgSymbol, for: writerSymbol)
            symbols.setParentSymbol(javaIOPkgSymbol, for: bufferedWriterSymbol)
        }
        let writerType = types.make(.classType(ClassType(
            classSymbol: writerSymbol, args: [], nullability: .nonNull
        )))
        let bufferedWriterType = types.make(.classType(ClassType(
            classSymbol: bufferedWriterSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(writerType, for: writerSymbol)
        symbols.setPropertyType(bufferedWriterType, for: bufferedWriterSymbol)

        let writerCloseableSymbol = types.ioCloseableInterfaceSymbol ?? javaIOCloseableSymbol
        symbols.setDirectSupertypes([writerCloseableSymbol], for: writerSymbol)
        types.setNominalDirectSupertypes([writerCloseableSymbol], for: writerSymbol)
        symbols.setDirectSupertypes([writerSymbol, writerCloseableSymbol], for: bufferedWriterSymbol)
        types.setNominalDirectSupertypes([writerSymbol, writerCloseableSymbol], for: bufferedWriterSymbol)
        symbols.insertFlags([.abstractType, .openType], for: writerSymbol)

        let writerMembers = fileMemberRows(of: writerSymbol, type: writerType, symbols: symbols, interner: interner)
        writerMembers.fn("write", "__kk_buffered_writer_write", [("text", types.stringType)], ret: types.unitType)
        writerMembers.fn("flush", "__kk_buffered_writer_flush", ret: types.unitType)
        writerMembers.fn("close", "__kk_buffered_writer_close_throwing", ret: types.unitType)

        let bufferedWriterMembers = fileMemberRows(of: bufferedWriterSymbol, type: bufferedWriterType, symbols: symbols, interner: interner)
        bufferedWriterMembers.fn("write", "__kk_buffered_writer_write", [("text", types.stringType)], ret: types.unitType)
        bufferedWriterMembers.fn("newLine", "__kk_buffered_writer_new_line", ret: types.unitType)

        bufferedWriterMembers.fn("flush", "__kk_buffered_writer_flush", ret: types.unitType)
        bufferedWriterMembers.fn("close", "__kk_buffered_writer_close_throwing", ret: types.unitType)
        for member in symbols.children(of: bufferedWriterSymbol) {
            guard let info = symbols.symbol(member), info.kind == .function else { continue }
            let name = interner.resolve(info.name)
            if name == "write" || name == "flush" || name == "close" {
                symbols.insertFlags([.openType, .overrideMember], for: member)
            }
        }

        let javaLangPkg = ensurePackage(
            path: ["java", "lang"],
            symbols: symbols,
            interner: interner
        )
        let javaLangPkgSymbol = symbols.lookup(fqName: javaLangPkg)
        let classLoaderSymbol = ensureClassSymbol(
            named: "ClassLoader",
            in: javaLangPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaLangPkgSymbol {
            symbols.setParentSymbol(javaLangPkgSymbol, for: classLoaderSymbol)
        }
        let classLoaderType = types.make(.classType(ClassType(
            classSymbol: classLoaderSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(classLoaderType, for: classLoaderSymbol)
        let inputStreamSymbol = ensureClassSymbol(
            named: "InputStream",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        let byteArrayInputStreamSymbol = ensureClassSymbol(
            named: "ByteArrayInputStream",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        let sequenceInputStreamSymbol = ensureClassSymbol(
            named: "SequenceInputStream",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        let outputStreamSymbol = ensureClassSymbol(
            named: "OutputStream",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaIOPkgSymbol {
            symbols.setParentSymbol(javaIOPkgSymbol, for: inputStreamSymbol)
            symbols.setParentSymbol(javaIOPkgSymbol, for: byteArrayInputStreamSymbol)
            symbols.setParentSymbol(javaIOPkgSymbol, for: sequenceInputStreamSymbol)
            symbols.setParentSymbol(javaIOPkgSymbol, for: outputStreamSymbol)
        }
        let inputStreamType = types.make(.classType(ClassType(
            classSymbol: inputStreamSymbol, args: [], nullability: .nonNull
        )))
        let byteArrayInputStreamType = types.make(.classType(ClassType(
            classSymbol: byteArrayInputStreamSymbol, args: [], nullability: .nonNull
        )))
        let sequenceInputStreamType = types.make(.classType(ClassType(
            classSymbol: sequenceInputStreamSymbol, args: [], nullability: .nonNull
        )))
        let outputStreamType = types.make(.classType(ClassType(
            classSymbol: outputStreamSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(inputStreamType, for: inputStreamSymbol)
        symbols.setPropertyType(byteArrayInputStreamType, for: byteArrayInputStreamSymbol)
        symbols.setPropertyType(sequenceInputStreamType, for: sequenceInputStreamSymbol)
        symbols.setPropertyType(outputStreamType, for: outputStreamSymbol)

        symbols.insertFlags([.abstractType, .openType], for: inputStreamSymbol)
        symbols.insertFlags([.abstractType, .openType], for: outputStreamSymbol)

        let streamCloseableSymbol = types.ioCloseableInterfaceSymbol ?? javaIOCloseableSymbol
        symbols.setDirectSupertypes([streamCloseableSymbol], for: inputStreamSymbol)
        types.setNominalDirectSupertypes([streamCloseableSymbol], for: inputStreamSymbol)
        symbols.setDirectSupertypes([streamCloseableSymbol], for: outputStreamSymbol)
        types.setNominalDirectSupertypes([streamCloseableSymbol], for: outputStreamSymbol)
        symbols.setDirectSupertypes([inputStreamSymbol], for: sequenceInputStreamSymbol)
        types.setNominalDirectSupertypes([inputStreamSymbol], for: sequenceInputStreamSymbol)
        symbols.setDirectSupertypes([inputStreamSymbol], for: byteArrayInputStreamSymbol)
        types.setNominalDirectSupertypes([inputStreamSymbol], for: byteArrayInputStreamSymbol)
        let nullableInputStreamType = types.makeNullable(inputStreamType)

        registerFileConstructor(
            ownerSymbol: sequenceInputStreamSymbol,
            ownerType: sequenceInputStreamType,
            parameters: [("first", inputStreamType), ("second", inputStreamType)],
            externalLinkName: "__kk_sequence_input_stream_new",
            symbols: symbols,
            interner: interner
        )

        if let arraySymbol = symbols.lookup(fqName: ["kotlin", "ByteArray"].map(interner.intern)) {
            let arrayType = types.make(.classType(ClassType(classSymbol: arraySymbol, args: [], nullability: .nonNull)))
            registerFileConstructor(
                ownerSymbol: byteArrayInputStreamSymbol,
                ownerType: byteArrayInputStreamType,
                parameters: [("buffer", arrayType)],
                externalLinkName: "__kk_bytearrayinputstream_new",
                symbols: symbols,
                interner: interner
            )
        }

        if let arraySymbol = symbols.lookup(fqName: ["kotlin", "ByteArray"].map(interner.intern)) {
            let owner = ensureClassSymbol(named: "ByteArrayOutputStream", in: javaIOPkg,
                symbols: symbols, interner: interner)
            if let javaIOPkgSymbol { symbols.setParentSymbol(javaIOPkgSymbol, for: owner) }
            let ownerType = types.make(.classType(ClassType(classSymbol: owner, args: [], nullability: .nonNull)))
            let arrayType = types.make(.classType(ClassType(classSymbol: arraySymbol, args: [], nullability: .nonNull)))
            symbols.setPropertyType(ownerType, for: owner)
            symbols.setDirectSupertypes([outputStreamSymbol], for: owner)
            types.setNominalDirectSupertypes([outputStreamSymbol], for: owner)
            registerFileConstructor(ownerSymbol: owner, ownerType: ownerType, parameters: [],
                externalLinkName: "__kk_bytearray_output_stream_new_default", symbols: symbols, interner: interner)
            registerFileConstructor(ownerSymbol: owner, ownerType: ownerType, parameters: [("size", intType)],
                externalLinkName: "__kk_bytearray_output_stream_new", symbols: symbols, interner: interner)
            for (name, link, result) in [
                ("toByteArray", "__kk_bytearray_output_stream_to_byte_array", arrayType),
                ("reset", "__kk_bytearray_output_stream_reset", types.unitType),
                ("size", "__kk_bytearray_output_stream_size", intType),
                ("toString", "__kk_bytearray_output_stream_to_string", types.stringType),
            ] {
                registerFileMemberFunction(named: name, externalLinkName: link,
                    ownerSymbol: owner, ownerType: ownerType, parameters: [], returnType: result,
                    symbols: symbols, interner: interner)
            }
        }

        let kotlinIOPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("io")],
            symbols: symbols
        )
        // Charset-bearing wrappers are Kotlin source. Their private runtime
        // bridges take an Int codec tag, not the source Charset object.
        registerSyntheticStringExtensionFunction(
            named: "byteInputStream",
            externalLinkName: "__kk_string_byteInputStream_flat",
            receiverType: types.stringType,
            parameters: [],
            returnType: byteArrayInputStreamType,
            packageFQName: kotlinIOPkg,
            symbols: symbols,
            interner: interner
        )

        for (ownerSymbol, ownerType) in [(inputStreamSymbol, inputStreamType), (outputStreamSymbol, outputStreamType)] {
            registerFileMemberFunction(named: "toString", externalLinkName: "__kk_io_stream_to_string",
                ownerSymbol: ownerSymbol, ownerType: ownerType, parameters: [], returnType: types.stringType,
                symbols: symbols, interner: interner)
        }

        let inputStreamMembers = fileMemberRows(of: inputStreamSymbol, type: inputStreamType, symbols: symbols, interner: interner)
        inputStreamMembers.fn("read", "__kk_input_stream_read", ret: intType)
        inputStreamMembers.fn("available", "__kk_input_stream_available_throwing", ret: intType)

        inputStreamMembers.fn("skip", "__kk_input_stream_skip", [("count", intType)], ret: intType)
        inputStreamMembers.fn("read", "__kk_input_stream_read_bytes", [("buffer", listOfIntType)], ret: intType)

        if let byteArraySymbol = symbols.lookup(fqName: byteArrayFQName) {
            let byteArrayType = types.make(.classType(ClassType(
                classSymbol: byteArraySymbol, args: [], nullability: .nonNull)))
            registerFileMemberFunction(
                named: "read", externalLinkName: "__kk_input_stream_read_bytes",
                ownerSymbol: inputStreamSymbol, ownerType: inputStreamType,
                parameters: [("buffer", byteArrayType)], returnType: intType,
                symbols: symbols, interner: interner)
            registerFileMemberFunction(
                named: "read", externalLinkName: "__kk_input_stream_read_range",
                ownerSymbol: inputStreamSymbol, ownerType: inputStreamType,
                parameters: [("buffer", byteArrayType), ("offset", intType), ("length", intType)],
                returnType: intType, symbols: symbols, interner: interner)
            registerFileConstructor(
                ownerSymbol: byteArrayInputStreamSymbol, ownerType: byteArrayInputStreamType,
                parameters: [("buffer", byteArrayType)], externalLinkName: "__kk_bytearray_inputStream",
                symbols: symbols, interner: interner)
        }

        inputStreamMembers.fn("readBytes", "__kk_input_stream_readAllBytes", ret: byteArrayReturnType)
        inputStreamMembers.fn("mark", "__kk_input_stream_mark", [("readLimit", intType)], ret: types.unitType)

        inputStreamMembers.fn("reset", "__kk_input_stream_reset", ret: types.unitType)
        inputStreamMembers.fn("markSupported", "__kk_input_stream_mark_supported", ret: types.booleanType)

        inputStreamMembers.fn("close", "__kk_input_stream_close_throwing", ret: types.unitType)

        // These bridge-backed declarations represent overridable Java class
        // members. Keep their vtable slots available so calls through an
        // InputStream reference reach source-backed subclasses such as
        // DataInputStream instead of passing the subclass object to a native
        // RuntimeInputStreamBox bridge.
        let inputStreamVirtualBridgeNames: Set<String> = [
            "__kk_input_stream_read",
            "__kk_input_stream_available_throwing",
            "__kk_input_stream_skip",
            "__kk_input_stream_read_bytes",
            "__kk_input_stream_read_range",
            "__kk_input_stream_readAllBytes",
            "__kk_input_stream_mark",
            "__kk_input_stream_reset",
            "__kk_input_stream_mark_supported",
            "__kk_input_stream_close_throwing",
        ]
        for member in symbols.children(of: inputStreamSymbol) {
            guard symbols.symbol(member)?.kind == .function,
                  let linkName = symbols.externalLinkName(for: member),
                  inputStreamVirtualBridgeNames.contains(linkName)
            else {
                continue
            }
            symbols.insertFlags(.openType, for: member)
        }

        let bufferedInputStreamSymbol = ensureClassSymbol(
            named: "BufferedInputStream",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaIOPkgSymbol {
            symbols.setParentSymbol(javaIOPkgSymbol, for: bufferedInputStreamSymbol)
        }
        let bufferedInputStreamType = types.make(.classType(ClassType(
            classSymbol: bufferedInputStreamSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(bufferedInputStreamType, for: bufferedInputStreamSymbol)

        symbols.setDirectSupertypes([inputStreamSymbol], for: bufferedInputStreamSymbol)
        types.setNominalDirectSupertypes([inputStreamSymbol], for: bufferedInputStreamSymbol)

        let bufferedInputStreamMembers = fileMemberRows(of: bufferedInputStreamSymbol, type: bufferedInputStreamType, symbols: symbols, interner: interner)
        bufferedInputStreamMembers.fn("readBytes", "__kk_input_stream_readAllBytes", ret: byteArrayReturnType)

        inputStreamMembers.fn("buffered", "__kk_input_stream_buffered_default", ret: bufferedInputStreamType)

        inputStreamMembers.fn("buffered", "__kk_input_stream_buffered", [("bufferSize", intType)], ret: bufferedInputStreamType)

        registerKotlinIOExtensionFunction(
            named: "copyTo",
            packageFQName: kotlinIOPkg,
            receiverType: inputStreamType,
            parameters: [
                ("out", outputStreamType),
                ("bufferSize", types.intType),
            ],
            returnType: types.longType,
            externalLinkName: "__kk_input_stream_copyTo",
            valueParameterHasDefaultValues: [false, true],
            valueParameterIsVararg: [false, false],
            symbols: symbols,
            interner: interner
        )

        let sequenceInputStreamMembers = fileMemberRows(of: sequenceInputStreamSymbol, type: sequenceInputStreamType, symbols: symbols, interner: interner)
        sequenceInputStreamMembers.fn("read", "__kk_sequence_input_stream_read", ret: intType)
        sequenceInputStreamMembers.fn("available", "__kk_sequence_input_stream_available_throwing", ret: intType)

        sequenceInputStreamMembers.fn("close", "__kk_sequence_input_stream_close_throwing", ret: types.unitType)

        let outputStreamMembers = fileMemberRows(of: outputStreamSymbol, type: outputStreamType, symbols: symbols, interner: interner)
        outputStreamMembers.fn("write", "__kk_output_stream_write_byte", [("value", intType)], ret: types.unitType)
        outputStreamMembers.fn("write", "__kk_output_stream_write_bytes", [("buffer", listOfIntType)], ret: types.unitType)

        if let byteArraySymbol = symbols.lookup(fqName: byteArrayFQName) {
            let byteArrayType = types.make(.classType(ClassType(
                classSymbol: byteArraySymbol, args: [], nullability: .nonNull
            )))
            outputStreamMembers.fn("write", "__kk_output_stream_write_bytes", [("buffer", byteArrayType)], ret: types.unitType)
            registerFileMemberFunction(
                named: "write", externalLinkName: "__kk_output_stream_write_range",
                ownerSymbol: outputStreamSymbol, ownerType: outputStreamType,
                parameters: [("buffer", byteArrayType), ("offset", intType), ("length", intType)],
                returnType: types.unitType, symbols: symbols, interner: interner)
        }

        outputStreamMembers.fn("flush", "__kk_output_stream_flush", ret: types.unitType)
        outputStreamMembers.fn("close", "__kk_output_stream_close_throwing", ret: types.unitType)

        let outputStreamVirtualBridgeNames: Set<String> = [
            "__kk_output_stream_write_byte",
            "__kk_output_stream_write_bytes",
            "__kk_output_stream_write_range",
            "__kk_output_stream_flush",
            "__kk_output_stream_close_throwing",
        ]
        for member in symbols.children(of: outputStreamSymbol) {
            guard symbols.symbol(member)?.kind == .function,
                  let linkName = symbols.externalLinkName(for: member),
                  outputStreamVirtualBridgeNames.contains(linkName)
            else {
                continue
            }
            symbols.insertFlags(.openType, for: member)
        }

        outputStreamMembers.fn("buffered", "__kk_output_stream_buffered", ret: outputStreamType)
        outputStreamMembers.fn("buffered", "__kk_output_stream_buffered_sized", [("bufferSize", intType)], ret: outputStreamType)

        let classLoaderMembers = fileMemberRows(of: classLoaderSymbol, type: classLoaderType, symbols: symbols, interner: interner)
        classLoaderMembers.fn("getResource", "__kk_classloader_getResource", [("name", types.stringType)], ret: nullableStringType)
        classLoaderMembers.fn("getResourceAsStream", "__kk_classloader_getResourceAsStream", [("name", types.stringType)], ret: nullableInputStreamType)

        registerTopLevelResourceFunction(
            packageFQName: javaLangPkg,
            name: "getSystemClassLoader",
            parameters: [],
            returnType: classLoaderType,
            externalLinkName: "__kk_classloader_getSystemClassLoader",
            symbols: symbols,
            interner: interner
        )

        registerTopLevelResourceFunction(
            packageFQName: kotlinIOPkg,
            name: "resourceExists",
            parameters: [("name", types.stringType)],
            returnType: types.booleanType,
            externalLinkName: "__kk_resource_exists",
            symbols: symbols,
            interner: interner
        )
        registerTopLevelResourceFunction(
            packageFQName: kotlinIOPkg,
            name: "readResourceAsText",
            parameters: [("name", types.stringType)],
            returnType: types.stringType,
            externalLinkName: "__kk_readResourceAsText",
            symbols: symbols,
            interner: interner
        )

        let kotlinTextPkgFQName = ensurePackage(
            path: ["kotlin", "text"],
            symbols: symbols,
            interner: interner
        )
        let kotlinTextPkgSymbol = symbols.lookup(fqName: kotlinTextPkgFQName)
        let outputStreamCharsetSymbol = ensureClassSymbol(
            named: "Charset",
            in: kotlinTextPkgFQName,
            symbols: symbols,
            interner: interner
        )
        if let kotlinTextPkgSymbol {
            symbols.setParentSymbol(kotlinTextPkgSymbol, for: outputStreamCharsetSymbol)
        }
        let outputStreamCharsetType = types.make(.classType(ClassType(
            classSymbol: outputStreamCharsetSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(outputStreamCharsetType, for: outputStreamCharsetSymbol)

        registerKotlinIOExtensionFunction(
            named: "bufferedWriter",
            packageFQName: kotlinIOPkg,
            receiverType: outputStreamType,
            parameters: [("charset", outputStreamCharsetType)],
            returnType: bufferedWriterType,
            externalLinkName: "__kk_output_stream_bufferedWriter",
            valueParameterHasDefaultValues: [true],
            valueParameterIsVararg: [false],
            symbols: symbols,
            interner: interner
        )

        registerKotlinIOExtensionFunction(
            named: "readText",
            packageFQName: kotlinIOPkg,
            receiverType: readerType,
            parameters: [],
            returnType: types.stringType,
            externalLinkName: "__kk_reader_readText",
            symbols: symbols,
            interner: interner
        )

        registerKotlinIOExtensionFunction(
            named: "copyTo",
            packageFQName: kotlinIOPkg,
            receiverType: readerType,
            parameters: [
                ("out", writerType),
                ("bufferSize", intType),
            ],
            returnType: types.longType,
            externalLinkName: "__kk_reader_copyTo",
            valueParameterHasDefaultValues: [false, false],
            valueParameterIsVararg: [false, false],
            symbols: symbols,
            interner: interner
        )

        registerKotlinIOExtensionFunction(
            named: "copyTo",
            packageFQName: kotlinIOPkg,
            receiverType: readerType,
            parameters: [("out", writerType)],
            returnType: types.longType,
            externalLinkName: "__kk_reader_copyTo_default",
            symbols: symbols,
            interner: interner
        )

        if let byteArraySymbol = symbols.lookup(fqName: byteArrayFQName) {
            let byteArrayType = types.make(.classType(ClassType(
                classSymbol: byteArraySymbol, args: [], nullability: .nonNull
            )))

            registerSyntheticStringExtensionFunction(
                named: "inputStream",
                externalLinkName: "__kk_bytearray_inputStream",
                receiverType: byteArrayType,
                parameters: [],
                returnType: byteArrayInputStreamType,
                packageFQName: kotlinIOPkg,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticStringExtensionFunction(
                named: "inputStream",
                externalLinkName: "__kk_bytearray_inputStream_range",
                receiverType: byteArrayType,
                parameters: [
                    ("offset", types.intType, false, false),
                    ("length", types.intType, false, false),
                ],
                returnType: byteArrayInputStreamType,
                packageFQName: kotlinIOPkg,
                symbols: symbols,
                interner: interner
            )
        }

        registerFilePackageExtensionFunction(
            named: "buffered",
            packageFQName: kotlinIOPkg,
            receiverType: writerType,
            parameters: [],
            returnType: bufferedWriterType,
            externalLinkName: "__kk_writer_buffered_default",
            symbols: symbols,
            interner: interner
        )
        registerFilePackageExtensionFunction(
            named: "buffered",
            packageFQName: kotlinIOPkg,
            receiverType: writerType,
            parameters: [("bufferSize", intType)],
            returnType: bufferedWriterType,
            externalLinkName: "__kk_writer_buffered",
            symbols: symbols,
            interner: interner
        )

        for (owner, names) in [
            (writerSymbol, Set(["write", "flush", "close"])),
            (inputStreamSymbol, Set(["read", "available", "skip", "readBytes", "mark", "reset", "markSupported", "close"])),
            (outputStreamSymbol, Set(["write", "flush", "close"])),
        ] {
            for member in symbols.children(of: owner) {
                guard let info = symbols.symbol(member), info.kind == .function,
                      names.contains(interner.resolve(info.name)) else { continue }
                symbols.insertFlags(.openType, for: member)
            }
        }


    }

    func resolveListSymbol(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID? {
        let listFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]
        return symbols.lookupNominal(fqName: listFQName)
    }

    func resolveSequenceSymbol(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID? {
        let sequenceFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("sequences"),
            interner.intern("Sequence"),
        ]
        return symbols.lookupNominal(fqName: sequenceFQName)
    }

    private func registerFileConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let initName = interner.intern("<init>")
        let ctorFQName = ownerInfo.fqName + [initName]
        if symbols.deferWorkUntilImportedMemberMaterializes(at: ctorFQName, work: { [self] in
            registerFileConstructor(
                ownerSymbol: ownerSymbol,
                ownerType: ownerType,
                parameters: parameters,
                externalLinkName: externalLinkName,
                symbols: symbols,
                interner: interner
            )
        }) {
            return
        }
        let hasMatchingConstructor = symbols.lookupAll(fqName: ctorFQName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == parameters.map(\.type)
        }
        guard !hasMatchingConstructor else {
            return
        }

        let ctorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: ctorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: ctorSymbol)
        symbols.setExternalLinkName(externalLinkName, for: ctorSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: ctorFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ctorSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: ownerType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: ctorSymbol
        )
    }

    func registerJVMFileMembers(symbols: SymbolTable, types: TypeSystem, interner: StringInterner) {
        let fileName = ["java", "io", "File"].map(interner.intern)
        guard let owner = symbols.lookupNominal(fqName: fileName), let fileType = symbols.propertyType(for: owner) else { return }
        registerFileConstructor(
            ownerSymbol: owner, ownerType: fileType,
            parameters: [("parent", types.makeNullable(fileType)), ("child", types.stringType)],
            externalLinkName: "java/io/File.<init>", symbols: symbols, interner: interner
        )
        registerFileMemberProperty(
            named: "absolutePath", externalLinkName: "java/io/File.getAbsolutePath",
            ownerSymbol: owner, returnType: types.stringType, symbols: symbols, interner: interner
        )
        registerFileMemberFunction(
            named: "mkdirs", externalLinkName: "java/io/File.mkdirs",
            ownerSymbol: owner, ownerType: fileType, parameters: [], returnType: types.booleanType,
            symbols: symbols, interner: interner
        )
    }

    private func registerKotlinIOExtensionFunction(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        valueParameterHasDefaultValues: [Bool]? = nil,
        valueParameterIsVararg: [Bool]? = nil,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        if let types = BundledSyntheticStubRegistration.types,
           BundledSyntheticStubRegistration.shouldSkipRegistration(
               declaredOwnerFQName: packageFQName, receiverType: receiverType,
               name: functionName, arity: parameters.count, symbols: symbols,
               types: types, interner: interner
           ) {
            return
        }
        let functionFQName = packageFQName + [functionName]
        let parameterTypes = parameters.map(\.type)
        let defaults = valueParameterHasDefaultValues
            ?? Array(repeating: false, count: parameters.count)
        let varargs = valueParameterIsVararg
            ?? Array(repeating: false, count: parameters.count)

        if symbols.deferWorkUntilImportedMemberMaterializes(at: functionFQName, work: { [self] in
            registerKotlinIOExtensionFunction(
                named: name,
                packageFQName: packageFQName,
                receiverType: receiverType,
                parameters: parameters,
                returnType: returnType,
                externalLinkName: externalLinkName,
                valueParameterHasDefaultValues: valueParameterHasDefaultValues,
                valueParameterIsVararg: valueParameterIsVararg,
                symbols: symbols,
                interner: interner
            )
        }) {
            return
        }
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == receiverType
                && existingSignature.parameterTypes == parameterTypes
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            if let existingSignature = symbols.functionSignature(for: existing) {
                let shouldUpdateSignature =
                    existingSignature.returnType != returnType
                    || existingSignature.valueParameterHasDefaultValues != defaults
                    || existingSignature.valueParameterIsVararg != varargs
                guard shouldUpdateSignature else {
                    return
                }
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: existingSignature.receiverType,
                        parameterTypes: existingSignature.parameterTypes,
                        returnType: returnType,
                        isSuspend: existingSignature.isSuspend,
                        valueParameterSymbols: existingSignature.valueParameterSymbols,
                        valueParameterHasDefaultValues: defaults,
                        valueParameterIsVararg: varargs,
                        hasStableParameterNames: existingSignature.hasStableParameterNames
                    ),
                    for: existing
                )
            }
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
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
            valueParameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: defaults,
                valueParameterIsVararg: varargs
            ),
            for: functionSymbol
        )
    }

    func fileMemberRows(of ownerSymbol: SymbolID, type ownerType: TypeID, symbols: SymbolTable, interner: StringInterner) -> SyntheticMemberRows {
        SyntheticMemberRows { name, externalLinkName, parameters, returnType in
            self.registerFileMemberFunction(
                named: name, externalLinkName: externalLinkName, ownerSymbol: ownerSymbol, ownerType: ownerType,
                parameters: parameters, returnType: returnType, symbols: symbols, interner: interner
            )
        }
    }

    func registerFileMemberFunction(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let functionName = interner.intern(name)
        let functionFQName = ownerInfo.fqName + [functionName]
        if symbols.deferWorkUntilImportedMemberMaterializes(at: functionFQName, work: { [self] in
            registerFileMemberFunction(
                named: name,
                externalLinkName: externalLinkName,
                ownerSymbol: ownerSymbol,
                ownerType: ownerType,
                parameters: parameters,
                returnType: returnType,
                symbols: symbols,
                interner: interner
            )
        }) {
            return
        }
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == ownerType
                && existingSignature.parameterTypes == parameters.map(\.type)
        }) {
            guard let existingInfo = symbols.symbol(existing),
                  existingInfo.flags.contains(.synthetic) || existingInfo.declSite == nil else {
                return
            }
            symbols.setExternalLinkName(externalLinkName, for: existing)
            if let existingSignature = symbols.functionSignature(for: existing),
               existingSignature.returnType != returnType {
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: existingSignature.receiverType,
                        parameterTypes: existingSignature.parameterTypes,
                        returnType: returnType,
                        isSuspend: existingSignature.isSuspend,
                        valueParameterSymbols: existingSignature.valueParameterSymbols,
                        valueParameterHasDefaultValues: existingSignature.valueParameterHasDefaultValues,
                        valueParameterIsVararg: existingSignature.valueParameterIsVararg,
                        hasStableParameterNames: existingSignature.hasStableParameterNames
                    ),
                    for: existing
                )
            }
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
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []

        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
            parameterTypes.append(parameter.type)
            parameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: parameterSymbols.count)
            ),
            for: functionSymbol
        )
    }

    private func ensureJavaIOPackage(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
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
        return javaIOPkg
    }

    func ensureJavaIOCloseableCompatibilityAnchor(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let javaIOPkg = ensureJavaIOPackage(symbols: symbols, interner: interner)
        let closeableName = interner.intern("Closeable")
        let closeableFQName = javaIOPkg + [closeableName]
        if let existing = symbols.lookupAll(fqName: closeableFQName).first(where: {
            symbols.symbol($0)?.kind == .interface
        }) {
            return existing
        }
        let symbol = symbols.define(
            kind: .interface,
            name: closeableName,
            fqName: closeableFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: javaIOPkg) {
            symbols.setParentSymbol(packageSymbol, for: symbol)
        }
        return symbol
    }

    func ensureJavaLangAutoCloseableCompatibilityAnchor(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let javaLangPkg = ensurePackage(
            path: ["java", "lang"],
            symbols: symbols,
            interner: interner
        )
        let closeableFQName = javaLangPkg + [interner.intern("AutoCloseable")]
        if let existing = symbols.lookupAll(fqName: closeableFQName).first(where: {
            symbols.symbol($0)?.kind == .interface
        }) {
            return existing
        }
        let symbol = symbols.define(
            kind: .interface,
            name: interner.intern("AutoCloseable"),
            fqName: closeableFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: javaLangPkg) {
            symbols.setParentSymbol(packageSymbol, for: symbol)
        }
        return symbol
    }

    private func registerTopLevelResourceFunction(
        packageFQName: [InternedString],
        name: String,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        guard symbols.lookupAll(fqName: functionFQName).isEmpty else {
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
        if let pkgSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(pkgSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var parameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
            parameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: parameterSymbols.count)
            ),
            for: functionSymbol
        )
    }

    private func registerFileMemberProperty(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
        }) {
            guard let existingInfo = symbols.symbol(existing),
                  existingInfo.flags.contains(.synthetic) || existingInfo.declSite == nil else {
                return
            }
            symbols.setExternalLinkName(externalLinkName, for: existing)
            symbols.setPropertyType(returnType, for: existing)
            return
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
        symbols.setPropertyType(returnType, for: propertySymbol)
    }

    private func registerFilePackageExtensionFunction(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        let parameterTypes = parameters.map(\.type)
        if symbols.deferWorkUntilImportedMemberMaterializes(at: functionFQName, work: { [self] in
            registerFilePackageExtensionFunction(
                named: name,
                packageFQName: packageFQName,
                receiverType: receiverType,
                parameters: parameters,
                returnType: returnType,
                externalLinkName: externalLinkName,
                symbols: symbols,
                interner: interner
            )
        }) {
            return
        }
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == receiverType
                && signature.parameterTypes == parameterTypes
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: parameterTypes,
                    returnType: returnType
                ),
                for: existing
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
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var parameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
            parameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameters.count),
                valueParameterIsVararg: Array(repeating: false, count: parameters.count)
            ),
            for: functionSymbol
        )
    }

}
