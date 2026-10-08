#if canImport(Testing)
@testable import CompilerCore
import RuntimeABI
import Testing

extension LoweringABIAndPropertyRegressionTests {
    @Test
    func testSourceBackedDurationBridgesPreserveThrowingContracts() throws {
        let source = """
        import kotlin.time.Duration

        fun parseDuration(value: String): Duration = Duration.parse(value)

        fun parseDurationOrNull(value: String): Duration? = Duration.parseOrNull(value)

        fun parseDurationIso(value: String): Duration = Duration.parseIsoString(value)

        fun parseDurationIsoOrNull(value: String): Duration? = Duration.parseIsoStringOrNull(value)
        """
        try withTemporaryFile(contents: source) { path in
            // Executable KIR includes bundled source bodies, which is necessary
            // to inspect the bridge calls inside Duration.kt wrappers.
            let context = makeCompilationContext(inputs: [path], emit: .executable)
            try runToLowering(context)
            let module = try #require(context.kir)
            let sema = try #require(context.sema)
            let expectations: [(RuntimeABIFunctionSpec, Bool)] = [
                (try loweringRuntimeABI("duration_parse"), true),
                (try loweringRuntimeABI("duration_parseOrNull"), false),
                (try loweringRuntimeABI("duration_parseIsoString"), true),
                (try loweringRuntimeABI("duration_parseIsoStringOrNull"), false),
            ]
            let expected = Dictionary(uniqueKeysWithValues: expectations.map { ($0.0.name, $0.1) })
            var observed: [String: [(callee: String, argumentCount: Int, canThrow: Bool)]] = [:]
            var durationCallees: Set<String> = []

            for function in findAllKIRFunctions(in: module) {
                for instruction in function.body {
                    guard case let .call(symbol, callee, arguments, _, canThrow, _, _, _) = instruction else {
                        continue
                    }
                    let calleeName = context.interner.resolve(callee)
                    if calleeName.localizedCaseInsensitiveContains("duration") ||
                        calleeName.localizedCaseInsensitiveContains("parse")
                    {
                        durationCallees.insert(calleeName)
                    }
                    // Source bridge names add a private prefix to the canonical
                    // ABI name when a call no longer retains its source symbol.
                    let linkName = symbol.flatMap { sema.symbols.externalLinkName(for: $0) } ??
                        expectations.first { callee == context.interner.intern("__" + $0.0.name) }?.0.name
                    guard let linkName, expected[linkName] != nil else { continue }
                    observed[linkName, default: []].append((
                        callee: calleeName,
                        argumentCount: arguments.count,
                        canThrow: canThrow
                    ))
                }
            }

            for (abi, expectedThrowing) in expectations {
                let linkName = abi.name
                #expect(abi.isThrowing == expectedThrowing)
                let argumentCount = abi.parameters.filter { $0.name != "outThrown" }.count
                #expect(argumentCount == 1)
                let calls = observed[linkName] ?? []
                #expect(
                    !calls.isEmpty,
                    "Expected a source-backed call to \(linkName); duration-related callees: \(durationCallees.sorted())"
                )
                #expect(
                    calls.allSatisfy { $0.argumentCount == argumentCount },
                    "Source-backed \(linkName) must pass exactly its String argument"
                )
                // An unprotected throwing call propagates through the enclosing
                // function's outThrown parameter, so its local thrownResult is
                // intentionally nil. `canThrow` is the lowering contract that
                // makes NativeEmitter append the outThrown argument.
                #expect(
                    calls.allSatisfy { $0.canThrow == expectedThrowing },
                    "Source-backed \(linkName) has an incorrect canThrow lowering: \(calls)"
                )
            }
        }
    }
}
#endif
