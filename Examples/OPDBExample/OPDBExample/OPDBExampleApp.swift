import SwiftUI

@main
struct OPDBExampleApp: App {
    @State private var model = MachineListModel()

    var body: some Scene {
        WindowGroup {
            MachineListView(model: model)
        }
    }
}
