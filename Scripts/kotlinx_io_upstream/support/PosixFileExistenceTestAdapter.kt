// Candidate test support only. This is not a product CInterop implementation.
// Pinned tempFileName uses normalized temporary Path plus a slash and hex name.
package platform.posix

import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem

public const val F_OK: Int = 0

public fun access(path: String, mode: Int): Int {
    require(mode == F_OK) { "The upstream file test adapter only supports F_OK (0)." }
    val normalized = Path(path)
    require(normalized.toString() == path) {
        "The upstream file test adapter only supports canonical Path input."
    }
    return if (SystemFileSystem.exists(normalized)) 0 else -1
}
