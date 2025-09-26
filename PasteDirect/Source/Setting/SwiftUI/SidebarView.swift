import SwiftUI

// MARK: - Sidebar View
struct SidebarView: View {
    @Binding var selectedCategory: SettingCategory?

    var body: some View {
        List(SettingCategory.allCategories, id: \.id, selection: $selectedCategory) { category in
            NavigationLink(value: category) {
                HStack {
                    Image(systemName: category.icon)
                        .foregroundColor(.primary)
                        .frame(width: 20, height: 20)

                    Text(category.title)
                        .font(.system(size: 13))

                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Settings")
        .frame(minWidth: 180)
        .listStyle(.sidebar)
        .apply(transform: { view in
            if #available(macOS 14.0, *) {
                view.toolbar(removing: .sidebarToggle)
            }
        })
        .toolbar { Text("") }
    }
}

extension View {
    @ViewBuilder
    func apply<V: View>(@ViewBuilder transform: (Self) -> V) -> some View {
        transform(self)
    }
}
