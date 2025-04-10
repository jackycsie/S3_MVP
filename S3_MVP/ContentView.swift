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

struct S3Bucket: Identifiable, Hashable {
    let id = UUID()
    let name: String?
    
    init(name: String?) {
        self.name = name
    }
    
    static func == (lhs: S3Bucket, rhs: S3Bucket) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct S3Item: Identifiable, Hashable {
    let id = UUID()
    let key: String
    let size: Int64?
    let lastModified: Date?
    let isFolder: Bool
    let storageClass: String?
    let contentType: String?
    
    init(key: String, size: Int64?, lastModified: Date?, isFolder: Bool, storageClass: String?, contentType: String?) {
        self.key = key
        self.size = size
        self.lastModified = lastModified
        self.isFolder = isFolder
        self.storageClass = storageClass
        self.contentType = contentType
    }
    
    static func == (lhs: S3Item, rhs: S3Item) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // 格式化文件大小
    var formattedSize: String {
        guard let size = size else { return "-" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    // 格式化最後修改時間
    var formattedLastModified: String {
        guard let date = lastModified else { return "-" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // 獲取簡化的文件類型
    var simpleContentType: String {
        guard let contentType = contentType else { return "-" }
        if let subtype = contentType.split(separator: "/").last {
            return String(subtype).uppercased()
        }
        return contentType
    }
    
    // 獲取簡化的存儲類型
    var simpleStorageClass: String {
        guard let storageClass = storageClass else { return "-" }
        return storageClass.replacingOccurrences(of: "STANDARD", with: "STD")
    }
}

struct ContentView: View {
    @State private var isLoggedIn = false
    @State private var accessKey = ""
    @State private var secretKey = ""
    @State private var region = "us-east-1"
    
    var body: some View {
        if isLoggedIn {
            MainView(
                accessKey: $accessKey,
                secretKey: $secretKey,
                region: $region,
                isLoggedIn: $isLoggedIn
            )
            .frame(minWidth: 1200, minHeight: 800)
        } else {
            VStack(spacing: 20) {
                Text("S3_MVP")
                    .font(.title)
                    .padding(.top, 20)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Access Key")
                    SecureField("", text: $accessKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Secret Key")
                    SecureField("", text: $secretKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Region")
                    Picker("選擇區域", selection: $region) {
                        Text("美國東部 (us-east-1)").tag("us-east-1")
                        Text("東京 (ap-northeast-1)").tag("ap-northeast-1")
                        Text("新加坡 (ap-southeast-1)").tag("ap-southeast-1")
                        Text("美國西部 (us-west-2)").tag("us-west-2")
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                Button("連接") {
                    Task {
                        await connect()
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 10)
                
                Spacer()
            }
            .padding()
            .frame(width: 300)
        }
    }
    
    private func connect() async {
        // 創建憑證身份
        let credentials = AWSCredentialIdentity(
            accessKey: accessKey,
            secret: secretKey
        )
        
        do {
            // 創建靜態憑證解析器
            let identityResolver = try StaticAWSCredentialIdentityResolver(credentials)
            
            // 設置 S3 配置
            let s3Configuration = try await S3Client.S3ClientConfiguration(
                awsCredentialIdentityResolver: identityResolver,
                region: region
            )
            
            // 創建 S3 客戶端
            let client = S3Client(config: s3Configuration)
            
            // 嘗試列出儲存桶以驗證憑證
            _ = try await client.listBuckets(input: ListBucketsInput())
            
            // 如果成功，設置登入狀態
            DispatchQueue.main.async {
                isLoggedIn = true
            }
        } catch {
            print("連接失敗：\(error)")
        }
    }
}

@MainActor
struct MainView: View {
    @Binding var accessKey: String
    @Binding var secretKey: String
    @Binding var region: String
    @Binding var isLoggedIn: Bool
    
    @State private var bucketNames: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedBucket: String?
    @State private var currentBucket: String?
    @State private var currentPath: String = ""
    @State private var currentPrefix: String = ""
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
    @State private var deleteError: String?
    @State private var isShowingFilePicker = false
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0
    @State private var uploadError: String?
    @State private var isShowingCreateDialog = false
    @State private var newItemName = ""
    @State private var isCreatingItem = false
    @State private var createItemError: String?
    @State private var selectedItemType = "folder" // "folder" 或 "file"
    
    var body: some View {
        NavigationView {
            // 左側邊欄（存儲桶列表）
            VStack {
                List(buckets) { bucket in
                    Text(bucket.name ?? "")
                        .tag(bucket.name)
                        .onTapGesture {
                            if let name = bucket.name {
                                selectBucket(name)
                            }
                        }
                }
                .frame(minWidth: 200, maxWidth: 300)
            }
            .navigationTitle("存儲桶")
            .toolbar {
                ToolbarItem {
                    Button(action: { isShowingCreateBucketSheet = true }) {
                        Label("新增存儲桶", systemImage: "plus")
                    }
                }
                
                ToolbarItem {
                    Button(action: {
                        isLoggedIn = false
                    }) {
                        Label("登出", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            
            // 右側內容（對象列表）
            if let selectedBucket = selectedBucket {
                objectListView()
                    .navigationTitle(selectedBucket)
            } else {
                Text("請選擇一個存儲桶")
                    .navigationTitle("")
            }
        }
        .frame(minWidth: 800, minHeight: 500)
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
        .onAppear {
            Task {
                await refreshBuckets()
            }
        }
    }
    
    private var buckets: [S3Bucket] {
        bucketNames.map { name in
            S3Bucket(name: name)
        }
    }
    
    private func refreshBuckets() async {
        await listBuckets()
    }
    
    private func listBuckets() async {
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
    
    private func objectListView() -> some View {
        VStack {
            // 導航欄
            HStack {
                Button(action: {
                    if navigationStack.count > 1 {
                        navigationStack.removeLast()
                        let previous = navigationStack.last!
                        currentPrefix = previous.prefix
                        updatePath(newPrefix: previous.prefix)
                        Task {
                            await listObjects(bucket: previous.bucket, prefix: previous.prefix)
                        }
                    }
                }) {
                    Image(systemName: "arrow.left")
                    Text("返回")
                }
                .disabled(navigationStack.count <= 1)
                
                Spacer()
                
                // 路徑導航
                HStack(spacing: 4) {
                    Text("/")
                        .foregroundColor(.gray)
                    
                    // Root 目錄
                    Button(action: {
                        navigateToPath(index: 0)
                    }) {
                        Text(currentBucket ?? "")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    
                    if !currentPath.isEmpty {
                        let components = currentPath.split(separator: "/")
                        ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                            Text("/")
                                .foregroundColor(.gray)
                            Button(action: {
                                navigateToPath(index: index + 1)
                            }) {
                                Text(String(component))
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Spacer()
                
                // 工具欄按鈕
                HStack(spacing: 12) {
                    Button(action: {
                        isShowingCreateDialog = true
                    }) {
                        Image(systemName: "plus")
                        Text("新增資料夾")
                    }
                    .disabled(currentBucket == nil)
                    
                    Button("刷新") {
                        Task {
                            if let current = navigationStack.last {
                                await listObjects(bucket: current.bucket, prefix: current.prefix)
                            }
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
                            Label("Upload File", systemImage: "square.and.arrow.up")
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
                            // 表頭
                            HStack(spacing: 0) {
                                Text("名稱")
                                    .frame(width: 300, alignment: .leading)
                                Text("大小")
                                    .frame(width: 100, alignment: .trailing)
                                Text("類型")
                                    .frame(width: 100, alignment: .center)
                                Text("存儲類型")
                                    .frame(width: 100, alignment: .center)
                                Text("最後修改時間")
                                    .frame(width: 180, alignment: .center)
                                Spacer()
                            }
                            .foregroundColor(.gray)
                            .font(.caption)
                            .padding(.vertical, 4)
                            .padding(.horizontal)
                            
                            ForEach(objects) { item in
                                ObjectRowView(
                                    item: item,
                                    currentPrefix: currentPrefix,
                                    currentBucket: currentBucket,
                                    selectedObjects: $selectedObjects,
                                    onFolderTap: { key in
                                        currentPrefix = key
                                        updatePath(newPrefix: key)
                                        if let bucket = currentBucket {
                                            navigationStack.append((bucket: bucket, prefix: key))
                                            Task {
                                                await listObjects(bucket: bucket, prefix: key)
                                            }
                                        }
                                    }
                                )
                            }
                        }
                        .listStyle(PlainListStyle())
                    }
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            let _ = providers.first?.loadObject(ofClass: URL.self) { url, error in
                guard let url = url, error == nil else {
                    print("拖放上傳錯誤：\(error?.localizedDescription ?? "未知錯誤")")
                    DispatchQueue.main.async {
                        self.uploadError = "拖放上傳失敗：\(error?.localizedDescription ?? "未知錯誤")"
                    }
                    return
                }
                
                Task { @MainActor in
                    await self.uploadFile(from: url)
                }
            }
            
            return true
        }
        .alert("新增項目", isPresented: $isShowingCreateDialog) {
            VStack {
                Picker("類型", selection: $selectedItemType) {
                    Text("文件夾").tag("folder")
                    Text("文件").tag("file")
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.bottom, 8)
                
                TextField(selectedItemType == "folder" ? "文件夾名稱" : "文件名稱", text: $newItemName)
                
                Button("取消", role: .cancel) {
                    newItemName = ""
                    createItemError = nil
                }
                
                Button(isCreatingItem ? "創建中..." : "創建") {
                    Task {
                        if selectedItemType == "folder" {
                            await createFolder()
                        } else {
                            await createEmptyFile()
                        }
                    }
                }
                .disabled(isCreatingItem)
            }
        } message: {
            if let error = createItemError {
                Text(error)
            } else {
                Text(selectedItemType == "folder" ? "請輸入新文件夾的名稱" : "請輸入新文件的名稱")
            }
        }
    }
    
    private func navigateToPath(index: Int) {
        guard index >= 0, index < navigationStack.count else { return }
        
        // 保留到指定索引的導航記錄
        navigationStack = Array(navigationStack.prefix(through: index))
        let target = navigationStack.last!
        
        // 更新當前狀態
        currentPrefix = target.prefix
        updatePath(newPrefix: target.prefix)
        
        // 加載目標目錄的內容
        Task {
            await listObjects(bucket: target.bucket, prefix: target.prefix)
        }
    }
    
    private func listObjects(bucket: String, prefix: String) async {
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
                    currentRegion = bucketRegion.isEmpty ? "us-east-1" : bucketRegion
                    
                    if currentRegion != region {
                        let newConfig = try await S3Client.S3ClientConfiguration(
                            awsCredentialIdentityResolver: identityResolver,
                            region: currentRegion
                        )
                        client = S3Client(config: newConfig)
                    }
                }
            } catch {
                print("獲取存儲桶位置時出錯：\(error.localizedDescription)")
            }
            
            let input = ListObjectsV2Input(
                bucket: bucket,
                delimiter: "/",
                maxKeys: 1000,
                prefix: prefix
            )
            
            let response = try await client.listObjectsV2(input: input)
            
            // 安全地提取 commonPrefixes
            let commonPrefixes = response.commonPrefixes ?? []
            
            // 初始化一個空數組來存儲文件夾
            var folders: [S3Item] = []
            
            // 遍歷 commonPrefixes 並創建 S3Item 實例
            for prefix in commonPrefixes {
                if let key = prefix.prefix {
                    let folder = S3Item(
                        key: key,
                        size: nil,
                        lastModified: nil,
                        isFolder: true,
                        storageClass: nil,
                        contentType: "application/x-directory"
                    )
                    folders.append(folder)
                }
            }
            
            // 安全地提取 contents
            let contents = response.contents ?? []
            
            // 初始化一個空數組來存儲文件
            var files: [S3Item] = []
            
            // 遍歷 contents 並創建 S3Item 實例
            for object in contents {
                if let key = object.key, key != prefix {
                    // 檢查是否是文件夾（以斜線結尾）
                    let isFolder = key.hasSuffix("/")
                    
                    if isFolder {
                        let folder = S3Item(
                            key: key,
                            size: nil,
                            lastModified: object.lastModified,
                            isFolder: true,
                            storageClass: object.storageClass?.rawValue,
                            contentType: "application/x-directory"
                        )
                        folders.append(folder)
                    } else {
                        let file = S3Item(
                            key: key,
                            size: object.size != nil ? Int64(object.size!) : nil,
                            lastModified: object.lastModified,
                            isFolder: false,
                            storageClass: object.storageClass?.rawValue,
                            contentType: nil
                        )
                        files.append(file)
                    }
                }
            }
            
            // 合併結果，文件夾在前
            self.objects = folders + files
            self.isLoadingObjects = false
            
        } catch let error as AWSServiceError {
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
        } catch {
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
    
    private func uploadFile(from fileURL: URL) async {
        isUploading = true
        uploadProgress = 0
        uploadError = nil
        
        do {
            // 檢查文件訪問權限
            let shouldAccessResource = fileURL.startAccessingSecurityScopedResource()
            defer {
                if shouldAccessResource {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }
            
            // 檢查文件是否存在並可讀
            let fileManager = FileManager.default
            var isDirectory: ObjCBool = false
            
            guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "文件不存在"])
            }
            
            guard !isDirectory.boolValue else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "不能上傳文件夾"])
            }
            
            guard fileManager.isReadableFile(atPath: fileURL.path) else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "文件無法讀取，請檢查權限"])
            }
            
            // 獲取文件數據
            let fileData: Data
            do {
                fileData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            } catch {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "無法讀取文件數據：\(error.localizedDescription)"])
            }
            
            let credentials = AWSCredentialIdentity(
                accessKey: accessKey,
                secret: secretKey
            )
            
            let identityResolver = try StaticAWSCredentialIdentityResolver(credentials)
            
            // 首先獲取存儲桶的實際區域
            var currentRegion = region
            var client: S3Client
            
            guard let bucket = currentBucket else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "未選擇存儲桶"])
            }
            
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
                print("獲取存儲桶位置時出錯：\(error.localizedDescription)")
            }
            
            // 創建上傳請求
            let fileName = fileURL.lastPathComponent
            let key = currentPrefix + fileName
            
            let input = PutObjectInput(
                body: .data(fileData),
                bucket: bucket,
                contentType: "text/plain",
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
                1. 存儲桶區域不匹配（當前：\(region)）
                2. 存儲桶權限不足
                3. 文件大小超出限制
                4. 網絡連接問題
                
                請檢查：
                1. 存儲桶是否在正確的區域
                2. IAM 用戶是否有 s3:PutObject 權限
                3. 存儲桶策略是否允許上傳
                4. 網絡連接是否正常
                
                技術細節：
                當前區域：\(region)
                錯誤類型：\(type(of: error))
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
                
                錯誤類型：\(type(of: error))
                """
                self.isUploading = false
            }
        }
    }
    
    private func deleteSelectedObjects() async {
        isDeletingObjects = true
        deleteError = nil
        
        do {
            let credentials = AWSCredentialIdentity(
                accessKey: accessKey,
                secret: secretKey
            )
            
            let identityResolver = try StaticAWSCredentialIdentityResolver(credentials)
            
            // 首先獲取存儲桶的實際區域
            var currentRegion = region
            var client: S3Client
            
            // 創建初始客戶端
            let initialConfig = try await S3Client.S3ClientConfiguration(
                awsCredentialIdentityResolver: identityResolver,
                region: currentRegion
            )
            client = S3Client(config: initialConfig)
            
            guard let bucket = currentBucket else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "未選擇存儲桶"])
            }
            
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
                print("獲取存儲桶位置時出錯：\(error.localizedDescription)")
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
                    
                    請檢查：
                    1. 對象權限設置
                    2. 存儲桶策略
                    3. IAM 用戶權限
                    """
                }
            }
            
            // 重新加載對象列表
            await listObjects(bucket: bucket, prefix: currentPrefix)
            
            DispatchQueue.main.async {
                self.selectedObjects.removeAll()
                self.isDeletingObjects = false
            }
            
        } catch let error as AWSServiceError {
            DispatchQueue.main.async {
                self.deleteError = """
                刪除對象時發生錯誤：
                \(error.message ?? "未知錯誤")
                
                可能原因：
                1. 存儲桶區域不匹配（當前：\(region)）
                2. 沒有刪除權限
                3. 對象可能已被刪除
                4. 存儲桶策略限制
                
                請檢查：
                1. IAM 用戶是否有 s3:DeleteObject 權限
                2. 存儲桶策略是否允許刪除操作
                3. 存儲桶區域設置是否正確
                4. 網絡連接是否正常
                """
                self.isDeletingObjects = false
            }
        } catch {
            DispatchQueue.main.async {
                self.deleteError = """
                刪除對象時發生錯誤：
                \(error.localizedDescription)
                
                錯誤類型：\(type(of: error))
                
                請檢查：
                1. 網絡連接
                2. AWS 憑證是否有效
                3. 存儲桶區域設置
                4. 對象是否仍然存在
                
                當前區域：\(region)
                """
                self.isDeletingObjects = false
            }
        }
    }
    
    private func createBucket(name: String) async {
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
    
    private func deleteBucket(name: String) async {
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
    
    private func selectBucket(_ name: String) {
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

    private func updatePath(newPrefix: String) {
        // 移除開頭和結尾的斜線
        let cleanPrefix = newPrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        if cleanPrefix.isEmpty {
            currentPath = ""
        } else {
            // 將路徑分割成組件
            let components = cleanPrefix.split(separator: "/")
            currentPath = components.joined(separator: "/")
        }
    }
    
    private func createFolder() async {
        guard let bucket = currentBucket, !newItemName.isEmpty else { return }
        
        isCreatingItem = true
        createItemError = nil
        
        do {
            let credentials = AWSCredentialIdentity(
                accessKey: accessKey,
                secret: secretKey
            )
            
            let identityResolver = try StaticAWSCredentialIdentityResolver(credentials)
            
            // 首先獲取存儲桶的實際區域
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
                    currentRegion = bucketRegion.isEmpty ? "us-east-1" : bucketRegion
                    
                    if currentRegion != region {
                        let newConfig = try await S3Client.S3ClientConfiguration(
                            awsCredentialIdentityResolver: identityResolver,
                            region: currentRegion
                        )
                        client = S3Client(config: newConfig)
                    }
                }
            } catch {
                print("獲取存儲桶位置時出錯：\(error.localizedDescription)")
            }
            
            // 移除所有斜線，然後在結尾添加兩條斜線
            let folderName = newItemName.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let folderPath = currentPrefix + folderName + "//"
            
            print("正在創建文件夾：\(folderPath)")
            
            // 使用空的 Data() 創建一個空對象
            let input = PutObjectInput(
                body: .data(Data()),
                bucket: bucket,
                key: folderPath
            )
            
            _ = try await client.putObject(input: input)
            print("文件夾創建成功")
            
            // 刷新列表
            await listObjects(bucket: bucket, prefix: currentPrefix)
            
            self.newItemName = ""
            self.isCreatingItem = false
            self.createItemError = nil
            self.isShowingCreateDialog = false
            
        } catch let error as AWSServiceError {
            let errorMessage = """
            創建文件夾失敗（AWS 服務錯誤）：
            錯誤信息：\(error.message ?? "未知錯誤")
            錯誤類型：\(type(of: error))
            當前區域：\(region)
            當前路徑：\(currentPrefix)
            文件夾名稱：\(newItemName)
            """
            print(errorMessage)
            self.createItemError = errorMessage
            self.isCreatingItem = false
        } catch {
            let errorMessage = """
            創建文件夾失敗（一般錯誤）：
            錯誤信息：\(error.localizedDescription)
            錯誤類型：\(type(of: error))
            當前區域：\(region)
            當前路徑：\(currentPrefix)
            文件夾名稱：\(newItemName)
            """
            print(errorMessage)
            self.createItemError = errorMessage
            self.isCreatingItem = false
        }
    }
    
    private func createEmptyFile() async {
        guard let bucket = currentBucket, !newItemName.isEmpty else { return }
        
        DispatchQueue.main.async {
            self.isCreatingItem = true
            self.createItemError = nil
        }
        
        do {
            // 創建憑證
            let credentials = AWSCredentialIdentity(
                accessKey: accessKey,
                secret: secretKey
            )
            
            let identityResolver = try StaticAWSCredentialIdentityResolver(credentials)
            
            // 首先獲取存儲桶的實際區域
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
                print("獲取存儲桶位置時出錯：\(error.localizedDescription)")
            }
            
            // 移除開頭和結尾的斜線
            let fileName = newItemName.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            
            // 構建完整的文件路徑
            let filePath = currentPrefix + fileName
            
            print("正在創建文件：\(filePath)")
            
            // 創建一個空文件
            let input = PutObjectInput(
                body: .data("".data(using: .utf8)!),
                bucket: bucket,
                contentType: "text/plain",
                key: filePath
            )
            
            _ = try await client.putObject(input: input)
            print("文件創建成功")
            
            // 刷新列表
            await listObjects(bucket: bucket, prefix: currentPrefix)
            
            // 清空文件名稱並更新狀態
            DispatchQueue.main.async {
                self.newItemName = ""
                self.isCreatingItem = false
                self.createItemError = nil
                self.isShowingCreateDialog = false
            }
            
        } catch let error as AWSServiceError {
            let errorMessage = """
            創建文件失敗（AWS 服務錯誤）：
            錯誤信息：\(error.message ?? "未知錯誤")
            錯誤類型：\(type(of: error))
            當前區域：\(region)
            當前路徑：\(currentPrefix)
            文件名稱：\(newItemName)
            """
            print(errorMessage)
            DispatchQueue.main.async {
                self.createItemError = errorMessage
                self.isCreatingItem = false
            }
        } catch {
            let errorMessage = """
            創建文件失敗（一般錯誤）：
            錯誤信息：\(error.localizedDescription)
            錯誤類型：\(type(of: error))
            當前區域：\(region)
            當前路徑：\(currentPrefix)
            文件名稱：\(newItemName)
            """
            print(errorMessage)
            DispatchQueue.main.async {
                self.createItemError = errorMessage
                self.isCreatingItem = false
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

// 新增 ObjectRowView 結構體
struct ObjectRowView: View {
    let item: S3Item
    let currentPrefix: String
    let currentBucket: String?
    @Binding var selectedObjects: Set<String>
    let onFolderTap: (String) -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            // 名稱和圖標
            HStack {
                Image(systemName: item.isFolder ? "folder" : "doc")
                    .foregroundColor(item.isFolder ? .blue : .gray)
                Text(item.key.replacingOccurrences(of: currentPrefix, with: ""))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: 300, alignment: .leading)
            
            // 大小
            Text(item.isFolder ? "-" : item.formattedSize)
                .frame(width: 100, alignment: .trailing)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            // 類型
            Text(item.isFolder ? "DIR" : item.simpleContentType)
                .frame(width: 100, alignment: .center)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            // 存儲類型
            Text(item.isFolder ? "-" : item.simpleStorageClass)
                .frame(width: 100, alignment: .center)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            // 最後修改時間
            Text(item.formattedLastModified)
                .frame(width: 180, alignment: .center)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
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
                .padding(.horizontal)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if item.isFolder {
                onFolderTap(item.key)
            }
        }
    }
}

