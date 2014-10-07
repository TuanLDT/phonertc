import Foundation

class Session {
    var plugin: PhoneRTCPlugin
    var config: SessionConfig
    var constraints: RTCMediaConstraints
    var peerConnection: RTCPeerConnection!
    var pcObserver: PCObserver!
    var queuedRemoteCandidates: [RTCICECandidate]?
    var peerConnectionFactory: RTCPeerConnectionFactory
    
    init(plugin: PhoneRTCPlugin, peerConnectionFactory: RTCPeerConnectionFactory, config: SessionConfig) {
        self.plugin = plugin
        self.queuedRemoteCandidates = []
        self.config = config
        self.peerConnectionFactory = peerConnectionFactory
        
        // initialize basic media constraints
        self.constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                RTCPair(key: "OfferToReceiveAudio", value: "true"),
                RTCPair(key: "OfferToReceiveVideo", value: "false"),
            ],
            
            optionalConstraints: [
                RTCPair(key: "internalSctpDataChannels", value: "true"),
                RTCPair(key: "DtlsSrtpKeyAgreement", value: "true")
            ]
        )
    }
    
    func call() {
        // initialize a PeerConnection
        self.pcObserver = PCObserver(session: self)
        self.peerConnection =
            peerConnectionFactory.peerConnectionWithICEServers([],
                constraints: self.constraints,
                delegate: self.pcObserver)
        
        // create a media stream and add audio and/or video tracks
        var mediaStream = peerConnectionFactory.mediaStreamWithLabel("ARDAMS")
        mediaStream.addAudioTrack(peerConnectionFactory.audioTrackWithID("ARDAMSa0"))
        
        self.peerConnection.addStream(mediaStream, constraints: self.constraints)
        
        // create offer if initiator
        if self.config.isInitiator {
            self.peerConnection.createOfferWithDelegate(SessionDescriptionDelegate(session: self),
                constraints: constraints)
        }

    }
    
    func receiveMessage(message: String) {
        var error : NSError?
        let data : AnyObject? = NSJSONSerialization.JSONObjectWithData(
            message.dataUsingEncoding(NSUTF8StringEncoding)!,
            options: NSJSONReadingOptions.allZeros,
            error: &error)
        
        let type: String = data?.objectForKey("type") as NSString
        
        switch type {
        case "candidate":
            let mid: String = data?.objectForKey("id") as NSString
            let sdpLineIndex: Int = (data?.objectForKey("label") as NSNumber).integerValue
            let sdp: String = data?.objectForKey("candidate") as NSString

            let candidate = RTCICECandidate(
                mid: mid,
                index: sdpLineIndex,
                sdp: sdp
            )
            
            if self.queuedRemoteCandidates != nil {
                self.queuedRemoteCandidates?.append(candidate)
            } else {
                self.peerConnection.addICECandidate(candidate)
            }
            
        case "offer", "answer":
            let sdpString: String = data?.objectForKey("sdp") as NSString
            let sdp = RTCSessionDescription(
                type: type,
                sdp: self.preferISAC(sdpString)
            )
            
            self.peerConnection.setRemoteDescriptionWithDelegate(
                SessionDescriptionDelegate(session: self),
                sessionDescription: sdp
            )
            
        case "bye":
            self.disconnect()
            
        default:
            println("Invalid message \(message)")
        }
    }
    
    func disconnect() {
        
    }
    
    func preferISAC(sdpDescription: String) -> String {
        var mLineIndex = -1
        var isac16kRtpMap: String?
        
        let origSDP = sdpDescription.stringByReplacingOccurrencesOfString("\r\n", withString: "\n")
        var lines = origSDP.componentsSeparatedByString("\n")
        let isac16kRegex = NSRegularExpression.regularExpressionWithPattern(
            "^a=rtpmap:(\\d+) ISAC/16000[\r]?$",
            options: NSRegularExpressionOptions.allZeros,
            error: nil)
        
        for var i = 0;
            (i < lines.count) && (mLineIndex == -1 || isac16kRtpMap == nil);
            ++i {
            let line = lines[i]
            if line.hasPrefix("m=audio ") {
                mLineIndex = i
                continue
            }
                
            isac16kRtpMap = self.firstMatch(isac16kRegex!, string: line)
        }
        
        if mLineIndex == -1 {
            println("No m=audio line, so can't prefer iSAC")
            return origSDP
        }
        
        if isac16kRtpMap == nil {
            println("No ISAC/16000 line, so can't prefer iSAC")
            return origSDP
        }
        
        let origMLineParts = lines[mLineIndex].componentsSeparatedByString(" ")

        var newMLine: [String] = []
        var origPartIndex = 0;
        
        // Format is: m=<media> <port> <proto> <fmt> ...
        newMLine.append(origMLineParts[origPartIndex++])
        newMLine.append(origMLineParts[origPartIndex++])
        newMLine.append(origMLineParts[origPartIndex++])
        newMLine.append(isac16kRtpMap!)
        
        for ; origPartIndex < origMLineParts.count; ++origPartIndex {
            if isac16kRtpMap != origMLineParts[origPartIndex] {
                newMLine.append(origMLineParts[origPartIndex])
            }
        }
        
        lines[mLineIndex] = " ".join(newMLine)
        return "\r\n".join(lines)
    }
    
    func firstMatch(pattern: NSRegularExpression, string: String) -> String? {
        var nsString = string as NSString
        
        let result = pattern.firstMatchInString(string,
            options: NSMatchingOptions.allZeros,
            range: NSMakeRange(0, nsString.length))
        
        if result == nil {
            return nil
        }
        
        return nsString.substringWithRange(result!.rangeAtIndex(1))
    }

}

