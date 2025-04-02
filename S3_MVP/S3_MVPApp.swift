//
//  S3_MVPApp.swift
//  S3_MVP
//
//  Created by Huang, Jacky on 2025/3/31.
//

import SwiftUI

@main
struct S3_MVPApp: App {
    @StateObject private var awsConfig = AWSConfiguration()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(awsConfig)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
