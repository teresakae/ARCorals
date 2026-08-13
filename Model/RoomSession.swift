import Combine
import Foundation

/// The room layer: owns the phase, the roster and the host/join lifecycle, and is the only
/// place that drives the transport.
///
/// The host is the sole authority on the roster. It builds the array and broadcasts it;
/// guests replace their copy wholesale and never merge, which is what keeps the two devices
/// from drifting into different orders or different membership.
@MainActor
final class RoomSession: ObservableObject {
    @Published private(set) var phase: RoomPhase = .home
    @Published private(set) var roomCode: RoomCode?
    @Published private(set) var players: [RoomPlayer] = []
    /// Between "join tapped" and "connected to the host". Not a fourth phase — the UI is
    /// still Home, with a progress row on it.
    @Published private(set) var isJoining = false
    @Published private(set) var discovery = DiscoveryState()
    /// Last thing that happened, in words, successes and failures alike. There is no
    /// separate error channel because every failure here recovers by returning Home.
    @Published private(set) var status: String?

    /// The AR module assigns itself here. Nil until `CoralAR` adopts the room layer, and
    /// everything below works unchanged with no conformer — see `ARPayloadChannel`.
    weak var arChannel: (any ARPayloadChannel)? {
        didSet { attachPayloadSender() }
    }

    private let deviceName: String
    private var transport: PeerTransport
    private var advertiser: RoomAdvertiser
    private var browser: RoomBrowser

    /// Raw peer name of the host. Host departure is detected by watching this one identity
    /// leave — not by "zero connected peers", which is also true of a perfectly healthy
    /// two-player room the moment the other guest steps out.
    private var hostID: String?
    /// Host candidate we have invited and are waiting on.
    private var pendingHostID: String?
    /// Host-side join order. Kept explicitly rather than read back from `connectedPeers` so
    /// the roster order is stable and so a peer refused for capacity never appears in it.
    private var guestIDs: [String] = []

    private var inviteDeadline: Task<Void, Never>?
    private var joinDeadline: Task<Void, Never>?

    var localPlayerID: String { transport.localName }
    var isHost: Bool { hostID == transport.localName }
    var localPlayer: RoomPlayer {
        players.first { $0.id == transport.localName } ?? RoomPlayer(id: transport.localName, isHost: isHost)
    }

    init(deviceName: String) {
        let transport = PeerTransport(deviceName: deviceName)
        self.deviceName = deviceName
        self.transport = transport
        self.advertiser = RoomAdvertiser(transport: transport)
        self.browser = RoomBrowser(transport: transport)
        wireStack()
    }

    // MARK: - Hosting

    func createRoom() {
        resetStack()
        let code = RoomCode.random()
        roomCode = code
        hostID = transport.localName
        transport.isRelayHost = true
        // ⚠️ Phase before roster. `refreshAdvertising()` is gated on being in the lobby, so
        // seeding the roster first leaves the host permanently undiscoverable — and nothing
        // reports an error, because from the frameworks' point of view nothing failed.
        phase = .lobby
        rebuildHostRoster()
        status = "Room \(code) is open."
        roomLog.info("hosting room \(code.value, privacy: .public) as \(self.transport.localName, privacy: .public)")
    }

    func startSession() {
        guard isHost, phase == .lobby else { return }
        phase = .inSession
        // Closes the room: `refreshAdvertising` stops advertising outside the lobby.
        refreshAdvertising()
        broadcast(.startSession)
        arChannel?.roomSessionDidStart(localPlayer: localPlayer, roster: players)
    }

    func endSession() {
        guard isHost, phase == .inSession else { return }
        phase = .lobby
        refreshAdvertising()
        broadcast(.endSession)
        arChannel?.roomSessionDidEnd()
    }

    // MARK: - Joining

    func joinRoom(code: RoomCode) {
        resetStack()
        roomCode = code
        isJoining = true
        status = "Looking for room \(code)…"
        browser.start()
        joinDeadline = deadline(after: RoomRules.joinTimeout) { [weak self] in
            self?.teardown(status: "No room \(code) answered.")
        }
        updateDiscovery()
    }

