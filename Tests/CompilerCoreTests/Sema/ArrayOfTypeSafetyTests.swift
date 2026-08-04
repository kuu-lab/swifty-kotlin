#if canImport(Testing)
@testable import CompilerCore
import Testing

/// TYPE-103: Verify that `arrayOf()` preserves element types and that
/// array-specific members are not incorrectly resolved on `Any` receivers.
@Suite
struct ArrayOfTypeSafetyTests {

    // MARK: - Positive: arrayOf(1, 2).get(0) should resolve without error
    // MARK: - testArrayOfTypeSafetyClean

    @Test
    func testArrayOfTypeSafetyClean() throws {

        let sources: [String] = [
            """
            package sample0

                    fun main() {
                        val arr = arrayOf(1, 2, 3)
                        val x = arr.get(0)
                        println(x)
                    }

            """,
            """
            package sample1

                    fun main() {
                        val arr = arrayOf("a", "b", "c")
                        val s = arr.size
                        println(s)
                    }

            """,
            """
            package sample2

                    fun main() {
                        val values: Array<String?> = arrayOfNulls<String>(3)
                        val first: String? = values[0]
                        println(first == null)
                    }

            """,
            """
            package sample3

                    fun main() {
                        val arr = arrayOf(1, 2, 3)
                        val b = arr.contains(2)
                        println(b)
                    }

            """,
            """
            package sample4

                    fun main() {
                        val arr = arrayOf(1, 2, 3, 4)
                        val idx = arr.binarySearch(3, compareBy<Int> { it })
                        println(idx)
                    }

            """,
            """
            package sample5

                    fun main(values: Array<out Int>) {
                        val idx = values.binarySearch(3, compareBy<Int> { it })
                        println(idx)
                    }

            """,
            """
            package sample6

                    fun main() {
                        val stringArray = arrayOf("a", "c", "e", "g")
                        val stringIndex = stringArray.binarySearch("c")
                        val stringRangeIndex = stringArray.binarySearch("d", 1, 4)

                        val boolArray = arrayOf(false, true)
                        val boolIndex = boolArray.binarySearch(false)

                        val intArray = intArrayOf(10, 20, 30, 40)
                        val intIndex = intArray.binarySearch(20)
                        val intFromIndex = intArray.binarySearch(30, 1)

                        val uintArray = uintArrayOf(10u, 20u, 30u, 40u)
                        val uintIndex = uintArray.binarySearch(30u)

                        val ulongArray = ulongArrayOf(10uL, 20uL, 30uL, 40uL)
                        val ulongRangeIndex = ulongArray.binarySearch(40uL, 1, 4)

                        println(stringIndex)
                        println(stringRangeIndex)
                        println(boolIndex)
                        println(intIndex)
                        println(intFromIndex)
                        println(uintIndex)
                        println(ulongRangeIndex)
                    }

            """,
            """
            package sample7

                    fun main() {
                        val arr = arrayOf(1, 2, 3)
                        val x = arr.get(0)
                    }

            """,
            """
            package sample8

                    fun main() {
                        val arr = intArrayOf(10, 20, 30)
                        val x = arr.get(0)
                        println(x)
                    }

            """,
            """
            package sample9

                    fun main() {
                        val arr = UShortArray(3) { it.toUShort() }
                        val x = arr.get(0)
                        println(x)
                    }

            """,
            """
            package sample10

                    fun main() {
                        val arr = UByteArray(3) { it.toUByte() }
                        val x = arr.get(0)
                        println(x)
                    }

            """,
            """
            package sample11

                    fun main() {
                        val arr = ushortArrayOf(1.toUShort(), 2.toUShort(), 65535.toUShort())
                        val x = arr[2]
                        println(x)
                    }

            """,
            """
            package sample12

                    fun main() {
                        val arr = ubyteArrayOf(1.toUByte(), 2.toUByte(), 255.toUByte())
                        val x = arr.get(1)
                        println(x)
                    }

            """,
            """
            package sample13

                    fun main() {
                        val arr = arrayOf(1, 3, 4, 7, 9)
                        val index = arr.binarySearch(4, 1, 4)
                        println(index)
                    }

            """,
            """
            package sample14

                    fun main() {
                        val arr = ULongArray(3) { it.toULong() }
                        val index = arr.binarySearch(1uL, 0, 3)
                        println(index)
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "Expected array type safety tests to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            // === testArrayOfIntGetResolvesWithoutError ===

            do {

                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            }

            // === testArrayOfStringSizeResolvesWithoutError ===

            do {

                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)

            }

            // === testArrayOfNullsResolvesAsNullableElementArray ===

            do {

                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            }

            // === testArrayOfContainsResolvesWithoutError ===

            do {

                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)

            }

            // === testArrayBinarySearchWithComparatorResolvesWithoutError ===

            do {

                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            }

            // === testProjectedArrayBinarySearchWithComparatorResolvesWithoutError ===

            do {

                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            }

            // === testArrayBinarySearchOverloadsResolveToInt ===

            do {

                let samplePath = paths[6]

                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

                let mainBody = try #require(findMainBodyStatements(in: ast, path: samplePath, ctx: ctx, interner: interner))
                let expectedNames: Set<String> = [
                    "stringIndex",
                    "stringRangeIndex",
                    "boolIndex",
                    "intIndex",
                    "intFromIndex",
                    "uintIndex",
                    "ulongRangeIndex",
                ]
                var seenNames: Set<String> = []
                for exprID in mainBody {
                    guard let expr = ast.arena.expr(exprID),
                          case let .localDecl(name, _, _, initializer, _, _) = expr,
                          let initializer,
                          let boundType = sema.bindings.exprType(for: initializer)
                    else { continue }

                    let localName = interner.resolve(name)
                    guard expectedNames.contains(localName) else { continue }

                    #expect(
                        boundType == sema.types.intType,
                        "Expected \(localName) to be typed as Int."
                    )
                    seenNames.insert(localName)
                }
                #expect(seenNames == expectedNames)

            }

            // === testArrayOfIntGetReturnsIntNotAny ===

            do {

                let samplePath = paths[7]



                // Walk the main body and find `val x = arr.get(0)`, then check
                // the initializer type is Int (not Any).
                let mainBody = try #require(findMainBodyStatements(in: ast, path: samplePath, ctx: ctx, interner: interner))
                var foundGetResult = false
                for exprID in mainBody {
                    guard let expr = ast.arena.expr(exprID),
                          case let .localDecl(_, _, _, initializer, _, _) = expr,
                          let initializer,
                          let boundType = sema.bindings.exprType(for: initializer)
                    else { continue }
                    // The get(0) call on Array<Int> should return Int, not Any.
                    if boundType == sema.types.intType {
                        foundGetResult = true
                    }
                }
                #expect(foundGetResult, "Expected arr.get(0) to be typed as Int, not Any.")

            }

            // === testIntArrayOfGetReturnsInt ===

            do {

                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            }

            // === testUShortArrayConstructorAndGetReturnUShort ===

            do {

                let samplePath = paths[9]

                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

                let mainBody = try #require(findMainBodyStatements(in: ast, path: samplePath, ctx: ctx, interner: interner))

                var foundUShortArray = false
                var foundUShortGet = false
                for exprID in mainBody {
                    guard let expr = ast.arena.expr(exprID),
                          case let .localDecl(name, _, _, initializer, _, _) = expr,
                          let initializer,
                          let boundType = sema.bindings.exprType(for: initializer)
                    else { continue }

                    if interner.resolve(name) == "arr",
                       case let .classType(classType) = sema.types.kind(of: boundType),
                       let symbol = sema.symbols.symbol(classType.classSymbol)
                    {
                        foundUShortArray = interner.resolve(symbol.name) == "UShortArray"
                    }

                    if interner.resolve(name) == "x" {
                        foundUShortGet = boundType == sema.types.ushortType
                    }
                }

                #expect(foundUShortArray, "Expected arr to be typed as UShortArray.")
                #expect(foundUShortGet, "Expected arr.get(0) to be typed as UShort.")

            }

            // === testUByteArrayConstructorInfersUByteElements ===

            do {

                let samplePath = paths[10]

                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

                let mainBody = try #require(findMainBodyStatements(in: ast, path: samplePath, ctx: ctx, interner: interner))

                var foundUByteArray = false
                var foundUByteGet = false
                for exprID in mainBody {
                    guard let expr = ast.arena.expr(exprID),
                          case let .localDecl(name, _, _, initializer, _, _) = expr,
                          let initializer,
                          let boundType = sema.bindings.exprType(for: initializer)
                    else { continue }

                    if interner.resolve(name) == "arr",
                       case let .classType(classType) = sema.types.kind(of: boundType),
                       let symbol = sema.symbols.symbol(classType.classSymbol)
                    {
                        foundUByteArray = interner.resolve(symbol.name) == "UByteArray"
                    }

                    if interner.resolve(name) == "x" {
                        foundUByteGet = boundType == sema.types.ubyteType
                    }
                }

                #expect(foundUByteArray, "Expected arr to be typed as UByteArray.")
                #expect(foundUByteGet, "Expected arr.get(0) to be typed as UByte.")

            }

            // === testUShortArrayFactoryReturnsUShortArray ===

            do {

                let samplePath = paths[11]

                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

                let mainBody = try #require(findMainBodyStatements(in: ast, path: samplePath, ctx: ctx, interner: interner))

                var foundUShortArray = false
                var foundIndexedUShort = false
                for exprID in mainBody {
                    guard let expr = ast.arena.expr(exprID),
                          case let .localDecl(name, _, _, initializer, _, _) = expr,
                          let initializer,
                          let boundType = sema.bindings.exprType(for: initializer)
                    else { continue }

                    if interner.resolve(name) == "arr",
                       case let .classType(classType) = sema.types.kind(of: boundType),
                       let symbol = sema.symbols.symbol(classType.classSymbol)
                    {
                        foundUShortArray = interner.resolve(symbol.name) == "UShortArray"
                    }

                    if interner.resolve(name) == "x" {
                        foundIndexedUShort = boundType == sema.types.ushortType
                    }
                }

                #expect(foundUShortArray, "Expected ushortArrayOf(...) to produce UShortArray.")
                #expect(foundIndexedUShort, "Expected indexed access to produce UShort.")

            }

            // === testUByteArrayOfFactoryResolvesWithoutError ===

            do {

                let samplePath = paths[12]

                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

                let mainBody = try #require(findMainBodyStatements(in: ast, path: samplePath, ctx: ctx, interner: interner))

                var foundUByteArray = false
                var foundIndexedUByte = false
                for exprID in mainBody {
                    guard let expr = ast.arena.expr(exprID),
                          case let .localDecl(name, _, _, initializer, _, _) = expr,
                          let initializer,
                          let boundType = sema.bindings.exprType(for: initializer)
                    else { continue }

                    if interner.resolve(name) == "arr",
                       case let .classType(classType) = sema.types.kind(of: boundType),
                       let symbol = sema.symbols.symbol(classType.classSymbol)
                    {
                        foundUByteArray = interner.resolve(symbol.name) == "UByteArray"
                    }

                    if interner.resolve(name) == "x" {
                        foundIndexedUByte = boundType == sema.types.ubyteType
                    }
                }

                #expect(foundUByteArray, "Expected ubyteArrayOf(...) to produce UByteArray.")
                #expect(foundIndexedUByte, "Expected indexed access to produce UByte.")

            }

            // === testArrayBinarySearchResolvesWithoutError ===

            do {

                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            }

            // === testULongArrayBinarySearchResolvesWithoutError ===

            do {

                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            }

        }

    }
    // MARK: - testArrayOfTypeSafetyErrors

    @Test
    func testArrayOfTypeSafetyErrors() throws {

        let sources: [String] = [
            """
            package sample0

                    fun test(x: Any) {
                        x.get(0)
                    }

            """,
            """
            package sample1

                    fun test(x: Any) {
                        x.size
                    }

            """,
            """
            package sample2

                    fun main() {
                        val arr = intArrayOf(1, 2, 3)
                        val idx = arr.binarySearch(2, compareBy<Int> { it })
                        println(idx)
                    }

            """,
            """
            package sample3

                    fun main() {
                        val arr = booleanArrayOf(true, false)
                        val idx = arr.binarySearch(true)
                        println(idx)
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // === testArrayGetOnAnyReceiverProducesError ===

            do {

                // `get` is not a member of Any; should produce unresolved member error.
                assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)

            }

            // === testArraySizeOnAnyReceiverProducesError ===

            do {

                // `size` is not a member of Any; should produce unresolved member/field error.
                let hasDiag = ctx.diagnostics.diagnostics.contains {
                    $0.code == "KSWIFTK-SEMA-0024" || $0.code == "KSWIFTK-SEMA-FIELD"
                }
                #expect(hasDiag, "Expected unresolved member diagnostic for .size on Any, got: \(ctx.diagnostics.diagnostics.map(\.code))")

            }

            // === testIntArrayBinarySearchWithComparatorProducesError ===

            do {

                assertHasDiagnostic("KSWIFTK-SEMA-0002", in: ctx)

            }

            // === testBooleanArrayBinarySearchIsRejected ===

            do {

                let hasArrayBinarySearchDiag = ctx.diagnostics.diagnostics.contains {
                    $0.code == "KSWIFTK-SEMA-0002" || $0.code == "KSWIFTK-SEMA-0024" || $0.code == "KSWIFTK-SEMA-BOUND"
                }
                #expect(
                    hasArrayBinarySearchDiag,
                    "Expected booleanArrayOf().binarySearch(...) to be rejected, got: \(ctx.diagnostics.diagnostics.map(\.code))"
                )

            }

        }

    }

    // MARK: - Helpers

    private func findMainBodyStatements(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        interner: StringInterner
    ) -> [ExprID]? {
        for file in ast.files {
            guard ctx.sourceManager.path(of: file.fileID) == path else { continue }
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .funDecl(function) = decl,
                      interner.resolve(function.name) == "main",
                      case let .block(statements, _) = function.body
                else { continue }
                return statements
            }
        }
        return nil
    }
}
#endif
