#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

/// `java.io` stream/reader/writer members lower to `__kk_*` runtime bridges.
/// A class-typed receiver must dispatch through the registered vtable slot —
/// the runtime factories (`__kk_string_writer_new`, `__kk_output_stream_bufferedWriter`,
/// `__kk_*_byteInputStream_*`, …) install those entries on every produced box —
/// so a Kotlin subclass override (e.g. `DataInputStream.read`,
/// `FlushingWriter.flush`) is reached instead of a direct `__kk_*` call that
/// bypassed overrides or panicked on a real object (KSWIFTK-RUNTIME-0001).
/// KUU-3851 covered `InputStream`/`OutputStream`; KUU-3860 extends the same
/// treatment to `Writer`/`BufferedWriter` (`w.flush()`/`w.write(text)` on a
/// `Writer`-typed receiver).
extension BuildKIRRegressionTests {
    private func virtualCallNamesAndCanThrow(
        from body: [KIRInstruction],
        interner: StringInterner
    ) -> [(String, Bool)] {
        body.compactMap { instruction in
            guard case let .virtualCall(_, callee, _, _, _, canThrow, _, _) = instruction else {
                return nil
            }
            return (interner.resolve(callee), canThrow)
        }
    }

    @Test
    func inputStreamReadOnBaseTypedReceiverDispatchesVirtually() throws {
        let source = """
        import java.io.InputStream
        fun probe(s: InputStream): Int = s.read()
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
        let virtuals = virtualCallNamesAndCanThrow(from: body, interner: ctx.interner)
        #expect(
            virtuals.contains { $0.0 == "__kk_input_stream_read" && $0.1 },
            "probe: expected throwing virtual __kk_input_stream_read, virtual=\(virtuals), direct=\(extractCallees(from: body, interner: ctx.interner))"
        )
    }

    @Test
    func streamBoxNominalReceiverAlsoDispatchesVirtually() throws {
        // `ByteArrayInputStream`/`OutputStream`/`Writer` receivers must use the
        // same slot path — the producer-registered box vtable resolves it to
        // the identical `__kk_*` bridge.
        let source = """
        import java.io.ByteArrayInputStream
        import java.io.OutputStream
        import java.io.Writer
        fun bytesProbe(s: ByteArrayInputStream): Int = s.read()
        fun outProbe(s: OutputStream) { s.close() }
        fun writerProbe(w: Writer) { w.flush() }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)