    func cancelJoin() {
        guard isJoining else { return }
        teardown(status: "Join cancelled.")
    }

    func leaveRoom() {
        guard phase != .home else { return }
        teardown(status: "Left the room.")
    }

    /// Single exit path, so the AR module is told the session ended no matter which way it
    /// ended — leaving, being timed out, or the host walking away.
    private func teardown(status newStatus: String) {
        let wasInSession = phase == .inSession
        resetStack()
        status = newStatus
        if wasInSession { arChannel?.roomSessionDidEnd() }
    }

    /// Called whenever discovery changes. Filtering by room code is a room rule, so it lives
    /// here rather than in `RoomBrowser`.
    private func evaluateCandidates() {
        updateDiscovery()
        guard isJoining, pendingHostID == nil, let code = roomCode else { return }

        let matches = browser.discovered
            .filter { $0.value[RoomService.InfoKey.roomCode] == code.value }
            .sorted { $0.key < $1.key }
        guard let candidate = matches.first else { return }

        // Occupancy rides along in discoveryInfo so a full room reads as "full" immediately
        // instead of as an invitation that is never answered.
        let count = Int(candidate.value[RoomService.InfoKey.playerCount] ?? "") ?? 0
        let capacity = Int(candidate.value[RoomService.InfoKey.capacity] ?? "") ?? RoomRules.maxPlayers
        guard count < capacity else {
            status = "Room \(code) is full."
            return
        }

        pendingHostID = candidate.key
        status = "Joining \(PeerName.presentable(candidate.key))…"
        browser.invite(candidate.key, timeout: RoomRules.inviteTimeout)
        inviteDeadline = deadline(after: RoomRules.inviteTimeout) { [weak self] in
            self?.retryAfterSilentInvite()
        }
    }

    /// A declined invitation is delivered as nothing at all — no callback, no error. Without
    /// this the guest waits out the whole join deadline and never makes a second attempt.
    private func retryAfterSilentInvite() {
        guard isJoining, pendingHostID != nil else { return }
        pendingHostID = nil
        status = "No answer — looking again."
        // Restarting clears the discovered set, so the candidate has to re-announce itself.
        browser.start()
        updateDiscovery()
    }

    // MARK: - Peer events

    private func peerConnected(_ peerName: String) {
        if isHost {
            // The advertiser's capacity gate is not enough on its own: two invitations can
            // both be accepted before either connection lands.
            guard guestIDs.count < RoomRules.maxPlayers - 1 else {
                send(.roomFull, to: peerName)
                return
            }
            guard !guestIDs.contains(peerName) else { return }
            guestIDs.append(peerName)
            rebuildHostRoster()
        } else if peerName == pendingHostID {
            inviteDeadline?.cancel()
            joinDeadline?.cancel()
            inviteDeadline = nil
            joinDeadline = nil
            pendingHostID = nil
            hostID = peerName
            isJoining = false
            browser.stop()
            phase = .lobby
            status = "Joined room \(roomCode?.value ?? "")."
            updateDiscovery()
        }
    }

    private func peerDisconnected(_ peerName: String) {
        if isHost {
            guard guestIDs.contains(peerName) else { return }
            guestIDs.removeAll { $0 == peerName }
            rebuildHostRoster()
        } else if peerName == hostID {
            teardown(status: "Host left the room.")
        } else if peerName == pendingHostID {
            retryAfterSilentInvite()
        }
    }

    private func rebuildHostRoster() {
        players = [RoomPlayer(id: transport.localName, isHost: true)]
            + guestIDs.map { RoomPlayer(id: $0, isHost: false) }
        // Advertising carries the player count, so it has to be republished on every change.
        refreshAdvertising()
        broadcast(.roster(players))
        arChannel?.rosterDidChange(players)
    }

    // MARK: - Messages

    private func received(_ packet: Packet) {
        switch packet.tag {
        case .control:
            guard let message = try? RoomMessage(decoding: packet) else {
                roomLog.error("undecodable control packet from \(packet.origin, privacy: .public)")
                return
            }
            handle(message, from: packet.origin)
        case .payloadReliable, .payloadUnreliable:
            // Opaque all the way through: the room layer hands the bytes to the AR seam
            // without decoding them, and `origin` is the author rather than the relay.
            arChannel?.receivePayload(packet.body, from: packet.origin)
        }
    }

