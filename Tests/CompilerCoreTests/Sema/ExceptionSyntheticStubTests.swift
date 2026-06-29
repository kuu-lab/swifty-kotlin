#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ExceptionSyntheticStubTests {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testNoWhenBranchMatchedExceptionSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

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
        #expect(sema.symbols.propertyType(for: noWhenSymbol) == noWhenType)

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
            ([], "kk_no_when_branch_matched_exception_new"),
            ([nullableStringType], "kk_no_when_branch_matched_exception_new_message"),
            ([nullableStringType, nullableThrowableType], "kk_no_when_branch_matched_exception_new_message_cause"),
            ([nullableThrowableType], "kk_no_when_branch_matched_exception_new_cause"),
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
        _ = try makeSema(source: """
        fun noArg(): RuntimeException = NoWhenBranchMatchedException()
        fun message(message: String?): RuntimeException = NoWhenBranchMatchedException(message)
        fun messageCause(message: String?, cause: Throwable?): RuntimeException = NoWhenBranchMatchedException(message, cause)
        fun cause(cause: Throwable?): RuntimeException = NoWhenBranchMatchedException(cause)
        """)
    }

    @Test func testCharacterCodingExceptionSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

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
        #expect(sema.symbols.propertyType(for: exceptionSymbol) == exceptionType)

        let nullableStringType = sema.types.makeNullable(sema.types.stringType)
        let constructorFQName = exceptionFQName + [interner.intern("<init>")]
        let constructors = sema.symbols.lookupAll(fqName: constructorFQName).filter {
            sema.symbols.symbol($0)?.kind == .constructor
        }
        let expected: [([TypeID], String)] = [
            ([], "kk_throwable_new"),
            ([nullableStringType], "kk_throwable_new"),
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
        _ = try makeSema(source: """
        import kotlin.text.CharacterCodingException

        fun noArg(): Exception = CharacterCodingException()
        fun message(message: String?): Exception = CharacterCodingException(message)
        fun catchCharacterCoding(): String =
            try { throw CharacterCodingException("bad input") }
            catch (e: CharacterCodingException) { e.message ?: "caught" }
        """)
    }

    @Test func testNoSuchFileExceptionSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let exceptionFQName = ["kotlin", "io", "NoSuchFileException"].map { interner.intern($0) }
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
        #expect(sema.symbols.propertyType(for: exceptionSymbol) == exceptionType)

        let constructorFQName = exceptionFQName + [interner.intern("<init>")]
        let constructors = sema.symbols.lookupAll(fqName: constructorFQName).filter {
            sema.symbols.symbol($0)?.kind == .constructor
        }
        let expected: [([TypeID], String)] = [
            ([], "kk_throwable_new"),
            ([sema.types.stringType], "kk_throwable_new"),
        ]
        for (parameterTypes, externalLinkName) in expected {
            let constructor = try #require(constructors.first {
                sema.symbols.functionSignature(for: $0)?.parameterTypes == parameterTypes
            })
            #expect(sema.symbols.functionSignature(for: constructor)?.returnType == exceptionType)
            #expect(sema.symbols.externalLinkName(for: constructor) == externalLinkName)
        }
    }

    @Test func testNoSuchFileExceptionResolvesInSource() throws {
        _ = try makeSema(source: """
        import kotlin.io.NoSuchFileException

        fun noArg(): Exception = NoSuchFileException()
        fun file(path: String): Exception = NoSuchFileException(path)
        fun catchNoSuchFile(): String =
            try { throw NoSuchFileException("missing.txt") }
            catch (e: NoSuchFileException) { e.message ?: "caught" }
        """)
    }

    // MARK: - STDLIB-IO-TYPE-002: FileAlreadyExistsException

    @Test func testFileAlreadyExistsExceptionSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let exceptionFQName = ["kotlin", "io", "FileAlreadyExistsException"].map { interner.intern($0) }
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
        #expect(sema.symbols.propertyType(for: exceptionSymbol) == exceptionType)

        let constructorFQName = exceptionFQName + [interner.intern("<init>")]
        let constructors = sema.symbols.lookupAll(fqName: constructorFQName).filter {
            sema.symbols.symbol($0)?.kind == .constructor
        }
        let expected: [([TypeID], String)] = [
            ([], "kk_throwable_new"),
            ([sema.types.stringType], "kk_throwable_new"),
        ]
        for (parameterTypes, externalLinkName) in expected {
            let constructor = try #require(constructors.first {
                sema.symbols.functionSignature(for: $0)?.parameterTypes == parameterTypes
            })
            #expect(sema.symbols.functionSignature(for: constructor)?.returnType == exceptionType)
            #expect(sema.symbols.externalLinkName(for: constructor) == externalLinkName)
        }
    }

    @Test func testFileAlreadyExistsExceptionResolvesInSource() throws {
        _ = try makeSema(source: """
        import kotlin.io.FileAlreadyExistsException

        fun noArg(): Exception = FileAlreadyExistsException()
        fun file(path: String): Exception = FileAlreadyExistsException(path)
        fun catchFileAlreadyExists(): String =
            try { throw FileAlreadyExistsException("duplicate.txt") }
            catch (e: FileAlreadyExistsException) { e.message ?: "caught" }
        """)
    }

    @Test func testConcurrentModificationExceptionSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

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
        #expect(sema.symbols.propertyType(for: exceptionSymbol) == exceptionType)

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
            ([], "kk_concurrent_modification_exception_new"),
            ([nullableStringType], "kk_concurrent_modification_exception_new_message"),
            ([nullableStringType, nullableThrowableType], "kk_concurrent_modification_exception_new_message_cause"),
            ([nullableThrowableType], "kk_concurrent_modification_exception_new_cause"),
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
        _ = try makeSema(source: """
        fun noArg(): RuntimeException = ConcurrentModificationException()
        fun message(message: String?): RuntimeException = ConcurrentModificationException(message)
        fun messageCause(message: String?, cause: Throwable?): RuntimeException = ConcurrentModificationException(message, cause)
        fun cause(cause: Throwable?): RuntimeException = ConcurrentModificationException(cause)
        """)
    }

    @Test func testArrayIndexOutOfBoundsExceptionSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

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
        #expect(sema.symbols.propertyType(for: exceptionSymbol) == exceptionType)

        let nullableStringType = sema.types.makeNullable(sema.types.stringType)
        let constructorFQName = exceptionFQName + [interner.intern("<init>")]
        let constructors = sema.symbols.lookupAll(fqName: constructorFQName).filter {
            sema.symbols.symbol($0)?.kind == .constructor
        }
        let expected: [([TypeID], String)] = [
            ([], "kk_array_index_out_of_bounds_exception_new"),
            ([nullableStringType], "kk_array_index_out_of_bounds_exception_new_message"),
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
        _ = try makeSema(source: """
        fun noArg(): IndexOutOfBoundsException = ArrayIndexOutOfBoundsException()
        fun message(message: String?): IndexOutOfBoundsException = ArrayIndexOutOfBoundsException(message)
        """)
    }
}
#endif
