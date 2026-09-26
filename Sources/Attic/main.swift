import Foundation
import AtticKit

// Attic                              the app
// Attic --snapshot <out> <fixture>   render each section to PNG from a fixture library (no Photos access)
// Attic --make-fixture <dir>         write the synthetic test library
// Attic --make-icon <file.png>       render the 1024 px app icon
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--snapshot"), args.count > i + 2 {
    Snapshot.run(out: URL(fileURLWithPath: args[i + 1]), fixture: URL(fileURLWithPath: args[i + 2]))
} else if let i = args.firstIndex(of: "--make-fixture"), args.count > i + 1 {
    do { print(try Fixture.make(at: URL(fileURLWithPath: args[i + 1])).path) } catch { print(error); exit(1) }
} else if let i = args.firstIndex(of: "--make-icon"), args.count > i + 1 {
    MainActor.assumeIsolated { do { try Icon.png(to: URL(fileURLWithPath: args[i + 1])) } catch { print(error); exit(1) } }
} else {
    AtticApp.main()
}
