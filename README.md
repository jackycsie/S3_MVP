# S3 MVP Manager

A SwiftUI application for managing AWS S3 buckets with a modern and user-friendly interface.

## Features

- 🪣 Bucket Management
  - Create new buckets
  - List existing buckets
  - Delete buckets
- 📁 Object Operations
  - Upload files to buckets
  - List objects in buckets
  - Multi-select and delete objects
  - Navigate through bucket directories
- 🔐 Security
  - AWS credentials management
  - Region-specific operations
  - Secure file handling

## Requirements

- macOS 13.0 or later
- Xcode 15.0 or later
- AWS Account with appropriate S3 permissions
- Swift 5.9 or later

## Setup

1. Clone the repository
```bash
git clone https://github.com/jackycsie/S3_MVP.git
cd S3_MVP
```

2. Open the project in Xcode
```bash
open S3_MVP.xcodeproj
```

3. Configure AWS Credentials
- Add your AWS Access Key
- Add your AWS Secret Key
- Select your preferred AWS Region

4. Build and Run the project in Xcode

## Architecture

- Built with SwiftUI for modern UI
- Uses AWS SDK for Swift for S3 operations
- Follows MVVM architecture pattern
- Implements async/await for asynchronous operations

## Best Practices

- Secure credential handling
- Error handling with user-friendly messages
- Region-aware operations
- Efficient large file handling
- Modern Swift concurrency

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- AWS SDK for Swift
- SwiftUI Framework
- Apple Developer Documentation 