import ArgumentParser

@main
struct EddingsCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ei-cli",
        abstract: "The Eddings Index — Personal Intelligence Platform",
        subcommands: [
            SyncCommand.self,
            SearchCommand.self,
            StatusCommand.self,
            MigrateCommand.self,
        ],
        defaultSubcommand: StatusCommand.self
    )
}
