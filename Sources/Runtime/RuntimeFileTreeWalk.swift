import Foundation

// MARK: - RuntimeFileTreeWalkBox (STDLIB-IO-TYPE-004)
//
// Backs kotlin.io.FileTreeWalk. All modifier methods (maxDepth, onEnter,
// onLeave, onFail, filter) return a fresh copy so the builder chain is
// immutable — matching Kotlin stdlib semantics.
//
// Traversal is materialised on demand via kk_file_tree_walk_toList / forEach.
// Lambda callbacks reuse `runtimeInvokeCollectionLambda1/2` (same ABI as
// collection HOF lambdas: fnPtr + closureRaw pair).

final class RuntimeFileTreeWalkBox {
    let rootPath: String
    let direction: Int      // 0 = TOP_DOWN (default), 1 = BOTTOM_UP
    let maxDepthVal: Int    // inclusive depth limit; Int.max = unlimited
    // Predicate/action callbacks stored as (fnPtr, closureRaw) pairs.
    // A zero fnPtr means "not registered".
    let filterFnPtr: Int;   let filterClosure: Int
    let onEnterFnPtr: Int;  let onEnterClosure: Int
    let onLeaveFnPtr: Int;  let onLeaveClosure: Int
    let onFailFnPtr: Int;   let onFailClosure: Int

    init(
        rootPath: String,
        direction: Int = 0,
        maxDepth: Int = Int.max,
        filterFnPtr: Int = 0, filterClosure: Int = 0,
        onEnterFnPtr: Int = 0, onEnterClosure: Int = 0,
        onLeaveFnPtr: Int = 0, onLeaveClosure: Int = 0,
        onFailFnPtr: Int = 0, onFailClosure: Int = 0
    ) {
        self.rootPath = rootPath
        self.direction = direction
        self.maxDepthVal = maxDepth
        self.filterFnPtr = filterFnPtr
        self.filterClosure = filterClosure
        self.onEnterFnPtr = onEnterFnPtr
        self.onEnterClosure = onEnterClosure
        self.onLeaveFnPtr = onLeaveFnPtr
        self.onLeaveClosure = onLeaveClosure
        self.onFailFnPtr = onFailFnPtr
        self.onFailClosure = onFailClosure
    }

    // MARK: - Immutable builder helpers

    func with(maxDepth: Int) -> RuntimeFileTreeWalkBox {
        RuntimeFileTreeWalkBox(
            rootPath: rootPath, direction: direction, maxDepth: maxDepth,
            filterFnPtr: filterFnPtr, filterClosure: filterClosure,
            onEnterFnPtr: onEnterFnPtr, onEnterClosure: onEnterClosure,
            onLeaveFnPtr: onLeaveFnPtr, onLeaveClosure: onLeaveClosure,
            onFailFnPtr: onFailFnPtr, onFailClosure: onFailClosure
        )
    }

    func withFilter(fnPtr: Int, closure: Int) -> RuntimeFileTreeWalkBox {
        RuntimeFileTreeWalkBox(
            rootPath: rootPath, direction: direction, maxDepth: maxDepthVal,
            filterFnPtr: fnPtr, filterClosure: closure,
            onEnterFnPtr: onEnterFnPtr, onEnterClosure: onEnterClosure,
            onLeaveFnPtr: onLeaveFnPtr, onLeaveClosure: onLeaveClosure,
            onFailFnPtr: onFailFnPtr, onFailClosure: onFailClosure
        )
    }

    func withOnEnter(fnPtr: Int, closure: Int) -> RuntimeFileTreeWalkBox {
        RuntimeFileTreeWalkBox(
            rootPath: rootPath, direction: direction, maxDepth: maxDepthVal,
            filterFnPtr: filterFnPtr, filterClosure: filterClosure,
            onEnterFnPtr: fnPtr, onEnterClosure: closure,
            onLeaveFnPtr: onLeaveFnPtr, onLeaveClosure: onLeaveClosure,
            onFailFnPtr: onFailFnPtr, onFailClosure: onFailClosure
        )
    }

    func withOnLeave(fnPtr: Int, closure: Int) -> RuntimeFileTreeWalkBox {
        RuntimeFileTreeWalkBox(
            rootPath: rootPath, direction: direction, maxDepth: maxDepthVal,
            filterFnPtr: filterFnPtr, filterClosure: filterClosure,
            onEnterFnPtr: onEnterFnPtr, onEnterClosure: onEnterClosure,
            onLeaveFnPtr: fnPtr, onLeaveClosure: closure,
            onFailFnPtr: onFailFnPtr, onFailClosure: onFailClosure
        )
    }

    func withOnFail(fnPtr: Int, closure: Int) -> RuntimeFileTreeWalkBox {
        RuntimeFileTreeWalkBox(
            rootPath: rootPath, direction: direction, maxDepth: maxDepthVal,
            filterFnPtr: filterFnPtr, filterClosure: filterClosure,
            onEnterFnPtr: onEnterFnPtr, onEnterClosure: onEnterClosure,
            onLeaveFnPtr: onLeaveFnPtr, onLeaveClosure: onLeaveClosure,
            onFailFnPtr: fnPtr, onFailClosure: closure
        )
    }
}

