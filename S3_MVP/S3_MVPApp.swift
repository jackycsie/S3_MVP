//
//  S3_MVPApp.swift
//  S3_MVP
//
//  Created by Huang, Jacky on 2025/3/31.
//

import SwiftUI
import AWSClientRuntime
import AWSS3
import AWSSDKIdentity

@main
struct S3_MVPApp: App {
    @StateObject private var awsConfig = AWSConfiguration()
    
    init() {
        // 從 awsConfig 讀取保存的憑證
        let accessKey = UserDefaults.standard.string(forKey: "AWSAccessKey") ?? ""
        let secretKey = UserDefaults.standard.string(forKey: "AWSSecretKey") ?? ""
        let region = UserDefaults.standard.string(forKey: "AWSRegion") ?? "美國東部 (us-east-1)"
        
        // 提取實際的區域代碼（如果存在）
        let actualRegion: String
        if region.contains("us-east-1") {
            actualRegion = "us-east-1"
        } else if region.contains("ap-northeast-1") {
            actualRegion = "ap-northeast-1"
        } else if region.contains("ap-southeast-1") {
            actualRegion = "ap-southeast-1"
        } else if region.contains("us-west-2") {
            actualRegion = "us-west-2"
        } else {
            actualRegion = "us-east-1" // 默認
        }
        
        // 初始化全局 SyncViewModel
        if !accessKey.isEmpty && !secretKey.isEmpty {
            Task { @MainActor in
                // 使用保存的憑證更新全局實例
                SyncViewModel.shared.updateCredentials(accessKey: accessKey, secretKey: secretKey, region: actualRegion)
                
                // 啟動全局計時器
                SyncViewModel.startGlobalSyncTimer(viewModel: SyncViewModel.shared)
                
                print("已在應用啟動時初始化 SyncViewModel，區域: \(actualRegion)")
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(awsConfig)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
    }
}
