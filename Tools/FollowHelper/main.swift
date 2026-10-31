import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("缺少要启动的桌宠应用路径。\n", stderr)
    exit(64)
}
FollowMonitor.run(applicationURL: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
