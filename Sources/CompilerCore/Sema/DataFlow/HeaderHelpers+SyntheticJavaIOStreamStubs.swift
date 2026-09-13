/// Synthetic stubs for the shared `java.io` stream primitives (`Reader`/
/// `Writer`/`InputStream`/`OutputStream` families) plus `java.io.File`'s
/// bare nominal shell.
///
/// CLEANUP-STUB-107 removed `java.io.File`'s own filesystem-operation
/// *members* — `readText`/`writeText`/`appendText`,
/// `exists`/`isFile`/`isDirectory`, `delete`/`mkdirs`/`listFiles`/`walk`,
/// `bufferedReader`/`bufferedWriter`/`inputStream`/`outputStream`/
/// `printWriter` factories, `copyTo`/`copyRecursively`, `PrintWriter`, and
/// `kotlin.io.createTempDir`/`createTempFile` — as target-out JVM-only
/// surface — see TODO.md. What remains here is kept because other surfaces
/// still depend on it:
///
/// - `File`'s two constructors (`File(path)` / `File(parent, child)`) and its
///   `path` property are NOT removed: `Stdlib/kotlin/io/Files.kt` (KSP-483)
///   builds new `File` values (`resolveSibling`/`normalize`), and
///   `kotlin.io.FileSystemException`'s `file`/`other` properties (KSP-619)
///   are typed `File`/`File?` with real call sites (e.g.
///   `AccessDeniedException(File(path))`). Without a constructor, `File`
///   would be a type nothing could ever produce.
/// - `Reader`/`BufferedReader`/`Writer`/`BufferedWriter`/`InputStream`/
///   `OutputStream`/`ByteArrayInputStream`/`SequenceInputStream`/
///   `BufferedInputStream` are reused by File-independent `kotlin.io`
///   extensions (`String.byteInputStream()`, `ByteArray.inputStream()`,
///   `InputStream.copyTo()`, etc). NOTE: despite bare class-symbol anchors
///   for `BufferedReader`/`BufferedWriter`/`OutputStream` existing in
///   `HeaderHelpers+SyntheticPathStubs.swift`, `Path` does not currently
///   register `bufferedReader()`/`bufferedWriter()`/`outputStream()` as
///   callable members — those anchors have no producer today. Since
///   `File.outputStream()`/`bufferedWriter()` were this compiler's only
///   producers of a bare `OutputStream`/`Writer`, those two types are
///   currently unconstructible from Kotlin source (CLEANUP-STUB-115 territory).
/// - `ClassLoader` resource access and `Charset` are unrelated to `File` but
///   were historically co-located in this file; left untouched here.

extension DataFlowSemaPhase {

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
        let javaIOPkgSymbol = symbols.lookup(fqName: javaIOPkg)

        // MARK: - File (bare shell + path + constructors only; see header doc)

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

        let listSymbol = resolveListSymbol(symbols: symbols, interner: interner)
        if listSymbol == nil {
            assertionFailure("kotlin.collections.List symbol not found; java.io stream stubs will use Any as fallback")
        }

        // List<String> type for BufferedReader.readLines()/useLines() return
        let listOfStringType: TypeID = if let listSym = listSymbol {
            types.make(.classType(ClassType(
                classSymbol: listSym,
                args: [.out(types.stringType)],
                nullability: .nonNull
            )))
        } else {
            types.anyType
        }

