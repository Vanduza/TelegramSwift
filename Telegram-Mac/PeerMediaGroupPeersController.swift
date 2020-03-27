//
//  PeerMediaGroupPeersController.swift
//  Telegram
//
//  Created by Mikhail Filimonov on 27/03/2020.
//  Copyright © 2020 Telegram. All rights reserved.
//

import Cocoa
import SwiftSignalKit
import Postbox
import TelegramCore
import SyncCore
import TGUIKit

private final class GroupPeersArguments {
    let context: AccountContext
    let removePeer: (PeerId)->Void
    init(context: AccountContext, removePeer:@escaping(PeerId)->Void) {
        self.context = context
        self.removePeer = removePeer
    }
    
    func peerInfo(_ peerId:PeerId) {
        context.sharedContext.bindings.rootNavigation().push(PeerInfoController(context: context, peerId: peerId))
    }
}

private struct GroupPeersState : Equatable {
    var temporaryParticipants: [TemporaryParticipant]
    var successfullyAddedParticipantIds: Set<PeerId>
    var removingParticipantIds: Set<PeerId>
}

private func _id_peer_id(_ id: PeerId) -> InputDataIdentifier {
    return InputDataIdentifier("_id_peer_id_\(id)")
}

extension GroupInfoEntry : Equatable {
    static func ==(lhs: GroupInfoEntry, rhs: GroupInfoEntry) -> Bool {
        return lhs.isEqual(to: rhs)
    }
}

