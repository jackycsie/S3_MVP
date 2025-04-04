# S3_MVP - AWS S3 Desktop Client

A native macOS application for managing AWS S3 buckets and objects, built with SwiftUI and AWS SDK for Swift.

## Features

- **Authentication**
  - AWS credentials (Access Key and Secret Key) support
  - Region selection
  - Automatic region detection for buckets

- **Bucket Management**
  - List all accessible buckets
  - Create new buckets
  - Delete empty buckets
  - Cross-region bucket support

- **Object Management**
  - Browse objects and folders
  - Upload files (drag & drop supported)
  - Delete objects (single or multiple)
  - Navigate through folder hierarchies
  - Breadcrumb navigation
  - File properties display (size, type, storage class, last modified)

- **User Interface**
  - Clean and intuitive macOS native interface
  - Resizable window layout
  - Progress indicators for operations
  - Detailed error messages
  - Multi-column object list with sorting

## Requirements

- macOS 11.0 or later
- Xcode 13.0 or later
- AWS Account with appropriate IAM permissions:
  - `s3:ListBuckets`
  - `s3:CreateBucket`
  - `s3:DeleteBucket`
  - `s3:ListObjects`
  - `s3:PutObject`
  - `s3:DeleteObject`
  - `s3:GetBucketLocation`

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/S3_MVP.git
   ```

2. Open the project in Xcode:
   ```bash
   cd S3_MVP
   open S3_MVP.xcodeproj
   ```

3. Build and run the project in Xcode

## Usage

1. Launch the application
2. Enter your AWS credentials:
   - Access Key ID
   - Secret Access Key
   - Select your preferred region
3. Click "Connect" to access your S3 resources
4. Navigate through buckets and objects using the sidebar and main view
5. Use the toolbar buttons for various operations:
   - Upload files
   - Delete objects
   - Create new buckets

## Security

- Credentials are not stored permanently
- All communications with AWS are secured using HTTPS
- The application uses AWS SDK's built-in security features

## Known Limitations

- Maximum file upload size is limited by available memory
- Folder upload is not supported
- No file download feature yet
- No bucket policy management
- No versioning support

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Built with [AWS SDK for Swift](https://aws.amazon.com/sdk-for-swift/)
- Uses SwiftUI for the user interface
- Inspired by various S3 management tools

## Contact

If you have any questions or suggestions, please open an issue on GitHub. 