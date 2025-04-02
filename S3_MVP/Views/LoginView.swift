import SwiftUI

struct LoginView: View {
    @Binding var isLoggedIn: Bool
    @Binding var accessKey: String
    @Binding var secretKey: String
    @Binding var region: String
    
    @State private var isValidating = false
    @State private var errorMessage: String?
    @State private var connectionStatus: ConnectionStatus = .none
    
    private enum ConnectionStatus {
        case none
        case validating
        case success
        case failed(String)
        
        var color: Color {
            switch self {
            case .none:
                return .gray
            case .validating:
                return .orange
            case .success:
                return .green
            case .failed:
                return .red
            }
        }
        
        var icon: String {
            switch self {
            case .none:
                return "circle"
            case .validating:
                return "circle.dotted"
            case .success:
                return "checkmark.circle.fill"
            case .failed:
                return "exclamationmark.circle.fill"
            }
        }
        
        var message: String {
            switch self {
            case .none:
                return "尚未驗證連接"
            case .validating:
                return "正在驗證連接..."
            case .success:
                return "連接成功"
            case .failed(let error):
                return "連接失敗：\(error)"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("AWS S3 存儲桶列表")
                .font(.largeTitle)
                .padding(.bottom, 30)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Access Key")
                    .foregroundColor(.secondary)
                SecureField("請輸入 Access Key", text: $accessKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 400)
                    .onChange(of: accessKey) { _ in
                        validateIfReady()
                    }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Secret Key")
                    .foregroundColor(.secondary)
                SecureField("請輸入 Secret Key", text: $secretKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 400)
                    .onChange(of: secretKey) { _ in
                        validateIfReady()
                    }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Region")
                    .foregroundColor(.secondary)
                Picker("選擇區域", selection: $region) {
                    Text("美國東部 (us-east-1)").tag("us-east-1")
                    Text("東京 (ap-northeast-1)").tag("ap-northeast-1")
                    Text("新加坡 (ap-southeast-1)").tag("ap-southeast-1")
                    Text("美國西部 (us-west-2)").tag("us-west-2")
                }
                .frame(width: 400)
                .onChange(of: region) { _ in
                    validateIfReady()
                }
            }
            
            // 連接狀態顯示
            HStack {
                Image(systemName: connectionStatus.icon)
                    .foregroundColor(connectionStatus.color)
                Text(connectionStatus.message)
                    .foregroundColor(connectionStatus.color)
                if case .validating = connectionStatus {
                    ProgressView()
                        .scaleEffect(0.5)
                        .padding(.leading, 5)
                }
            }
            .padding()
            .frame(height: 50)
            
            Button(action: {
                Task {
                    await login()
                }
            }) {
                if isValidating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .frame(width: 100)
                } else {
                    Text("登入")
                        .frame(width: 100)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(accessKey.isEmpty || secretKey.isEmpty || isValidating || !isConnectionSuccessful)
        }
        .padding()
    }
    
    private func validateIfReady() {
        guard !accessKey.isEmpty && !secretKey.isEmpty else {
            connectionStatus = .none
            return
        }
        
        Task {
            await validateConnection()
        }
    }
    
    private func validateConnection() async {
        guard !isValidating else { return }
        
        connectionStatus = .validating
        isValidating = true
        
        do {
            let isValid = try await AWSCredentialUtility.validateCredentials(
                accessKey: accessKey,
                secretKey: secretKey,
                region: region
            )
            
            if isValid {
                connectionStatus = .success
            }
        } catch let error as AWSCredentialError {
            connectionStatus = .failed(error.localizedDescription)
        } catch {
            connectionStatus = .failed(error.localizedDescription)
        }
        
        isValidating = false
    }
    
    private func login() async {
        isValidating = true
        
        do {
            let isValid = try await AWSCredentialUtility.validateCredentials(
                accessKey: accessKey,
                secretKey: secretKey,
                region: region
            )
            
            if isValid {
                isLoggedIn = true
            }
        } catch {
            connectionStatus = .failed(error.localizedDescription)
        }
        
        isValidating = false
    }
    
    private var isConnectionSuccessful: Bool {
        if case .success = connectionStatus {
            return true
        }
        return false
    }
} 