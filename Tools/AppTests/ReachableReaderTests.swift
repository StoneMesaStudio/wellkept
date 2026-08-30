import Testing
import Foundation
import WellkeptCore

//  ReachableReaderTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **The promise this row lives or dies by: we can prove a service is ON, and we can never prove
//  one is off.**
//
//  Every test below is about a sentence that would be wrong in a way nobody could see from the
//  outside. "Remote Login: Off" on a Mac somebody can log into looks exactly like "Remote Login:
//  Off" on a Mac nobody can, and the person reading it has no way to tell which one they have.
//
//  Nothing here reads this Mac. The `netstat` fixtures below are real output, typed out, so the
//  suite gives the same answer on an M3, on an Intel Mac Pro, and on a build machine with the
//  network down.

@Suite struct ReachableReaderNetstatTests {

    /// Real `netstat -an` output from this Mac, 2026-08-27, trimmed to the interesting lines.
    static let sample = """
        Active Internet connections (including servers)
        Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)
        tcp4       0      0  127.0.0.1.631          *.*                    LISTEN
        tcp6       0      0  ::1.631                *.*                    LISTEN
        tcp4       0      0  127.0.0.1.8787         *.*                    LISTEN
        tcp46      0      0  *.3306                 *.*                    LISTEN
        tcp6       0      0  *.7000                 *.*                    LISTEN
        tcp4       0      0  *.7000                 *.*                    LISTEN
        tcp4       0      0  192.168.1.14.52413     17.253.11.201.443      ESTABLISHED
        udp4       0      0  *.5353                 *.*
        udp6       0      0  *.5353                 *.*
        Active LOCAL (UNIX) domain sockets
        Address          Type   Recv-Q Send-Q            Inode             Conn
        """

    @Test func onlyListeningSocketsAreEvidence() {
        let sockets = ReachableReader.parseNetstat(Self.sample)
        // The established connection to Apple on 443 is a conversation somebody's Mac is already
        // having, not a door standing open. It must not appear.
        #expect(!sockets.contains { $0.port == 443 })
        #expect(sockets.contains { $0.port == 7000 })
    }

    /// IPv6 is where a naive split on "." loses the port. `::1.631` has four of them.
    @Test func anIPv6AddressStillYieldsItsPort() {
        let sockets = ReachableReader.parseNetstat(Self.sample)
        let sixes = sockets.filter { $0.address == "::1" }
        #expect(sixes.count == 1)
        #expect(sixes.first?.port == 631)
        #expect(sixes.first?.isLoopback == true)
    }

    /// ⚠️ The distinction the whole row is named for: bound to loopback means nothing outside this
    /// Mac can reach it, and bound to `*` means anything on the network can try.
    @Test func theBindAddressSaysWhatCanReachIt() {
        let sockets = ReachableReader.parseNetstat(Self.sample)
        let printing = sockets.first { $0.port == 631 && $0.address == "127.0.0.1" }
        let airplay = sockets.first { $0.port == 7000 }
        #expect(printing?.reach == .thisMacOnly)
        #expect(airplay?.reach == .localNetwork)
    }

    /// A bound UDP socket is read, because Remote Management's agent answers on 3283 over both. A
    /// UDP socket in a conversation is not.
    @Test func boundUDPSocketsAreReadAndBusyOnesAreNot() {
        let sockets = ReachableReader.parseNetstat(Self.sample)
        #expect(sockets.contains { $0.port == 5353 && $0.isUDP })
        let chatty = ReachableReader.parseNetstat("udp4 0 0 192.168.1.14.5353 17.253.11.201.5353")
        #expect(chatty.isEmpty)
    }

    /// Headers, the Unix-domain table and anything else unexpected are skipped rather than guessed
    /// at. `netstat` prints several tables and only one of them is about the network.
    @Test func nonsenseIsSkippedRatherThanGuessedAt() {
        #expect(ReachableReader.parseNetstat("").isEmpty)
        #expect(ReachableReader.parseNetstat("Proto Recv-Q Send-Q Local Address").isEmpty)
        #expect(ReachableReader.parseNetstat("tcp4 0 0 malformed *.* LISTEN").isEmpty)
    }
}

