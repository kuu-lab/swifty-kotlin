fun main(args: Array<String>) {
    println("count=" + args.size)
    for (index in args.indices) {
        println("arg[" + index + "]=" + args[index] + "|utf16=" + args[index].length)
    }
}
