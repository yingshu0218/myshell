// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MyShell",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MyShell", targets: ["MyShell"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/migueldeicaza/SwiftTerm.git",
            exact: "1.15.0"
        )
    ],
    targets: [
        .target(
            name: "CMyShellPTY",
            path: "Support/CMyShellPTY",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "MyShell",
            dependencies: [
                "CMyShellPTY",
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "MyShellTests",
            dependencies: ["MyShell"],
            path: "Tests"
        )
    ]
)
