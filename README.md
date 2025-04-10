# S3_MVP - AWS S3 Client for macOS

A native macOS application built with SwiftUI for managing AWS S3 buckets and objects.

## Features

- 🔐 Secure AWS credentials management
- 📂 Bucket management (create, delete, list)
- 📁 Folder operations (create folders)
- 📄 File operations (upload, delete)
- 🌐 Multi-region support
- 📱 Native macOS UI with SwiftUI
- 🔄 Real-time updates
- ✨ Drag and drop file upload

## Requirements

- macOS 11.0 or later
- Xcode 13.0 or later
- AWS Account with S3 access

## Dependencies

- SwiftUI
- AWSClientRuntime
- AWSS3
- AWSSDKIdentity
- AWSSTS
- ClientRuntime

## Installation

1. Clone the repository
2. Open the project in Xcode
3. Build and run the application

## Usage

1. Launch the application
2. Enter your AWS credentials:
   - Access Key
   - Secret Key
   - Select Region
3. Click "Connect" to access your S3 buckets

### Bucket Operations
- Create new buckets
- Delete existing buckets
- View bucket contents

### File Operations
- Create folders (supports double-slash format)
- Upload files via drag & drop or file picker
- Delete files and folders
- Navigate through folder hierarchy

## Recent Updates

### Version 1.1.0
- Added folder creation with double-slash format
- Improved folder navigation
- Enhanced error handling and user feedback
- Updated UI elements for better user experience

## Security

This application handles AWS credentials locally and securely. No credentials are stored or transmitted outside of the application.

## Contributing

Feel free to submit issues and enhancement requests.

## License

[MIT License](LICENSE)

## Disclaimer

This is a minimal viable product (MVP) and should be used with caution in production environments. 