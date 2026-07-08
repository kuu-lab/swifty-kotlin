
extension CollectionLiteralConstructionLoweringPass {

    /// Rewrites java.io.File constructors and File member runtime calls.
    func rewriteFileCall(
        symbol: SymbolID?,
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        canThrow: Bool,
        thrownResult: KIRExprID?,
        module: KIRModule,
        ctx: KIRContext,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        // --- Rewrite File(path) → kk_file_new(path) (STDLIB-565)
        //     Rewrite File(parent, child) → kk_file_new_parent_child(parent, child) (STDLIB-IO-087) ---
        if callee == lookup.fileConstructorName {
            let fileCallee = arguments.count == 2
                ? lookup.kkFileNewParentChildName
                : lookup.kkFileNewName
            loweredBody.append(.call(
                symbol: nil,
                callee: fileCallee,
                arguments: arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { state.fileExprIDs.insert(result.rawValue) }
            return true
        }

        // --- Rewrite File member calls: readText/writeText/readLines (STDLIB-320) ---
        if callee == lookup.readTextName,
           arguments.count == 1,
           state.fileExprIDs.contains(arguments[0].rawValue),
           isJavaIOFileMember(symbol: symbol, ctx: ctx, interner: ctx.interner)
        {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkFileReadTextName,
                arguments: arguments,
                result: result,
                canThrow: true,
                thrownResult: thrownResult
            ))
            return true
        }

        if callee == lookup.writeTextName,
           arguments.count == 2,
           state.fileExprIDs.contains(arguments[0].rawValue),
           isJavaIOFileMember(symbol: symbol, ctx: ctx, interner: ctx.interner)
        {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkFileWriteTextName,
                arguments: arguments,
                result: result,
                canThrow: true,
                thrownResult: thrownResult
            ))
            return true
        }

        if callee == lookup.appendTextName,
           arguments.count == 2,
           state.fileExprIDs.contains(arguments[0].rawValue),
           isJavaIOFileMember(symbol: symbol, ctx: ctx, interner: ctx.interner)
        {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkFileAppendTextName,
                arguments: arguments,
                result: result,
                canThrow: true,
                thrownResult: thrownResult
            ))
            return true
        }

        if callee == lookup.readLinesName,
           arguments.count == 1,
           state.fileExprIDs.contains(arguments[0].rawValue),
           isJavaIOFileMember(symbol: symbol, ctx: ctx, interner: ctx.interner)
        {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkFileReadLinesName,
                arguments: arguments,
                result: result,
                canThrow: true,
                thrownResult: thrownResult
            ))
            if let result { state.listExprIDs.insert(result.rawValue) }
            return true
        }

        // --- Rewrite File member calls (STDLIB-321) ---
        // Only rewrite calls on File expressions (tracked in state.fileExprIDs)
        if arguments.count >= 1, state.fileExprIDs.contains(arguments[0].rawValue) {
            let receiverID = arguments[0]
            let kkCallee: InternedString?

            switch callee {
            case lookup.readTextName:
                kkCallee = lookup.kkFileReadTextName
            case lookup.writeTextName:
                kkCallee = lookup.kkFileWriteTextName
            case lookup.appendTextName:
                kkCallee = lookup.kkFileAppendTextName
            case lookup.readLinesName:
                kkCallee = lookup.kkFileReadLinesName
            case lookup.existsName:
                kkCallee = lookup.kkFileExistsName
            case lookup.isFileName:
                kkCallee = lookup.kkFileIsFileName
            case lookup.isDirectoryName:
                kkCallee = lookup.kkFileIsDirectoryName
            case lookup.forEachLineName:
                kkCallee = lookup.kkFileForEachLineName
            // STDLIB-IO-FN-016: forEachBlock — arity-based dispatch
            case lookup.forEachBlockName:
                kkCallee = arguments.count == 2
                    ? lookup.kkFileForEachBlockName
                    : lookup.kkFileForEachBlockBlockSizeName
            case lookup.useLinesName:
                kkCallee = lookup.kkFileUseLinesName
            case lookup.bufferedReaderName:
                // Only rewrite argument-less bufferedReader(); the runtime
                // function kk_file_bufferedReader does not accept charset/bufferSize.
                kkCallee = arguments.count == 1 ? lookup.kkFileBufferedReaderName : nil
            case lookup.bufferedWriterName:
                // Only rewrite argument-less bufferedWriter()
                kkCallee = arguments.count == 1 ? lookup.kkFileBufferedWriterName : nil
            case lookup.printWriterName:
                // Only rewrite argument-less printWriter() (STDLIB-IO-FN-027)
                kkCallee = arguments.count == 1 ? lookup.kkFilePrintWriterName : nil
            case lookup.walkName:
                kkCallee = lookup.kkFileWalkName
            case lookup.walkTopDownName:
                kkCallee = lookup.kkFileWalkTopDownName
            case lookup.walkBottomUpName:
                kkCallee = lookup.kkFileWalkBottomUpName
            case lookup.listFilesName:
                kkCallee = lookup.kkFileListFilesName
            case lookup.deleteName:
                kkCallee = lookup.kkFileDeleteName
            case lookup.mkdirsName:
                kkCallee = lookup.kkFileMkdirsName
            case lookup.readBytesName:
                kkCallee = lookup.kkFileReadBytesName
            case lookup.appendBytesName:
                kkCallee = lookup.kkFileAppendBytesName
            case lookup.writeBytesName:
                kkCallee = lookup.kkFileWriteBytesName
            // STDLIB-IO-087: Additional File operations
            case lookup.absolutePathName:
                kkCallee = lookup.kkFileAbsolutePathName
            case lookup.canonicalPathName:
                kkCallee = lookup.kkFileCanonicalPathName
            case lookup.lengthName:
                kkCallee = lookup.kkFileLengthName
            case lookup.lastModifiedName:
                kkCallee = lookup.kkFileLastModifiedName
            case lookup.createNewFileName:
                kkCallee = lookup.kkFileCreateNewFileName
            case lookup.canReadName:
                kkCallee = lookup.kkFileCanReadName
            case lookup.canWriteName:
                kkCallee = lookup.kkFileCanWriteName
            case lookup.canExecuteName:
                kkCallee = lookup.kkFileCanExecuteName
            default:
                kkCallee = nil
            }

            if let target = kkCallee {
                let memberArgs = (
                    callee == lookup.forEachLineName
                        || callee == lookup.forEachBlockName
                        || callee == lookup.useLinesName
                        || callee == lookup.writeTextName
                        || callee == lookup.appendTextName
                        || callee == lookup.appendBytesName
                        || callee == lookup.writeBytesName
                ) ? [receiverID] + arguments.dropFirst() : [receiverID]
                loweredBody.append(.call(
                    symbol: nil,
                    callee: target,
                    arguments: memberArgs,
                    result: result,
                    canThrow: canThrow,
                    thrownResult: thrownResult
                ))
                // Track walk() result as FileTreeWalk; other collection results as lists
                if let result, callee == lookup.walkName {
                    state.fileTreeWalkExprIDs.insert(result.rawValue)
                } else if let result,
                   callee == lookup.listFilesName || callee == lookup.readLinesName || callee == lookup.readBytesName
                {
                    state.listExprIDs.insert(result.rawValue)
                }
                // Track fallback-path walkTopDown/walkBottomUp results as FileTreeWalk
                if let result,
                   callee == lookup.walkTopDownName || callee == lookup.walkBottomUpName
                {
                    state.fileTreeWalkExprIDs.insert(result.rawValue)
                }
                // Track bufferedReader()/bufferedWriter()/printWriter() results as file-like exprs for chained member calls
                if let result,
                   callee == lookup.bufferedReaderName || callee == lookup.bufferedWriterName
                    || callee == lookup.printWriterName
                {
                    state.fileExprIDs.insert(result.rawValue)
                }
                return true
            }
        }

        // --- FileTreeWalk kk_* callee tracking (STDLIB-IO-TYPE-004 / STDLIB-IO-PATH-FN-039) ---
        // When externalLinkName is set in Sema, the KIR callee is already kk_*.
        // We only need to tag results in fileTreeWalkExprIDs so builder chains
        // that follow can identify the receiver.
        if callee == lookup.kkFileWalkName
            || callee == lookup.kkFileWalkTopDownName
            || callee == lookup.kkFileWalkBottomUpName
            || callee == lookup.kkFileWalkWithDirectionName
        {
            if let result { state.fileTreeWalkExprIDs.insert(result.rawValue) }
            // The call instruction is already correct; let the default handler append it.
            return false
        }

        // STDLIB-IO-PATH-FN-039: kk_path_walk result is a List<Path> (Sequence<Path> materialised)
        if callee == lookup.kkPathWalkName {
            if let result { state.listExprIDs.insert(result.rawValue) }
            return false
        }

        // kk_file_tree_walk_to_list: result is a List<File>
        if callee == lookup.kkFileTreeWalkToListName {
            if let result { state.listExprIDs.insert(result.rawValue) }
            return false
        }

        if arguments.count >= 1, state.fileTreeWalkExprIDs.contains(arguments[0].rawValue) {
            // maxDepth: pure value set, no lambda → just track result
            if callee == lookup.kkFileTreeWalkMaxDepthName {
                if let result { state.fileTreeWalkExprIDs.insert(result.rawValue) }
                return false
            }

            // filter / onEnter / onLeave / onFail: (walkRaw, fnPtr) → inject closureRaw → track result
            if callee == lookup.kkFileTreeWalkFilterName
                || callee == lookup.kkFileTreeWalkOnEnterName
                || callee == lookup.kkFileTreeWalkOnLeaveName
                || callee == lookup.kkFileTreeWalkOnFailName
            {
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                loweredBody.append(.call(
                    symbol: symbol,
                    callee: callee,
                    arguments: arguments + [zeroExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                if let result { state.fileTreeWalkExprIDs.insert(result.rawValue) }
                return true
            }

            // forEach: (walkRaw, fnPtr) → inject closureRaw (can throw via callback)
            if callee == lookup.kkFileTreeWalkForEachName {
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                loweredBody.append(.call(
                    symbol: symbol,
                    callee: callee,
                    arguments: arguments + [zeroExpr],
                    result: result,
                    canThrow: canThrow,
                    thrownResult: thrownResult
                ))
                return true
            }

            // sortedBy: (walkRaw, fnPtr) → inject closureRaw → result is List<File>
            if callee == lookup.kkFileTreeWalkSortedByName {
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                loweredBody.append(.call(
                    symbol: symbol,
                    callee: callee,
                    arguments: arguments + [zeroExpr],
                    result: result,
                    canThrow: canThrow,
                    thrownResult: thrownResult
                ))
                if let result { state.listExprIDs.insert(result.rawValue) }
                return true
            }
        }

        // --- Append closureRaw argument for File lambda-accepting methods (STDLIB-322) ---
        // STDLIB-IO-FN-040: also covers `kk_buffered_reader_useLines`, the synthetic
        // stub for `kotlin.io.Reader.useLines` (resolved against `BufferedReader`).
        // STDLIB-IO-FN-017: also covers `kk_buffered_reader_forEachLine`, the synthetic
        // stub for `kotlin.io.Reader.forEachLine` (resolved against `BufferedReader`).
        // When the KIR callee is already rewritten via externalLinkName,
        // the lambda argument must be supplemented with closureRaw (0)
        // so the runtime receives (receiverRaw, fnPtr, closureRaw, outThrown).
        if callee == lookup.kkFileForEachLineName
            || callee == lookup.kkFileForEachBlockName
            || callee == lookup.kkFileForEachBlockBlockSizeName
            || callee == lookup.kkFileUseLinesName
            || callee == lookup.kkBufferedReaderUseLinesName
            || callee == lookup.kkBufferedReaderForEachLineName
            || callee == lookup.kkPathUseLinesName
            || callee == lookup.kkPathUseLinesDefaultName
        {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            loweredBody.append(.call(
                symbol: symbol,
                callee: callee,
                arguments: arguments + [zeroExpr],
                result: result,
                canThrow: canThrow,
                thrownResult: thrownResult
            ))
            return true
        }

        // --- FileTreeWalk HOF rewrites ---
        // walk().forEach { ... }  →  kk_file_tree_walk_forEach(walkRaw, fnPtr, closureRaw=0, outThrown)
        // walk().toList()         →  kk_file_tree_walk_to_list(walkRaw) → tagged as list
        if arguments.count >= 1, state.fileTreeWalkExprIDs.contains(arguments[0].rawValue) {
            let receiverID = arguments[0]
            if callee == lookup.forEachName, arguments.count >= 2 {
                let lambdaID = arguments[1]
                let closureRawID: KIRExprID
                if arguments.count >= 3 {
                    closureRawID = arguments[2]
                } else {
                    let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                    loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    closureRawID = zeroExpr
                }
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkFileTreeWalkForEachName,
                    arguments: [receiverID, lambdaID, closureRawID],
                    result: result,
                    canThrow: canThrow,
                    thrownResult: thrownResult
                ))
                return true
            }
            if callee == lookup.toListName {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkFileTreeWalkToListName,
                    arguments: [receiverID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                if let result { state.listExprIDs.insert(result.rawValue) }
                return true
            }
        }

        return false
    }
}
