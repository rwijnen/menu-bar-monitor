import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let store: MetricsStore

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemMessage: String?

    var body: some View {
        Form {
            Section("Menu bar style") {
                ForEach(MenuBarStyle.allCases) { style in
                    StyleOption(style: style, isSelected: settings.style == style,
                                preview: MenuBarLabel(store: store, settings: settings,
                                                      style: style)) {
                        settings.style = style
                    }
                }
            }

            Section {
                ForEach(Metric.allCases) { metric in
                    Toggle(metric.title, isOn: Binding(
                        get: { settings.isVisible(metric) },
                        set: { settings.setVisible(metric, $0) }))
                        .disabled(!settings.canHide(metric))
                }
            } header: {
                Text("Show in menu bar")
            } footer: {
                Text("Each is its own item, with its own dropdown. ⌘-drag one to move it. "
                     + "At least one stays visible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Picker("Update every", selection: $settings.refreshInterval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                }
                Toggle(isOn: $settings.colorWarnings) {
                    Text("Colour warnings")
                    Text("CPU turns red above 85%. Memory turns amber or red under pressure.")
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginItemMessage {
                    Text(loginItemMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemMessage = SMAppService.mainApp.status == .requiresApproval
                ? "Approve Menu Bar Monitor in System Settings > General > Login Items."
                : nil
        } catch {
            loginItemMessage = "Couldn't update the login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct StyleOption<Preview: View>: View {
    let style: MenuBarStyle
    let isSelected: Bool
    let preview: Preview
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(style.title)
                    Text(style.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                preview
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.06)))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
