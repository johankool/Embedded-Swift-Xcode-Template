//
//  WelcomeView.swift
//  ESPSwiftInstaller
//
//  Created by Gibeom Ko on 5/29/26.
//

import SwiftUI

// First screen shown to the user.
// Displays requirements and a button to start installation.
struct WelcomeView: View {
    
    @ObservedObject var installer: Installer
    
    // Pre-flight checks
    private var hasXcode: Bool {
        FileManager.default.fileExists(atPath: "/Applications/Xcode.app")
    }
    
    private var hasGit: Bool {
        FileManager.default.fileExists(atPath: "/usr/bin/git")
    }
    
    // Homebrew lives in /opt/homebrew on Apple silicon and /usr/local on Intel.
    private var hasHomebrew: Bool {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .contains { FileManager.default.fileExists(atPath: $0) }
    }
    
    private var canInstall: Bool {
        hasXcode && hasGit
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            // ── Header ───────────────────────────────────────────
            VStack(spacing: 12) {
                Image(systemName: "cpu")
                    .font(.system(size: 52))
                    .foregroundColor(.accentColor)
                
                Text("Embedded Swift for ESP32")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("This installer will set up everything you need to write ESP32 firmware in Swift using Xcode.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 36)
            .padding(.bottom, 28)
            
            // ── Requirements ─────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                Text("Requirements")
                    .font(.headline)
                    .padding(.bottom, 2)
                
                RequirementRow(
                    title: "Xcode",
                    detail: "Required for building projects",
                    isMet: hasXcode
                )
                RequirementRow(
                    title: "Git",
                    detail: "Required for ESP-IDF installation",
                    isMet: hasGit
                )
                RequirementRow(
                    title: "Homebrew",
                    detail: "Installs Python 3.10+, CMake and Ninja if missing",
                    isMet: hasHomebrew,
                    isRequired: false
                )
                RequirementRow(
                    title: "Internet Connection",
                    detail: "~3 GB download (ESP-IDF + Swift toolchain)",
                    isMet: true
                )
            }
            .padding(.horizontal, 48)
            
            Spacer()
            
            // ── Action ───────────────────────────────────────────
            VStack(spacing: 8) {
                if !canInstall {
                    Text("Please install Xcode and Git before continuing.")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                Button(action: {
                    installer.startInstallation()
                }) {
                    Text("Install")
                        .frame(width: 120)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canInstall)
                .controlSize(.large)
            }
            .padding(.bottom, 28)
        }
    }
}

// ── Subview ───────────────────────────────────────────────────────

struct RequirementRow: View {
    let title: String
    let detail: String
    let isMet: Bool
    var isRequired: Bool = true
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isMet ? "checkmark.circle.fill" : (isRequired ? "xmark.circle.fill" : "exclamationmark.circle.fill"))
                .foregroundColor(isMet ? .green : (isRequired ? .red : .orange))
                .font(.system(size: 18))
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}
