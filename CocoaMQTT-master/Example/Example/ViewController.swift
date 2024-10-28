//
//  ViewController.swift
//  Example
//
//  Created by CrazyWisdom on 15/12/14.
//  Copyright © 2015年 emqtt.io. All rights reserved.
//

import UIKit
import CocoaMQTT

struct Hellhound {
    var ledSwitch: UISwitch
    var ledSlider: UISlider
    var battery: BatteryView
    var view: UIView
    var isConnected: Bool = false
}

class ViewController: UIViewController {
    let defaultHost      = "broker.hivemq.com"
    let kTopicPrefix     = "HellHounds-MQTT"
    let kTopicSetState   = "set-state"
    let kTopicSetLevel   = "set-level"
    let kTopicStatus     = "status"
    let kTopicStatusJSON = "status-json"
    let kTopicGetStatus  = "msg"
    let kMqttLedOn       = "0"
    let kMqttLedOff      = "1"
    let kEmptyResponse   = "EMPTY_RESPONSE"
    
    let kNumHellhounds = 4

    enum ConnectionState {
        case connected
        case connecting
        case disconnected
    }

    var mqtt: CocoaMQTT?
    
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var connectSpinner: UIActivityIndicatorView!
    
    @IBOutlet weak var masterOnButton: UIButton!
    @IBOutlet weak var masterOffButton: UIButton!

    @IBOutlet weak var ledSwitch1: UISwitch!
    @IBOutlet weak var ledSwitch2: UISwitch!
    @IBOutlet weak var ledSwitch3: UISwitch!
    @IBOutlet weak var ledSwitchJack: UISwitch!
    @IBOutlet weak var ledSwitchMaster: UISwitch!

    @IBOutlet weak var ledSlider1: UISlider!
    @IBOutlet weak var ledSlider2: UISlider!
    @IBOutlet weak var ledSlider3: UISlider!
    @IBOutlet weak var ledSliderJack: UISlider!
    @IBOutlet weak var ledSliderMaster: UISlider!

    @IBOutlet weak var batteryMeter1: BatteryView!
    @IBOutlet weak var batteryMeter2: BatteryView!
    @IBOutlet weak var batteryMeter3: BatteryView!
    @IBOutlet weak var batteryMeterJack: BatteryView!
    @IBOutlet weak var batteryMeterMaster: BatteryView!
    
    @IBOutlet weak var hellhoundView1: UIView!
    @IBOutlet weak var hellhoundView2: UIView!
    @IBOutlet weak var hellhoundView3: UIView!
    @IBOutlet weak var hellhoundViewJack: UIView!
    @IBOutlet weak var hellhoundViewMaster: UIView!

    // MARK: - Overlay
    var overlayView: UIView!
    var overlayLabel: UILabel!
    var overlaySpinner: UIActivityIndicatorView!

    func setupOverlay() {
        overlayView = UIView(frame: view.bounds)
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        overlayView.isHidden = true

        overlaySpinner = UIActivityIndicatorView(style: .large)
        // TODO: Make it white
        overlaySpinner.color = .white
        overlaySpinner.center = overlayView.center
        overlaySpinner.startAnimating()

        overlayLabel = UILabel()
        overlayLabel.textColor = .white
        overlayLabel.textAlignment = .center
        overlayLabel.translatesAutoresizingMaskIntoConstraints = false

        overlayView.addSubview(overlaySpinner)
        overlayView.addSubview(overlayLabel)

        view.addSubview(overlayView)

        // Center the label below the spinner
        NSLayoutConstraint.activate([
            overlayLabel.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
            overlayLabel.topAnchor.constraint(equalTo: overlaySpinner.bottomAnchor, constant: 20)
        ])
    }

    func showOverlay(withText text: String) {
        overlayLabel.text = text
        overlayView.isHidden = false
    }

    func hideOverlay() {
        overlayView.isHidden = true
    }

    // MARK: -

