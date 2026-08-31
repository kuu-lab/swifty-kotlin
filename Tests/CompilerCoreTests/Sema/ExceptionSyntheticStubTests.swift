#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ExceptionSyntheticStubTests {
    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        if let cached = Self._sharedSema { return cached }
        let pair = try makeSema()
        Self._sharedSema = pair
        return pair
    }

    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    private static nonisolated(unsafe) var _sharedSourceSema: (SemaModule, StringInterner)?

    private static let resolveSources: [String] = [
        """
        fun noArg(): RuntimeException = NoWhenBranchMatchedException()
        fun message(message: String?): RuntimeException = NoWhenBranchMatchedException(message)
        fun messageCause(message: String?, cause: Throwable?): RuntimeException = NoWhenBranchMatchedException(message, cause)
        fun cause(cause: Throwable?): RuntimeException = NoWhenBranchMatchedException(cause)
        """,
        """
        import kotlin.text.CharacterCodingException

        fun noArg(): Exception = CharacterCodingException()
        fun message(message: String?): Exception = CharacterCodingException(message)
        fun catchCharacterCoding(): String =
            try { throw CharacterCodingException("bad input") }
            catch (e: CharacterCodingException) { e.message ?: "caught" }
        """,
        """
        fun noArg(): RuntimeException = ConcurrentModificationException()
        fun message(message: String?): RuntimeException = ConcurrentModificationException(message)
        fun messageCause(message: String?, cause: Throwable?): RuntimeException = ConcurrentModificationException(message, cause)
        fun cause(cause: Throwable?): RuntimeException = ConcurrentModificationException(cause)
        """,
        """
        fun noArg(): IndexOutOfBoundsException = ArrayIndexOutOfBoundsException()
        fun message(message: String?): IndexOutOfBoundsException = ArrayIndexOutOfBoundsException(message)
        """,
        """
        fun noArg(): RuntimeException = NegativeArraySizeException()
        fun message(message: String?): RuntimeException = NegativeArraySizeException(message)
        """,
    ]

    private func sharedSourceSema() throws -> (SemaModule, StringInterner) {
        if let cached = Self._sharedSourceSema { return cached }
        let pair = try makeSema(sources: Self.resolveSources)
        Self._sharedSourceSema = pair
        return pair
    }

    private func makeSema(sources: [String]) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        let packaged = sources.enumerated().map { index, source in
            "package sample\(index)\n\(source)"
        }
        try withTemporaryFiles(contents: packaged) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testNoWhenBranchMatchedExceptionSurfaceIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let noWhenFQName = ["kotlin", "NoWhenBranchMatchedException"].map { interner.intern($0) }
        let noWhenSymbol = try #require(sema.symbols.lookup(fqName: noWhenFQName))
        #expect(sema.symbols.symbol(noWhenSymbol)?.kind == .class)

        let runtimeExceptionFQName = ["kotlin", "RuntimeException"].map { interner.intern($0) }
        let runtimeExceptionSymbol = try #require(sema.symbols.lookup(fqName: runtimeExceptionFQName))
        let supertypesContains = sema.symbols.directSupertypes(for: noWhenSymbol).contains(runtimeExceptionSymbol)
        #expect(supertypesContains)

        let noWhenType = sema.types.make(.classType(ClassType(
            classSymbol: noWhenSymbol,
            args: [],
            nullability: .nonNull
        )))
        #expect(!(sema.symbols.symbol(noWhenSymbol)?.flags.contains(.synthetic) ?? true))

        let throwableFQName = ["kotlin", "Throwable"].map { interner.intern($0) }
        let throwableSymbol = try #require(sema.symbols.lookup(fqName: throwableFQName))
        let nullableThrowableType = sema.types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nullable
        )))
        let nullableStringType = sema.types.makeNullable(sema.types.stringType)

        let constructorFQName = noWhenFQName + [interner.intern("<init>")]
        let constructors = sema.symbols.lookupAll(fqName: constructorFQName).filter {
            sema.symbols.symbol($0)?.kind == .constructor
        }
        let expected: [([TypeID], String)] = [
            ([], "__kk_no_when_branch_matched_exception_new"),
            ([nullableStringType], "__kk_no_when_branch_matched_exception_new_message"),
            ([nullableStringType, nullableThrowableType], "__kk_no_when_branch_matched_exception_new_message_cause"),
            ([nullableThrowableType], "__kk_no_when_branch_matched_exception_new_cause"),
        ]
        for (parameterTypes, externalLinkName) in expected {
            let constructor = try #require(constructors.first {
                sema.symbols.functionSignature(for: $0)?.parameterTypes == parameterTypes
            })
            #expect(sema.symbols.functionSignature(for: constructor)?.returnType == noWhenType)
            #expect(sema.symbols.externalLinkName(for: constructor) == externalLinkName)
        }
    }

    @Test func testNoWhenBranchMatchedExceptionResolvesInSource() throws {
        _ = try sharedSourceSema()
    }

    @Test func testCharacterCodingExceptionSurfaceIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let exceptionFQName = ["kotlin", "text", "CharacterCodingException"].map { interner.intern($0) }
        let exceptionSymbol = try #require(sema.symbols.lookup(fqName: exceptionFQName))
        #expect(sema.symbols.symbol(exceptionSymbol)?.kind == .class)

        let rootExceptionFQName = ["kotlin", "Exception"].map { interner.intern($0) }
        let rootExceptionSymbol = try #require(sema.symbols.lookup(fqName: rootExceptionFQName))
        let supertypesContains = sema.symbols.directSupertypes(for: exceptionSymbol).contains(rootExceptionSymbol)
        #expect(supertypesContains)

        let exceptionType = sema.types.make(.classType(ClassType(
            classSymbol: exceptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        #expect(!(sema.symbols.symbol(exceptionSymbol)?.flags.contains(.synthetic) ?? true))

        let nullableStringType = sema.types.makeNullable(sema.types.stringType)
        let constructorFQName = exceptionFQName + [interner.intern("<init>")]
        let constructors = sema.symbols.lookupAll(fqName: constructorFQName).filter {
            sema.symbols.symbol($0)?.kind == .constructor
        }
        let expected: [([TypeID], String)] = [
            ([], "__kk_character_coding_exception_new"),
            ([nullableStringType], "__kk_character_coding_exception_new_message"),
        ]
        for (parameterTypes, externalLinkName) in expected {
            let constructor = try #require(constructors.first {
                sema.symbols.functionSignature(for: $0)?.parameterTypes == parameterTypes
            })
            #expect(sema.symbols.functionSignature(for: constructor)?.returnType == exceptionType)
            #expect(sema.symbols.externalLinkName(for: constructor) == externalLinkName)
        }
    }

    @Test func testCharacterCodingExceptionResolvesInSource() throws {
        _ = try sharedSourceSema()
    }

    @Test func testConcurrentModificationExceptionSurfaceIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let exceptionFQName = ["kotlin", "ConcurrentModificationException"].map { interner.intern($0) }
        let exceptionSymbol = try #require(sema.symbols.lookup(fqName: exceptionFQName))
        #expect(sema.symbols.symbol(exceptionSymbol)?.kind == .class)

        let runtimeExceptionFQName = ["kotlin", "RuntimeException"].map { interner.intern($0) }
        let runtimeExceptionSymbol = try #require(sema.symbols.lookup(fqName: runtimeExceptionFQName))
        let supertypesContains = sema.symbols.directSupertypes(for: exceptionSymbol).contains(runtimeExceptionSymbol)
        #expect(supertypesContains)

        let exceptionType = sema.types.make(.classType(ClassType(
            classSymbol: exceptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        #expect(!(sema.symbols.symbol(exceptionSymbol)?.flags.contains(.synthetic) ?? true))

        let throwableFQName = ["kotlin", "Throwable"].map { interner.intern($0) }
        let throwableSymbol = try #require(sema.symbols.lookup(fqName: throwableFQName))
        let nullableThrowableType = sema.types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nullable
        )))
        let nullableStringType = sema.types.makeNullable(sema.types.stringType)

        let constructorFQName = exceptionFQName + [interner.intern("<init>")]
        let constructors = sema.symbols.lookupAll(fqName: constructorFQName).filter {
            sema.symbols.symbol($0)?.kind == .constructor
        }
        let expected: [([TypeID], String)] = [
            ([], "__kk_concurrent_modification_exception_new"),
            ([nullableStringType], "__kk_concurrent_modification_exception_new_message"),
            ([nullableStringType, nullableThrowableType], "__kk_concurrent_modification_exception_new_message_cause"),
            ([nullableThrowableType], "__kk_concurrent_modification_exception_new_cause"),
        ]
        for (parameterTypes, externalLinkName) in expected {
            let constructor = try #require(constructors.first {
                sema.symbols.functionSignature(for: $0)?.parameterTypes == parameterTypes
            })
            #expect(sema.symbols.functionSignature(for: constructor)?.returnType == exceptionType)
            #expect(sema.symbols.externalLinkName(for: constructor) == externalLinkName)
        }
    }

    @Test func testConcurrentModificationExceptionResolvesInSource() throws {
        _ = try sharedSourceSema()
    }

    @Test func testArrayIndexOutOfBoundsExceptionSurfaceIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let exceptionFQName = ["kotlin", "ArrayIndexOutOfBoundsException"].map { interner.intern($0) }
        let exceptionSymbol = try #require(sema.symbols.lookup(fqName: exceptionFQName))
        #expect(sema.symbols.symbol(exceptionSymbol)?.kind == .class)

        let indexOutOfBoundsFQName = ["kotlin", "IndexOutOfBoundsException"].map { interner.intern($0) }
        let indexOutOfBoundsSymbol = try #require(sema.symbols.lookup(fqName: indexOutOfBoundsFQName))
        let supertypesContains = sema.symbols.directSupertypes(for: exceptionSymbol).contains(indexOutOfBoundsSymbol)
        #expect(supertypesContains)

        let exceptionType = sema.types.make(.classType(ClassType(
            classSymbol: exceptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        #expect(!(sema.symbols.symbol(exceptionSymbol)?.flags.contains(.synthetic) ?? true))

        let nullableStringType = sema.types.makeNullable(sema.types.stringType)
        let constructorFQName = exceptionFQName + [interner.intern("<init>")]
        let constructors = sema.symbols.lookupAll(fqName: constructorFQName).filter {
            sema.symbols.symbol($0)?.kind == .constructor
        }
        let expected: [([TypeID], String)] = [
            ([], "__kk_array_index_out_of_bounds_exception_new"),
            ([nullableStringType], "__kk_array_index_out_of_bounds_exception_new_message"),
        ]
        for (parameterTypes, externalLinkName) in expected {
            let constructor = try #require(constructors.first {
                sema.symbols.functionSignature(for: $0)?.parameterTypes == parameterTypes
            })
            #expect(sema.symbols.functionSignature(for: constructor)?.returnType == exceptionType)
            #expect(sema.symbols.externalLinkName(for: constructor) == externalLinkName)
        }
    }

    @Test func testArrayIndexOutOfBoundsExceptionResolvesInSource() throws {
        _ = try sharedSourceSema()
    }

    @Test func testNegativeArraySizeExceptionSurfaceIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let exceptionFQName = ["kotlin", "NegativeArraySizeException"].map { interner.intern($0) }
        let exceptionSymbol = try #require(sema.symbols.lookup(fqName: exceptionFQName))
        #expect(sema.symbols.symbol(exceptionSymbol)?.kind == .class)

        let runtimeExceptionFQName = ["kotlin", "RuntimeException"].map { interner.intern($0) }
        let runtimeExceptionSymbol = try #require(sema.symbols.lookup(fqName: runtimeExceptionFQName))
        let supertypesContains = sema.symbols.directSupertypes(for: exceptionSymbol).contains(runtimeExceptionSymbol)
        #expect(supertypesContains)

        let exceptionType = sema.types.make(.classType(ClassType(
            classSymbol: exceptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        #expect(sema.symbols.propertyType(for: exceptionSymbol) == exceptionType)

        let nullableStringType = sema.types.makeNullable(sema.types.stringType)
        let constructorFQName = exceptionFQName + [interner.intern("<init>")]
        let constructors = sema.symbols.lookupAll(fqName: constructorFQName).filter {
            sema.symbols.symbol($0)?.kind == .constructor
        }
        let expected: [([TypeID], String)] = [
            ([], "kk_negative_array_size_exception_new"),
            ([nullableStringType], "kk_negative_array_size_exception_new_message"),
        ]
        for (parameterTypes, externalLinkName) in expected {
            let constructor = try #require(constructors.first {
                sema.symbols.functionSignature(for: $0)?.parameterTypes == parameterTypes
            })
            #expect(sema.symbols.functionSignature(for: constructor)?.returnType == exceptionType)
            #expect(sema.symbols.externalLinkName(for: constructor) == externalLinkName)
        }
    }

    @Test func testNegativeArraySizeExceptionResolvesInSource() throws {
        _ = try sharedSourceSema()
    }

    @Test func testCommonExceptionHierarchyIsSourceBacked() throws {
        let (sema, interner) = try sharedSema()
        let cases: [(name: String, parent: String, arities: [Int], links: [String])] = [
            ("Error", "Throwable", [0, 1, 2, 1], [
                "__kk_error_new", "__kk_error_new_message", "__kk_error_new_message_cause", "__kk_error_new_cause",
            ]),
            ("Exception", "Throwable", [0, 1, 2, 1], [
                "__kk_exception_new", "__kk_exception_new_message", "__kk_exception_new_message_cause", "__kk_exception_new_cause",
            ]),
            ("RuntimeException", "Exception", [0, 1, 2, 1], []),
            ("IllegalArgumentException", "RuntimeException", [0, 1, 2, 1], [
                "__kk_illegal_argument_exception_new", "__kk_illegal_argument_exception_new_message", "__kk_illegal_argument_exception_new_message_cause", "__kk_illegal_argument_exception_new_cause",
            ]),
            ("IllegalStateException", "RuntimeException", [0, 1, 2, 1], [
                "__kk_illegal_state_exception_new", "__kk_illegal_state_exception_new_message", "__kk_illegal_state_exception_new_message_cause", "__kk_illegal_state_exception_new_cause",
            ]),
            ("IndexOutOfBoundsException", "RuntimeException", [0, 1], []),
            ("ArrayIndexOutOfBoundsException", "IndexOutOfBoundsException", [0, 1], [
                "__kk_array_index_out_of_bounds_exception_new", "__kk_array_index_out_of_bounds_exception_new_message",
            ]),
            ("ConcurrentModificationException", "RuntimeException", [0, 1, 2, 1], [
                "__kk_concurrent_modification_exception_new", "__kk_concurrent_modification_exception_new_message", "__kk_concurrent_modification_exception_new_message_cause", "__kk_concurrent_modification_exception_new_cause",
            ]),
            ("UnsupportedOperationException", "RuntimeException", [0, 1, 2, 1], [
                "__kk_unsupported_operation_exception_new", "__kk_unsupported_operation_exception_new_message", "__kk_unsupported_operation_exception_new_message_cause", "__kk_unsupported_operation_exception_new_cause",
            ]),
            ("NumberFormatException", "IllegalArgumentException", [0, 1], []),
            ("NullPointerException", "RuntimeException", [0, 1], []),
            ("ClassCastException", "RuntimeException", [0, 1], [
                "__kk_class_cast_exception_new", "__kk_class_cast_exception_new_message",
            ]),
            ("AssertionError", "Error", [0, 1, 2], [
                "__kk_assertion_error_new", "__kk_assertion_error_new_message", "__kk_assertion_error_new_message_cause",
            ]),
            ("NoSuchElementException", "RuntimeException", [0, 1], [
                "__kk_no_such_element_exception_new", "__kk_no_such_element_exception_new_message",
            ]),
            ("ArithmeticException", "RuntimeException", [0, 1], [
                "__kk_arithmetic_exception_new", "__kk_arithmetic_exception_new_message",
            ]),
            ("NoWhenBranchMatchedException", "RuntimeException", [0, 1, 2, 1], [
                "__kk_no_when_branch_matched_exception_new", "__kk_no_when_branch_matched_exception_new_message", "__kk_no_when_branch_matched_exception_new_message_cause", "__kk_no_when_branch_matched_exception_new_cause",
            ]),
            ("UninitializedPropertyAccessException", "RuntimeException", [0, 1, 2, 1], [
                "__kk_uninitialized_property_access_exception_new", "__kk_uninitialized_property_access_exception_new_message", "__kk_uninitialized_property_access_exception_new_message_cause", "__kk_uninitialized_property_access_exception_new_cause",
            ]),
        ]

        for entry in cases {
            let classFQName = ["kotlin", entry.name].map { interner.intern($0) }
            let classSymbol = try #require(sema.symbols.lookup(fqName: classFQName))
            let classInfo = try #require(sema.symbols.symbol(classSymbol))
            #expect(classInfo.kind == .class)
            #expect(!classInfo.flags.contains(.synthetic), "(entry.name) must be source-backed")

            let parentFQName = ["kotlin", entry.parent].map { interner.intern($0) }
            let parentSymbol = try #require(sema.symbols.lookup(fqName: parentFQName))
            #expect(sema.symbols.directSupertypes(for: classSymbol).contains(parentSymbol))

            let constructorFQName = classFQName + [interner.intern("<init>")]
            let constructors = sema.symbols.lookupAll(fqName: constructorFQName).filter {
                sema.symbols.symbol($0)?.kind == .constructor
            }
            #expect(constructors.count == entry.arities.count)
            let arities = constructors.compactMap { sema.symbols.functionSignature(for: $0)?.parameterTypes.count }.sorted()
            #expect(arities == entry.arities.sorted())
            let links = constructors.compactMap { sema.symbols.externalLinkName(for: $0) }
            #expect(Set(links) == Set(entry.links))
            for constructor in constructors {
                #expect(!(sema.symbols.symbol(constructor)?.flags.contains(.synthetic) ?? true))
            }
        }
    }
}
#endif
