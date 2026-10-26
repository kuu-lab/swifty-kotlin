package java.lang

import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_process_start")
private external fun __startProcess(command: String): kotlin.Long

public class ProcessBuilder(vararg command: String) {
    private var commandArguments: MutableList<String> = command.toMutableList()

    public fun command(): MutableList<String> = commandArguments

    public fun command(command: List<String>): ProcessBuilder {
        commandArguments = command.toMutableList()
        return this
    }

    public fun command(vararg command: String): ProcessBuilder {
        commandArguments = command.toMutableList()
        return this
    }

    public fun start(): Process {
        if (commandArguments.isEmpty()) throw IllegalArgumentException("command is empty")
        if (commandArguments.any { it.contains('\u0000') }) {
            throw IllegalArgumentException("command contains a null character")
        }
        val handle = __startProcess(commandArguments.joinToString(separator = "\u0000"))
        if (handle == 0L) throw IllegalStateException("Unable to start process")
        return Process(handle)
    }
}