    var hellhounds: [Hellhound] = []
    var masterHellhound: Hellhound!
    
    func getHellhounds() -> [Hellhound] {
        return [
            Hellhound(ledSwitch: ledSwitch1, ledSlider: ledSlider1, battery: batteryMeter1, view: hellhoundView1),
            Hellhound(ledSwitch: ledSwitch2, ledSlider: ledSlider2, battery: batteryMeter2, view: hellhoundView2),
            Hellhound(ledSwitch: ledSwitch3, ledSlider: ledSlider3, battery: batteryMeter3, view: hellhoundView3),
            Hellhound(ledSwitch: ledSwitchJack, ledSlider: ledSliderJack, battery: batteryMeterJack, view: hellhoundViewJack)
        ]
    }

    func getMasterHellhound() -> Hellhound {
        return Hellhound(ledSwitch: ledSwitchMaster, ledSlider: ledSliderMaster, battery: batteryMeterMaster, view: hellhoundViewMaster)
    }

    func mqttConnect() {
        connectionState = .connecting
        _ = mqtt!.connect()
    }

    var connectionState: ConnectionState = .disconnected {
        didSet {
        print("Connection state changed to: \(connectionState)")
            updateConnectionUI()
        }
    }

    func updateConnectionUI() {
        switch connectionState {
        case .connected:
            connectButton.setTitle("Connected", for: .normal)
            connectButton.isSelected = true
            hideOverlay()
        case .connecting:
            connectButton.setTitle("Connecting...", for: .normal)
            connectButton.isSelected = false
            showOverlay(withText: "Connecting...")
        case .disconnected:
            connectButton.setTitle("Connect", for: .normal)
            connectButton.isSelected = false
            hideOverlay()
        }
    }

    @IBAction func connectToServer() {
        print("connectToServer pressed")
        connectionState = .connecting
        mqttConnect()
    }
    
    func fullTopicFor(topic: String, hellhoundIndex: Int) -> String {
        return "\(kTopicPrefix)/\(hellhoundIndex)/\(topic)"
    }
    
    func fullTopicForAllHounds(topic: String) -> String {
        return kTopicPrefix + "$" + topic
    }
    
    func mqttSetState(value: Bool, hellhoundIndex: Int) {
        let topic = fullTopicFor(topic: kTopicSetState, hellhoundIndex: hellhoundIndex)
        let stateValue = value ? kMqttLedOff : kMqttLedOn
        mqtt!.publish(topic, withString: stateValue, qos: .qos0)
    }
    
    func mqttSetBrightness(value: Int, hellhoundIndex: Int) {
        let topic = fullTopicFor(topic: kTopicSetLevel, hellhoundIndex: hellhoundIndex)
        let stateValue = String(value)
        print("SET BRIGHTNESS TOPIC: \(topic), SV:\(stateValue)")
        mqtt!.publish(topic, withString: stateValue, qos: .qos0)
    }
    
    func mqttGetStatus() {
        for i in 0..<hellhounds.count {
            let topic = fullTopicFor(topic: kTopicGetStatus, hellhoundIndex: i)
            // value is ignored. "0" arbitrary
            mqtt!.publish(topic, withString: "0", qos: .qos0)
        }
    }
    
    func mqttSubscribeStatus() {
        for i in 0..<hellhounds.count {
            let subscribeJSONTopic = fullTopicFor(topic: kTopicStatusJSON, hellhoundIndex: i)
            mqtt!.subscribe(subscribeJSONTopic, qos: CocoaMQTTQoS.qos1)
        }
    }
    