        // (String) -> Unit function type for BufferedReader.forEachLine action parameter
        let stringToUnitType = types.make(.functionType(FunctionType(
            params: [types.stringType],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))

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

        let nullableStringType = types.makeNullable(types.stringType)
        let intType = types.intType

        // ByteArray is represented as List<Int> in the runtime.
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

        // MARK: - Reader / BufferedReader types (STDLIB-567)

        // `java.io.Reader` is the abstract supertype of `BufferedReader` and is
        // the receiver of `kotlin.io` extension functions such as
        // `Reader.readText()` (STDLIB-IO-FN-033). We register it as a synthetic
        // class so that extension calls on any concrete reader instance
        // resolve correctly.
        let readerSymbol = ensureClassSymbol(
            named: "Reader",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
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

        // BufferedReader.readLine() -> String?
        registerFileMemberFunction(
            named: "readLine",
            externalLinkName: "__kk_buffered_reader_readLine",
            ownerSymbol: bufferedReaderSymbol,
            ownerType: bufferedReaderType,
            parameters: [],
            returnType: nullableStringType,
            symbols: symbols,
            interner: interner
        )

        // BufferedReader.readLines() -> List<String>
        registerFileMemberFunction(
            named: "readLines",
            externalLinkName: "__kk_buffered_reader_readLines",
            ownerSymbol: bufferedReaderSymbol,
            ownerType: bufferedReaderType,
            parameters: [],
            returnType: listOfStringType,
            symbols: symbols,
            interner: interner
        )

        // BufferedReader.close() -> Unit
        registerFileMemberFunction(
            named: "close",
            externalLinkName: "__kk_buffered_reader_close",
            ownerSymbol: bufferedReaderSymbol,
            ownerType: bufferedReaderType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // Register BufferedReader as a Reader/Closeable subtype.
        // - Reader supertype lets `Reader.readText()` (STDLIB-IO-FN-033) resolve
        //   when invoked on a `BufferedReader` value.
        // - Closeable supertype (STDLIB-IO-093) lets `.use {}` work:
        //   `path.bufferedReader().use { reader -> ... }`.
        let readerCloseableSymbol = types.ioCloseableInterfaceSymbol ?? javaIOCloseableSymbol
        symbols.setDirectSupertypes([readerCloseableSymbol], for: readerSymbol)
        types.setNominalDirectSupertypes([readerCloseableSymbol], for: readerSymbol)
        symbols.setDirectSupertypes([readerSymbol, readerCloseableSymbol], for: bufferedReaderSymbol)
        types.setNominalDirectSupertypes([readerSymbol, readerCloseableSymbol], for: bufferedReaderSymbol)

        // BufferedReader.read() -> Int  (STDLIB-IO-091)
        registerFileMemberFunction(
            named: "read",
            externalLinkName: "__kk_buffered_reader_read",
            ownerSymbol: bufferedReaderSymbol,
            ownerType: bufferedReaderType,
            parameters: [],
            returnType: intType,
            symbols: symbols,
            interner: interner
        )

        // BufferedReader.ready() -> Boolean  (STDLIB-IO-091)
        registerFileMemberFunction(
            named: "ready",
            externalLinkName: "__kk_buffered_reader_ready",
            ownerSymbol: bufferedReaderSymbol,
            ownerType: bufferedReaderType,
            parameters: [],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        // BufferedReader.iterator() -> Iterator<String>  (STDLIB-IO-FN-022)
        //
        // The standard library declares `iterator()` as an `operator` extension on
        // `BufferedReader` so that `for (line in reader) { ... }` is a shorthand
        // for iterating over the reader's lines. We register the function as a
        // synthetic *operator* member here so it can be picked up both by
        // explicit calls (`reader.iterator()`) and by the for-loop lowering
        // (which requires the `.operatorFunction` flag).
        let iteratorOfStringType = syntheticIteratorType(
            elementType: types.stringType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerFileMemberFunction(
            named: "iterator",
            externalLinkName: "__kk_buffered_reader_iterator",
            ownerSymbol: bufferedReaderSymbol,
            ownerType: bufferedReaderType,
            parameters: [],
            returnType: iteratorOfStringType,
            symbols: symbols,
            interner: interner
        )
        // Promote the synthetic iterator member to an operator function so that
        // implicit `for (line in reader)` resolution succeeds. We look up the
        // symbol after registration because `registerFileMemberFunction` does
        // not surface the newly defined SymbolID.
        let iteratorFQName: [InternedString] = (symbols.symbol(bufferedReaderSymbol)?.fqName ?? [])
            + [interner.intern("iterator")]
        for candidate in symbols.lookupAll(fqName: iteratorFQName) {
            guard let info = symbols.symbol(candidate),
                  info.flags.contains(.synthetic),
                  let signature = symbols.functionSignature(for: candidate),
                  signature.receiverType == bufferedReaderType,
                  signature.parameterTypes.isEmpty
            else { continue }
            symbols.insertFlags(.operatorFunction, for: candidate)
        }

        // BufferedReader.useLines { lines: List<String> -> T } (STDLIB-IO-FN-040)
        //
        // Kotlin declares `useLines` as an extension function on `kotlin.io.Reader`
        // (which `BufferedReader` extends). The lambda is invoked with the receiver's
        // remaining lines as a `Sequence<String>`, and the reader is closed before
        // the function returns. We model the lambda parameter as `List<String>`,
        // flowing through the same runtime helper shape (lines materialised
        // eagerly into a `RuntimeListBox`).
        let listOfStringToAnyTypeBR = types.make(.functionType(FunctionType(
            params: [listOfStringType],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerFileMemberFunction(
            named: "useLines",
            externalLinkName: "__kk_buffered_reader_useLines",
            ownerSymbol: bufferedReaderSymbol,
            ownerType: bufferedReaderType,
            parameters: [("block", listOfStringToAnyTypeBR)],
            returnType: types.anyType,
            symbols: symbols,
            interner: interner
        )

        // BufferedReader.forEachLine { line: String -> Unit } (STDLIB-IO-FN-017)
        //
        // Kotlin declares `forEachLine` as an extension function on `kotlin.io.Reader`
        // (which `BufferedReader` extends). The lambda receives each line as a `String`
        // and returns `Unit`. We model it as a member of `java.io.BufferedReader`.
        // Unlike `useLines`, the reader is NOT automatically closed after iteration.
        registerFileMemberFunction(
            named: "forEachLine",
            externalLinkName: "__kk_buffered_reader_forEachLine",
            ownerSymbol: bufferedReaderSymbol,
            ownerType: bufferedReaderType,
            parameters: [("action", stringToUnitType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - Writer / BufferedWriter types (STDLIB-IO-091/093)

        let writerSymbol = ensureClassSymbol(
            named: "Writer",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
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

        // Register BufferedWriter as a Closeable subtype (STDLIB-IO-093)
        let writerCloseableSymbol = types.ioCloseableInterfaceSymbol ?? javaIOCloseableSymbol
        symbols.setDirectSupertypes([writerCloseableSymbol], for: writerSymbol)
        types.setNominalDirectSupertypes([writerCloseableSymbol], for: writerSymbol)
        symbols.setDirectSupertypes([writerSymbol, writerCloseableSymbol], for: bufferedWriterSymbol)
        types.setNominalDirectSupertypes([writerSymbol, writerCloseableSymbol], for: bufferedWriterSymbol)

        // BufferedWriter.write(text: String) -> Unit
        registerFileMemberFunction(
            named: "write",
            externalLinkName: "__kk_buffered_writer_write",
            ownerSymbol: bufferedWriterSymbol,
            ownerType: bufferedWriterType,
            parameters: [("text", types.stringType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // BufferedWriter.newLine() -> Unit
        registerFileMemberFunction(
            named: "newLine",
            externalLinkName: "__kk_buffered_writer_new_line",
            ownerSymbol: bufferedWriterSymbol,
            ownerType: bufferedWriterType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // BufferedWriter.flush() -> Unit
        registerFileMemberFunction(
            named: "flush",
            externalLinkName: "__kk_buffered_writer_flush",
            ownerSymbol: bufferedWriterSymbol,
            ownerType: bufferedWriterType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // BufferedWriter.close() -> Unit
        registerFileMemberFunction(
            named: "close",
            externalLinkName: "__kk_buffered_writer_close",
            ownerSymbol: bufferedWriterSymbol,
            ownerType: bufferedWriterType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - InputStream / OutputStream (STDLIB-IO-092)

        // MARK: - Resource access (STDLIB-IO-093; unrelated to File, historically co-located)

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

        // Register InputStream/OutputStream as Closeable subtypes (STDLIB-IO-093)
        // so that .use {} works with stream resources.
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

        registerFileConstructor(
            ownerSymbol: byteArrayInputStreamSymbol,
            ownerType: byteArrayInputStreamType,
            parameters: [("buffer", listOfIntType)],
            externalLinkName: "__kk_bytearrayinputstream_new",
            symbols: symbols,
            interner: interner
        )

        // STDLIB-IO-FN-011: String.byteInputStream(charset: Charset = Charsets.UTF_8): ByteArrayInputStream
        // Lives in kotlin.io as an extension function on String. Two overloads are
        // exposed so callers can resolve both `value.byteInputStream()` and
        // `value.byteInputStream(Charsets.UTF_16)` without relying on default-argument
        // synthesis. ByteArrayInputStream → InputStream → Closeable, so the return
        // type carries `.use {}` compatibility through existing supertype wiring.
        let kotlinIOPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("io")],
            symbols: symbols
        )
        let kotlinTextPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("text")]
        let charsetFQName = kotlinTextPkg + [interner.intern("Charset")]
        if let charsetSymbol = symbols.lookup(fqName: charsetFQName) {
            let charsetType = types.make(.classType(ClassType(
                classSymbol: charsetSymbol, args: [], nullability: .nonNull
            )))
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
            registerSyntheticStringExtensionFunction(
                named: "byteInputStream",
                externalLinkName: "__kk_string_byteInputStream_charset_flat",
                receiverType: types.stringType,
                parameters: [
                    ("charset", charsetType, false, false),
                ],
                returnType: byteArrayInputStreamType,
                packageFQName: kotlinIOPkg,
                symbols: symbols,
                interner: interner
            )
        }

        registerFileMemberFunction(
            named: "read",
            externalLinkName: "__kk_input_stream_read",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [],
            returnType: intType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "available",
            externalLinkName: "__kk_input_stream_available",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [],
            returnType: intType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "skip",
            externalLinkName: "__kk_input_stream_skip",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [("count", intType)],
            returnType: intType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "read",
            externalLinkName: "__kk_input_stream_read_bytes",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [("buffer", listOfIntType)],
            returnType: intType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - InputStream.readBytes() (STDLIB-IO-FN-029)
        //
        // Kotlin defines:
        //   public fun InputStream.readBytes(): ByteArray
        //
        // Reads all remaining bytes from `this` and returns them as a freshly
        // allocated ByteArray. We model ByteArray as List<Int>.
        //
        // Note: this extension does NOT close the receiver — callers typically
        // wrap the call in `.use { it.readBytes() }`. Sema only needs to
        // resolve the call shape; the runtime drains the stream.
        registerFileMemberFunction(
            named: "readBytes",
            externalLinkName: "__kk_input_stream_readAllBytes",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [],
            returnType: listOfIntType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "mark",
            externalLinkName: "__kk_input_stream_mark",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [("readLimit", intType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "reset",
            externalLinkName: "__kk_input_stream_reset",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "markSupported",
            externalLinkName: "__kk_input_stream_mark_supported",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "close",
            externalLinkName: "__kk_input_stream_close",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - BufferedInputStream and InputStream.buffered() (STDLIB-IO-FN-003)
        //
        // Kotlin defines:
        //   public inline fun InputStream.buffered(bufferSize: Int = DEFAULT_BUFFER_SIZE): BufferedInputStream
        // We model BufferedInputStream as a java.io.InputStream subtype and expose
        // both the zero-arg and bufferSize overloads as member-style synthetic stubs
        // on InputStream so user code can call `inputStream.buffered()` or
        // `inputStream.buffered(8 * 1024)` and receive a BufferedInputStream value.
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

        // BufferedInputStream extends InputStream so it inherits Closeable + read/skip/etc.
        symbols.setDirectSupertypes([inputStreamSymbol], for: bufferedInputStreamSymbol)
        types.setNominalDirectSupertypes([inputStreamSymbol], for: bufferedInputStreamSymbol)

        // STDLIB-IO-FN-029: BufferedInputStream.readBytes() — delegate to the same
        // runtime entry so that member dispatch resolves without a supertype walk.
        registerFileMemberFunction(
            named: "readBytes",
            externalLinkName: "__kk_input_stream_readAllBytes",
            ownerSymbol: bufferedInputStreamSymbol,
            ownerType: bufferedInputStreamType,
            parameters: [],
            returnType: listOfIntType,
            symbols: symbols,
            interner: interner
        )

        // InputStream.buffered() -> BufferedInputStream (uses DEFAULT_BUFFER_SIZE = 8 * 1024)
        registerFileMemberFunction(
            named: "buffered",
            externalLinkName: "__kk_input_stream_buffered_default",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [],
            returnType: bufferedInputStreamType,
            symbols: symbols,
            interner: interner
        )

        // InputStream.buffered(bufferSize: Int) -> BufferedInputStream
        registerFileMemberFunction(
            named: "buffered",
            externalLinkName: "__kk_input_stream_buffered",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [("bufferSize", intType)],
            returnType: bufferedInputStreamType,
            symbols: symbols,
            interner: interner
        )

        // STDLIB-IO-FN-013: InputStream.copyTo(out, bufferSize) -> Long
        //
        // Kotlin signature:
        //   public fun InputStream.copyTo(
        //       out: OutputStream,
        //       bufferSize: Int = DEFAULT_BUFFER_SIZE
        //   ): Long
        //
        // Registered as a kotlin.io extension function on InputStream.
        // Two overloads: one with an explicit bufferSize and one that
        // relies on the default (DEFAULT_BUFFER_SIZE = 8 * 1024).
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

        registerFileMemberFunction(
            named: "read",
            externalLinkName: "__kk_sequence_input_stream_read",
            ownerSymbol: sequenceInputStreamSymbol,
            ownerType: sequenceInputStreamType,
            parameters: [],
            returnType: intType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "available",
            externalLinkName: "__kk_sequence_input_stream_available",
            ownerSymbol: sequenceInputStreamSymbol,
            ownerType: sequenceInputStreamType,
            parameters: [],
            returnType: intType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "close",
            externalLinkName: "__kk_sequence_input_stream_close",
            ownerSymbol: sequenceInputStreamSymbol,
            ownerType: sequenceInputStreamType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "write",
            externalLinkName: "__kk_output_stream_write_byte",
            ownerSymbol: outputStreamSymbol,
            ownerType: outputStreamType,
            parameters: [("value", intType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "write",
            externalLinkName: "__kk_output_stream_write_bytes",
            ownerSymbol: outputStreamSymbol,
            ownerType: outputStreamType,
            parameters: [("buffer", listOfIntType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "flush",
            externalLinkName: "__kk_output_stream_flush",
            ownerSymbol: outputStreamSymbol,
            ownerType: outputStreamType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "close",
            externalLinkName: "__kk_output_stream_close",
            ownerSymbol: outputStreamSymbol,
            ownerType: outputStreamType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // STDLIB-IO-FN-004: OutputStream.buffered() / buffered(bufferSize) extension members.
        // Returns an OutputStream that wraps the receiver with buffering. The runtime
        // implementation is identity-compatible: the underlying RuntimeOutputStreamBox
        // already streams through the OS, so the wrapped handle is the same instance.
        // This satisfies Kotlin's `fun OutputStream.buffered(bufferSize: Int = DEFAULT_BUFFER_SIZE): BufferedOutputStream`
        // contract at the Sema surface — callers can chain `.write(...)` / `.flush()` / `.close()` etc.
        registerFileMemberFunction(
            named: "buffered",
            externalLinkName: "__kk_output_stream_buffered",
            ownerSymbol: outputStreamSymbol,
            ownerType: outputStreamType,
            parameters: [],
            returnType: outputStreamType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "buffered",
            externalLinkName: "__kk_output_stream_buffered_sized",
            ownerSymbol: outputStreamSymbol,
            ownerType: outputStreamType,
            parameters: [("bufferSize", intType)],
            returnType: outputStreamType,
            symbols: symbols,
            interner: interner
        )

        // ClassLoader resource access functions (STDLIB-IO-093)

        registerFileMemberFunction(
            named: "getResource",
            externalLinkName: "__kk_classloader_getResource",
            ownerSymbol: classLoaderSymbol,
            ownerType: classLoaderType,
            parameters: [("name", types.stringType)],
            returnType: nullableStringType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "getResourceAsStream",
            externalLinkName: "__kk_classloader_getResourceAsStream",
            ownerSymbol: classLoaderSymbol,
            ownerType: classLoaderType,
            parameters: [("name", types.stringType)],
            returnType: nullableInputStreamType,
            symbols: symbols,
            interner: interner
        )

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

        // MARK: - OutputStream.bufferedWriter(charset) (STDLIB-IO-FN-009)
        //
        // Kotlin signature: `public fun OutputStream.bufferedWriter(
        //     charset: Charset = Charsets.UTF_8
        // ): BufferedWriter`  declared in the `kotlin.io` package.
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

        // MARK: - Reader.readText() (STDLIB-IO-FN-033)
        //
        // Kotlin signature: `public fun Reader.readText(): String` declared in
        // the `kotlin.io` package. Reads the entire remaining content of the
        // receiver into a single `String`. Mirrors the stdlib semantics of
        // exhausting the reader; the runtime helper `__kk_reader_readText`
        // delegates to `RuntimeBufferedReaderBox.readText()`.
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

        // MARK: - Reader.copyTo(out: Writer, bufferSize: Int) -> Long  (STDLIB-IO-FN-014)
        //
        // Kotlin signature:
        //   public fun Reader.copyTo(out: Writer, bufferSize: Int = DEFAULT_BUFFER_SIZE): Long
        // declared in the `kotlin.io` package.  Copies the receiver's remaining
        // characters into `out` using an internal buffer of `bufferSize` chars
        // (Kotlin's default is 16 * 1024 = 16384) and returns the total number
        // of characters transferred.  Neither the receiver nor `out` is closed.
        //
        // We register both the two-arg form (with `bufferSize`'s default-value
        // marker) and a zero-arg overload that routes to a `_default` runtime
        // variant — matching how Path extensions handle defaulted parameters
        // because codegen does not currently synthesise default-value calls.
        // Two-arg overload (explicit bufferSize required): reader.copyTo(writer, 1024)
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

        // Single-arg overload (default bufferSize): reader.copyTo(writer)
        // Registers as a separate overload to avoid ambiguity between this
        // and the two-arg form.
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

        // MARK: - ByteArray.inputStream() and ByteArray.inputStream(offset, length) (STDLIB-IO-FN-020 / STDLIB-IO-FN-021)
        //
        // Kotlin stdlib declares two overloads in kotlin.io:
        //   fun ByteArray.inputStream(): ByteArrayInputStream
        //   fun ByteArray.inputStream(offset: Int, length: Int): ByteArrayInputStream
        //
        // We register both on the ByteArray class symbol so that extension-receiver
        // resolution succeeds for both `bytes.inputStream()` and
        // `bytes.inputStream(offset, length)`.
        if let byteArraySymbol = symbols.lookup(fqName: byteArrayFQName) {
            let byteArrayType = types.make(.classType(ClassType(
                classSymbol: byteArraySymbol, args: [], nullability: .nonNull
            )))

            // STDLIB-IO-FN-020: ByteArray.inputStream() -> ByteArrayInputStream
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

            // STDLIB-IO-FN-021: ByteArray.inputStream(offset: Int, length: Int) -> ByteArrayInputStream
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

        // MARK: - kotlin.io.Writer.buffered (STDLIB-IO-FN-006)
        // Writer.buffered(): BufferedWriter
        // Writer.buffered(bufferSize: Int): BufferedWriter
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

        // STDLIB-IO-FN-007: kotlin.io.InputStream.bufferedReader(charset)
        // Top-level extension function on java.io.InputStream returning BufferedReader.
        // Signature: fun InputStream.bufferedReader(charset: Charset = Charsets.UTF_8): BufferedReader
        let resolvedCharsetType: TypeID = {
            if let charsetSymbol = symbols.lookup(fqName: charsetFQName) {
                return types.make(.classType(ClassType(
                    classSymbol: charsetSymbol,
                    args: [],
                    nullability: .nonNull
                )))
            }
            return types.anyType
        }()

        registerExtensionFunction(
            named: "bufferedReader",
            packageFQName: kotlinIOPkg,
            receiverType: inputStreamType,
            parameters: [("charset", resolvedCharsetType)],
            returnType: bufferedReaderType,
            externalLinkName: "__kk_input_stream_bufferedReader",
            valueParameterHasDefaultValues: [true],
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - Private Helpers

    func resolveListSymbol(
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

    /// Registers a top-level extension function in a Kotlin package
    /// (e.g. `kotlin.io`) whose receiver is a class symbol such as
    /// `java.io.OutputStream`.  Used for stdlib extensions like
    /// `OutputStream.bufferedWriter(charset)` (STDLIB-IO-FN-009).
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
        let functionFQName = packageFQName + [functionName]
        let parameterTypes = parameters.map(\.type)
        let defaults = valueParameterHasDefaultValues
            ?? Array(repeating: false, count: parameters.count)
        let varargs = valueParameterIsVararg
            ?? Array(repeating: false, count: parameters.count)

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
                        valueParameterIsVararg: varargs
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
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == ownerType
                && existingSignature.parameterTypes == parameters.map(\.type)
        }) {
            // Only overwrite synthetic symbols to avoid clobbering user/stdlib declarations
            guard let existingInfo = symbols.symbol(existing),
                  existingInfo.flags.contains(.synthetic) || existingInfo.declSite == nil else {
                return
            }
            symbols.setExternalLinkName(externalLinkName, for: existing)
            // Update the signature if the return type diverges from the intended type
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
                        valueParameterIsVararg: existingSignature.valueParameterIsVararg
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

    /// Keep the JVM compatibility nominal without synthesizing the common
    /// `kotlin.AutoCloseable` or `kotlin.io.Closeable` declarations.
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

    /// Register a top-level Kotlin extension function in `packageFQName` with the
    /// provided receiver. Mirrors `registerPathExtensionFunction` from
    /// `HeaderHelpers+SyntheticPathStubs.swift`, scoped to this file so that
    /// extensions on `InputStream` / `OutputStream` can live next to the rest
    /// of the java.io stream stubs without leaking helpers between extension files.
    private func registerExtensionFunction(
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
        let functionFQName = packageFQName + [functionName]
        let parameterTypes = parameters.map(\.type)
        let defaults = valueParameterHasDefaultValues
            ?? Array(repeating: false, count: parameters.count)
        let varargs = valueParameterIsVararg
            ?? Array(repeating: false, count: parameters.count)

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
                        valueParameterIsVararg: varargs
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
        if let pkgSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(pkgSymbol, for: functionSymbol)
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
            // Only overwrite synthetic symbols to avoid clobbering user/stdlib declarations
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

    /// Registers a synthetic top-level extension function on a receiver type within
    /// a package (e.g. `kotlin.io.Writer.buffered()`).
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
