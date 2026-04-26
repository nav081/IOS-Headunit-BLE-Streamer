//
//  IOS_HeadunitApp.swift
//  IOS Headunit
//
//  Created by Navneet Yadav on 24/04/26.
//

import SwiftUI

@main
struct IOS_HeadunitApp: App {
    @Environment(\.scenePhase) var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .active:
                print("[APP] Active - Streaming may resume")
            case .inactive:
                print("[APP] Inactive")
            case .background:
                print("[APP] Background - BLE & Location continue if enabled")
            @unknown default:
                break
            }
        }
    }
}