    func mqttHandleMessage(topic: String, message: String) {
        let topicComponents = topic.components(separatedBy: "/")
        assert(topicComponents.count == 3)
        let hellhoundId = topicComponents[1]
        if topicComponents[2] == kTopicStatusJSON {
            do {
                let filteredMessage = message.filter { !"\\".contains($0) }
                let data = Data(filteredMessage.utf8)
                if let jsonArray = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Int] {
//                    print(jsonArray) // use the json here
                    let ledState = (jsonArray["ledState"] == 1)
                    let brightness = jsonArray["ledLvl"]!
                    let battery = jsonArray["battery"]!
                    updateHellhoundView(index: Int(hellhoundId) ?? 0, isOn: ledState, brightness: brightness, batteryLevel: battery)
                } else {
                    print("bad json\n\(filteredMessage)")
                }
            } catch let error as NSError {
                print(error)
            }
            return
        }
    }
    
    @IBAction func ledSwitchValueChanged(_ sender: UISwitch) {
        mqttSetState(value: sender.isOn, hellhoundIndex: sender.tag)
    }
    
    @IBAction func ledBrightnessValueChanged(_ sender: UISlider) {
        mqttSetBrightness(value: Int(round(sender.value)), hellhoundIndex: sender.tag)
    }

    @IBAction func ledMasterSwitchValueChanged(_ sender: UISwitch) {
        for i in 0..<hellhounds.count {
            mqttSetState(value: sender.isOn, hellhoundIndex: i)
        }
    }
    
    @IBAction func ledMasterBrightnessValueChanged(_ sender: UISlider) {
        for i in 0..<hellhounds.count {
            mqttSetBrightness(value: Int(round(sender.value)), hellhoundIndex: i)
        }
    }

    @IBAction func masterButtonPressed(_ sender: UIButton) {
        let isOn = sender == masterOnButton
        for i in 0..<hellhounds.count {
            mqttSetState(value: isOn, hellhoundIndex: i)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupOverlay()
        hellhounds = getHellhounds()
        masterHellhound = getMasterHellhound()
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        tabBarController?.delegate = self
        mqttSetting()
        mqttConnect()
        
        for hound in hellhounds + [masterHellhound!] {
            hound.ledSlider.maximumValue = 100.0
            hound.ledSlider.isContinuous = false
            hound.battery.direction = .maxXEdge
            hound.battery.level = 4
            hound.battery.lowThreshold = 20
            hound.view.alpha = 0.3
        }

        if let tabBarController = self.tabBarController {
            var viewControllers = tabBarController.viewControllers
            viewControllers?.remove(at: 2)
            viewControllers?.remove(at: 1)
            tabBarController.viewControllers = viewControllers
        }
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        navigationController?.navigationBar.isHidden = false
    }
    
    // update master hellhound view to highest value of all hellhounds for isOn and brightness
    func updateMasterHellhoundView() {
        var isOn = false
        var brightness: Float = 0
        var batteryLevel: Int? = nil
        var isConnected = false
        for hound in hellhounds where hound.isConnected {
            if hound.ledSwitch.isOn {
                isOn = true
            }
            if hound.ledSlider.value > brightness {
                brightness = hound.ledSlider.value
            }
            if batteryLevel == nil || hound.battery.level < batteryLevel! {
                batteryLevel = hound.battery.level
            }
            isConnected = true
        }
        masterHellhound.ledSwitch.isOn = isOn
        masterHellhound.ledSlider.value = brightness
        if let batteryLevel = batteryLevel {
            masterHellhound.battery.level = batteryLevel
        }
        masterHellhound.isConnected = isConnected
        masterHellhound.view.alpha = isConnected ? 1.0 : 0.3
    }
    
    func updateHellhoundView(index: Int, isOn: Bool, brightness: Int, batteryLevel: Int) {
        print("updateHellhoundView: index: \(index) isOn: \(isOn) brightness: \(brightness) batteryLevel: \(batteryLevel)")
        hellhounds[index].ledSwitch.isOn = isOn
        hellhounds[index].ledSlider.value = Float(brightness)
        hellhounds[index].battery.level = Int(batteryLevel)
        hellhounds[index].isConnected = true
        hellhounds[index].view.alpha = 1.0
        updateMasterHellhoundView()
    }
    
    func mqttSetting() {
        let clientID = "HellHounds-Test-" + String(ProcessInfo().processIdentifier)
        mqtt = CocoaMQTT(clientID: clientID, host: defaultHost, port: 1883)
        mqtt!.username = ""
        mqtt!.password = ""
        mqtt!.willMessage = CocoaMQTTMessage(topic: "/will", string: "dieout")
        mqtt!.keepAlive = 60
        mqtt!.delegate = self
        mqtt!.didReceiveMessage = { mqtt, message, id in
//            print("Message received in topic \(message.topic) with payload \(message.string!)")
        }
        
    }

    func getClientCertFromP12File(certName: String, certPassword: String) -> CFArray? {
        // get p12 file path
        let resourcePath = Bundle.main.path(forResource: certName, ofType: "p12")
        
        guard let filePath = resourcePath, let p12Data = NSData(contentsOfFile: filePath) else {
            print("Failed to open the certificate file: \(certName).p12")
            return nil
        }
        
        // create key dictionary for reading p12 file
        let key = kSecImportExportPassphrase as String
        let options: NSDictionary = [key: certPassword]
        
        var items: CFArray?
        let securityError = SecPKCS12Import(p12Data, options, &items)
        
        guard securityError == errSecSuccess else {
            if securityError == errSecAuthFailed {
                print("ERROR: SecPKCS12Import returned errSecAuthFailed. Incorrect password?")
            } else {
                print("Failed to open the certificate file: \(certName).p12")
            }
            return nil
        }
        
        guard let theArray = items, CFArrayGetCount(theArray) > 0 else {
            return nil
        }
        
        let dictionary = (theArray as NSArray).object(at: 0)
        guard let identity = (dictionary as AnyObject).value(forKey: kSecImportItemIdentity as String) else {
            return nil
        }
        let certArray = [identity] as CFArray
        
        return certArray
    }

}

