/// Opens DEXMA's windows. `AppCoordinator` does it; view models only ask, so none of them
/// creates a window itself.
protocol WindowRouter: AnyObject {
    func showSettings()
    func showWelcome()
}