// MARK: - Box helpers

private func treeWalkBox(from raw: Int) -> RuntimeFileTreeWalkBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeFileTreeWalkBox.self)
}

// Duplicate of the private runtimeFileBox helper in RuntimeFileIO.swift.
// Needed here because that helper is file-private.
private func fileBoxFromHandle(_ raw: Int) -> RuntimeFileBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeFileBox.self)
}

// MARK: - Factory

/// Creates a new FileTreeWalk rooted at the file described by `fileRaw`.
/// `directionRaw`: a boxed Int — 0 = TOP_DOWN, 1 = BOTTOM_UP.
/// `File.walkTopDown()` — thin wrapper for Sema stub (no direction argument).
@_cdecl("kk_file_walkTopDown")
public func kk_file_walkTopDown(_ fileRaw: Int) -> Int {
    kk_file_tree_walk_create(fileRaw, kk_box_int(0))
}

/// `File.walkBottomUp()` — thin wrapper for Sema stub (no direction argument).
@_cdecl("kk_file_walkBottomUp")
public func kk_file_walkBottomUp(_ fileRaw: Int) -> Int {
    kk_file_tree_walk_create(fileRaw, kk_box_int(1))
}

@_cdecl("kk_file_tree_walk_create")
public func kk_file_tree_walk_create(_ fileRaw: Int, _ directionRaw: Int) -> Int {
    guard let file = fileBoxFromHandle(fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_tree_walk_create received invalid File handle")
    }
    let box = RuntimeFileTreeWalkBox(
        rootPath: file.path,
        direction: kk_unbox_int(directionRaw)
    )
    return registerRuntimeObject(box)
}

// MARK: - Builder methods (all return new handles)

@_cdecl("kk_file_tree_walk_maxDepth")
public func kk_file_tree_walk_maxDepth(_ walkRaw: Int, _ depthRaw: Int) -> Int {
    guard let walk = treeWalkBox(from: walkRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_tree_walk_maxDepth received invalid FileTreeWalk handle")
    }
    let depth = max(0, kk_unbox_int(depthRaw))
    return registerRuntimeObject(walk.with(maxDepth: depth))
}

@_cdecl("kk_file_tree_walk_filter")
public func kk_file_tree_walk_filter(
    _ walkRaw: Int, _ fnPtr: Int, _ closureRaw: Int
) -> Int {
    guard let walk = treeWalkBox(from: walkRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_tree_walk_filter received invalid FileTreeWalk handle")
    }
    return registerRuntimeObject(walk.withFilter(fnPtr: fnPtr, closure: closureRaw))
}

@_cdecl("kk_file_tree_walk_onEnter")
public func kk_file_tree_walk_onEnter(
    _ walkRaw: Int, _ fnPtr: Int, _ closureRaw: Int
) -> Int {
    guard let walk = treeWalkBox(from: walkRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_tree_walk_onEnter received invalid FileTreeWalk handle")
    }
    return registerRuntimeObject(walk.withOnEnter(fnPtr: fnPtr, closure: closureRaw))
}

@_cdecl("kk_file_tree_walk_onLeave")
public func kk_file_tree_walk_onLeave(
    _ walkRaw: Int, _ fnPtr: Int, _ closureRaw: Int
) -> Int {
    guard let walk = treeWalkBox(from: walkRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_tree_walk_onLeave received invalid FileTreeWalk handle")
    }
    return registerRuntimeObject(walk.withOnLeave(fnPtr: fnPtr, closure: closureRaw))
}

@_cdecl("kk_file_tree_walk_onFail")
public func kk_file_tree_walk_onFail(
    _ walkRaw: Int, _ fnPtr: Int, _ closureRaw: Int
) -> Int {
    guard let walk = treeWalkBox(from: walkRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_tree_walk_onFail received invalid FileTreeWalk handle")
    }
    return registerRuntimeObject(walk.withOnFail(fnPtr: fnPtr, closure: closureRaw))
}

// MARK: - Traversal

/// Materialises the walk into a `RuntimeListBox` of File handles.
/// Applies `maxDepth`, `onEnter`, `onLeave`, `onFail` and `filter` as configured.
@_cdecl("kk_file_tree_walk_toList")
public func kk_file_tree_walk_toList(
    _ walkRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let walk = treeWalkBox(from: walkRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_tree_walk_toList received invalid FileTreeWalk handle")
    }
    var results: [Int] = []
    var thrown = 0
    runtimeFileTreeWalkCollect(
        path: walk.rootPath, depth: 0, walk: walk,
        results: &results, thrown: &thrown
    )
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    return registerRuntimeObject(RuntimeListBox(elements: results))
}

