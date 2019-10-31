//
//  ViewController.swift
//  Example
//
//  Created by CrazyWisdom on 15/12/14.
//  Copyright © 2015年 emqtt.io. All rights reserved.
//

import UIKit
import CocoaMQTT


class ViewController: UIViewController {
//    let defaultHost = "127.0.0.1"
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

    var mqtt: CocoaMQTT?
    
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var connectSpinner: UIActivityIndicatorView!
    
    @IBOutlet weak var masterOnButton: UIButton!
    @IBOutlet weak var masterOffButton: UIButton!

    @IBOutlet weak var ledSwitch1: UISwitch!
    @IBOutlet weak var ledSwitch2: UISwitch!
    @IBOutlet weak var ledSwitch3: UISwitch!
    @IBOutlet weak var ledSwitch4: UISwitch!

    @IBOutlet weak var ledSlider1: UISlider!
    @IBOutlet weak var ledSlider2: UISlider!
    @IBOutlet weak var ledSlider3: UISlider!
    @IBOutlet weak var ledSlider4: UISlider!

    @IBOutlet weak var batteryMeter1: BatteryView!
    @IBOutlet weak var batteryMeter2: BatteryView!
    @IBOutlet weak var batteryMeter3: BatteryView!
    @IBOutlet weak var batteryMeter4: BatteryView!

    lazy var hellhounds = getHellhounds()
    
    func getHellhounds() -> [(ledSwitch: UISwitch, ledSlider: UISlider, battery: BatteryView)] {
        return [(ledSwitch1, ledSlider1, batteryMeter1),
                (ledSwitch2, ledSlider2, batteryMeter2),
                (ledSwitch3, ledSlider3, batteryMeter3),
                (ledSwitch4, ledSlider4, batteryMeter4),
        ]
    }

    func mqttConnect() {
        _ = mqtt!.connect()
    }

    @IBAction func connectToServer() {
        connectSpinner.startAnimating()
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
        TRACE("SET BRIGHTNESS TOPIC: \(topic), SV:\(stateValue)")
        mqtt!.publish(topic, withString: stateValue, qos: .qos0)
    }
    
    func mqttGetStatus() {
        for i in 0..<kNumHellhounds
        {
            let topic = fullTopicFor(topic: kTopicGetStatus, hellhoundIndex: i)
            // value is ignored. "0" arbitrary
            mqtt!.publish(topic, withString: "0", qos: .qos0)
        }
    }
    
    func mqttSubscribeStatus() {
        for i in 0..<kNumHellhounds
        {
//            let subscribeTopic = fullTopicFor(topic: kTopicStatus, hellhoundIndex: i)
//            mqtt!.subscribe(subscribeTopic, qos: CocoaMQTTQOS.qos1)
            let subscribeJSONTopic = fullTopicFor(topic: kTopicStatusJSON, hellhoundIndex: i)
            mqtt!.subscribe(subscribeJSONTopic, qos: CocoaMQTTQOS.qos1)
        }
    }
    
    func mqttHandleMessage(topic: String, message: String) {
        connectButton.isSelected = true
        connectSpinner.stopAnimating()

        let topicComponents = topic.components(separatedBy: "/")
        assert(topicComponents.count == 3);
        let hellhoundId = topicComponents[1];
        if topicComponents[2] == kTopicStatusJSON {
            do {
                let filteredMessage = message.filter { !"\\".contains($0) }
                print (filteredMessage)
                let data = Data(filteredMessage.utf8)
                if let jsonArray = try JSONSerialization.jsonObject(with: data, options : .allowFragments) as? [String: Int]
                {
                   print(jsonArray) // use the json here
                    let ledState = (jsonArray["ledState"] == 1)
                    let brightness = jsonArray["ledLvl"]!
                    let battery = jsonArray["battery"]!
                    updateHellhoundView(index: Int(hellhoundId) ?? 0, isOn: ledState, brightness: brightness, batteryLevel: battery)
                } else {
                    print("bad json")
                }
            } catch let error as NSError {
                print(error)
            }
            return;
        }
    }
    
