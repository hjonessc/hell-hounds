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
    let defaultHost   = "broker.hivemq.com"
    let topicPrefix   = "HellHounds-MQTT/esp/"
    let topicSetState = "set-state"
    let topicSetLevel = "set-level"
    let topicStatus   = "/status"
    let mqttLedOn     = "0"
    let mqttLedOff    = "1"

    var mqtt: CocoaMQTT?
    
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var ledSwitch1: UISwitch!
    @IBOutlet weak var ledSlider1: UISlider!
    @IBOutlet weak var ledSwitch2: UISwitch!
    @IBOutlet weak var ledSlider2: UISlider!
    @IBOutlet weak var ledSwitch3: UISwitch!
    @IBOutlet weak var ledSlider3: UISlider!
    @IBOutlet weak var batteryMeter1: BatteryView!

    lazy var hellhounds = getHellhounds()
    
    func getHellhounds() -> [(ledSwitch: UISwitch, ledSlider: UISlider, battery: BatteryView)] {
        return [(ledSwitch1, ledSlider1, batteryMeter1),
            (ledSwitch2, ledSlider2, batteryMeter1),
            (ledSwitch3, ledSlider3, batteryMeter1)]
    }
    

    @IBAction func connectToServer() {
        _ = mqtt!.connect()
    }
    
    func mqttSetState(value: Bool, hellhoundIndex: Int) {
        let topic = topicPrefix + topicSetState
        let stateValue = value ? mqttLedOff : mqttLedOn
        mqtt!.publish(topic, withString: stateValue, qos: .qos0)
    }
    
    func mqttSetBrightness(value: Int, hellhoundIndex: Int) {
        let topic = topicPrefix + topicSetLevel
        let stateValue = String(value)
        mqtt!.publish(topic, withString: stateValue, qos: .qos0)
    }
    
    @IBAction func ledSwitchValueChanged(_ sender: UISwitch) {
        mqttSetState(value: sender.isOn, hellhoundIndex: sender.tag)
    }
    
    @IBAction func ledBrightnessValueChanged(_ sender: UISlider) {
        mqttSetBrightness(value: Int(round(sender.value)), hellhoundIndex: sender.tag)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        tabBarController?.delegate = self
        mqttSetting()
        // selfSignedSSLSetting()
        // simpleSSLSetting()
        
        for hound in hellhounds {
            hound.ledSlider.maximumValue = 100.0
            hound.ledSlider.isContinuous = false
            hound.battery.direction = .maxXEdge
            hound.battery.level = 4
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
            mqtt.subscribe("HellHounds-MQTT/esp/status", qos: CocoaMQTTQOS.qos1)
//            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
//                mqtt.publish("HellHounds-MQTT/esp/status", withString: "", qos: .qos0)
//            }

//            let chatViewController = storyboard?.instantiateViewController(withIdentifier: "ChatViewController") as? ChatViewController
//            chatViewController?.mqtt = mqtt
//            navigationController!.pushViewController(chatViewController!, animated: true)
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
        let messageString = String(message.string.description.filter { !"\n\r".contains($0) })

        TRACE("message: \(messageString), id: \(id)")
        var valueArray = message.string.description.components(separatedBy: CharacterSet.decimalDigits.inverted)
        valueArray = valueArray.filter(){$0 != ""}
        assert(valueArray.count>=2, "too few integers in status message")

        let switchOn = Int(valueArray[0])==1
        let brightness = Int(valueArray[1]) ?? 0
        TRACE("    array: \(valueArray) switchOn: \(switchOn) brightness: \(brightness)")

        updateHellhoundView(index: 0, isOn: switchOn, brightness: brightness, batteryLevel: brightness)
        updateHellhoundView(index: 1, isOn: switchOn, brightness: brightness, batteryLevel: brightness)
        updateHellhoundView(index: 2, isOn: switchOn, brightness: brightness, batteryLevel: brightness)
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
