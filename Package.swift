// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "S3_MVP",
    platforms: [
        .macOS(.v11),
        .iOS(.v13)
    ],
    dependencies: [
        .package(
            url: "https://github.com/awslabs/aws-sdk-swift",
            from: "1.0.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "S3_MVP",
            dependencies: [
                .product(name: "AWSS3", package: "aws-sdk-swift")
            ],
            path: "Sources")
    ]
) 