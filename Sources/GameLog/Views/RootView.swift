import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @SceneStorage("sidebarIsVisible") private var sidebarIsVisible = true
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        @Bindable var model = model

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            LogWorkspaceView()
        }
        .inspector(isPresented: $model.isInspectorPresented) {
            InspectorView()
                .inspectorColumnWidth(min: 300, ideal: 350, max: 460)
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: String(localized: "搜索 Tag 或消息"))
        .toolbar {
            MainToolbar()
        }
        .sheet(item: $model.exportPreview) { _ in
            ExportPreviewView()
                .environment(model)
        }
        .task {
            columnVisibility = sidebarIsVisible ? .all : .detailOnly
            await model.bootstrap()
        }
        .onChange(of: columnVisibility) { _, newValue in
            sidebarIsVisible = newValue != .detailOnly
        }
    }
}
