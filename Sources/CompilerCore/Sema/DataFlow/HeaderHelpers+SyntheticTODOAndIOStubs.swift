import RuntimeABI

/// Synthetic stdlib stubs for kotlin's not-yet-implemented helper, kotlin.io.println (0-arg), and kotlin.io.readLine (STDLIB-063).
/// These stubs enable name resolution and type checking; runtime behavior is implemented in Runtime.
extension DataFlowSemaPhase {
    func registerSyntheticTODOAndIOStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        bundledIndex: BundledDeclarationIndex = .empty,
        skipStats: SyntheticStubSkipStatsCollector? = nil
    ) {
        let kotlinPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin")],
            symbols: symbols
        )
        let kotlinIOPkg = ensureSyntheticPackageHierarchy(fqName: [interner.intern("kotlin"), interner.intern("io")], symbols: symbols)

        registerSyntheticIOTopLevelProperty(
            named: "DEFAULT_BUFFER_SIZE",
            packageFQName: kotlinIOPkg,
            returnType: types.intType,
            externalLinkName: "kk_io_default_buffer_size",
            constValue: .intLiteral(8192),
            symbols: symbols,
            interner: interner
        )

        registerSyntheticTopLevelFunction(
            named: "println",
            packageFQName: kotlinIOPkg,
            parameters: [],
            returnType: types.unitType,
            externalLinkName: "kk_println_newline",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "println",
            packageFQName: kotlinIOPkg,
            parameters: [(name: "message", type: types.makeNullable(types.anyType))],
            returnType: types.unitType,
            externalLinkName: "kk_println_any",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticTopLevelFunction(
            named: "print",
            packageFQName: kotlinIOPkg,
            parameters: [],
            returnType: types.unitType,
            externalLinkName: "kk_print_noarg",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "print",
            packageFQName: kotlinIOPkg,
            parameters: [(name: "message", type: types.makeNullable(types.anyType))],
            returnType: types.unitType,
            externalLinkName: "kk_print_any",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticTopLevelFunction(
            named: "readLine",
            packageFQName: kotlinIOPkg,
            parameters: [],
            returnType: types.makeNullable(types.stringType),
            externalLinkName: "kk_readline",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticTopLevelFunction(
            named: "readln",
            packageFQName: kotlinIOPkg,
            parameters: [],
            returnType: types.stringType,
            externalLinkName: "kk_readln",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticTopLevelFunction(
            named: "readlnOrNull",
            packageFQName: kotlinIOPkg,
            parameters: [],
            returnType: types.makeNullable(types.stringType),
            externalLinkName: "kk_readlnOrNull",
            symbols: symbols,
            interner: interner
        )

        // --- Sequence factory functions (STDLIB-097) ---
        let kotlinSequencesPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("sequences")],
            symbols: symbols
        )
        let sequenceSymbol = registerSyntheticSequenceStub(
            packageFQName: kotlinSequencesPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticSequenceBuilderStub(
            symbols: symbols,
            types: types,
            interner: interner
        )

        // --- Grouping type (STDLIB-285/286) ---
        registerSyntheticGroupingStub(
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerSyntheticGenericSequenceVarargFunction(
            named: "sequenceOf",
            packageFQName: kotlinSequencesPkg,
            sequenceSymbol: sequenceSymbol,
            externalLinkName: "kk_sequence_of",
            symbols: symbols,
            types: types,
            interner: interner
        )

        // STDLIB-277: emptySequence<T>()
        registerSyntheticGenericSequenceNoArgFunction(
            named: "emptySequence",
            packageFQName: kotlinSequencesPkg,
            sequenceSymbol: sequenceSymbol,
            externalLinkName: "kk_empty_sequence",
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerSyntheticGenerateSequenceFunction(
            named: "generateSequence",
            packageFQName: kotlinSequencesPkg,
            sequenceSymbol: sequenceSymbol,
            externalLinkName: "kk_sequence_generate",
            symbols: symbols,
            types: types,
            interner: interner
        )

        // STDLIB-SEQ-002: 1-arg form generateSequence(nextFunction: () -> T?)
        registerSyntheticGenerateSequenceNoArgFunction(
            named: "generateSequence",
            packageFQName: kotlinSequencesPkg,
            sequenceSymbol: sequenceSymbol,
            externalLinkName: "kk_sequence_generate_noarg",
            symbols: symbols,
            types: types,
            interner: interner
        )

        // STDLIB-331/564: iterator {} builder → Iterator<T>
        // Registered with SequenceScope<T> receiver so yield() resolves inside the lambda.
        registerSyntheticIteratorBuilderStub(
            packageFQName: kotlinSequencesPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // STDLIB-330: sequence { yield(x) } builder
        registerSyntheticSequenceBuilderStub(
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerSyntheticSequenceJoinToMember(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinSequencesPkg: kotlinSequencesPkg,
            bundledIndex: bundledIndex,
            skipStats: skipStats
        )
        registerSyntheticSequenceJoinToStringMember(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinSequencesPkg: kotlinSequencesPkg,
            bundledIndex: bundledIndex,
            skipStats: skipStats
        )
        registerSyntheticSequenceTerminalMembers(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinSequencesPkg: kotlinSequencesPkg
        )

        // --- kotlin.system package functions (STDLIB-131/132) ---
        let kotlinSystemPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("system")],
            symbols: symbols
        )

        registerSyntheticTopLevelFunction(
            named: "exitProcess",
            packageFQName: kotlinSystemPkg,
            parameters: [(name: "status", type: types.intType)],
            returnType: types.nothingType,
            externalLinkName: "kk_system_exitProcess",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticTopLevelFunction(
            named: "getTimeMicros",
            packageFQName: kotlinSystemPkg,
            parameters: [],
            returnType: types.longType,
            externalLinkName: "kk_system_getTimeMicros",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticTopLevelFunction(
            named: "getTimeMillis",
            packageFQName: kotlinSystemPkg,
            parameters: [],
            returnType: types.longType,
            externalLinkName: "kk_system_getTimeMillis",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticTopLevelFunction(
            named: "getTimeNanos",
            packageFQName: kotlinSystemPkg,
            parameters: [],
            returnType: types.longType,
            externalLinkName: "kk_system_getTimeNanos",
            symbols: symbols,
            interner: interner
        )

        let blockFunctionType = types.make(.functionType(FunctionType(
            params: [],
            returnType: types.unitType
        )))

        registerSyntheticTopLevelFunction(
            named: "measureTimeMicros",
            packageFQName: kotlinSystemPkg,
            parameters: [(name: "block", type: blockFunctionType)],
            returnType: types.longType,
            externalLinkName: "kk_system_measureTimeMicros",
            stdlibSpecialCallKind: .measureTimeMicros,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticTopLevelFunction(
            named: "measureTimeMillis",
            packageFQName: kotlinSystemPkg,
            parameters: [(name: "block", type: blockFunctionType)],
            returnType: types.longType,
            externalLinkName: "kk_system_measureTimeMillis",
            stdlibSpecialCallKind: .measureTimeMillis,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticTopLevelFunction(
            named: "measureNanoTime",
            packageFQName: kotlinSystemPkg,
            parameters: [(name: "block", type: blockFunctionType)],
            returnType: types.longType,
            externalLinkName: "kk_system_measureNanoTime",
            stdlibSpecialCallKind: .measureNanoTime,
            symbols: symbols,
            interner: interner
        )

        // --- kotlin.system.System object (STDLIB-131) ---
        let systemSymbol = ensureSyntheticObjectSymbol(
            named: "System",
            in: kotlinSystemPkg,
            symbols: symbols,
            interner: interner
        )
        let systemType = types.make(.classType(ClassType(
            classSymbol: systemSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(systemType, for: systemSymbol)
        registerSyntheticSystemMember(
            ownerSymbol: systemSymbol,
            ownerType: systemType,
            name: "currentTimeMillis",
            externalLinkName: "kk_system_currentTimeMillis",
            returnType: types.longType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticSystemMember(
            ownerSymbol: systemSymbol,
            ownerType: systemType,
            name: "nanoTime",
            externalLinkName: "kk_system_nanoTime",
            returnType: types.longType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticSystemMember(
            ownerSymbol: systemSymbol,
            ownerType: systemType,
            name: "processStartNanos",
            externalLinkName: "kk_system_process_start_nanos",
            returnType: types.longType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        // --- kotlin.native.Platform (STDLIB-NATIVE-169) ---
        let kotlinNativePkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("native")],
            symbols: symbols
        )
        let osFamilySymbol = ensureSyntheticPlatformEnumClass(
            named: "OsFamily",
            entries: [
                "UNKNOWN", "MACOSX", "IOS", "TVOS", "WATCHOS",
                "LINUX", "WINDOWS", "ANDROID", "WASM",
            ],
            in: kotlinNativePkg,
            symbols: symbols,
            interner: interner
        )
        let osFamilyType = types.make(.classType(ClassType(
            classSymbol: osFamilySymbol,
            args: [],
            nullability: .nonNull
        )))
        setSyntheticPlatformEnumEntryTypes(
            enumSymbol: osFamilySymbol,
            enumType: osFamilyType,
            symbols: symbols
        )

        let cpuArchitectureSymbol = ensureSyntheticPlatformEnumClass(
            named: "CpuArchitecture",
            entries: [
                "UNKNOWN", "X86", "X64", "ARM32",
                "ARM64", "MIPS32", "MIPSEL32", "WASM32",
            ],
            in: kotlinNativePkg,
            symbols: symbols,
            interner: interner
        )
        let cpuArchitectureType = types.make(.classType(ClassType(
            classSymbol: cpuArchitectureSymbol,
            args: [],
            nullability: .nonNull
        )))
        setSyntheticPlatformEnumEntryTypes(
            enumSymbol: cpuArchitectureSymbol,
            enumType: cpuArchitectureType,
            symbols: symbols
        )
        let memoryModelSymbol = ensureSyntheticPlatformEnumClass(
            named: "MemoryModel",
            entries: [
                "STRICT", "RELAXED", "EXPERIMENTAL",
            ],
            in: kotlinNativePkg,
            symbols: symbols,
            interner: interner
        )
        let memoryModelType = types.make(.classType(ClassType(
            classSymbol: memoryModelSymbol,
            args: [],
            nullability: .nonNull
        )))
        setSyntheticPlatformEnumEntryTypes(
            enumSymbol: memoryModelSymbol,
            enumType: memoryModelType,
            symbols: symbols
        )

        let platformSymbol = ensureSyntheticObjectSymbol(
            named: "Platform",
            in: kotlinNativePkg,
            symbols: symbols,
            interner: interner
        )
        let platformType = types.make(.classType(ClassType(
            classSymbol: platformSymbol,
            args: [],
            nullability: .nonNull
        )))
        let booleanType = types.make(.primitive(.boolean, .nonNull))
        symbols.setPropertyType(platformType, for: platformSymbol)

        registerSyntheticObjectProperty(
            ownerSymbol: platformSymbol,
            name: "canAccessUnaligned",
            propertyType: booleanType,
            externalLinkName: "kk_platform_canAccessUnaligned",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticObjectProperty(
            ownerSymbol: platformSymbol,
            name: "isLittleEndian",
            propertyType: booleanType,
            externalLinkName: "kk_platform_isLittleEndian",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticObjectProperty(
            ownerSymbol: platformSymbol,
            name: "osFamily",
            propertyType: osFamilyType,
            externalLinkName: "kk_platform_osFamily",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticObjectProperty(
            ownerSymbol: platformSymbol,
            name: "cpuArchitecture",
            propertyType: cpuArchitectureType,
            externalLinkName: "kk_platform_cpuArchitecture",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticObjectProperty(
            ownerSymbol: platformSymbol,
            name: "memoryModel",
            propertyType: memoryModelType,
            externalLinkName: "kk_platform_memoryModel",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticSystemMember(
            ownerSymbol: platformSymbol,
            ownerType: platformType,
            name: "getAvailableProcessors",
            externalLinkName: "kk_platform_getAvailableProcessors",
            returnType: types.intType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        // --- java.lang.System / Runtime memory management (STDLIB-PERF-154) ---
        let javaLangPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("java"), interner.intern("lang")],
            symbols: symbols
        )
        let javaClassSymbol = ensureSyntheticJavaLangClassSymbol(
            in: javaLangPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticJavaClassExtensionProperty(
            kotlinPkg: kotlinPkg,
            javaClassSymbol: javaClassSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        let javaSystemSymbol = ensureSyntheticObjectSymbol(
            named: "System",
            in: javaLangPkg,
            symbols: symbols,
            interner: interner
        )
        let javaSystemType = types.make(.classType(ClassType(
            classSymbol: javaSystemSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(javaSystemType, for: javaSystemSymbol)
        registerSyntheticSystemMember(
            ownerSymbol: javaSystemSymbol,
            ownerType: javaSystemType,
            name: "gc",
            externalLinkName: "kk_system_gc",
            returnType: types.unitType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        let runtimeSymbol = ensureSyntheticObjectSymbol(
            named: "Runtime",
            in: javaLangPkg,
            symbols: symbols,
            interner: interner
        )
        let runtimeType = types.make(.classType(ClassType(
            classSymbol: runtimeSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(runtimeType, for: runtimeSymbol)
        registerSyntheticSystemMember(
            ownerSymbol: runtimeSymbol,
            ownerType: runtimeType,
            name: "getRuntime",
            externalLinkName: "kk_runtime_getRuntime",
            returnType: runtimeType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticSystemMember(
            ownerSymbol: runtimeSymbol,
            ownerType: runtimeType,
            name: "totalMemory",
            externalLinkName: "kk_runtime_totalMemory",
            returnType: types.longType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticSystemMember(
            ownerSymbol: runtimeSymbol,
            ownerType: runtimeType,
            name: "freeMemory",
            externalLinkName: "kk_runtime_freeMemory",
            returnType: types.longType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticSystemMember(
            ownerSymbol: runtimeSymbol,
            ownerType: runtimeType,
            name: "maxMemory",
            externalLinkName: "kk_runtime_maxMemory",
            returnType: types.longType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        // KSP-618: kotlin.synchronized is Kotlin source
        // (Stdlib/kotlin/Synchronized.kt) over the demoted __kk_synchronized
        // bridge, so no synthetic stub is registered here.

        // --- java.io.File (STDLIB-320) ---
        let javaIOPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("java"), interner.intern("io")],
            symbols: symbols
        )
        let fileSymbol = ensureClassSymbol(
            named: "File",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        let fileType = types.make(.classType(ClassType(
            classSymbol: fileSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(fileType, for: fileSymbol)

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
            packageFQName: kotlinIOPkg,
            parameters: [],
            returnType: fileType,
            externalLinkName: "kk_io_createTempDir_default",
            annotations: deprecatedCreateTempDirAnnotations,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "createTempDir",
            packageFQName: kotlinIOPkg,
            parameters: [(name: "prefix", type: types.stringType)],
            returnType: fileType,
            externalLinkName: "kk_io_createTempDir_prefix",
            annotations: deprecatedCreateTempDirAnnotations,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "createTempDir",
            packageFQName: kotlinIOPkg,
            parameters: [
                (name: "prefix", type: types.stringType),
                (name: "suffix", type: types.makeNullable(types.stringType)),
            ],
            returnType: fileType,
            externalLinkName: "kk_io_createTempDir_prefix_suffix",
            annotations: deprecatedCreateTempDirAnnotations,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "createTempDir",
            packageFQName: kotlinIOPkg,
            parameters: [
                (name: "prefix", type: types.stringType),
                (name: "suffix", type: types.makeNullable(types.stringType)),
                (name: "directory", type: types.makeNullable(fileType)),
            ],
            returnType: fileType,
            externalLinkName: "kk_io_createTempDir",
            annotations: deprecatedCreateTempDirAnnotations,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticTopLevelFunction(
            named: "createTempFile",
            packageFQName: kotlinIOPkg,
            parameters: [],
            returnType: fileType,
            externalLinkName: "kk_io_createTempFile_default",
            annotations: deprecatedCreateTempFileAnnotations,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "createTempFile",
            packageFQName: kotlinIOPkg,
            parameters: [(name: "prefix", type: types.stringType)],
            returnType: fileType,
            externalLinkName: "kk_io_createTempFile_prefix",
            annotations: deprecatedCreateTempFileAnnotations,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "createTempFile",
            packageFQName: kotlinIOPkg,
            parameters: [
                (name: "prefix", type: types.stringType),
                (name: "suffix", type: types.makeNullable(types.stringType)),
            ],
            returnType: fileType,
            externalLinkName: "kk_io_createTempFile_prefix_suffix",
            annotations: deprecatedCreateTempFileAnnotations,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "createTempFile",
            packageFQName: kotlinIOPkg,
            parameters: [
                (name: "prefix", type: types.stringType),
                (name: "suffix", type: types.makeNullable(types.stringType)),
                (name: "directory", type: types.makeNullable(fileType)),
            ],
            returnType: fileType,
            externalLinkName: "kk_io_createTempFile",
            annotations: deprecatedCreateTempFileAnnotations,
            symbols: symbols,
            interner: interner
        )

        // File(path: String) constructor
        registerSyntheticConstructor(
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            externalLinkName: "kk_file_new",
            parameters: [(name: "path", type: types.stringType)],
            symbols: symbols,
            interner: interner
        )

        // readText(): String
        registerSyntheticSystemMember(
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            name: "readText",
            externalLinkName: "kk_file_readText",
            returnType: types.stringType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        // writeText(text: String): Unit
        registerSyntheticSystemMember(
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            name: "writeText",
            externalLinkName: "kk_file_writeText",
            returnType: types.unitType,
            parameters: [(name: "text", type: types.stringType)],
            symbols: symbols,
            interner: interner
        )

        // appendText(text: String): Unit
        registerSyntheticSystemMember(
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            name: "appendText",
            externalLinkName: "kk_file_appendText",
            returnType: types.unitType,
            parameters: [(name: "text", type: types.stringType)],
            symbols: symbols,
            interner: interner
        )

        // readLines(): List<String>
        let listOfStringType = makeFileListOfStringType(
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticSystemMember(
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            name: "readLines",
            externalLinkName: "kk_file_readLines",
            returnType: listOfStringType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        // --- kotlin.time package (STDLIB-230/231/585) ---
        let kotlinTimePkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("time")],
            symbols: symbols
        )

        // Register synthetic Duration class (STDLIB-585)
        let durationName = interner.intern("Duration")
        let durationFQName = kotlinTimePkg + [durationName]
        let durationSymbol: SymbolID = if let existing = symbols.lookup(fqName: durationFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: durationName,
                fqName: durationFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let packageSymbol = symbols.lookup(fqName: kotlinTimePkg) {
            symbols.setParentSymbol(packageSymbol, for: durationSymbol)
        }

        let durationClassType = types.make(.classType(ClassType(
            classSymbol: durationSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(durationClassType, for: durationSymbol)

        // Register Duration.inWholeNanoseconds property (returns Long)
        registerSyntheticDurationMember(
            named: "inWholeNanoseconds",
            externalLinkName: "kk_duration_inWholeNanoseconds",
            durationSymbol: durationSymbol,
            durationFQName: durationFQName,
            receiverType: durationClassType,
            returnType: types.longType,
            symbols: symbols,
            interner: interner,
            isProperty: true
        )

        // Register Duration.toString() (returns String)
        registerSyntheticDurationMember(
            named: "toString",
            externalLinkName: "kk_duration_toString",
            durationSymbol: durationSymbol,
            durationFQName: durationFQName,
            receiverType: durationClassType,
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )

        // measureTime / measureTimedValue live in bundled Kotlin source
        // (Stdlib/kotlin/time/MeasureTime.kt).

        // --- STDLIB-HOF-029: 関数型完全実装 ---
        registerSyntheticFunctionTypes(
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func makeFileListOfStringType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let listFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]
        guard let listSymbol = symbols.lookup(fqName: listFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(types.stringType)],
            nullability: .nonNull
        )))
    }

    private func registerSyntheticConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        externalLinkName: String,
        parameters: [(name: String, type: TypeID)],
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

    func registerSequenceScopeMember(
        named name: String,
        sequenceScopeSymbol: SymbolID,
        sequenceScopeFQName: [InternedString],
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let memberName = interner.intern(name)
        let memberFQName = sequenceScopeFQName + [memberName]
        let parameterTypes = parameters.map(\.type)
        if symbols.lookupAll(fqName: memberFQName).contains(where: { symbolID in
            symbols.functionSignature(for: symbolID)?.parameterTypes == parameterTypes
        }) {
            return
        }

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(sequenceScopeSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)

        var parameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: parameterSymbol)
            parameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameters.count),
                valueParameterIsVararg: Array(repeating: false, count: parameters.count),
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerSyntheticDurationMember(
        named name: String,
        externalLinkName: String,
        durationSymbol: SymbolID,
        durationFQName: [InternedString],
        receiverType: TypeID,
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner,
        isProperty: Bool = false
    ) {
        let memberName = interner.intern(name)
        let memberFQName = durationFQName + [memberName]

        // If a symbol already exists at this fqName, ensure its linkage
        // metadata is up-to-date (mirroring registerSyntheticTopLevelFunction).
        if let existing = symbols.lookup(fqName: memberFQName) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            if isProperty {
                symbols.setPropertyType(returnType, for: existing)
            }
            return
        }

        if isProperty {
            let memberSymbol = symbols.define(
                kind: .property,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(durationSymbol, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
            symbols.setPropertyType(returnType, for: memberSymbol)
        } else {
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(durationSymbol, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: returnType,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [],
                    classTypeParameterCount: 0
                ),
                for: memberSymbol
            )
        }
    }

    func registerSequenceMemberStub(
        named name: String,
        externalLinkName: String,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        sequenceSymbol: SymbolID,
        sequenceFQName: [InternedString],
        typeParamSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner,
        annotations: [MetadataAnnotationRecord] = [],
        canThrow: Bool = false,
        typeParameterUpperBounds: [TypeID] = [],
        typeParameterUpperBoundsList: [[TypeID]]? = nil,
        additionalTypeParameterSymbols: [SymbolID] = [],
        additionalTypeParameterUpperBoundsList: [[TypeID]] = [],
        flags: SymbolFlags = [.synthetic, .operatorFunction]
    ) {
        if BundledSyntheticStubRegistration.preBundledPass {
            return
        }

        let memberName = interner.intern(name)
        let memberFQName = sequenceFQName + [memberName]
        let requestedParameterTypes = parameters.map(\.type)
        let resolvedExternalLinkName = StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
            ownerKind: .sequence,
            memberName: name,
            arity: parameters.count,
            fallback: externalLinkName
        )

        if let existing = symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes == requestedParameterTypes
                && signature.returnType == returnType
        }) {
            // KSP-441〜447: source Sequence 関数が存在すれば、合成外部リンクで上書きしない。
            if symbols.symbol(existing)?.declSite != nil {
                return
            }
            symbols.setExternalLinkName(resolvedExternalLinkName, for: existing)
            return
        }

        if let types = BundledSyntheticStubRegistration.types,
           BundledSyntheticStubRegistration.shouldSkipRegistration(
               declaredOwnerFQName: sequenceFQName,
               receiverType: receiverType,
               name: memberName,
               arity: parameters.count,
               symbols: symbols,
               types: types,
               interner: interner
           )
        {
            return
        }

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        symbols.setParentSymbol(sequenceSymbol, for: memberSymbol)
        symbols.setExternalLinkName(resolvedExternalLinkName, for: memberSymbol)
        if !annotations.isEmpty {
            symbols.setAnnotations(annotations, for: memberSymbol)
        }

        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: parameterSymbol)
            parameterTypes.append(parameter.type)
            parameterSymbols.append(parameterSymbol)
        }

        let allTypeParameterSymbols = [typeParamSymbol] + additionalTypeParameterSymbols
        let reifiedTypeParameterIndices = Set(
            allTypeParameterSymbols.enumerated().compactMap { index, symbolID in
                symbols.symbol(symbolID)?.flags.contains(.reifiedTypeParameter) == true ? index : nil
            }
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                canThrow: canThrow,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameters.count),
                valueParameterIsVararg: Array(repeating: false, count: parameters.count),
                typeParameterSymbols: allTypeParameterSymbols,
                reifiedTypeParameterIndices: reifiedTypeParameterIndices,
                typeParameterUpperBoundsList: (typeParameterUpperBoundsList ?? [typeParameterUpperBounds]) + additionalTypeParameterUpperBoundsList,
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    func makeSyntheticIterableType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let iterableFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterable"),
        ]
        guard let iterableSymbol = symbols.lookup(fqName: iterableFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: iterableSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    private func registerSyntheticObjectProperty(
        ownerSymbol: SymbolID,
        name: String,
        propertyType: TypeID,
        externalLinkName: String,
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
            symbols.setPropertyType(propertyType, for: existing)
            symbols.setExternalLinkName(externalLinkName, for: existing)
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
        symbols.setPropertyType(propertyType, for: propertySymbol)
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
    }

    private func ensureSyntheticJavaLangClassSymbol(
        in javaLangPkg: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let classSymbol = ensureClassSymbol(
            named: "Class",
            in: javaLangPkg,
            symbols: symbols,
            interner: interner
        )
        let className = interner.intern("Class")
        let typeParamName = interner.intern("T")
        let typeParamFQName = javaLangPkg + [className, typeParamName]
        let typeParamSymbol = symbols.lookup(fqName: typeParamFQName) ?? symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: classSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: classSymbol)
        return classSymbol
    }

    private func registerSyntheticJavaClassExtensionProperty(
        kotlinPkg: [InternedString],
        javaClassSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let propertyName = interner.intern("javaClass")
        let propertyFQName = kotlinPkg + [propertyName]
        let typeParamName = interner.intern("T")
        let typeParamFQName = propertyFQName + [typeParamName]
        let typeParamSymbol = symbols.lookup(fqName: typeParamFQName) ?? symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: javaClassSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        let externalLinkName = "kk_any_javaClass"

        let propertySymbol: SymbolID
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
                && symbols.extensionPropertyReceiverType(for: symbolID) == typeParamType
        }) {
            propertySymbol = existing
        } else {
            propertySymbol = symbols.define(
                kind: .property,
                name: propertyName,
                fqName: propertyFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let packageSymbol = symbols.lookup(fqName: kotlinPkg) {
                symbols.setParentSymbol(packageSymbol, for: propertySymbol)
            }
            symbols.setExtensionPropertyReceiverType(typeParamType, for: propertySymbol)
        }

        symbols.setPropertyType(returnType, for: propertySymbol)
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)

        let getterSymbol: SymbolID
        if let existingGetter = symbols.extensionPropertyGetterAccessor(for: propertySymbol) {
            getterSymbol = existingGetter
        } else {
            getterSymbol = symbols.define(
                kind: .function,
                name: interner.intern("get"),
                fqName: propertyFQName + [interner.intern("$get")],
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(propertySymbol, for: getterSymbol)
            symbols.setExtensionPropertyGetterAccessor(getterSymbol, for: propertySymbol)
            symbols.setAccessorOwnerProperty(propertySymbol, for: getterSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: typeParamType,
                parameterTypes: [],
                returnType: returnType,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: [],
                typeParameterSymbols: [typeParamSymbol],
                typeParameterUpperBoundsList: [[types.anyType]],
                classTypeParameterCount: 0
            ),
            for: getterSymbol
        )
        symbols.setExternalLinkName(externalLinkName, for: getterSymbol)
    }

    private func ensureSyntheticPlatformEnumClass(
        named name: String,
        entries: [String],
        in pkg: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let internedName = interner.intern(name)
        let fqName = pkg + [internedName]
        let enumSymbol: SymbolID
        if let existing = symbols.lookup(fqName: fqName) {
            enumSymbol = existing
        } else {
            let symbol = symbols.define(
                kind: .enumClass,
                name: internedName,
                fqName: fqName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let pkgSymbol = symbols.lookup(fqName: pkg), pkgSymbol != .invalid {
                symbols.setParentSymbol(pkgSymbol, for: symbol)
            }
            enumSymbol = symbol
        }

        for entry in entries {
            let entryName = interner.intern(entry)
            let entryFQName = fqName + [entryName]
            if symbols.lookup(fqName: entryFQName) != nil {
                continue
            }
            let entrySymbol = symbols.define(
                kind: .field,
                name: entryName,
                fqName: entryFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(enumSymbol, for: entrySymbol)
        }

        return enumSymbol
    }

    private func setSyntheticPlatformEnumEntryTypes(
        enumSymbol: SymbolID,
        enumType: TypeID,
        symbols: SymbolTable
    ) {
        guard let enumInfo = symbols.symbol(enumSymbol) else { return }
        for child in symbols.children(ofFQName: enumInfo.fqName) {
            guard let childInfo = symbols.symbol(child), childInfo.kind == .field else {
                continue
            }
            symbols.setPropertyType(enumType, for: child)
        }
    }

/// Synthetic stubs for java.io.File type.
///
/// Covers:
/// - STDLIB-320: `File(String)` constructor, `readText`, `writeText`, `readLines`
/// - STDLIB-664: `appendText(text: String)` member function
/// - STDLIB-321: `name`, `path` properties; `exists()`, `isFile()`, `isDirectory()` query methods
/// - STDLIB-322: `forEachLine(action:)` member function
/// - STDLIB-323: `delete()`, `mkdirs()`, `listFiles()`, `walk()` filesystem operations
/// - STDLIB-664: `appendText(text: String)` member function
/// - STDLIB-567: `bufferedReader()` returning `BufferedReader` with `readLine()`, `readLines()`, `close()`
///
/// Each stub registers the java.io.File class, its constructor, member properties,
/// and member functions in the symbol table so that name resolution and type
/// checking succeed without requiring a full java.io runtime on the classpath.
    func registerSyntheticFileIOStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let javaIOPkg = ensureJavaIOPackage(symbols: symbols, interner: interner)
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

        // List<File> type for listFiles return
        let listSymbol = resolveListSymbol(symbols: symbols, interner: interner)
        if listSymbol == nil {
            assertionFailure("kotlin.collections.List symbol not found; File IO stubs will use Any as fallback")
        }
        let listOfFileType: TypeID = if let listSym = listSymbol {
            types.make(.classType(ClassType(
                classSymbol: listSym,
                args: [.out(fileType)],
                nullability: .nonNull
            )))
        } else {
            types.anyType
        }
        let nullableListOfFileType = types.makeNullable(listOfFileType)

        // List<String> type for readLines return
        let listOfStringType: TypeID = if let listSym = listSymbol {
            types.make(.classType(ClassType(
                classSymbol: listSym,
                args: [.out(types.stringType)],
                nullability: .nonNull
            )))
        } else {
            types.anyType
        }

        // (String) -> Unit function type for forEachLine action parameter
        let stringToUnitType = types.make(.functionType(FunctionType(
            params: [types.stringType],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))

        // MARK: - File(String) constructor (STDLIB-320)

        registerFileConstructor(
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [("path", types.stringType)],
            externalLinkName: "kk_file_new",
            symbols: symbols,
            interner: interner
        )

        // MARK: - File(parent, child) constructor (STDLIB-IO-087)

        registerFileConstructor(
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [("parent", types.stringType), ("child", types.stringType)],
            externalLinkName: "kk_file_new_parent_child",
            symbols: symbols,
            interner: interner
        )

        // MARK: - File properties (STDLIB-321)

        // KSP-483: `name` is migrated to Kotlin source (Stdlib/kotlin/io/Files.kt,
        // auto-loaded by LoadSourcesPhase) as a pure-logic extension property
        // derived from `path`. Direct compat stub removed.

        // KSP-483: `nameWithoutExtension` is migrated to Kotlin source
        // (Stdlib/kotlin/io/Files.kt). Direct compat stub removed.

        // KSP-483: `path` reads File's internal state, so it stays a direct
        // synthetic member (not migrated). A Kotlin-source extension property
        // named `path` would collide with the `kotlin.io.path` package FQName
        // in this compiler's symbol table, so the other 12 pure-logic members
        // below read `path` through this member instead of a bridge.
        registerFileMemberProperty(
            named: "path",
            externalLinkName: "kk_file_path",
            ownerSymbol: fileSymbol,
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - Additional File properties (STDLIB-IO-087)

        registerFileMemberProperty(
            named: "absolutePath",
            externalLinkName: "kk_file_absolutePath",
            ownerSymbol: fileSymbol,
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberProperty(
            named: "canonicalPath",
            externalLinkName: "kk_file_canonicalPath",
            ownerSymbol: fileSymbol,
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )

        let nullableStringType = types.makeNullable(types.stringType)

        // KSP-483: `parent` and `extension` are migrated to Kotlin source
        // (Stdlib/kotlin/io/Files.kt) as pure-logic extension properties
        // derived from `path`. Direct compat stubs removed.

        // MARK: - File query methods (STDLIB-321)

        registerFileMemberFunction(
            named: "exists",
            externalLinkName: "kk_file_exists",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "isFile",
            externalLinkName: "kk_file_isFile",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "isDirectory",
            externalLinkName: "kk_file_isDirectory",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - Additional File query/operation methods (STDLIB-IO-087)

        registerFileMemberFunction(
            named: "createNewFile",
            externalLinkName: "kk_file_createNewFile",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "length",
            externalLinkName: "kk_file_length",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: types.longType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "lastModified",
            externalLinkName: "kk_file_lastModified",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: types.longType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "canRead",
            externalLinkName: "kk_file_canRead",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "canWrite",
            externalLinkName: "kk_file_canWrite",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "canExecute",
            externalLinkName: "kk_file_canExecute",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        // KSP-483: `resolveSibling` (File/String overloads), `normalize`,
        // `startsWith` (File/String overloads), and `toRelativeString` are
        // migrated to Kotlin source (Stdlib/kotlin/io/Files.kt) as pure-logic
        // functions derived from `path`. Direct compat stubs removed.

        // MARK: - File read/write methods (STDLIB-320)
        // NOTE: Kotlin source exists in Stdlib/kotlin/io/FileIO.kt (MIGRATION-IO-001)

        registerFileMemberFunction(
            named: "readText",
            externalLinkName: "kk_file_readText",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "writeText",
            externalLinkName: "kk_file_writeText",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [("text", types.stringType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - File.appendText() (STDLIB-664)
        // NOTE: Kotlin source exists in Stdlib/kotlin/io/FileIO.kt (MIGRATION-IO-001)

        registerFileMemberFunction(
            named: "appendText",
            externalLinkName: "kk_file_appendText",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [("text", types.stringType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "readLines",
            externalLinkName: "kk_file_readLines",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: listOfStringType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - File.readBytes() (STDLIB-665)
        // NOTE: Kotlin source exists in Stdlib/kotlin/io/FileIO.kt (MIGRATION-IO-001)

        // ByteArray is represented as List<Int> in the runtime
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

        registerFileMemberFunction(
            named: "readBytes",
            externalLinkName: "kk_file_readBytes",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: listOfIntType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - File.appendBytes() (STDLIB-IO-FN-001)
        // NOTE: Kotlin source exists in Stdlib/kotlin/io/FileIO.kt (MIGRATION-IO-001)
        //
        // Kotlin signature: `fun File.appendBytes(array: ByteArray): Unit`
        // ByteArray is represented internally as List<Int>; we register both
        // the ByteArray-typed overload (user-facing) and List<Int> (internal)
        // so that both `byteArrayOf(...)` and `listOf(...)` argument styles resolve.

        let byteArrayFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("ByteArray")]
        let appendBytesByteArrayType: TypeID
        if let byteArraySymbol = symbols.lookup(fqName: byteArrayFQName) {
            appendBytesByteArrayType = types.make(.classType(ClassType(
                classSymbol: byteArraySymbol, args: [], nullability: .nonNull
            )))
        } else {
            appendBytesByteArrayType = listOfIntType
        }

        for arrayParamType in [appendBytesByteArrayType, listOfIntType] {
            registerFileMemberFunction(
                named: "appendBytes",
                externalLinkName: "kk_file_appendBytes",
                ownerSymbol: fileSymbol,
                ownerType: fileType,
                parameters: [("array", arrayParamType)],
                returnType: types.unitType,
                symbols: symbols,
                interner: interner
            )
        }

        // MARK: - File.writeBytes() (MIGRATION-IO-001)
        // NOTE: Kotlin source exists in Stdlib/kotlin/io/FileIO.kt (MIGRATION-IO-001)
        //
        // Kotlin signature: `fun File.writeBytes(array: ByteArray): Unit`

        for arrayParamType in [appendBytesByteArrayType, listOfIntType] {
            registerFileMemberFunction(
                named: "writeBytes",
                externalLinkName: "kk_file_writeBytes",
                ownerSymbol: fileSymbol,
                ownerType: fileType,
                parameters: [("array", arrayParamType)],
                returnType: types.unitType,
                symbols: symbols,
                interner: interner
            )
        }

        // MARK: - MIGRATION-IO-001: Private C-bridge stubs called from BundledKotlinStdlib

        registerFileMemberFunction(
            named: "__kk_file_readText",
            externalLinkName: "kk_file_readText",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "__kk_file_writeText",
            externalLinkName: "kk_file_writeText",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [("text", types.stringType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "__kk_file_appendText",
            externalLinkName: "kk_file_appendText",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [("text", types.stringType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "__kk_file_readBytes",
            externalLinkName: "kk_file_readBytes",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: listOfIntType,
            symbols: symbols,
            interner: interner
        )

        for arrayParamType in [appendBytesByteArrayType, listOfIntType] {
            registerFileMemberFunction(
                named: "__kk_file_appendBytes",
                externalLinkName: "kk_file_appendBytes",
                ownerSymbol: fileSymbol,
                ownerType: fileType,
                parameters: [("array", arrayParamType)],
                returnType: types.unitType,
                symbols: symbols,
                interner: interner
            )
        }

        for arrayParamType in [appendBytesByteArrayType, listOfIntType] {
            registerFileMemberFunction(
                named: "__kk_file_writeBytes",
                externalLinkName: "kk_file_writeBytes",
                ownerSymbol: fileSymbol,
                ownerType: fileType,
                parameters: [("array", arrayParamType)],
                returnType: types.unitType,
                symbols: symbols,
                interner: interner
            )
        }

        // MARK: - File line-by-line operations (STDLIB-322)

        registerFileMemberFunction(
            named: "forEachLine",
            externalLinkName: "kk_file_forEachLine",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [("action", stringToUnitType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - File.forEachBlock(action) and File.forEachBlock(blockSize, action) (STDLIB-IO-FN-016)
        let byteArrayToIntToUnitType = types.make(.functionType(FunctionType(
            params: [listOfIntType, types.intType],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerFileMemberFunction(
            named: "forEachBlock",
            externalLinkName: "kk_file_forEachBlock",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [("action", byteArrayToIntToUnitType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
        registerFileMemberFunction(
            named: "forEachBlock",
            externalLinkName: "kk_file_forEachBlock_blockSize",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [("blockSize", types.intType), ("action", byteArrayToIntToUnitType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - File.useLines {} (STDLIB-566)

        // (List<String>) -> T  (represented as Any for generic return)
        let listOfStringToAnyType = types.make(.functionType(FunctionType(
            params: [listOfStringType],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))

        registerFileMemberFunction(
            named: "useLines",
            externalLinkName: "kk_file_useLines",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [("block", listOfStringToAnyType)],
            returnType: types.anyType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - File filesystem operations (STDLIB-323)

        registerFileMemberFunction(
            named: "delete",
            externalLinkName: "kk_file_delete",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "mkdirs",
            externalLinkName: "kk_file_mkdirs",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "listFiles",
            externalLinkName: "kk_file_listFiles",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: nullableListOfFileType,
            symbols: symbols,
            interner: interner
        )

        // File.walk() returns FileTreeWalk (lazy walk); registered after FileTreeWalk stub
        let fileTreeWalkType = resolveFileTreeWalkType(symbols: symbols, types: types, interner: interner) ?? listOfFileType
        registerFileMemberFunction(
            named: "walk",
            externalLinkName: "kk_file_walk",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: fileTreeWalkType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - Reader / BufferedReader types and File.bufferedReader() (STDLIB-567)

        // `java.io.Reader` is the abstract supertype of `BufferedReader` and is
        // the receiver of `kotlin.io` extension functions such as
        // `Reader.readText()` (STDLIB-IO-FN-033). We register it as a synthetic
        // class so that extension calls on any concrete reader instance (which
        // is currently always a `BufferedReader`) resolve correctly.
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

        // File.bufferedReader() -> BufferedReader
        registerFileMemberFunction(
            named: "bufferedReader",
            externalLinkName: "kk_file_bufferedReader",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: bufferedReaderType,
            symbols: symbols,
            interner: interner
        )

        // BufferedReader.readLine() -> String?
        registerFileMemberFunction(
            named: "readLine",
            externalLinkName: "kk_buffered_reader_readLine",
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
            externalLinkName: "kk_buffered_reader_readLines",
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
            externalLinkName: "kk_buffered_reader_close",
            ownerSymbol: bufferedReaderSymbol,
            ownerType: bufferedReaderType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // Register BufferedReader as a Reader/Closeable subtype.
        // - Reader supertype lets `Reader.readText()` (STDLIB-IO-FN-033) resolve
        //   when invoked on a `BufferedReader` value (the only concrete reader
        //   currently produced by `File.bufferedReader()` etc.).
        // - Closeable supertype (STDLIB-IO-093) lets `.use {}` work:
        //   `file.bufferedReader().use { reader -> ... }`.
        if let closeableSymbol = types.closeableInterfaceSymbol {
            symbols.setDirectSupertypes([closeableSymbol], for: readerSymbol)
            types.setNominalDirectSupertypes([closeableSymbol], for: readerSymbol)
            symbols.setDirectSupertypes([readerSymbol, closeableSymbol], for: bufferedReaderSymbol)
            types.setNominalDirectSupertypes([readerSymbol, closeableSymbol], for: bufferedReaderSymbol)
        } else {
            symbols.setDirectSupertypes([readerSymbol], for: bufferedReaderSymbol)
            types.setNominalDirectSupertypes([readerSymbol], for: bufferedReaderSymbol)
        }
        // MARK: - BufferedWriter type and File.bufferedWriter() (STDLIB-IO-091)

        // BufferedReader.read() -> Int  (STDLIB-IO-091)
        registerFileMemberFunction(
            named: "read",
            externalLinkName: "kk_buffered_reader_read",
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
            externalLinkName: "kk_buffered_reader_ready",
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
            externalLinkName: "kk_buffered_reader_iterator",
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
        // the function returns. We model the lambda parameter as `List<String>` for
        // parity with the existing `File.useLines` stub — both flow through the same
        // runtime helper shape (lines materialised eagerly into a `RuntimeListBox`).
        let listOfStringToAnyTypeBR = types.make(.functionType(FunctionType(
            params: [listOfStringType],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerFileMemberFunction(
            named: "useLines",
            externalLinkName: "kk_buffered_reader_useLines",
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
        // and returns `Unit`. We model it as a member of `java.io.BufferedReader` so
        // user code can call `file.bufferedReader().forEachLine { line -> ... }`.
        // Unlike `useLines`, the reader is NOT automatically closed after iteration.
        registerFileMemberFunction(
            named: "forEachLine",
            externalLinkName: "kk_buffered_reader_forEachLine",
            ownerSymbol: bufferedReaderSymbol,
            ownerType: bufferedReaderType,
            parameters: [("action", stringToUnitType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - BufferedWriter type and File.bufferedWriter() (STDLIB-IO-091/093)

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
        if let closeableSymbol = types.closeableInterfaceSymbol {
            symbols.setDirectSupertypes([closeableSymbol], for: writerSymbol)
            types.setNominalDirectSupertypes([closeableSymbol], for: writerSymbol)
            symbols.setDirectSupertypes([writerSymbol, closeableSymbol], for: bufferedWriterSymbol)
            types.setNominalDirectSupertypes([writerSymbol, closeableSymbol], for: bufferedWriterSymbol)
        } else {
            symbols.setDirectSupertypes([writerSymbol], for: bufferedWriterSymbol)
            types.setNominalDirectSupertypes([writerSymbol], for: bufferedWriterSymbol)
        }

        // File.bufferedWriter() -> BufferedWriter
        registerFileMemberFunction(
            named: "bufferedWriter",
            externalLinkName: "kk_file_bufferedWriter",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: bufferedWriterType,
            symbols: symbols,
            interner: interner
        )

        // BufferedWriter.write(text: String) -> Unit
        registerFileMemberFunction(
            named: "write",
            externalLinkName: "kk_buffered_writer_write",
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
            externalLinkName: "kk_buffered_writer_new_line",
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
            externalLinkName: "kk_buffered_writer_flush",
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
            externalLinkName: "kk_buffered_writer_close",
            ownerSymbol: bufferedWriterSymbol,
            ownerType: bufferedWriterType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - InputStream / OutputStream (STDLIB-IO-092)

        // MARK: - Resource access (STDLIB-IO-093)

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
        if let closeableSymbol = types.closeableInterfaceSymbol {
            symbols.setDirectSupertypes([closeableSymbol], for: inputStreamSymbol)
            types.setNominalDirectSupertypes([closeableSymbol], for: inputStreamSymbol)
            symbols.setDirectSupertypes([closeableSymbol], for: outputStreamSymbol)
            types.setNominalDirectSupertypes([closeableSymbol], for: outputStreamSymbol)
        }
        symbols.setDirectSupertypes([inputStreamSymbol], for: sequenceInputStreamSymbol)
        types.setNominalDirectSupertypes([inputStreamSymbol], for: sequenceInputStreamSymbol)
        symbols.setDirectSupertypes([inputStreamSymbol], for: byteArrayInputStreamSymbol)
        types.setNominalDirectSupertypes([inputStreamSymbol], for: byteArrayInputStreamSymbol)
        let nullableInputStreamType = types.makeNullable(inputStreamType)
        let listIntType: TypeID = if let listSym = listSymbol {
            types.make(.classType(ClassType(
                classSymbol: listSym,
                args: [.out(types.intType)],
                nullability: .nonNull
            )))
        } else {
            types.anyType
        }

        registerFileMemberFunction(
            named: "inputStream",
            externalLinkName: "kk_file_inputStream",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: inputStreamType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "outputStream",
            externalLinkName: "kk_file_outputStream",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: outputStreamType,
            symbols: symbols,
            interner: interner
        )

        registerFileConstructor(
            ownerSymbol: sequenceInputStreamSymbol,
            ownerType: sequenceInputStreamType,
            parameters: [("first", inputStreamType), ("second", inputStreamType)],
            externalLinkName: "kk_sequence_input_stream_new",
            symbols: symbols,
            interner: interner
        )

        registerFileConstructor(
            ownerSymbol: byteArrayInputStreamSymbol,
            ownerType: byteArrayInputStreamType,
            parameters: [("buffer", listIntType)],
            externalLinkName: "kk_bytearrayinputstream_new",
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
                externalLinkName: "kk_string_byteInputStream_flat",
                receiverType: types.stringType,
                parameters: [],
                returnType: byteArrayInputStreamType,
                packageFQName: kotlinIOPkg,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticStringExtensionFunction(
                named: "byteInputStream",
                externalLinkName: "kk_string_byteInputStream_charset_flat",
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
            externalLinkName: "kk_input_stream_read",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [],
            returnType: intType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "available",
            externalLinkName: "kk_input_stream_available",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [],
            returnType: intType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "skip",
            externalLinkName: "kk_input_stream_skip",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [("count", intType)],
            returnType: intType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "read",
            externalLinkName: "kk_input_stream_read_bytes",
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
        // allocated ByteArray.  We model ByteArray as List<Int>, matching the
        // representation used by File.readBytes() / Path.readBytes().
        //
        // Note: this extension does NOT close the receiver — callers typically
        // wrap the call in `.use { it.readBytes() }`.  Sema only needs to
        // resolve the call shape; the runtime drains the stream.
        registerFileMemberFunction(
            named: "readBytes",
            externalLinkName: "kk_input_stream_readAllBytes",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [],
            returnType: listOfIntType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "mark",
            externalLinkName: "kk_input_stream_mark",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [("readLimit", intType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "reset",
            externalLinkName: "kk_input_stream_reset",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "markSupported",
            externalLinkName: "kk_input_stream_mark_supported",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "close",
            externalLinkName: "kk_input_stream_close",
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
            externalLinkName: "kk_input_stream_readAllBytes",
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
            externalLinkName: "kk_input_stream_buffered_default",
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
            externalLinkName: "kk_input_stream_buffered",
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
            externalLinkName: "kk_input_stream_copyTo",
            valueParameterHasDefaultValues: [false, true],
            valueParameterIsVararg: [false, false],
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "read",
            externalLinkName: "kk_sequence_input_stream_read",
            ownerSymbol: sequenceInputStreamSymbol,
            ownerType: sequenceInputStreamType,
            parameters: [],
            returnType: intType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "available",
            externalLinkName: "kk_sequence_input_stream_available",
            ownerSymbol: sequenceInputStreamSymbol,
            ownerType: sequenceInputStreamType,
            parameters: [],
            returnType: intType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "close",
            externalLinkName: "kk_sequence_input_stream_close",
            ownerSymbol: sequenceInputStreamSymbol,
            ownerType: sequenceInputStreamType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "write",
            externalLinkName: "kk_output_stream_write_byte",
            ownerSymbol: outputStreamSymbol,
            ownerType: outputStreamType,
            parameters: [("value", intType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "write",
            externalLinkName: "kk_output_stream_write_bytes",
            ownerSymbol: outputStreamSymbol,
            ownerType: outputStreamType,
            parameters: [("buffer", listOfIntType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "flush",
            externalLinkName: "kk_output_stream_flush",
            ownerSymbol: outputStreamSymbol,
            ownerType: outputStreamType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "close",
            externalLinkName: "kk_output_stream_close",
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
            externalLinkName: "kk_output_stream_buffered",
            ownerSymbol: outputStreamSymbol,
            ownerType: outputStreamType,
            parameters: [],
            returnType: outputStreamType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "buffered",
            externalLinkName: "kk_output_stream_buffered_sized",
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
            externalLinkName: "kk_classloader_getResource",
            ownerSymbol: classLoaderSymbol,
            ownerType: classLoaderType,
            parameters: [("name", types.stringType)],
            returnType: nullableStringType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "getResourceAsStream",
            externalLinkName: "kk_classloader_getResourceAsStream",
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
            externalLinkName: "kk_classloader_getSystemClassLoader",
            symbols: symbols,
            interner: interner
        )

        registerTopLevelResourceFunction(
            packageFQName: kotlinIOPkg,
            name: "resourceExists",
            parameters: [("name", types.stringType)],
            returnType: types.booleanType,
            externalLinkName: "kk_resource_exists",
            symbols: symbols,
            interner: interner
        )
        registerTopLevelResourceFunction(
            packageFQName: kotlinIOPkg,
            name: "readResourceAsText",
            parameters: [("name", types.stringType)],
            returnType: types.stringType,
            externalLinkName: "kk_readResourceAsText",
            symbols: symbols,
            interner: interner
        )

        // KSP-483: `invariantSeparatorsPath` is migrated to Kotlin source
        // (Stdlib/kotlin/io/Files.kt) as a pure-logic extension property
        // derived from `path`. Direct compat stub removed.

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
            externalLinkName: "kk_output_stream_bufferedWriter",
            valueParameterHasDefaultValues: [true],
            valueParameterIsVararg: [false],
            symbols: symbols,
            interner: interner
        )

        // MARK: - PrintWriter type and File.printWriter() (STDLIB-IO-FN-027)

        let printWriterSymbol = ensureClassSymbol(
            named: "PrintWriter",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaIOPkgSymbol {
            symbols.setParentSymbol(javaIOPkgSymbol, for: printWriterSymbol)
        }
        let printWriterType = types.make(.classType(ClassType(
            classSymbol: printWriterSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(printWriterType, for: printWriterSymbol)

        // Register PrintWriter as a Closeable subtype so that .use {} works
        if let closeableSymbol = types.closeableInterfaceSymbol {
            symbols.setDirectSupertypes([closeableSymbol], for: printWriterSymbol)
            types.setNominalDirectSupertypes([closeableSymbol], for: printWriterSymbol)
        }

        // File.printWriter() -> PrintWriter
        registerFileMemberFunction(
            named: "printWriter",
            externalLinkName: "kk_file_printWriter",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: printWriterType,
            symbols: symbols,
            interner: interner
        )

        // PrintWriter.print(text: String) -> Unit
        registerFileMemberFunction(
            named: "print",
            externalLinkName: "kk_print_writer_print",
            ownerSymbol: printWriterSymbol,
            ownerType: printWriterType,
            parameters: [("text", types.stringType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // PrintWriter.println(text: String) -> Unit
        registerFileMemberFunction(
            named: "println",
            externalLinkName: "kk_print_writer_println",
            ownerSymbol: printWriterSymbol,
            ownerType: printWriterType,
            parameters: [("text", types.stringType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // PrintWriter.println() -> Unit  (no-arg overload)
        registerFileMemberFunction(
            named: "println",
            externalLinkName: "kk_print_writer_println_no_arg",
            ownerSymbol: printWriterSymbol,
            ownerType: printWriterType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // PrintWriter.write(text: String) -> Unit
        registerFileMemberFunction(
            named: "write",
            externalLinkName: "kk_print_writer_write",
            ownerSymbol: printWriterSymbol,
            ownerType: printWriterType,
            parameters: [("text", types.stringType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // PrintWriter.flush() -> Unit
        registerFileMemberFunction(
            named: "flush",
            externalLinkName: "kk_print_writer_flush",
            ownerSymbol: printWriterSymbol,
            ownerType: printWriterType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // PrintWriter.close() -> Unit
        registerFileMemberFunction(
            named: "close",
            externalLinkName: "kk_print_writer_close",
            ownerSymbol: printWriterSymbol,
            ownerType: printWriterType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - File.copyTo(target, overwrite, bufferSize) (STDLIB-IO-FN-015)
        //
        // Kotlin signature: `public fun File.copyTo(
        //     target: File,
        //     overwrite: Boolean = false,
        //     bufferSize: Int = DEFAULT_BUFFER_SIZE
        // ): File` declared in the `kotlin.io` package.
        registerKotlinIOExtensionFunction(
            named: "copyTo",
            packageFQName: kotlinIOPkg,
            receiverType: fileType,
            parameters: [
                ("target", fileType),
                ("overwrite", types.booleanType),
                ("bufferSize", types.intType),
            ],
            returnType: fileType,
            externalLinkName: "kk_file_copyTo",
            valueParameterHasDefaultValues: [false, true, true],
            valueParameterIsVararg: [false, false, false],
            symbols: symbols,
            interner: interner
        )

        // MARK: - Reader.readText() (STDLIB-IO-FN-033)
        //
        // Kotlin signature: `public fun Reader.readText(): String` declared in
        // the `kotlin.io` package. Reads the entire remaining content of the
        // receiver into a single `String`. Mirrors the stdlib semantics of
        // exhausting the reader; the runtime helper `kk_reader_readText`
        // delegates to `RuntimeBufferedReaderBox.readText()`.
        registerKotlinIOExtensionFunction(
            named: "readText",
            packageFQName: kotlinIOPkg,
            receiverType: readerType,
            parameters: [],
            returnType: types.stringType,
            externalLinkName: "kk_reader_readText",
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
            externalLinkName: "kk_reader_copyTo",
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
            externalLinkName: "kk_reader_copyTo_default",
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
                externalLinkName: "kk_bytearray_inputStream",
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
                externalLinkName: "kk_bytearray_inputStream_range",
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
            externalLinkName: "kk_writer_buffered_default",
            symbols: symbols,
            interner: interner
        )
        registerFilePackageExtensionFunction(
            named: "buffered",
            packageFQName: kotlinIOPkg,
            receiverType: writerType,
            parameters: [("bufferSize", intType)],
            returnType: bufferedWriterType,
            externalLinkName: "kk_writer_buffered",
            symbols: symbols,
            interner: interner
        )

        // STDLIB-IO-FN-007: kotlin.io.InputStream.bufferedReader(charset)
        // Top-level extension function on java.io.InputStream returning BufferedReader.
        // Signature: fun InputStream.bufferedReader(charset: Charset = Charsets.UTF_8): BufferedReader
        // charsetFQName is already defined above (line 1042) as kotlinTextPkg + ["Charset"]
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
            externalLinkName: "kk_input_stream_bufferedReader",
            valueParameterHasDefaultValues: [true],
            symbols: symbols,
            interner: interner
        )

        // KSP-483: `isRooted` is migrated to Kotlin source (Stdlib/kotlin/io/Files.kt)
        // as a pure-logic extension property derived from `path`. Direct compat
        // stub removed.

        // MARK: - File.copyRecursively(target, overwrite) (STDLIB-IO-FN-012)
        //
        // Kotlin signature:
        //   public fun File.copyRecursively(
        //       target: File,
        //       overwrite: Boolean = false,
        //       onError: (File, IOException) -> OnErrorAction = { _, exception -> throw exception }
        //   ): Boolean
        //
        // This stub covers the primary (target, overwrite) overload.  The `onError`
        // lambda parameter is not modelled here; callers relying on the default
        // error handler (re-throw) are fully supported by the runtime implementation.
        registerKotlinIOExtensionFunction(
            named: "copyRecursively",
            packageFQName: kotlinIOPkg,
            receiverType: fileType,
            parameters: [
                ("target", fileType),
                ("overwrite", types.booleanType),
            ],
            returnType: types.booleanType,
            externalLinkName: "kk_file_copyRecursively",
            valueParameterHasDefaultValues: [false, true],
            valueParameterIsVararg: [false, false],
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

    /// Register a top-level Kotlin extension function in `packageFQName` with the
    /// provided receiver. Mirrors `registerPathExtensionFunction` from
    /// `HeaderHelpers+SyntheticPathStubs.swift`, scoped to FileIO so that
    /// extensions on `InputStream` / `OutputStream` can live next to the rest
    /// of the FileIO stubs without leaking helpers between extension files.
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