/// Iterates the walk, calling `fn(file)` for each yielded element.
@_cdecl("kk_file_tree_walk_forEach")
public func kk_file_tree_walk_forEach(
    _ walkRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let walk = treeWalkBox(from: walkRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_tree_walk_forEach received invalid FileTreeWalk handle")
    }
    var results: [Int] = []
    var collectThrown = 0
    runtimeFileTreeWalkCollect(
        path: walk.rootPath, depth: 0, walk: walk,
        results: &results, thrown: &collectThrown
    )
    if collectThrown != 0 {
        outThrown?.pointee = collectThrown
        return 0
    }
    for elem in results {
        var lambdaThrown = 0
        _ = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr, closureRaw: closureRaw, value: elem,
            outThrown: &lambdaThrown
        )
        if lambdaThrown != 0 {
            outThrown?.pointee = lambdaThrown
            return 0
        }
    }
    return 0
}

// MARK: - Traversal implementation

/// Recursive DFS entry point. Dispatches to the directory or regular-file path.
private func runtimeFileTreeWalkCollect(
    path: String,
    depth: Int,
    walk: RuntimeFileTreeWalkBox,
    results: inout [Int],
    thrown: inout Int
) {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return }

    let fileHandle = registerRuntimeObject(RuntimeFileBox(path))

    // Evaluate the user-supplied filter predicate (if any).
    let passesFilter: Bool
    if walk.filterFnPtr != 0 {
        var filterThrown = 0
        let r = runtimeInvokeCollectionLambda1(
            fnPtr: walk.filterFnPtr, closureRaw: walk.filterClosure,
            value: fileHandle, outThrown: &filterThrown
        )
        if filterThrown != 0 { thrown = filterThrown; return }
        passesFilter = runtimeCollectionBool(r)
    } else {
        passesFilter = true
    }

    if isDir.boolValue {
        runtimeFileTreeWalkDirectory(
            path: path, fileHandle: fileHandle,
            depth: depth, passesFilter: passesFilter,
            walk: walk, results: &results, thrown: &thrown
        )
    } else if passesFilter {
        results.append(fileHandle)
    }
}

/// Handles a single directory node. Manages TOP_DOWN / BOTTOM_UP ordering,
/// onEnter / onLeave callbacks, maxDepth pruning, and onFail on I/O errors.
private func runtimeFileTreeWalkDirectory(
    path: String,
    fileHandle: Int,
    depth: Int,
    passesFilter: Bool,
    walk: RuntimeFileTreeWalkBox,
    results: inout [Int],
    thrown: inout Int
) {
    // onEnter: called before descending. false → skip contents (dir is still yielded).
    var shouldDescend = true
    if walk.onEnterFnPtr != 0 {
        var enterThrown = 0
        let r = runtimeInvokeCollectionLambda1(
            fnPtr: walk.onEnterFnPtr, closureRaw: walk.onEnterClosure,
            value: fileHandle, outThrown: &enterThrown
        )
        if enterThrown != 0 { thrown = enterThrown; return }
        shouldDescend = runtimeCollectionBool(r)
    }

    // TOP_DOWN: yield directory first, contents after.
    if walk.direction == 0 && passesFilter {
        results.append(fileHandle)
    }

    if shouldDescend && depth < walk.maxDepthVal {
        // List immediate children, handling directory-read errors via onFail.
        let childNames: [String]
        do {
            childNames = try FileManager.default.contentsOfDirectory(atPath: path).sorted()
        } catch {
            if walk.onFailFnPtr != 0 {
                let exceptionHandle = runtimeAllocateThrowable(
                    message: "IOException: \(error.localizedDescription)"
                )
                var failThrown = 0
                _ = runtimeInvokeCollectionLambda2(
                    fnPtr: walk.onFailFnPtr, closureRaw: walk.onFailClosure,
                    lhs: fileHandle, rhs: exceptionHandle, outThrown: &failThrown
                )
                if failThrown != 0 { thrown = failThrown }
            }
            // Still yield in BOTTOM_UP even on read failure.
            if walk.direction == 1 && passesFilter {
                results.append(fileHandle)
            }
            return
        }

        for child in childNames {
            if thrown != 0 { return }
            let childPath = (path as NSString).appendingPathComponent(child)
            runtimeFileTreeWalkCollect(
                path: childPath, depth: depth + 1,
                walk: walk, results: &results, thrown: &thrown
            )
        }

        // onLeave: called after all contents have been visited.
        if walk.onLeaveFnPtr != 0 && thrown == 0 {
            var leaveThrown = 0
            _ = runtimeInvokeCollectionLambda1(
                fnPtr: walk.onLeaveFnPtr, closureRaw: walk.onLeaveClosure,
                value: fileHandle, outThrown: &leaveThrown
            )
            if leaveThrown != 0 { thrown = leaveThrown; return }
        }
    }

    // BOTTOM_UP: yield directory after its contents.
    if walk.direction == 1 && passesFilter {
        results.append(fileHandle)
    }
}