@Suite struct ReachableReaderObservationTests {

    /// ⚠️ **Port 5000 is not proof of AirPlay.** AirPlay Receiver does hold it, and so does every
    /// second local web server ever written. A person running one must not be told AirPlay is on.
    @Test func aDevelopmentServerOnPort5000IsNotAirPlay() {
        let sockets = [ReachableReader.Socket(port: 5000, address: "*", isUDP: false)]
        let air = ReachableReader.observations(from: sockets)
            .first { $0.service == .airPlayReceiver }
        #expect(air?.standing == .notObserved)
    }

    /// Every service gets a line, whether or not anything was seen of it — and the line for a
    /// service we saw nothing of says what that means.
    @Test func everyServiceGetsALineAndNoneOfThemSaysOff() {
        let observations = ReachableReader.observations(from: [])
        #expect(observations.count == ReachableReader.Service.allCases.count)
        #expect(observations.allSatisfy { $0.standing == .notObserved })

        for service in ReachableReader.Service.allCases {
            let sentence = service.notSeenSentence.lowercased()
            #expect(!sentence.contains("is off"))
            #expect(sentence.contains("cannot" ) || sentence.contains("no way"))
        }
    }

    /// A service bound to both loopback and every address is reported at its widest reach. That is
    /// the ordinary arrangement, and reporting the narrower one would understate it.
    @Test func theWidestReachWins() {
        let sockets = [
            ReachableReader.Socket(port: 22, address: "127.0.0.1", isUDP: false),
            ReachableReader.Socket(port: 22, address: "*", isUDP: false),
        ]
        let login = ReachableReader.observations(from: sockets).first { $0.service == .remoteLogin }
        #expect(login?.standing == .listening(.localNetwork))
    }
}

@Suite struct ReachableReaderRowTests {

    /// **A real Mac, 2026-08-27.** AirPlay Receiver listening on the network, the Public folder
    /// set up to be shared with guests, File Sharing not seen. Neither is a crisis, and the row
    /// says both plainly with no colour on either.
    @Test func sampleMacReadsAsTwoPlainFacts() {
        let survey = ReachableReader.Survey(
            sockets: [ReachableReader.Socket(port: 7000, address: "*", isUDP: false)],
            guestLoginEnabled: false,
            sharedFolders: [ReachableReader.SharedFolder(name: "Ada's Public Folder",
                                                         path: "/Users/ada/Public",
                                                         guestAccess: true)]
        )
        let row = ReachableReader.row(from: survey)

        #expect(row.headline.contains("AirPlay Receiver"))
        #expect(row.headline.contains("guests allowed"))
        #expect(row.concerns.isEmpty)
        #expect(row.severity == .information)
        #expect(row.status == .good)
        #expect(row.complete)
    }

    /// ⚠️ **Configuration is not observation.** A folder set up for guests while nothing is serving
    /// it is not an open door, and the row has to say so — otherwise the honest reading of a shared
    /// Public folder is a scare on a Mac nobody can reach.
    @Test func aSharedFolderWithNoFileSharingSaysSo() {
        let survey = ReachableReader.Survey(
            sockets: [],
            guestLoginEnabled: false,
            sharedFolders: [ReachableReader.SharedFolder(name: "Public", path: "/Users/x/Public",
                                                         guestAccess: true)]
        )
        let reason = ReachableReader.row(from: survey).reason ?? ""
        #expect(reason.contains("setting, not an open door"))
        #expect(reason.contains("cannot prove it is switched off"))
    }

    /// ⚠️ **The caveat is unconditional.** It is a fact about our method, not about the machine, so
    /// it appears on a Mac with five services listening and on a Mac with none.
    @Test func everyRowNamesTheLimitOfWhatWasLookedAt() {
        let quiet = ReachableReader.Survey(sockets: [], guestLoginEnabled: false,
                                           sharedFolders: [])
        let busy = ReachableReader.Survey(
            sockets: ReachableReader.Service.allCases.compactMap { service in
                service.ports.first.map { ReachableReader.Socket(port: $0, address: "*", isUDP: false) }
            },
            guestLoginEnabled: true,
            sharedFolders: []
        )
        for row in [ReachableReader.row(from: quiet), ReachableReader.row(from: busy)] {
            #expect(row.reason?.contains("nothing above says a service is off") == true)
            #expect(row.concerns.isEmpty, "this row has no route to amber and must not find one")
        }
    }

