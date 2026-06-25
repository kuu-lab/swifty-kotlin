package kotlin.io

import java.io.File

// MIGRATION-IO-003
// File 走査・操作関数を Kotlin source に移行する
// 移行元: Sources/Runtime/RuntimeFileIO.swift
//   kk_file_walk, kk_file_walkTopDown, kk_file_walkBottomUp,
//   kk_file_walk_with_direction, kk_file_tree_walk_*,
//   kk_file_copyTo, kk_file_copyRecursively,
//   kk_file_forEachLine, kk_file_useLines
//
// NOTE: Not yet wired into the compiler pipeline.
// Sema stubs in HeaderHelpers+SyntheticFileTreeWalkStubs.swift and
// HeaderHelpers+SyntheticFileIOStubs.swift dispatch directly to the
// kk_file_* ABI functions. This file is the migration target; wiring
// (and removal of the corresponding synthetic stubs and ABI entries)
// happens in a follow-up task.
//
// Dependencies when wiring:
//   - File.exists(), isDirectory(), isFile(), listFiles(), delete(), mkdirs()
//   - File.name, File.path properties
//   - File.readLines() -> List<String>
//   - List<T>.sortedBy() (MIGRATION-COL-006 / kk_list_sortedBy)

// ─── FileWalkDirection ────────────────────────────────────────────────────────

public enum class FileWalkDirection {
    TOP_DOWN, BOTTOM_UP
}

// ─── FileTreeWalk ──────────────────────────────────────────────────────────────
//
// Pure Kotlin implementation of kotlin.io.FileTreeWalk.
// Provides pre-order (TOP_DOWN) or post-order (BOTTOM_UP) traversal using
// File.listFiles() for directory contents, sorted alphabetically by name to
// ensure deterministic output matching the Swift ABI behaviour.

public class FileTreeWalk(
    private val start: File,
    private val direction: FileWalkDirection = FileWalkDirection.TOP_DOWN
) {
    private var maxDepthLimit: Int = Int.MAX_VALUE
    private var filterFn: ((File) -> Boolean)? = null
    private var onEnterFn: ((File) -> Boolean)? = null
    private var onLeaveFn: ((File) -> Unit)? = null
    private var onFailFn: ((File, Exception) -> Unit)? = null

    private fun copy(): FileTreeWalk {
        val c = FileTreeWalk(start, direction)
        c.maxDepthLimit = maxDepthLimit
        c.filterFn = filterFn
        c.onEnterFn = onEnterFn
        c.onLeaveFn = onLeaveFn
        c.onFailFn = onFailFn
        return c
    }

    public fun maxDepth(depth: Int): FileTreeWalk {
        val c = copy()
        c.maxDepthLimit = depth
        return c
    }

    public fun filter(predicate: (File) -> Boolean): FileTreeWalk {
        val c = copy()
        c.filterFn = predicate
        return c
    }

    public fun onEnter(function: (File) -> Boolean): FileTreeWalk {
        val c = copy()
        c.onEnterFn = function
        return c
    }

    public fun onLeave(function: (File) -> Unit): FileTreeWalk {
        val c = copy()
        c.onLeaveFn = function
        return c
    }

    public fun onFail(function: (File, Exception) -> Unit): FileTreeWalk {
        val c = copy()
        c.onFailFn = function
        return c
    }

    private fun collect(file: File, depth: Int, result: MutableList<File>) {
        val visible = filterFn?.invoke(file) ?: true

        if (direction == FileWalkDirection.TOP_DOWN && visible) {
            result.add(file)
        }

        if (file.isDirectory() && depth < maxDepthLimit) {
            val descend = onEnterFn?.invoke(file) ?: true
            if (descend) {
                val children = file.listFiles()
                if (children != null) {
                    for (child in children.sortedBy { it.name }) {
                        collect(child, depth + 1, result)
                    }
                }
            }
            onLeaveFn?.invoke(file)
        }

        if (direction == FileWalkDirection.BOTTOM_UP && visible) {
            result.add(file)
        }
    }

    public fun toList(): List<File> {
        val result = mutableListOf<File>()
        collect(start, 0, result)
        return result
    }

    public fun forEach(action: (File) -> Unit) {
        for (f in toList()) {
            action(f)
        }
    }

    public fun <R : Comparable<R>> sortedBy(selector: (File) -> R): List<File> =
        toList().sortedBy(selector)
}

// ─── File.walk extensions ─────────────────────────────────────────────────────

public fun File.walk(direction: FileWalkDirection = FileWalkDirection.TOP_DOWN): FileTreeWalk =
    FileTreeWalk(this, direction)

public fun File.walkTopDown(): FileTreeWalk = FileTreeWalk(this, FileWalkDirection.TOP_DOWN)

public fun File.walkBottomUp(): FileTreeWalk = FileTreeWalk(this, FileWalkDirection.BOTTOM_UP)

// ─── File.deleteRecursively ───────────────────────────────────────────────────

public fun File.deleteRecursively(): Boolean {
    if (isDirectory()) {
        val children = listFiles()
        if (children != null) {
            for (child in children) {
                if (!child.deleteRecursively()) return false
            }
        }
    }
    return delete() || !exists()
}

// ─── File.copyTo ─────────────────────────────────────────────────────────────
//
// Buffered byte-level file copy requires InputStream/OutputStream primitives
// not yet available as pure Kotlin in this build. Delegates to the Swift ABI
// bridge until MIGRATION-IO-002 provides pure-Kotlin streams.

@Suppress("UNCHECKED_CAST")
private external fun kk_file_copyTo(file: File, target: File, overwrite: Boolean, bufferSize: Int): File

public fun File.copyTo(
    target: File,
    overwrite: Boolean = false,
    bufferSize: Int = DEFAULT_BUFFER_SIZE
): File = kk_file_copyTo(this, target, overwrite, bufferSize)

// ─── File.copyRecursively ────────────────────────────────────────────────────

public fun File.copyRecursively(target: File, overwrite: Boolean = false): Boolean {
    if (!exists()) return false
    if (isDirectory()) {
        target.mkdirs()
        val children = listFiles() ?: return true
        for (child in children) {
            val childDst = File(target.path + "/" + child.name)
            if (!child.copyRecursively(childDst, overwrite)) return false
        }
        return true
    }
    copyTo(target, overwrite)
    return target.exists()
}

// ─── File.forEachLine ────────────────────────────────────────────────────────

public fun File.forEachLine(action: (String) -> Unit) {
    for (line in readLines()) {
        action(line)
    }
}

// ─── File.useLines ───────────────────────────────────────────────────────────

public fun <T> File.useLines(block: (List<String>) -> T): T = block(readLines())
