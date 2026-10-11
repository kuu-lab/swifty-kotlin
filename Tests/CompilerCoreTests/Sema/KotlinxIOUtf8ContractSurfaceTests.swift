@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import TestStdlibCache
import Testing

@Suite(.serialized)
struct KotlinxIOUtf8ContractSurfaceTests {
    private func check(_ source: String, library: Bool, expectsErrors: Bool) throws -> CompilationContext {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let input = directory.appendingPathComponent("Input.kt")
        try source.write(to: input, atomically: true, encoding: .utf8)
        // Tiny Core inputs remain available for any later signature assertion failure.
        let path: String?
        if library {
            TestStdlibCache.shared.prepare()
            path = try #require(CompilerOptions.defaultStdlibLibraryPath)
        } else {
            path = nil
        }
        let ctx = makeCompilationContext(inputs: [input.path], stdlibLibraryPath: path,
            allowDefaultStdlibLibrary: false)
        try #require(ctx.options.stdlibLibraryPath == path)
        try #require(ctx.options.includeStdlib == !library)
        try #require(!ctx.options.allowDefaultStdlibLibrary)
        try runSema(ctx)
        try #require(ctx.diagnostics.hasError == expectsErrors, "\(ctx.diagnostics.diagnostics)")
        return ctx
    }