private func groupPeersEntries(state: GroupPeersState, isEditing: Bool, view: PeerView, inputActivities: [PeerId: PeerInputActivity], channelMembers: [RenderedChannelParticipant], arguments: GroupPeersArguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index:Int32 = 0
    
    var usersBlock:[GroupInfoEntry] = []
    
    
    func applyBlock(_ block:[GroupInfoEntry]) {
        var block = block
        for (i, item) in block.enumerated() {
            var viewType = bestGeneralViewType(block, for: i)
            if i == 0 {
                if block.count > 1 {
                    viewType = .innerItem
                } else {
                    viewType = .lastItem
                }
            }
            
            block[i] = item.withUpdatedViewType(viewType)
            
        }
        for item in block {
            switch item {
            case let .member(_, _, _, peer, presence, inputActivity, memberStatus, editing, enabled, viewType):
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_peer_id(peer!.id), equatable: InputDataEquatable(item), item: { initialSize, stableId in
                    let label: String
                    switch memberStatus {
                    case let .admin(rank):
                        label = rank
                    case .member:
                        label = ""
                    }
                    
                    var string:String = L10n.peerStatusRecently
                    var color:NSColor = theme.colors.grayText
                    
                    if let peer = peer as? TelegramUser, let botInfo = peer.botInfo {
                        string = botInfo.flags.contains(.hasAccessToChatHistory) ? L10n.peerInfoBotStatusHasAccess : L10n.peerInfoBotStatusHasNoAccess
                    } else if let presence = presence as? TelegramUserPresence {
                        let timestamp = CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970
                        (string, _, color) = stringAndActivityForUserPresence(presence, timeDifference: arguments.context.timeDifference, relativeTo: Int32(timestamp))
                    }
                    
                    let interactionType:ShortPeerItemInteractionType
                    if let editing = editing {
                        
                        interactionType = .deletable(onRemove: { memberId in
                            arguments.removePeer(memberId)
                        }, deletable: editing.editable)
                    } else {
                        interactionType = .plain
                    }
                    
                    return ShortPeerRowItem(initialSize, peer: peer!, account: arguments.context.account, stableId: stableId, enabled: enabled, height: 50, photoSize: NSMakeSize(36, 36), titleStyle: ControlStyle(font: .medium(12.5), foregroundColor: theme.colors.text), statusStyle: ControlStyle(font: NSFont.normal(12.5), foregroundColor:color), status: string, inset: NSEdgeInsets(left:0,right:0), interactionType: interactionType, generalType: .context(label), viewType: viewType, action:{
                        arguments.peerInfo(peer!.id)
                    }, inputActivity: inputActivity)
                }))
                index += 1
            default:
                break
            }
            
        }
       // entries.append(contentsOf: block)
    }
    
    
    if let group = peerViewMainPeer(view) {
        let access = group.groupAccess
        
        if let cachedGroupData = view.cachedData as? CachedGroupData, let participants = cachedGroupData.participants {
            
            var updatedParticipants = participants.participants
            let existingParticipantIds = Set(updatedParticipants.map { $0.peerId })
            
            var peerPresences: [PeerId: PeerPresence] = view.peerPresences
            var peers: [PeerId: Peer] = view.peers
            var disabledPeerIds = state.removingParticipantIds
            
            if !state.temporaryParticipants.isEmpty {
                for participant in state.temporaryParticipants {
                    if !existingParticipantIds.contains(participant.peer.id) {
                        updatedParticipants.append(.member(id: participant.peer.id, invitedBy: arguments.context.account.peerId, invitedAt: participant.timestamp))
                        if let presence = participant.presence, peerPresences[participant.peer.id] == nil {
                            peerPresences[participant.peer.id] = presence
                        }
                        if peers[participant.peer.id] == nil {
                            peers[participant.peer.id] = participant.peer
                        }
                        disabledPeerIds.insert(participant.peer.id)
                    }
                }
            }
            
            let sortedParticipants = participants.participants.filter({peers[$0.peerId]?.displayTitle != nil}).sorted(by: { lhs, rhs in
                let lhsPresence = view.peerPresences[lhs.peerId] as? TelegramUserPresence
                let rhsPresence = view.peerPresences[rhs.peerId] as? TelegramUserPresence
                
                let lhsActivity = inputActivities[lhs.peerId]
                let rhsActivity = inputActivities[rhs.peerId]
                
                if lhsActivity != nil && rhsActivity == nil {
                    return true
                } else if rhsActivity != nil && lhsActivity == nil {
                    return false
                }
                
                if let lhsPresence = lhsPresence, let rhsPresence = rhsPresence {
                    return lhsPresence.status > rhsPresence.status
                } else if let _ = lhsPresence {
                    return true
                } else if let _ = rhsPresence {
                    return false
                }
                
                return lhs < rhs
            })
            
            for i in 0 ..< sortedParticipants.count {
                if let peer = view.peers[sortedParticipants[i].peerId] {
                    let memberStatus: GroupInfoMemberStatus
                    if access.highlightAdmins {
                        switch sortedParticipants[i] {
                        case .admin:
                            memberStatus = .admin(rank: L10n.chatAdminBadge)
                        case  .creator:
                            memberStatus = .admin(rank: L10n.chatOwnerBadge)
                        case .member:
                            memberStatus = .member
                        }
                    } else {
                        memberStatus = .member
                    }
                    
                    let editing:ShortPeerDeleting?
                    
                    if isEditing, let group = group as? TelegramGroup {
                        let deletable:Bool = group.canRemoveParticipant(sortedParticipants[i]) || (sortedParticipants[i].invitedBy == arguments.context.peerId && sortedParticipants[i].peerId != arguments.context.peerId)
                        editing = ShortPeerDeleting(editable: deletable)
                    } else {
                        editing = nil
                    }
                    
                    usersBlock.append(.member(section: Int(sectionId), index: i, peerId: peer.id, peer: peer, presence: view.peerPresences[peer.id], activity: inputActivities[peer.id], memberStatus: memberStatus, editing: editing, enabled: !disabledPeerIds.contains(peer.id), viewType: .singleItem))
                }
            }
        }
        
        if let cachedGroupData = view.cachedData as? CachedChannelData {
            let participants = channelMembers
            var updatedParticipants = participants
            let existingParticipantIds = Set(updatedParticipants.map { $0.peer.id })
            var peerPresences: [PeerId: PeerPresence] = view.peerPresences
            var peers: [PeerId: Peer] = view.peers
            var disabledPeerIds = state.removingParticipantIds
            
            
            if !state.temporaryParticipants.isEmpty {
                for participant in state.temporaryParticipants {
                    if !existingParticipantIds.contains(participant.peer.id) {
                        updatedParticipants.append(RenderedChannelParticipant(participant: .member(id: participant.peer.id, invitedAt: participant.timestamp, adminInfo: nil, banInfo: nil, rank: nil), peer: participant.peer))
                        if let presence = participant.presence, peerPresences[participant.peer.id] == nil {
                            peerPresences[participant.peer.id] = presence
                        }
                        if participant.peer.id == arguments.context.account.peerId {
                            peerPresences[participant.peer.id] = TelegramUserPresence(status: .present(until: Int32.max), lastActivity: Int32.max)
                        }
                        if peers[participant.peer.id] == nil {
                            peers[participant.peer.id] = participant.peer
                        }
                        disabledPeerIds.insert(participant.peer.id)
                    }
                }
            }
        
            
            var sortedParticipants = participants.filter({!$0.peer.rawDisplayTitle.isEmpty}).sorted(by: { lhs, rhs in
                let lhsPresence = lhs.presences[lhs.peer.id] as? TelegramUserPresence
                let rhsPresence = rhs.presences[rhs.peer.id] as? TelegramUserPresence
                
                let lhsActivity = inputActivities[lhs.peer.id]
                let rhsActivity = inputActivities[rhs.peer.id]
                
                if lhsActivity != nil && rhsActivity == nil {
                    return true
                } else if rhsActivity != nil && lhsActivity == nil {
                    return false
                }
                
                if let lhsPresence = lhsPresence, let rhsPresence = rhsPresence {
                    return lhsPresence.status > rhsPresence.status
                } else if let _ = lhsPresence {
                    return true
                } else if let _ = rhsPresence {
                    return false
                }
                
                return lhs < rhs
            })
            
            
            for i in 0 ..< sortedParticipants.count {
                let memberStatus: GroupInfoMemberStatus
                if access.highlightAdmins {
                    switch sortedParticipants[i].participant {
                    case let .creator(_, rank):
                        memberStatus = .admin(rank: rank ?? L10n.chatOwnerBadge)
                    case let .member(_, _, adminRights, _, rank):
                        memberStatus = adminRights != nil ? .admin(rank: rank ?? L10n.chatAdminBadge) : .member
                    }
                } else {
                    memberStatus = .member
                }
                
                let editing:ShortPeerDeleting?
                
                if isEditing, let group = group as? TelegramChannel {
                    let deletable:Bool = group.canRemoveParticipant(sortedParticipants[i].participant, accountId: arguments.context.account.peerId)
                    editing = ShortPeerDeleting(editable: deletable)
                } else {
                    editing = nil
                }
                
                usersBlock.append(GroupInfoEntry.member(section: Int(sectionId), index: i, peerId: sortedParticipants[i].peer.id, peer: sortedParticipants[i].peer, presence: sortedParticipants[i].presences[sortedParticipants[i].peer.id], activity: inputActivities[sortedParticipants[i].peer.id], memberStatus: memberStatus, editing: editing, enabled: !disabledPeerIds.contains(sortedParticipants[i].peer.id), viewType: .singleItem))
            }
        }
        
    }
    
    applyBlock(usersBlock)
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
//
    return entries
}