    @IBAction func ledSwitchValueChanged(_ sender: UISwitch) {
        mqttSetState(value: sender.isOn, hellhoundIndex: sender.tag)
    }
    
    @IBAction func ledBrightnessValueChanged(_ sender: UISlider) {
        mqttSetBrightness(value: Int(round(sender.value)), hellhoundIndex: sender.tag)
    }

    @IBAction func masterButtonPressed(_ sender: UIButton) {
        let isOn = sender==masterOnButton
        for i in 0..<kNumHellhounds {
            mqttSetState(value: isOn, hellhoundIndex: i)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        tabBarController?.delegate = self
        mqttSetting()
        mqttConnect()
        // selfSignedSSLSetting()
        // simpleSSLSetting()
        
        for hound in hellhounds {
            hound.ledSlider.maximumValue = 100.0
            hound.ledSlider.isContinuous = false
            hound.battery.direction = .maxXEdge
            hound.battery.level = 4
            hound.battery.lowThreshold = 20
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
    
    func updateHellhoundView(index: Int, isOn: Bool, brightness: Int, batteryLevel: Int) {
        TRACE("index: \(index) isOn: \(isOn) brightness: \(brightness) batteryLevel: \(batteryLevel)")
        hellhounds[index].ledSwitch.isOn = isOn
        hellhounds[index].ledSlider.value = Float(brightness)
        hellhounds[index].battery.level = Int(batteryLevel)
    }
    
    func mqttSetting() {
        let clientID = "HellHounds-Test-" + String(ProcessInfo().processIdentifier)
        mqtt = CocoaMQTT(clientID: clientID, host: defaultHost, port: 1883)
        mqtt!.username = ""
        mqtt!.password = ""
        mqtt!.willMessage = CocoaMQTTWill(topic: "/will", message: "dieout")
        mqtt!.keepAlive = 60
        mqtt!.delegate = self
        mqtt!.didReceiveMessage = { mqtt, message, id in
            print("Message received in topic \(message.topic) with payload \(message.string!)")
        }
        
    }

    func simpleSSLSetting() {
        let clientID = "CocoaMQTT-" + String(ProcessInfo().processIdentifier)
        mqtt = CocoaMQTT(clientID: clientID, host: defaultHost, port: 8883)
        mqtt!.username = ""
        mqtt!.password = ""
        mqtt!.willMessage = CocoaMQTTWill(topic: "/will", message: "dieout")
        mqtt!.keepAlive = 60
        mqtt!.delegate = self
        mqtt!.enableSSL = true
    }
    
    func selfSignedSSLSetting() {
        let clientID = "CocoaMQTT-" + String(ProcessInfo().processIdentifier)
        mqtt = CocoaMQTT(clientID: clientID, host: defaultHost, port: 8883)
        mqtt!.username = ""
        mqtt!.password = ""
        mqtt!.willMessage = CocoaMQTTWill(topic: "/will", message: "dieout")
        mqtt!.keepAlive = 60
        mqtt!.delegate = self
        mqtt!.enableSSL = true
        mqtt!.allowUntrustCACertificate = true
        
        let clientCertArray = getClientCertFromP12File(certName: "client-keycert", certPassword: "MySecretPassword")
        
        var sslSettings: [String: NSObject] = [:]
        sslSettings[kCFStreamSSLCertificates as String] = clientCertArray
        
        mqtt!.sslSettings = sslSettings
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
        let options : NSDictionary = [key: certPassword]
        
        var items : CFArray?
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
            self.mqttSubscribeStatus()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.mqttGetStatus()
            }
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
        let messageString = message.string ?? kEmptyResponse;
        TRACE("message: \(messageString), id: \(id)")
        mqttHandleMessage(topic: message.topic, message: messageString);
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopic topics: [String]) {
        TRACE("topics: \(topics)")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopic topic: String) {
        TRACE("topic: \(topic)")
    }
    
    func mqttDidPing(_ mqtt: CocoaMQTT) {
        TRACE()
    }
    
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
        TRACE()
    }

    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        TRACE("\(err.description)")
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