        let bytesBody = try findKIRFunctionBody(named: "bytesProbe", in: module, interner: ctx.interner)
        #expect(
            extractVirtualCallees(from: bytesBody, interner: ctx.interner).contains("__kk_input_stream_read"),
            "bytesProbe: \(extractCallees(from: bytesBody, interner: ctx.interner))"
        )

        let outBody = try findKIRFunctionBody(named: "outProbe", in: module, interner: ctx.interner)
        #expect(
            virtualCallNamesAndCanThrow(from: outBody, interner: ctx.interner)
                .contains { $0.0 == "__kk_output_stream_close_throwing" && $0.1 },
            "outProbe: \(extractCallees(from: outBody, interner: ctx.interner))"
        )

        let writerBody = try findKIRFunctionBody(named: "writerProbe", in: module, interner: ctx.interner)
        #expect(
            virtualCallNamesAndCanThrow(from: writerBody, interner: ctx.interner)
                .contains { $0.0 == "__kk_buffered_writer_flush" && $0.1 },
            "writerProbe: \(extractCallees(from: writerBody, interner: ctx.interner))"
        )
    }

    @Test
    func writerWriteAndCloseOnBaseTypedReceiverDispatchVirtually() throws {
        // KUU-3860: `Writer.write(text)` and `Writer.close()` on a
        // `Writer`-typed receiver must route through vtable[0]/vtable[2]
        // just like `flush` — a `BufferedWriter`/`StringWriter` box resolves
        // the slot to the `__kk_buffered_writer_*` bridge, while a Kotlin
        // subclass override wins through the same slot.
        let source = """
        import java.io.Writer
        fun writeProbe(w: Writer, text: String) { w.write(text) }
        fun closeProbe(w: Writer) { w.close() }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)

        let writeBody = try findKIRFunctionBody(named: "writeProbe", in: module, interner: ctx.interner)
        #expect(
            virtualCallNamesAndCanThrow(from: writeBody, interner: ctx.interner)
                .contains { $0.0 == "__kk_buffered_writer_write" && $0.1 },
            "writeProbe: \(extractCallees(from: writeBody, interner: ctx.interner))"
        )

        let closeBody = try findKIRFunctionBody(named: "closeProbe", in: module, interner: ctx.interner)
        #expect(
            virtualCallNamesAndCanThrow(from: closeBody, interner: ctx.interner)
                .contains { $0.0 == "__kk_buffered_writer_close_throwing" && $0.1 },
            "closeProbe: \(extractCallees(from: closeBody, interner: ctx.interner))"
        )
    }

    @Test
    func sequenceInputStreamOwnMemberStaysDirect() throws {
        // `SequenceInputStream` is final in the synthetic graph; its own
        // specialized `__kk_sequence_input_stream_*` bridges remain direct.
        let source = """
        import java.io.SequenceInputStream
        fun seqProbe(s: SequenceInputStream): Int = s.read()
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "seqProbe", in: module, interner: ctx.interner)
        #expect(
            extractCallees(from: body, interner: ctx.interner).contains("__kk_sequence_input_stream_read"),
            "seqProbe: \(extractVirtualCallees(from: body, interner: ctx.interner))"
        )
    }

    /// All `kk_object_register_vtable_method` registrations in the module:
    /// (slot, methodSymbol) pairs resolved from their constant expressions.
    private func allVtableMethodRegistrations(
        in module: KIRModule,
        interner: StringInterner
    ) -> [(slot: Int64, method: SymbolID)] {
        findAllKIRFunctions(in: module).flatMap { function in
            var intConstants: [KIRExprID: Int64] = [:]
            var symbolConstants: [KIRExprID: SymbolID] = [:]
            for instruction in function.body {
                if case let .constValue(result, .intLiteral(value)) = instruction {
                    intConstants[result] = value
                }
                if case let .constValue(result, .symbolRef(symbol)) = instruction {
                    symbolConstants[result] = symbol
                }
            }
            return function.body.compactMap { instruction -> (slot: Int64, method: SymbolID)? in
                guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                      interner.resolve(callee) == "kk_object_register_vtable_method",
                      arguments.count == 3,
                      let slot = intConstants[arguments[1]],
                      let method = symbolConstants[arguments[2]]
                else { return nil }
                return (slot, method)
            }
        }
    }

    // KUU-3860: `Writer.write(text: String)` dispatches through the raw
    // `__kk_buffered_writer_write` ABI — `(i64 receiver, i64 textHandle,
    // outThrown)` — because every entry registered for the slot, including
    // the runtime box entries, uses that ABI. A Kotlin subclass override is
    // a flat source function whose `String` parameter is the `{ ptr, i64,
    // i64, i64 }` aggregate, so the slot must register a `kk_itable_bridge_*`
    // adapter whose outer signature is raw (int word for `text`), not the
    // flat thunk itself — otherwise the vtable lookup hands a raw handle to
    // a callee that reads four words of it and crashes.
    @Test
    func writerWriteOverrideRegistersRawABIBridgeInVtableSlot() throws {
        TestStdlibCache.shared.prepare()
        let context = makeContextFromSource("""
        import java.io.BufferedWriter
        import java.io.StringWriter
        import java.io.Writer

        class RecordingWriter(w: Writer) : BufferedWriter(w) {
            override fun write(text: String) {}
        }
        fun probe(): Writer = RecordingWriter(StringWriter())
        """, allowDefaultStdlibLibrary: true)
        try runToKIR(context)
        #expect(!context.diagnostics.hasError)
        let sema = try #require(context.sema)
        let module = try #require(context.kir)
        let interner = context.interner

        let writerWrite = try #require(sema.symbols.lookupAll(fqName: [
            interner.intern("java"), interner.intern("io"), interner.intern("Writer"),
            interner.intern("write"),
        ]).first { symbol in
            sema.symbols.symbol(symbol)?.kind == .function
        })
        let nominal = try #require(sema.symbols.lookup(fqName: [
            interner.intern("RecordingWriter"),
        ]))
        let slot = try #require(
            sema.symbols.nominalLayout(for: nominal)?.vtableSlots[writerWrite].map(Int64.init)
        )

        let slotRegistrations = allVtableMethodRegistrations(in: module, interner: interner)
            .filter { $0.slot == slot }
        #expect(!slotRegistrations.isEmpty)

        // The registered entry must be a synthesized bridge taking the raw
        // word/handle form for `text`, not the flat-ABI Kotlin thunk and not
        // the runtime `__kk_*` bridge itself.
        let registeredFunctionNames = slotRegistrations.compactMap {
            module.arena.function(for: $0.method).map { interner.resolve($0.name) }
        }
        let bridgeNames = registeredFunctionNames.filter { $0.hasPrefix("kk_itable_bridge_") }
        #expect(
            !bridgeNames.isEmpty,
            "the String-typed Writer.write slot must register a raw-ABI itable bridge: \(registeredFunctionNames)"
        )
        for bridgeName in bridgeNames {
            let bridge = try #require(findAllKIRFunctions(in: module).first {
                interner.resolve($0.name) == bridgeName
            })
            #expect(
                bridge.params.count == 2
                    && bridge.params[1].type == sema.types.intType,
                "bridge \(bridgeName) must present the raw dispatch ABI (receiver, raw text word): \(bridge.params.map { "\($0.type)" })"
            )
        }
        let externalLinkNames = slotRegistrations.compactMap {
            sema.symbols.externalLinkName(for: $0.method)
        }
        #expect(
            !externalLinkNames.contains("__kk_buffered_writer_write"),
            "the runtime box bridge belongs only to box registrations, not the Kotlin override slot"
        )
    }
}
#endif