func PeerMediaGroupPeersController(context: AccountContext, peerId: PeerId, editing: Signal<Bool, NoError>) -> InputDataController {
    
    
    let initialState = GroupPeersState(temporaryParticipants: [], successfullyAddedParticipantIds: Set(), removingParticipantIds: Set())
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((GroupPeersState) -> GroupPeersState) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    let actionsDisposable = DisposableSet()
    
    
    var loadMoreControl: PeerChannelMemberCategoryControl?
    
    let channelMembersPromise = Promise<[RenderedChannelParticipant]>()
    
    let inputActivity = context.account.peerInputActivities(peerId: peerId)
        |> map { activities -> [PeerId : PeerInputActivity] in
            return activities.reduce([:], { (current, activity) -> [PeerId : PeerInputActivity] in
                var current = current
                current[activity.0] = activity.1
                return current
            })
    }

    if peerId.namespace == Namespaces.Peer.CloudChannel {
        let (disposable, control) = context.peerChannelMemberCategoriesContextsManager.recent(postbox: context.account.postbox, network: context.account.network, accountPeerId: context.account.peerId, peerId: peerId, updated: { state in
            channelMembersPromise.set(.single(state.list))
        })
        loadMoreControl = control
        actionsDisposable.add(disposable)
    } else {
        channelMembersPromise.set(.single([]))
    }
    
    
    
    
    let arguments = GroupPeersArguments(context: context, removePeer: { memberId in
        
        let signal = context.account.postbox.loadedPeerWithId(memberId)
            |> deliverOnMainQueue
            |> mapToSignal { peer -> Signal<Bool, NoError> in
                let result = ValuePromise<Bool>()
                result.set(true)
                return result.get()
            }
            |> mapToSignal { value -> Signal<Void, NoError> in
                if value {
                    updateState { state in
                        var state = state
                        for i in 0 ..< state.temporaryParticipants.count {
                            if state.temporaryParticipants[i].peer.id == memberId {
                                state.temporaryParticipants.remove(at: i)
                                break
                            }
                        }
                        state.successfullyAddedParticipantIds.remove(memberId)
                        state.removingParticipantIds.insert(memberId)
                        return state
                    }
                    
                    if peerId.namespace == Namespaces.Peer.CloudChannel {
                        return context.peerChannelMemberCategoriesContextsManager.updateMemberBannedRights(account: context.account, peerId: peerId, memberId: memberId, bannedRights: TelegramChatBannedRights(flags: [.banReadMessages], untilDate: Int32.max))
                            |> afterDisposed {
                                updateState { state in
                                    var state = state
                                    state.removingParticipantIds.remove(memberId)
                                    return state
                                }
                        }
                    }
                    
                    return removePeerMember(account: context.account, peerId: peerId, memberId: memberId)
                        |> deliverOnMainQueue
                        |> afterDisposed {
                            updateState { state in
                                var state = state
                                state.removingParticipantIds.remove(memberId)
                                return state
                            }
                    }
                } else {
                    return .complete()
                }
        }
        actionsDisposable.add(signal.start())
        
    })
    
    let dataSignal = combineLatest(queue: prepareQueue, statePromise.get(), context.account.postbox.peerView(id: peerId), channelMembersPromise.get(), inputActivity, editing) |> map {
        return InputDataSignalValue(entries: groupPeersEntries(state: $0, isEditing: $4, view: $1, inputActivities: $3, channelMembers: $2, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: dataSignal, title: "")
    controller.bar = .init(height: 0)
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    controller.getBackgroundColor = {
        theme.colors.background
    }
    
    controller.didLoaded = { controller, _ in
        controller.tableView.setScrollHandler { position in
            if let loadMoreControl = loadMoreControl {
                switch position.direction {
                case .bottom:
                    context.peerChannelMemberCategoriesContextsManager.loadMore(peerId: peerId, control: loadMoreControl)
                default:
                    break
                }
            }
        }
        
    }
    
    return controller
}
