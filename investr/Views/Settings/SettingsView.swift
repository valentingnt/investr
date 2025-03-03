import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Layout.spacing) {
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
                                
                                Text("Track your investments with ease.")
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
}

#Preview {
    SettingsView()
} 