    @Test(arguments: [false, true])
    func realNinePublicUtf8OverloadsKeepSourceAndImportedSignatures(library: Bool) throws {
        let ctx = try check("""
        @file:OptIn(kotlinx.io.DelicateIoApi::class)
        import kotlinx.io.*
        import kotlinx.io.readLineStrict as strictLine
        fun use(source: Source, sink: Sink, buffer: Buffer, chars: CharSequence) {
            sink.writeString("A")
            sink.writeString("A", 0, 1)
            sink.writeString(chars, 0, chars.length)
            sink.writeCodePointValue(0x10000)
            val point: Int = source.readCodePointValue()
            val line: String? = source.readLine()
            val strict: String = source.strictLine()
            val bounded: String = source.strictLine(1)
            val all: String = source.readString()
            val count: String = source.readString(0)
            val direct: String = buffer.readString()
        }
        // These producer-side OptIn annotations must not require consent from
        // callers of the ordinary public Source operations.
        fun publicReads(source: Source, charset: kotlin.text.Charset) {
            source.readByteString()
            source.readByteString(0)
            source.readString(charset)
            source.readString(0L, charset)
        }
        open class Utf8ProbeBase {
            fun utf8ProbePriority(): Int = 8
        }
        class Utf8ProbeSub : Utf8ProbeBase()
        private fun Utf8ProbeSub.utf8ProbeOnly(): Int = 7
        private fun Utf8ProbeSub.utf8ProbePriority(): Int = 9
        fun Utf8ProbeBase.ifReceiverProbe(): Int {
            if (this is Utf8ProbeSub) return utf8ProbeOnly()
            return 0
        }
        fun Utf8ProbeBase.elseReceiverProbe(): Int {
            if (this !is Utf8ProbeSub) return 0 else return utf8ProbeOnly()
        }
        fun Utf8ProbeBase.whenReceiverProbe(): Int = when (this) {
            is Utf8ProbeSub -> utf8ProbeOnly()
            else -> 0
        }
        fun Utf8ProbeBase.guardReturnReceiverProbe(): Int {
            if (this !is Utf8ProbeSub) return 0
            return utf8ProbeOnly()
        }
        private fun Utf8ProbeBase.utf8ProbeShadow(): Int = 4
        private fun Utf8ProbeSub.utf8ProbeShadow(): Int = 5
        fun Utf8ProbeBase.shadowReceiverProbe(other: Utf8ProbeBase): Int {
            if (this !is Utf8ProbeSub) return 0
            return other.run { utf8ProbeShadow() }
        }
        fun Utf8ProbeBase.memberPriorityProbe(): Int {
            if (this is Utf8ProbeSub) return utf8ProbePriority()
            return 0
        }
        class Utf8ProbeOuter {
            fun utf8ProbeOuterOnly(): Int = 6
            fun receiverTowerProbe(source: Utf8ProbeBase): Int = source.run {
                if (this is Utf8ProbeSub) return@run utf8ProbeOnly()
                utf8ProbeOuterOnly()
            }
        }
        """, library: library, expectsErrors: false)
        let sema = try #require(ctx.sema)
        var identities = Set<SymbolID>()
        for (name, count) in [("writeString", 2), ("writeCodePointValue", 1), ("readString", 3),
                              ("readCodePointValue", 1), ("readLine", 1), ("readLineStrict", 1)] {
            let ids = sema.symbols.lookupAll(fqName: ["kotlinx", "io", name].map(ctx.interner.intern))
                .filter { id in
                    guard let symbol = sema.symbols.symbol(id) else { return false }
                    return symbol.kind == .function && symbol.visibility == .public &&
                        sema.symbols.functionSignature(for: id)?.receiverType != nil
                }
            try #require(ids.count == count, "\(name) actual public extension overload count")
            for id in ids {
                let symbol = try #require(sema.symbols.symbol(id))
                try #require(symbol.flags.contains(.importedLibrary) == library)
                let signature = try #require(sema.symbols.functionSignature(for: id))
                if name == "writeString" {
                    try #require(signature.valueParameterHasDefaultValues == [false, true, true])
                } else if name == "readLineStrict" {
                    try #require(signature.valueParameterHasDefaultValues == [true])
                }
                if name == "readLine" {
                    try #require(sema.types.kind(of: signature.returnType) == .stringStruct(.nullable))
                }
                identities.insert(id)
            }
        }
        try #require(identities.count == 9)
        let ast = try #require(ctx.ast)
        let input = try #require(ctx.options.inputs.first)
        func requireProbeCalls(_ name: String, count: Int, chosenFQName: [String], receiverName: String) throws {
            var ranges = Set<SourceRange>()
            var bound: [SourceRange: ExprID] = [:]
            for (index, expr) in ast.arena.exprs.enumerated() {
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(callName, _) = ast.arena.expr(callee),
                      ctx.interner.resolve(callName) == name else { continue }
                let id = ExprID(rawValue: Int32(index))
                guard let range = ast.arena.exprRange(id),
                      ctx.sourceManager.path(of: range.start.file) == input else { continue }
                ranges.insert(range)
                if sema.bindings.callBinding(for: id) != nil { bound[range] = id }
            }
            try #require(ranges.count == count)
            try #require(Set(bound.keys) == ranges, "Every implicit receiver probe must resolve")
            for id in bound.values {
                let binding = try #require(sema.bindings.callBinding(for: id))
                let chosen = try #require(sema.symbols.symbol(binding.chosenCallee))
                try #require(chosen.fqName.map(ctx.interner.resolve) == chosenFQName)
                let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
                let receiver = try #require(signature.receiverType)
                guard case let .classType(classType) = sema.types.kind(of: receiver) else {
                    Issue.record("Expected the probe's declared nominal receiver")
                    return
                }
                let receiverSymbol = try #require(sema.symbols.symbol(classType.classSymbol))
                try #require(ctx.interner.resolve(receiverSymbol.name) == receiverName)
                try #require(signature.returnType == sema.types.intType)
            }
        }
        try requireProbeCalls("utf8ProbeOnly", count: 5,
            chosenFQName: ["utf8ProbeOnly"], receiverName: "Utf8ProbeSub")
        try requireProbeCalls("utf8ProbePriority", count: 1,
            chosenFQName: ["Utf8ProbeBase", "utf8ProbePriority"], receiverName: "Utf8ProbeBase")
        try requireProbeCalls("utf8ProbeOuterOnly", count: 1,
            chosenFQName: ["Utf8ProbeOuter", "utf8ProbeOuterOnly"], receiverName: "Utf8ProbeOuter")
        try requireProbeCalls("utf8ProbeShadow", count: 1,
            chosenFQName: ["utf8ProbeShadow"], receiverName: "Utf8ProbeBase")

        // A branch smart cast must not change the unguarded/else receiver,
        // and producer consent must not suppress direct InternalIoApi uses.
        let rejected = try check("""
        import kotlinx.io.*
        open class Utf8RejectedBase
        class Utf8RejectedSub : Utf8RejectedBase()
        private fun Utf8RejectedSub.utf8RejectedOnly(): Int = 1
        fun Utf8RejectedBase.unguarded(): Int = utf8RejectedOnly()
        fun Utf8RejectedBase.outsideBranch(): Int {
            if (this is Utf8RejectedSub) { val ok: Int = utf8RejectedOnly() }
            return utf8RejectedOnly()
        }
        fun Utf8RejectedBase.negativeElse(): Int {
            if (this is Utf8RejectedSub) return utf8RejectedOnly()
            else return utf8RejectedOnly()
        }
        fun noInternalConsent(source: Source) { val raw: Buffer = source.buffer }
        """, library: library, expectsErrors: true)
        let errors = rejected.diagnostics.diagnostics.filter { $0.severity == .error }
        try #require(errors.count == 4, "\(errors)")
        try #require(errors.filter { $0.code == "KSWIFTK-SEMA-0002" }.count == 3)
        let optIn = errors.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
        try #require(optIn.count == 1 && optIn[0].message.contains("InternalIoApi"))
        let rejectedInput = try #require(rejected.options.inputs.first)
        var rejectedCallLines = Set<Int>()
        for diagnostic in errors where diagnostic.code == "KSWIFTK-SEMA-0002" {
            let range = try #require(diagnostic.primaryRange)
            try #require(rejected.sourceManager.path(of: range.start.file) == rejectedInput)
            try #require(rejected.sourceManager.slice(range) == "utf8RejectedOnly()")
            rejectedCallLines.insert(rejected.sourceManager.lineColumn(of: range.start).line)
        }
        try #require(rejectedCallLines == [5, 8, 12])
        let optInRange = try #require(optIn[0].primaryRange)
        try #require(rejected.sourceManager.path(of: optInRange.start.file) == rejectedInput)
        try #require(rejected.sourceManager.lineColumn(of: optInRange.start).line == 14)

        // Guarding an unrelated value establishes no fact for the current this.
        // An ordinary escaped-name local is not a receiver parameter either.
        let guardedNegatives = [
            """
            open class GuardBase
            class GuardSub : GuardBase()
            private fun GuardSub.guardOnly(): Int = 1
            fun GuardBase.guardNone(other: GuardBase): Int {
                if (other !is GuardSub) return 0
                return guardOnly()
            }
            """,
            """
            open class ShadowBase
            class ShadowSub : ShadowBase()
            private fun ShadowSub.shadowOnly(): Int = 1
            fun ShadowBase.receiverShadow(): Int {
                val `this` = ShadowSub()
                return shadowOnly()
            }
            """,
        ]
        for (index, source) in guardedNegatives.enumerated() {
            let negative = try check(source, library: library, expectsErrors: true)
            let negativeErrors = negative.diagnostics.diagnostics.filter { $0.severity == .error }
            try #require(negativeErrors.count == 1, "\(negativeErrors)")
            let diagnostic = negativeErrors[0]
            try #require(diagnostic.code == "KSWIFTK-SEMA-0002")
            let range = try #require(diagnostic.primaryRange)
            let path = try #require(negative.options.inputs.first)
            try #require(negative.sourceManager.path(of: range.start.file) == path)
            try #require(negative.sourceManager.lineColumn(of: range.start).line == 6)
            try #require(negative.sourceManager.slice(range) == (index == 0 ? "guardOnly()" : "shadowOnly()"))
        }
    }

    @Test(arguments: [false, true], ["source.readUtf8()", "sink.writeUtf8(\"A\")",
        "buffer.commonReadUtf8CodePoint()", "buffer.commonWriteUtf8CodePoint(65)"])
    func privateCodecsAndOkioHomonymsDoNotLeakThroughWildcard(library: Bool, forbiddenCall: String) throws {
        _ = try check("""
        import kotlinx.io.*
        fun bad(source: Source, sink: Sink, buffer: Buffer) {
            \(forbiddenCall)
        }
        """, library: library, expectsErrors: true)
    }
}
