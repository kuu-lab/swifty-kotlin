#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct IntegerFloorDivMemberCallTests {

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testSignedAndUnsignedFloorDivMemberCallsInferExpectedTypes
            """
            package sample0

                    fun sample(b: Byte, s: Short, i: Int, l: Long, ub: UByte, us: UShort, ui: UInt, ul: ULong) {
                        val byteShort: Int = b.floorDiv(s)
                        val intLong: Long = i.floorDiv(l)
                        val longByte: Long = l.floorDiv(b)
                        val ubyteUshort: UInt = ub.floorDiv(us)
                        val uintUbyte: UInt = ui.floorDiv(ub)
                        val ulongUInt: ULong = ul.floorDiv(ui)
                        val uintULong: ULong = ui.floorDiv(ul)
                    }

            """,
            // testFloorDivRejectsFloatingAndMixedSignednessReceivers
            """
            package sample1

                    fun sample(i: Int, ui: UInt, d: Double) {
                        i.floorDiv(ui)
                        ui.floorDiv(i)
                        d.floorDiv(2.0)
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            _ = try #require(ctx.ast)

            _ = try #require(ctx.sema)


            // === testSignedAndUnsignedFloorDivMemberCallsInferExpectedTypes ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                #expect(sample0Diagnostics.isEmpty, "Expected floorDiv overload matrix to type-check cleanly")

            }

            // === testFloorDivRejectsFloatingAndMixedSignednessReceivers ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                do {
                    } catch {
                    // Diagnostics are asserted below.
                }

                #expect(
                    sample1Diagnostics.count >= 3,
                    "Expected floorDiv to reject mixed signedness and floating receivers"
                )

            }

        }
    }

}

#endif