    /// Nothing seen is never printed as a zero, and never as "off".
    @Test func nothingSeenIsNeverAZero() {
        let row = ReachableReader.row(from: .init(sockets: [], guestLoginEnabled: false,
                                                 sharedFolders: []))
        #expect(row.measure == nil)
        #expect(row.headline.contains("Nothing we can see is listening"))
        #expect(!row.headline.lowercased().contains(" off"))
    }

    /// ⚠️ Nothing readable at all is an unreadable row — **not** a row saying nothing is listening.
    /// `.notReported`, so there is no button and the check stays complete: no permission on this
    /// Mac produces a socket list.
    @Test func aSurveyThatReadNothingSaysSoRatherThanSayingNothingIsListening() {
        let row = ReachableReader.row(from: .init())
        #expect(row.unreadable == .notReported)
        #expect(row.status == .notChecked)
        #expect(row.remedy == nil)
        #expect(row.complete)
        #expect(!row.headline.lowercased().contains("nothing is listening"))
    }

    /// Somebody else's database on 3306 is a fact, listed without colour and without being called a
    /// sharing service. Loopback-only ports are left out entirely — nothing outside this Mac can
    /// reach them.
    ///
    /// ⚠️ **And macOS's own ports are not blamed on the person.** Bonjour holds 5353 on every Mac
    /// Apple has ever shipped; a line filing it under "programs you installed" is the app telling
    /// somebody they did something they did not do.
    @Test func otherPortsAreAPlainFactAndLoopbackOnesAreNotListed() {
        let sockets = [
            ReachableReader.Socket(port: 3306, address: "*", isUDP: false),
            ReachableReader.Socket(port: 5353, address: "*", isUDP: true),
            ReachableReader.Socket(port: 8787, address: "127.0.0.1", isUDP: false),
            ReachableReader.Socket(port: 7000, address: "*", isUDP: false),
        ]
        let value = ReachableReader.otherPortsValue(
            sockets, observations: ReachableReader.observations(from: sockets)) ?? ""
        #expect(value.contains("3306"))
        #expect(value.contains("5353 (Bonjour"))
        #expect(!value.contains("8787"))
        #expect(!value.contains("7000"), "a named service must not be listed twice")
        #expect(!value.contains("you installed"),
                "macOS's own ports must not be reported as the person's doing")
        #expect(value.contains("Some of these are macOS's own"))
    }

    /// The guest account reads from a setting rather than from a socket, so "off" is allowed here —
    /// and only here. It is what the Mac's own preference says, and it is worded as that.
    @Test func theGuestAccountIsTheOneThingWeCanReadDirectly() {
        let on = ReachableReader.details(survey: .init(sockets: [], guestLoginEnabled: true,
                                                       sharedFolders: []),
                                         observations: ReachableReader.observations(from: []),
                                         shared: [])
        #expect(on.first { $0.label == "Guest login" }?.value.hasPrefix("On —") == true)

        let unknown = ReachableReader.details(survey: .init(sockets: []),
                                              observations: ReachableReader.observations(from: []),
                                              shared: [])
        #expect(unknown.first { $0.label == "Guest login" }?.value
                == Unreadable.notReported.sentence)
    }

    /// Two share points can carry the same name, and `DetailPair` is identified by its label.
    @Test func twoSharedFoldersWithTheSameNameStillGetTwoLines() {
        let folders = [
            ReachableReader.SharedFolder(name: "Public", path: "/Users/a/Public", guestAccess: true),
            ReachableReader.SharedFolder(name: "Public", path: "/Users/b/Public", guestAccess: false),
        ]
        let pairs = ReachableReader.details(survey: .init(sockets: [], sharedFolders: folders),
                                            observations: ReachableReader.observations(from: []),
                                            shared: folders)
        let lines = pairs.filter { $0.label.hasPrefix("Shared folder") }
        #expect(lines.count == 2)
        #expect(Set(lines.map(\.id)).count == 2)
    }
}