extension ViewController: CocoaMQTTDelegate {
    // Optional ssl CocoaMQTTDelegate
    func mqtt(_ mqtt: CocoaMQTT, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
        TRACE("trust: \(trust)")
        /// Validate the server certificate
        ///
        /// Some custom validation...
        ///
        /// if validatePassed {
        ///     completionHandler(true)
        /// } else {
        ///     completionHandler(false)
        /// }
        completionHandler(true)
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        TRACE("ack: \(ack)")

        if ack == .accept {
            connectionState = .connected
            self.mqttSubscribeStatus()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.mqttGetStatus()
            }
        } else {
            connectionState = .disconnected
        }
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didStateChangeTo state: CocoaMQTTConnState) {
        TRACE("new state: \(state)")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
        TRACE("message: \(message.string.description), id: \(id)")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
        TRACE("id: \(id)")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16 ) {
        let messageString = message.string ?? kEmptyResponse
        TRACE("message: \(messageString), id: \(id)")
        mqttHandleMessage(topic: message.topic, message: messageString)
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
        TRACE("success: \(success), failed: \(failed)")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
        TRACE("topics: \(topics)")
    }

    func mqttDidPing(_ mqtt: CocoaMQTT) {
        TRACE()
    }
    
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
        TRACE()
    }

    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        TRACE("\(err.description)")
        connectionState = .disconnected
    }
}

extension ViewController: UITabBarControllerDelegate {
    // Prevent automatic popToRootViewController on double-tap of UITabBarController
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        return viewController != tabBarController.selectedViewController
    }
}

extension ViewController {
    func TRACE(_ message: String = "", fun: String = #function) {
        let names = fun.components(separatedBy: ":")
        var prettyName: String
        if names.count == 2 {
            prettyName = names[0]
        } else {
            prettyName = names[1]
        }
        
        if fun == "mqttDidDisconnect(_:withError:)" {
            prettyName = "didDisconect"
        }

        print("[TRACE] [\(prettyName)]: \(message)")
    }
}

extension Optional {
    // Unwarp optional value for printing log only
    var description: String {
        if let warped = self {
            return "\(warped)"
        }
        return ""
    }
}
