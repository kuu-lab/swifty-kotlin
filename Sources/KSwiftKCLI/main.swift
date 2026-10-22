import Foundation

let args = Array(ProcessInfo.processInfo.arguments.dropFirst())
exit(CLIApplication.run(args: args))
