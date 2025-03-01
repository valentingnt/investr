import SwiftUI

struct SettingsView: View {
    @AppStorage("apiCacheExpirationMinutes") private var apiCacheExpirationMinutes: Int = 15
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Layout.spacing) {
                        // Cache Settings
                        VStack(alignment: .leading, spacing: Theme.Layout.smallSpacing) {
                            Text("Cache Settings")
                                .font(Theme.Typography.title3)
                                .foregroundColor(Theme.Colors.primaryText)
                                .padding(.bottom, 4)
                            
                            VStack(spacing: Theme.Layout.smallSpacing) {
                                Picker("Cache Duration", selection: $apiCacheExpirationMinutes) {
                                    Text("5 minutes").tag(5)
                                    Text("15 minutes").tag(15)
                                    Text("30 minutes").tag(30)
                                    Text("1 hour").tag(60)
                                    Text("2 hours").tag(120)
                                }
                                .pickerStyle(.segmented)
                                .padding(.bottom, 8)
                                
                                HStack {
                                    Text("Current Setting")
                                        .font(Theme.Typography.body)
                                        .foregroundColor(Theme.Colors.primaryText)
                                    Spacer()
                                    Text(formatCacheDuration(apiCacheExpirationMinutes))
                                        .font(Theme.Typography.bodyBold)
                                        .foregroundColor(Theme.Colors.accent)
                                }
                                
                                Text("Longer cache durations reduce network usage but may display outdated information.")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.secondaryText)
                                    .padding(.top, 4)
                            }
                            .padding(Theme.Layout.padding)
                            .background(Theme.Colors.secondaryBackground)
                            .cornerRadius(Theme.Layout.cornerRadius)
                        }
                        
                        // About Section
                        VStack(alignment: .leading, spacing: Theme.Layout.smallSpacing) {
                            Text("About")
                                .font(Theme.Typography.title3)
                                .foregroundColor(Theme.Colors.primaryText)
                                .padding(.bottom, 4)
                            
                            VStack(alignment: .leading, spacing: Theme.Layout.smallSpacing) {
                                // Creator information
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Creator")
                                        .font(Theme.Typography.captionBold)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                    
                                    Text("Valentin Genest")
                                        .font(Theme.Typography.bodyBold)
                                        .foregroundColor(Theme.Colors.primaryText)
                                }
                                .padding(.bottom, 8)
                                
                                // App information
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("App Version")
                                        .font(Theme.Typography.captionBold)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                    
                                    Text("Investr 1.0")
                                        .font(Theme.Typography.body)
                                        .foregroundColor(Theme.Colors.primaryText)
                                }
                                .padding(.bottom, 8)
                                
                                Divider()
                                    .background(Theme.Colors.separator)
                                    .padding(.vertical, 8)
                                
                                Text("Data is refreshed based on the cache duration settings.")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.secondaryText)
                            }
                            .padding(Theme.Layout.padding)
                            .background(Theme.Colors.secondaryBackground)
                            .cornerRadius(Theme.Layout.cornerRadius)
                        }
                    }
                    .padding(Theme.Layout.padding)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }
    
    private func formatCacheDuration(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) minutes"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours) hour\(hours > 1 ? "s" : "")"
            } else {
                return "\(hours) hour\(hours > 1 ? "s" : "") \(remainingMinutes) minute\(remainingMinutes > 1 ? "s" : "")"
            }
        }
    }
}

#Preview {
    SettingsView()
        .preferredColorScheme(.dark)
} 