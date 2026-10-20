extension JVMFunctionBuilder {
    func boundary() -> Int {
        let id = label(); instructions.append(.regionBoundary(id)); return id
    }
    func closeRegion(_ index: Int) {
        guard let start = activeRegions[index].start else { return }
        let end = boundary()
        activeRegions[index].segments.append((start, end)); activeRegions[index].start = nil
    }
    /// Inline finally on each escaping edge. Split protected ranges so an
    /// exception from this copy cannot re-enter the same finally or catches.
    func emitFinalizers(leavingLoop: Int? = nil, leavingInline: Int? = nil) throws {
        let saved = finalizers
        defer { finalizers = saved }
        while let frame = finalizers.last, leavingLoop.map({ frame.loops.count >= $0 }) ?? true, leavingInline.map({ finalizers.count > $0 }) ?? true {
            finalizers.removeLast()
            let indices = Array(frame.regionDepth..<activeRegions.count)
            let live = indices.filter { activeRegions[$0].start != nil }
            for i in live { closeRegion(i) }
            try emitFinalizer(frame)
            for i in live { activeRegions[i].start = boundary() }
            if terminated { return }
        }
    }
    func emitFinalizer(_ frame: FinallyFrame) throws {
        let savedScopes = scopes, savedLoops = loops
        let savedThis = thisValue, savedReceiver = extensionValue, savedContexts = contextualReceivers, savedArguments = inlineArguments, savedReturns = inlineReturns, savedLambda = lambdaID
        scopes = frame.scopes; loops = frame.loops
        thisValue = frame.dispatch; extensionValue = frame.receiver; contextualReceivers = frame.contexts
        inlineArguments = frame.arguments; inlineReturns = frame.returns; lambdaID = frame.lambda
        defer {
            scopes = savedScopes; loops = savedLoops
            thisValue = savedThis; extensionValue = savedReceiver; contextualReceivers = savedContexts
            inlineArguments = savedArguments; inlineReturns = savedReturns; lambdaID = savedLambda
        }
        if declaration.isInline { instructions.append(.inlineFinallyMarker(frame.regionDepth + 1, start: true)) }
        _ = try expression(frame.body, discarded: true)
        if declaration.isInline, !terminated { instructions.append(.inlineFinallyMarker(frame.regionDepth + 1, start: false)) }
    }
    func tryExpression(_ id: ExprID, _ body: ExprID, _ catches: [CatchClause], _ finalizer: ExprID?, discarded: Bool = false) throws -> JVMValue? {
        let type = try program.expressionType(id)
        let result = discarded || type == .unit ? nil : try value(type)
        let end = label(), depth = activeRegions.count
        let frame = finalizer.map { FinallyFrame(body: $0, scopes: scopes, loops: loops, regionDepth: depth, dispatch: thisValue, receiver: extensionValue, contexts: contextualReceivers, arguments: inlineArguments, returns: inlineReturns, lambda: lambdaID) }
        let preserved = pendingAllocations + (beforeDelegation ? [thisValue].compactMap { $0 } : [])
        if let frame { finalizers.append(frame) }
        let start = boundary()
        activeRegions.append((start, []))
        var normal = false
        func finishBranch(_ source: JVMValue?) throws {
            if terminated { return }
            if let result {
                guard let source else { throw fail("JVM try expression branch has no value.", id) }
                instructions.append(.copy(try convert(source, to: type), result))
            }
            if let frame {
                let saved = finalizers; finalizers.removeLast()
                try emitFinalizer(frame)
                finalizers = saved
            }
            if !terminated { normal = true; jump(end) }
        }
        let source = try expression(body, discarded: discarded)
        closeRegion(depth)
        let bodyRegions = activeRegions.removeLast().segments
        try finishBranch(source)
        var catchRegions: [(Int, Int)] = []
        for clause in catches {
            guard let binding = program.sema.bindings.catchClauseBinding(for: clause.body) else { throw fail("Missing JVM catch binding.", id) }
            let type = try program.type(binding.parameterType)
            guard let name = type.referenceName else { throw fail("JVM catch must name an exception class.", id) }
            let handler = label(), exception = try value(type)
            for segment in bodyRegions { handlers.append(JVMExceptionHandler(start: segment.0, end: segment.1, handler: handler, type: name)) }
            instructions.append(.exceptionHandler(handler, exception, preserving: preserved)); terminated = false
            scopes.append([:])
            if let name = clause.paramName { scopes[scopes.count - 1][name] = Local(value: exception, mutable: false) }
            activeRegions.append((boundary(), []))
            let source = try expression(clause.body, discarded: discarded)
            closeRegion(depth); catchRegions += activeRegions.removeLast().segments
            scopes.removeLast()
            try finishBranch(source)
        }
        if let frame {
            finalizers.removeLast()
            let handler = label(), exception = try value(.reference("java/lang/Throwable", nullable: false))
            for segment in bodyRegions + catchRegions { handlers.append(JVMExceptionHandler(start: segment.0, end: segment.1, handler: handler, type: nil)) }
            instructions.append(.exceptionHandler(handler, exception, preserving: preserved)); terminated = false
            try emitFinalizer(frame)
            if !terminated { instructions.append(.throwValue(exception)); terminated = true }
        }
        if normal { mark(end) } else { terminated = true }
        return result
    }
}