    /// Assigned into the channel so the AR module can transmit without naming recipients.
    /// Guests address the host and the host broadcasts — the star topology stays in here.
    private func attachPayloadSender() {
        arChannel?.sendPayload = { [weak self] payload, reliability in
            guard let self, phase == .inSession else { return }
            let packet = Packet(tag: reliability.tag, origin: transport.localName, body: payload)
            if isHost {
                transport.broadcast(packet)
            } else if let hostID {
                transport.send(packet, to: hostID)
            }
        }
    }

    private func handle(_ message: RoomMessage, from origin: String) {
        // Host authority, enforced on receipt: control traffic from anywhere but the host is
        // dropped rather than trusted.
        guard !isHost, origin == hostID else { return }
        switch message {
        case .roster(let roster):
            players = roster
            arChannel?.rosterDidChange(roster)
        case .roomFull:
            teardown(status: "That room is full.")
        case .startSession:
            phase = .inSession
            arChannel?.roomSessionDidStart(localPlayer: localPlayer, roster: players)
        case .endSession:
            phase = .lobby
            arChannel?.roomSessionDidEnd()
        }
    }

    private func broadcast(_ message: RoomMessage) {
        guard let packet = encoded(message) else { return }
        transport.broadcast(packet)
    }

    private func send(_ message: RoomMessage, to peerName: String) {
        guard let packet = encoded(message) else { return }
        transport.send(packet, to: peerName)
    }

    private func encoded(_ message: RoomMessage) -> Packet? {
        do {
            return try message.encodedPacket(origin: transport.localName)
        } catch {
            roomLog.error("could not encode control message: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Discovery plumbing

    private func refreshAdvertising() {
        guard isHost, phase == .lobby, let code = roomCode else {
            advertiser.stop()
            updateDiscovery()
            return
        }
        advertiser.start(discoveryInfo: [
            RoomService.InfoKey.roomCode: code.value,
            RoomService.InfoKey.playerCount: String(players.count),
            RoomService.InfoKey.capacity: String(RoomRules.maxPlayers)
        ])
        updateDiscovery()
    }

    private func updateDiscovery() {
        discovery = DiscoveryState(
            isAdvertising: advertiser.isAdvertising,
            isBrowsing: browser.isBrowsing,
            peersSeen: browser.discovered.count,
            peersMatchingCode: browser.discovered.values
                .filter { $0[RoomService.InfoKey.roomCode] == roomCode?.value }.count
        )
    }

    /// Tears the room down and rebuilds the peer stack. A disconnected `MCSession` is not
    /// documented as reusable, so every room gets a fresh transport — and with it a fresh
    /// peer-name suffix.
    private func resetStack() {
        inviteDeadline?.cancel()
        joinDeadline?.cancel()
        inviteDeadline = nil
        joinDeadline = nil
        advertiser.stop()
        browser.stop()
        transport.disconnect()

        let transport = PeerTransport(deviceName: deviceName)
        self.transport = transport
        self.advertiser = RoomAdvertiser(transport: transport)
        self.browser = RoomBrowser(transport: transport)
        wireStack()

        phase = .home
        roomCode = nil
        players = []
        guestIDs = []
        hostID = nil
        pendingHostID = nil
        isJoining = false
        updateDiscovery()
    }

    private func wireStack() {
        transport.onPeerConnected = { [weak self] in self?.peerConnected($0) }
        transport.onPeerDisconnected = { [weak self] in self?.peerDisconnected($0) }
        transport.onPacket = { [weak self] in self?.received($0) }
        advertiser.shouldAcceptInvitation = { [weak self] in
            guard let self else { return false }
            return isHost && phase == .lobby && players.count < RoomRules.maxPlayers
        }
        advertiser.onStateChange = { [weak self] in self?.updateDiscovery() }
        browser.onChange = { [weak self] in self?.evaluateCandidates() }
    }

    private func deadline(after seconds: TimeInterval, then body: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            body()
        }
    }
}
