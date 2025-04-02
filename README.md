# S3_MVP - AWS S3 Client for macOS

A native macOS application for managing AWS S3 buckets and objects, built with SwiftUI.

## Features

- AWS S3 Bucket Management
  - List all buckets
  - Create new buckets
  - Delete empty buckets
  - Automatic region detection and switching

- Object Operations
  - Browse objects with folder hierarchy
  - Upload files via drag-and-drop or file picker
  - Delete single or multiple objects
  - Navigate through folders
  - Display file sizes and last modified dates

- User Interface
  - Modern macOS native interface built with SwiftUI
  - Split view layout with bucket list and object browser
  - Progress indicators for operations
  - Detailed error messages and feedback
  - Dark mode support

## Requirements

- macOS 11.0 or later
- Xcode 13.0 or later
- AWS Account with S3 access
- Valid AWS Access Key and Secret Key with appropriate permissions

## Installation

1. Clone the repository
```bash
git clone https://github.com/jackycsie/S3_MVP.git
```

2. Open the project in Xcode
```bash
cd S3_MVP
open S3_MVP.xcodeproj
```

3. Build and run the application

## Usage

1. Launch the application
2. Enter your AWS credentials:
   - Access Key
   - Secret Key
   - Region (default: us-east-1)
3. Click "Login" to connect to AWS
4. Browse your buckets and objects
5. Use the toolbar buttons or drag-and-drop to perform operations

## Security

- Credentials are stored securely in macOS Keychain
- Application runs in sandboxed environment
- All communications with AWS are encrypted
- No data is stored locally except for credentials

## Development

The project follows the GitFlow workflow:
- `main`: Production releases
- `develop`: Development branch
- `feature/*`: New features
- `hotfix/*`: Critical fixes
- `release/*`: Release preparation

## Building DMG

To create a DMG file for distribution:

1. Build the project in Xcode
2. Run the create_dmg script:
```bash
chmod +x create_dmg.sh
./create_dmg.sh
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## Acknowledgments

- Built with SwiftUI
- Uses AWS SDK for Swift
- Inspired by AWS Console interface 