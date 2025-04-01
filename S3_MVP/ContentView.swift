import SwiftUI
import AWSClientRuntime
import AWSS3
import AWSSDKIdentity
import AWSSTS
import ClientRuntime

extension URLRequest {
    init(url: URL, timeoutInterval: TimeInterval, httpMethod: String, headers: [String: String]) {
        self.init(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeoutInterval)
        self.httpMethod = httpMethod
        headers.forEach { self.setValue($1, forHTTPHeaderField: $0) }
    }
}

struct S3Item: Identifiable, Hashable {
    let id = UUID()
    let key: String
    let size: Int64?
    let lastModified: Date?
    let isFolder: Bool
    
    static func == (lhs: S3Item, rhs: S3Item) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct ContentView: View {
    @State private var bucketNames: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var accessKey: String = ""
    @State private var secretKey: String = ""
    @State private var region: String = "us-east-1" // 改為美國東部區域
    @State private var isValidating = false
    @State private var validationMessage: String?
    @State private var isTestingConnection = false
    @State private var connectionTestResult: String?
    @State private var connectionTestColor: Color = .black
    @State private var connectionStatus: [String: Bool] = [:]
    @State private var selectedBucket: String?
    @State private var currentPath: String = ""
    @State private var objects: [S3Item] = []
    @State private var isLoadingObjects = false
    @State private var objectsError: String?
    @State private var navigationStack: [(bucket: String, prefix: String)] = []
    @State private var isShowingCreateBucketSheet = false
    @State private var newBucketName = ""
    @State private var isCreatingBucket = false
    @State private var isDeletingBucket = false
    @State private var bucketToDelete: String?
    @State private var showDeleteAlert = false
    @State private var selectedObjects: Set<String> = []
    @State private var isDeletingObjects = false
    @State private var deleteError: String? = nil
    @State private var currentBucket: String? = nil
    @State private var currentPrefix: String = ""
    @State private var isShowingFilePicker = false
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0
    @State private var uploadError: String? = nil
    
    var body: some View {
        HSplitView {
            // 左側存儲桶列表
            VStack {
                // 添加工具欄
                HStack {
                    Button(action: {
                        isShowingCreateBucketSheet = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                        Text("新增存儲桶")
                    }
                    .disabled(isCreatingBucket)
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                if !bucketNames.isEmpty {
                    List(bucketNames, id: \.self) { name in
                        HStack {
                            Text(name)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectBucket(name)
                                }
                            
                            Spacer()
                            
                            // 刪除按鈕
                            Button(action: {
                                bucketToDelete = name
                                showDeleteAlert = true
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        .background(selectedBucket == name ? Color.blue.opacity(0.2) : Color.clear)
                    }
                } else {
                    VStack {
                        Spacer()
                        Text("尚未獲取存儲桶列表")
                            .foregroundColor(.gray)
                        Spacer()
                    }
                }
            }
            .frame(minWidth: 200, maxWidth: .infinity)
            .sheet(isPresented: $isShowingCreateBucketSheet) {
                CreateBucketView(
                    isPresented: $isShowingCreateBucketSheet,
                    bucketName: $newBucketName,
                    region: $region,
                    isCreating: $isCreatingBucket,
                    onCreate: { name in
                        Task {
                            await createBucket(name: name)
                        }
                    }
                )
            }
            .alert("確認刪除", isPresented: $showDeleteAlert) {
                Button("取消", role: .cancel) {}
                Button("刪除", role: .destructive) {
                    if let bucket = bucketToDelete {
                        Task {
                            await deleteBucket(name: bucket)
                        }
                    }
                }
            } message: {
                if let bucket = bucketToDelete {
                    Text("確定要刪除存儲桶 '\(bucket)' 嗎？此操作無法撤銷。")
                }
            }
            
            // 右側內容
            if let selectedBucket = selectedBucket {
                VStack {
                    // 導航欄
                    HStack {
                        Button(action: {
                            if navigationStack.count > 1 {
                                navigationStack.removeLast()
                                let previous = navigationStack.last!
                                Task {
                                    await listObjects(bucket: previous.bucket, prefix: previous.prefix)
                                }
                                currentPath = previous.prefix
                            }
                        }) {
                            Image(systemName: "arrow.left")
                            Text("返回")
                        }
                        .disabled(navigationStack.count <= 1)
                        
                        Spacer()
                        
                        Text("當前路徑：/\(currentPath)")
                            .foregroundColor(.gray)
                        
                        Spacer()
                        
                        Button("刷新") {
                            Task {
                                if let current = navigationStack.last {
                                    await listObjects(bucket: current.bucket, prefix: current.prefix)
                                }
                            }
                        }
                    }
                    .padding()
                    
                    if isLoadingObjects {
                        ProgressView("正在加載...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = objectsError {
                        Text(error)
                            .foregroundColor(.red)
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
        VStack {
                            // 頂部工具欄
                            HStack {
                                // 新增按鈕
                                Button(action: {
                                    isShowingFilePicker = true
                                }) {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text("上傳文件")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .fileImporter(
                                    isPresented: $isShowingFilePicker,
                                    allowedContentTypes: [.item],
                                    allowsMultipleSelection: false
                                ) { result in
                                    switch result {
                                    case .success(let files):
                                        if let fileURL = files.first {
                                            Task {
                                                await uploadFile(from: fileURL)
                                            }
                                        }
                                    case .failure(let error):
                                        uploadError = "選擇文件失敗：\(error.localizedDescription)"
                                    }
                                }
                                
                                if isUploading {
                                    ProgressView("上傳中... \(Int(uploadProgress * 100))%")
                                        .padding(.leading)
                                }
                                
                                Spacer()
                                
                                if !selectedObjects.isEmpty {
                                    Text("已選擇 \(selectedObjects.count) 個項目")
                                        .foregroundColor(.secondary)
                                    
                                    Button(action: {
                                        selectedObjects.removeAll()
                                    }) {
                                        Text("取消選擇")
                                    }
                                    .buttonStyle(.borderless)
                                    
                                    Button(action: {
                                        Task {
                                            await deleteSelectedObjects()
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: "trash")
                                            Text("刪除選中項目")
                                        }
                                    }
                                    .disabled(isDeletingObjects)
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
                                }
                            }
                            .padding(.bottom, 8)
                            
                            if let error = uploadError {
                                Text(error)
                                    .foregroundColor(.red)
                                    .padding()
                            }
                            
                            if isDeletingObjects {
                                ProgressView("正在刪除...")
                                    .padding()
                            }
                            
                            if let error = deleteError {
                                Text(error)
                                    .foregroundColor(.red)
                                    .padding()
                            }
                            
                            if objects.isEmpty {
                                Text("此目錄為空")
                                    .foregroundColor(.gray)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                // 對象列表
                                List {
                                    ForEach(objects) { item in
                                        HStack {
                                            Image(systemName: item.isFolder ? "folder" : "doc")
                                                .foregroundColor(item.isFolder ? .blue : .gray)
                                            
                                            VStack(alignment: .leading) {
                                                Text(item.key.replacingOccurrences(of: currentPrefix, with: ""))
                                                if !item.isFolder, let size = item.size {
                                                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            
                                            Spacer()
                                            
                                            if !item.isFolder {
                                                Toggle(isOn: Binding(
                                                    get: { selectedObjects.contains(item.key) },
                                                    set: { isSelected in
                                                        if isSelected {
                                                            selectedObjects.insert(item.key)
                                                        } else {
                                                            selectedObjects.remove(item.key)
                                                        }
                                                    }
                                                )) {
                                                    EmptyView()
                                                }
                                                .toggleStyle(CheckboxToggleStyle())
                                            }
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if item.isFolder {
                                                currentPrefix = item.key
                                                if let bucket = currentBucket {
                                                    Task {
                                                        await listObjects(bucket: bucket, prefix: item.key)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 顯示原有的控制面板
                VStack(spacing: 20) {
                    Text("AWS S3 存儲桶列表")
                        .font(.title)
                        .padding()
                    
                    TextField("Access Key", text: $accessKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.horizontal)
                    
                    SecureField("Secret Key", text: $secretKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.horizontal)
                    
                    Picker("Region", selection: $region) {
                        Text("美國東部 (us-east-1)").tag("us-east-1")
                        Text("東京 (ap-northeast-1)").tag("ap-northeast-1")
                        Text("新加坡 (ap-southeast-1)").tag("ap-southeast-1")
                        Text("美國西部 (us-west-2)").tag("us-west-2")
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding(.horizontal)
                    
                    Button(action: {
                        Task {
                            await testConnection()
                        }
                    }) {
                        if isTestingConnection {
                            HStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("測試連接中...")
                                    .foregroundColor(.white)
                            }
                        } else {
                            Text("測試連接")
                                .foregroundColor(.white)
                        }
                    }
                    .padding()
                    .background(isTestingConnection ? Color.gray : Color.orange)
                    .cornerRadius(10)
                    .disabled(isTestingConnection)
                    
                    if let result = connectionTestResult {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(connectionStatus.sorted(by: { $0.key < $1.key }), id: \.key) { endpoint, isConnected in
                                HStack {
                                    Image(systemName: isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(isConnected ? .green : .red)
                                    Text(endpoint)
                                    Spacer()
                                    Text(isConnected ? "已連接" : "未連接")
                                        .foregroundColor(isConnected ? .green : .red)
                                }
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }
                    
                    HStack(spacing: 20) {
                        Button("驗證憑證") {
                            Task {
                                await validateCredentials()
                            }
                        }
                        .padding()
                        .foregroundColor(.white)
                        .background(Color.green)
                        .cornerRadius(10)
                        .disabled(isValidating || isLoading)
                        
                        Button("獲取存儲桶列表") {
                            Task {
                                await listBuckets()
                            }
                        }
                        .padding()
                        .foregroundColor(.white)
                        .background(Color.blue)
                        .cornerRadius(10)
                        .disabled(isLoading || isValidating)
                    }
                    
                    if isValidating {
                        ProgressView("正在驗證憑證...")
                    } else if isLoading {
                        ProgressView("正在獲取存儲桶列表...")
                    }
                    
                    if let validation = validationMessage {
                        Text(validation)
                            .foregroundColor(validation.contains("成功") ? .green : .red)
                            .padding()
                            .multilineTextAlignment(.center)
                    }
                    
                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .padding()
                            .multilineTextAlignment(.center)
                    }
                    
                    Spacer()
                }
                .frame(minWidth: 400, maxWidth: .infinity)
                .padding()
            }
        }
    }
    
    func testConnection() async {
        let endpoints = [
            "sts.\(region).amazonaws.com",
            "s3.\(region).amazonaws.com"
        ]
        
        DispatchQueue.main.async {
            self.isTestingConnection = true
            self.connectionTestResult = "正在測試連接..."
            self.connectionTestColor = .orange
            self.connectionStatus.removeAll()
        }
        
        for endpoint in endpoints {
            let urlString = "https://\(endpoint)"
            guard let url = URL(string: urlString) else { continue }
            
            do {
                let request = URLRequest(url: url)
                let (_, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    let isSuccess = (200...499).contains(httpResponse.statusCode)
                    DispatchQueue.main.async {
                        self.connectionStatus[endpoint] = isSuccess
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.connectionStatus[endpoint] = false
                }
            }
            
            // 添加短暫延遲
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        DispatchQueue.main.async {
            let allConnected = self.connectionStatus.values.allSatisfy { $0 }
            self.connectionTestResult = allConnected ? "所有服務都可以連接" : "部分服務無法連接"
            self.connectionTestColor = allConnected ? .green : .red
            self.isTestingConnection = false
        }
    }
    
    private func getErrorSolution(for error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet:
            return "請檢查您的網絡連接是否正常"
        case .timedOut:
            return "連接超時，請檢查網絡速度或嘗試其他網絡"
        case .cannotFindHost:
            return "無法找到服務器，請檢查 DNS 設置或嘗試其他區域"
        case .cannotConnectToHost:
            return "無法連接到服務器，可能是防火牆限制或網絡問題"
        case .networkConnectionLost:
            return "網絡連接中斷，請檢查網絡穩定性"
        case .dnsLookupFailed:
            return "DNS 查詢失敗，請檢查 DNS 設置或切換網絡"
        default:
            return "請檢查網絡連接和設置，或嘗試切換到其他網絡"
        }
    }
    
    func validateCredentials() async {
        isValidating = true
        validationMessage = nil
        
        guard !accessKey.isEmpty else {
            validationMessage = "請輸入 Access Key"
            isValidating = false
            return
        }
        
        guard !secretKey.isEmpty else {
            validationMessage = "請輸入 Secret Key"
            isValidating = false
            return
        }
        
        do {
            let credentials = AWSCredentialIdentity(
                accessKey: accessKey,
                secret: secretKey
            )
            
            let identityResolver = try StaticAWSCredentialIdentityResolver(credentials)
            
            let stsConfig = try await STSClient.STSClientConfiguration(
                awsCredentialIdentityResolver: identityResolver,
                region: region
            )
            
            let stsClient = STSClient(config: stsConfig)
            
            let response = try await stsClient.getCallerIdentity(input: GetCallerIdentityInput())
            
            DispatchQueue.main.async {
                self.validationMessage = """
                憑證驗證成功！
                帳戶 ID: \(response.account ?? "未知")
                用戶 ARN: \(response.arn ?? "未知")
                """
                self.isValidating = false
            }
        } catch {
            DispatchQueue.main.async {
                self.validationMessage = """
                憑證驗證失敗：
                \(error.localizedDescription)
                
                請檢查：
                1. Access Key 是否正確
                2. Secret Key 是否正確
                3. 網絡連接是否正常
                4. 憑證是否有效
                """
                self.isValidating = false
            }
        }
    }
    
    func listBuckets() async {
        isLoading = true
        errorMessage = nil
        
        guard !accessKey.isEmpty else {
            errorMessage = "請輸入 Access Key"
            isLoading = false
            return
        }
        
        guard !secretKey.isEmpty else {
            errorMessage = "請輸入 Secret Key"
            isLoading = false
            return
        }
        
        do {
            // 創建憑證身份
            let credentials = AWSCredentialIdentity(
                accessKey: accessKey,
                secret: secretKey
            )
            
            // 創建靜態憑證解析器
            let identityResolver = try StaticAWSCredentialIdentityResolver(credentials)
            
            // 設置 S3 配置
            let s3Configuration = try await S3Client.S3ClientConfiguration(
                awsCredentialIdentityResolver: identityResolver,
                region: region
            )
            
            // 創建 S3 客戶端
            let client = S3Client(config: s3Configuration)
            
            // 列出 S3 儲存桶
            let response = try await client.listBuckets(input: ListBucketsInput())
            
            DispatchQueue.main.async {
                self.bucketNames = response.buckets?.compactMap { $0.name } ?? []
                self.isLoading = false
                if self.bucketNames.isEmpty {
                    self.errorMessage = "未找到任何存儲桶"
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = """
                錯誤：\(error.localizedDescription)
                
                可能的原因：
                1. Access Key 或 Secret Key 不正確
                2. 網絡連接問題：
                   - 檢查 DNS 設置
                   - 檢查網絡連接
                   - 嘗試使用其他網絡
                3. 選擇的區域不正確
                4. 憑證沒有足夠的權限
                
                請檢查以上問題並重試
                
                技術細節：
                Region: \(region)
                """
                self.isLoading = false
            }
        }
    }
    
    func listObjects(bucket: String, prefix: String) async {
        isLoadingObjects = true
        objectsError = nil
        objects = []
        
        do {
            let credentials = AWSCredentialIdentity(
                accessKey: accessKey,
                secret: secretKey
            )
            
            let identityResolver = try StaticAWSCredentialIdentityResolver(credentials)
            
            // 首先嘗試使用當前區域
            var currentRegion = region
            var client: S3Client
            
            // 創建初始客戶端
            let initialConfig = try await S3Client.S3ClientConfiguration(
                awsCredentialIdentityResolver: identityResolver,
                region: currentRegion
            )
            client = S3Client(config: initialConfig)
            
            // 嘗試獲取存儲桶的實際區域
            let locationInput = GetBucketLocationInput(bucket: bucket)
            do {
                let locationResponse = try await client.getBucketLocation(input: locationInput)
                if let bucketRegion = locationResponse.locationConstraint?.rawValue {
                    // 如果返回空字符串，表示是 us-east-1
                    currentRegion = bucketRegion.isEmpty ? "us-east-1" : bucketRegion
                    
                    // 如果區域不同，創建新的客戶端
                    if currentRegion != region {
                        let newConfig = try await S3Client.S3ClientConfiguration(
                            awsCredentialIdentityResolver: identityResolver,
                            region: currentRegion
                        )
                        client = S3Client(config: newConfig)
                    }
                }
            } catch {
                // 如果獲取位置失敗，記錄錯誤但繼續嘗試列出對象
                print("獲取存儲桶位置時出錯：\(error.localizedDescription)")
            }
            
            let input = ListObjectsV2Input(
                bucket: bucket,
                delimiter: "/",
                maxKeys: 1000,
                prefix: prefix
            )
            
            let response = try await client.listObjectsV2(input: input)
            
            DispatchQueue.main.async {
                // 處理文件夾
                let folders = (response.commonPrefixes ?? []).map { prefix in
                    S3Item(
                        key: prefix.prefix ?? "",
                        size: nil,
                        lastModified: nil,
                        isFolder: true
                    )
                }
                
                // 處理文件
                let files = (response.contents ?? []).filter { $0.key != prefix }.map { object in
                    S3Item(
                        key: object.key ?? "",
                        size: object.size != nil ? Int64(object.size!) : nil,
                        lastModified: object.lastModified,
                        isFolder: false
                    )
                }
                
                // 合併結果，文件夾在前
                self.objects = folders + files
                self.isLoadingObjects = false
            }
        } catch let error as AWSServiceError {
            DispatchQueue.main.async {
                self.objectsError = """
                無法獲取對象列表：
                \(error.message ?? "未知錯誤")
                
                請檢查：
                1. 存儲桶區域設置（當前：\(region)）
                2. 是否有足夠的訪問權限
                3. 存儲桶是否存在
                4. 網絡連接是否正常
                
                如果確定權限正確但仍然無法訪問，
                可能是因為存儲桶在其他區域，
                請嘗試在控制面板中切換到正確的區域後重試。
                """
                self.isLoadingObjects = false
            }
        } catch {
            DispatchQueue.main.async {
                self.objectsError = """
                訪問存儲桶失敗：
                \(error.localizedDescription)
                
                可能原因：
                1. 網絡連接問題
                2. 存儲桶區域不匹配
                3. 權限不足
                
                當前區域：\(region)
                """
                self.isLoadingObjects = false
            }
        }
    }
    
    private func formatFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "未知" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // 新增存儲桶
    func createBucket(name: String) async {
        isCreatingBucket = true
        
        do {
            let credentials = AWSCredentialIdentity(
                accessKey: accessKey,
                secret: secretKey
            )
            
            let identityResolver = try StaticAWSCredentialIdentityResolver(credentials)
            
            let s3Configuration = try await S3Client.S3ClientConfiguration(
                awsCredentialIdentityResolver: identityResolver,
                region: region
            )
            
            let client = S3Client(config: s3Configuration)
            
            let input = CreateBucketInput(
                bucket: name,
                createBucketConfiguration: region == "us-east-1" ? nil : .init(locationConstraint: .init(rawValue: region))
            )
            
            _ = try await client.createBucket(input: input)
            
            // 重新獲取存儲桶列表
            await listBuckets()
            
            DispatchQueue.main.async {
                self.isCreatingBucket = false
                self.isShowingCreateBucketSheet = false
                self.newBucketName = ""
            }
        } catch let error as AWSServiceError {
            DispatchQueue.main.async {
                self.errorMessage = """
                創建存儲桶失敗：
                \(error.message ?? "未知錯誤")
                
                可能的原因：
                1. 存儲桶名稱已被使用（S3 存儲桶名稱在全球範圍內必須唯一）
                2. 存儲桶名稱不符合命名規則
                3. 沒有足夠的權限（需要 s3:CreateBucket 權限）
                4. 網絡連接問題
                5. 區域設置問題（當前區域：\(region)）
                
                請確保：
                1. 存儲桶名稱全局唯一
                2. 名稱符合 S3 命名規則
                3. IAM 用戶具有創建存儲桶的權限
                4. 選擇了正確的區域
                """
                self.isCreatingBucket = false
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = """
                創建存儲桶失敗：
                \(error.localizedDescription)
                
                請檢查網絡連接和權限設置。
                當前區域：\(region)
                """
                self.isCreatingBucket = false
            }
        }
    }
    
    // 刪除存儲桶
    func deleteBucket(name: String) async {
        isDeletingBucket = true
        
        do {
            let credentials = AWSCredentialIdentity(
                accessKey: accessKey,
                secret: secretKey
            )
            
            let identityResolver = try StaticAWSCredentialIdentityResolver(credentials)
            
            let s3Configuration = try await S3Client.S3ClientConfiguration(
                awsCredentialIdentityResolver: identityResolver,
                region: region
            )
            
            let client = S3Client(config: s3Configuration)
            
            let input = DeleteBucketInput(bucket: name)
            
            _ = try await client.deleteBucket(input: input)
            
            // 如果刪除的是當前選中的存儲桶，清除選擇
            if selectedBucket == name {
                DispatchQueue.main.async {
                    self.selectedBucket = nil
                    self.currentPath = ""
                    self.objects = []
                }
            }
            
            // 重新獲取存儲桶列表
            await listBuckets()
            
            DispatchQueue.main.async {
                self.isDeletingBucket = false
                self.bucketToDelete = nil
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = """
                刪除存儲桶失敗：
                \(error.localizedDescription)
                
                可能的原因：
                1. 存儲桶不為空
                2. 沒有足夠的權限
                3. 網絡連接問題
                """
                self.isDeletingBucket = false
                self.bucketToDelete = nil
            }
        }
    }
    
    // 當選擇存儲桶時更新 currentBucket
    func selectBucket(_ name: String) {
        selectedBucket = name
        currentBucket = name
        currentPrefix = ""
        currentPath = ""
        navigationStack = [(bucket: name, prefix: "")]
        selectedObjects.removeAll()
        Task {
            await listObjects(bucket: name, prefix: "")
        }
    }
    
    // 刪除選中的對象
    func deleteSelectedObjects() async {
        isDeletingObjects = true
        deleteError = nil
        
        do {
            let credentials = AWSCredentialIdentity(
                accessKey: accessKey,
                secret: secretKey
            )
            
            let identityResolver = try StaticAWSCredentialIdentityResolver(credentials)
            let s3Configuration = try await S3Client.S3ClientConfiguration(
                awsCredentialIdentityResolver: identityResolver,
                region: region
            )
            
            let client = S3Client(config: s3Configuration)
            
            guard let bucket = currentBucket else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "未選擇存儲桶"])
            }
            
            // 創建刪除請求
            let objectsToDelete = selectedObjects.map { S3ClientTypes.ObjectIdentifier(key: $0) }
            let input = DeleteObjectsInput(
                bucket: bucket,
                delete: S3ClientTypes.Delete(objects: objectsToDelete)
            )
            
            // 執行刪除
            let response = try await client.deleteObjects(input: input)
            
            // 檢查是否有刪除失敗的對象
            if let errors = response.errors, !errors.isEmpty {
                let errorMessages = errors.map { error in
                    "• \(error.key ?? "未知對象"): \(error.message ?? "未知錯誤")"
                }.joined(separator: "\n")
                
                DispatchQueue.main.async {
                    self.deleteError = """
                    部分對象刪除失敗：
                    \(errorMessages)
                    """
                }
            }
            
            // 重新加載對象列表
            await listObjects(bucket: bucket, prefix: currentPrefix)
            
            DispatchQueue.main.async {
                self.selectedObjects.removeAll()
                self.isDeletingObjects = false
            }
            
        } catch {
            DispatchQueue.main.async {
                self.deleteError = """
                刪除對象時發生錯誤：
                \(error.localizedDescription)
                
                請檢查：
                1. 網絡連接
                2. 存儲桶權限
                3. 對象是否仍然存在
                """
                self.isDeletingObjects = false
            }
        }
    }
    
    // 上傳文件
    func uploadFile(from fileURL: URL) async {
        isUploading = true
        uploadProgress = 0
        uploadError = nil
        
        do {
            // 檢查文件訪問權限
            guard fileURL.startAccessingSecurityScopedResource() else {
                throw NSError(domain: "", code: -1, 
                    userInfo: [NSLocalizedDescriptionKey: "無法訪問選擇的文件，請確保授予應用程序訪問權限。"])
            }
            defer {
                fileURL.stopAccessingSecurityScopedResource()
            }
            
            let credentials = AWSCredentialIdentity(
                accessKey: accessKey,
                secret: secretKey
            )
            
            let identityResolver = try StaticAWSCredentialIdentityResolver(credentials)
            let s3Configuration = try await S3Client.S3ClientConfiguration(
                awsCredentialIdentityResolver: identityResolver,
                region: region
            )
            
            let client = S3Client(config: s3Configuration)
            
            guard let bucket = currentBucket else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "未選擇存儲桶"])
            }
            
            // 檢查文件是否存在
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "文件不存在或無法訪問"])
            }
            
            // 獲取文件數據
            let fileData: Data
            do {
                fileData = try Data(contentsOf: fileURL)
            } catch {
                throw NSError(domain: "", code: -1, 
                    userInfo: [NSLocalizedDescriptionKey: "無法讀取文件數據：\(error.localizedDescription)"])
            }
            
            // 創建上傳請求
            let fileName = fileURL.lastPathComponent
            let key = currentPrefix + fileName
            
            let input = PutObjectInput(
                body: .data(fileData),
                bucket: bucket,
                key: key
            )
            
            // 執行上傳
            _ = try await client.putObject(input: input)
            
            // 重新加載對象列表
            await listObjects(bucket: bucket, prefix: currentPrefix)
            
            DispatchQueue.main.async {
                self.isUploading = false
                self.uploadProgress = 1.0
            }
            
        } catch let error as AWSServiceError {
            DispatchQueue.main.async {
                self.uploadError = """
                上傳文件失敗：
                \(error.message ?? "未知錯誤")
                
                可能原因：
                1. 存儲桶權限不足
                2. 文件大小超出限制
                3. 網絡連接問題
                4. 存儲桶區域設置不正確
                
                請檢查：
                1. IAM 用戶是否有 s3:PutObject 權限
                2. 存儲桶策略是否允許上傳
                3. 網絡連接是否正常
                """
                self.isUploading = false
            }
        } catch {
            DispatchQueue.main.async {
                self.uploadError = """
                上傳文件失敗：
                \(error.localizedDescription)
                
                請檢查：
                1. 文件訪問權限
                2. 文件是否可讀
                3. 文件是否存在
                4. 應用程序是否有權限訪問該文件
                """
                self.isUploading = false
            }
        }
    }
}

// 創建存儲桶的視圖
struct CreateBucketView: View {
    @Binding var isPresented: Bool
    @Binding var bucketName: String
    @Binding var region: String
    @Binding var isCreating: Bool
    let onCreate: (String) -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("請輸入存儲桶名稱", text: $bucketName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(height: 36)
                            .disabled(isCreating)
                        
                        Picker("區域", selection: $region) {
                            Text("美國東部 (us-east-1)").tag("us-east-1")
                            Text("東京 (ap-northeast-1)").tag("ap-northeast-1")
                            Text("新加坡 (ap-southeast-1)").tag("ap-southeast-1")
                            Text("美國西部 (us-west-2)").tag("us-west-2")
                        }
                        .pickerStyle(MenuPickerStyle())
                        .disabled(isCreating)
                    }
                    .padding(.vertical, 12)
                }
                .padding(.horizontal, 4)
                
                Section(header: Text("注意事項").font(.headline)) {
                    VStack(alignment: .leading, spacing: 16) {
                        NoticeRow(icon: "exclamationmark.circle.fill", text: "存儲桶名稱必須是全局唯一的")
                        NoticeRow(icon: "textformat.abc", text: "名稱只能包含小寫字母、數字和連字符")
                        NoticeRow(icon: "character.cursor.ibeam", text: "長度必須在 3-63 個字符之間")
                        NoticeRow(icon: "minus", text: "不能以連字符開頭或結尾")
                    }
                    .padding(.vertical, 12)
                }
                .padding(.horizontal, 4)
                
                // 底部按鈕
                HStack(spacing: 16) {
                    Spacer()
                    
                    Button(action: {
                        isPresented = false
                    }) {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                            Text("離開視窗")
                        }
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                    .disabled(isCreating)
                    .buttonStyle(.borderless)
                    .foregroundColor(.gray)
                    
                    Button("取消") {
                        bucketName = ""
                    }
                    .disabled(isCreating || bucketName.isEmpty)
                    .buttonStyle(.borderless)
                    .foregroundColor(.gray)
                    
                    Button(action: {
                        onCreate(bucketName)
                    }) {
                        if isCreating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .frame(width: 80)
                        } else {
                            Text("創建")
                                .frame(width: 80)
                        }
                    }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(bucketName.isEmpty || isCreating)
                    .buttonStyle(.borderedProminent)
        }
        .padding()
            }
            .navigationTitle("新增存儲桶")
            .frame(minWidth: 600, minHeight: 500)
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}

// 注意事項行的視圖組件
struct NoticeRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
            Text(text)
                .font(.body)
        }
    }
}
