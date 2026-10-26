//
//  ViewController.swift
//  Example
//
//  Created by CrazyWisdom on 15/12/14.
//  Copyright © 2015年 emqtt.io. All rights reserved.
//

import UIKit

/// The storyboard controls for one hound card.
struct HoundCard {
    var ledSwitch: UISwitch
    var ledSlider: UISlider
    var battery: BatteryView
    var view: UIView
}

class ViewController: UIViewController {
    // For testing, launch with `-mqttHost localhost` (and optionally `-mqttPort 1884`),
    // read through UserDefaults, to use a local broker.
    let store = HoundStore(transport: MQTTNIOTransport(
        host: UserDefaults.standard.string(forKey: "mqttHost") ?? "broker.hivemq.com",
        port: UserDefaults.standard.integer(forKey: "mqttPort").nonZero ?? 1883
    ))

    @IBOutlet weak var connectButton: UIButton!

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

    /// Card i shows hound index i; the switch and slider tags hold the same index.
    var houndCards: [HoundCard] = []
    var masterCard: HoundCard!

    func getHoundCards() -> [HoundCard] {
        return [
            HoundCard(ledSwitch: ledSwitch1, ledSlider: ledSlider1, battery: batteryMeter1, view: hellhoundView1),
            HoundCard(ledSwitch: ledSwitch2, ledSlider: ledSlider2, battery: batteryMeter2, view: hellhoundView2),
            HoundCard(ledSwitch: ledSwitch3, ledSlider: ledSlider3, battery: batteryMeter3, view: hellhoundView3),
            HoundCard(ledSwitch: ledSwitchJack, ledSlider: ledSliderJack, battery: batteryMeterJack, view: hellhoundViewJack)
        ]
    }

    func getMasterCard() -> HoundCard {
        return HoundCard(ledSwitch: ledSwitchMaster, ledSlider: ledSliderMaster, battery: batteryMeterMaster, view: hellhoundViewMaster)
    }

    // UIKit tracks the store properties read here and calls this again when they change.
    override func updateProperties() {
        super.updateProperties()
        updateConnectionUI(store.connectionState)
        for (card, hound) in zip(houndCards, store.hounds) {
            updateCard(card, hound: hound)
        }
        if let masterCard {
            updateCard(masterCard, hound: store.master)
        }
    }

    func updateConnectionUI(_ connectionState: MQTTConnectionState) {
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
        store.connect()
    }

    @IBAction func ledSwitchValueChanged(_ sender: UISwitch) {
        store.setOn(sender.isOn, houndIndex: sender.tag)
    }

    @IBAction func ledBrightnessValueChanged(_ sender: UISlider) {
        store.setBrightness(Int(round(sender.value)), houndIndex: sender.tag)
    }

    @IBAction func ledMasterSwitchValueChanged(_ sender: UISwitch) {
        store.setAllOn(sender.isOn)
    }

    @IBAction func ledMasterBrightnessValueChanged(_ sender: UISlider) {
        store.setAllBrightness(Int(round(sender.value)))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupOverlay()
        houndCards = getHoundCards()
        masterCard = getMasterCard()
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        tabBarController?.delegate = self

        for card in houndCards + [masterCard!] {
            card.ledSlider.maximumValue = 100.0
            card.ledSlider.isContinuous = false
            card.battery.direction = .maxXEdge
            card.battery.level = 4
            card.battery.lowThreshold = 20
            card.view.alpha = 0.3
        }

        if let tabBarController = self.tabBarController {
            var viewControllers = tabBarController.viewControllers
            viewControllers?.remove(at: 2)
            viewControllers?.remove(at: 1)
            tabBarController.viewControllers = viewControllers
        }

        // Stay connected only while in the foreground; the transport reconnects on its own in between.
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        store.connect()
    }

    @objc func appDidEnterBackground() {
        store.disconnect()
    }

    @objc func appWillEnterForeground() {
        store.connect()
    }

    override func viewWillAppear(_ animated: Bool) {
        navigationController?.navigationBar.isHidden = false
    }

    func updateCardColor(_ cardView: UIView, isConnected: Bool) {
        // Set background color
        cardView.backgroundColor = UIColor(red: 75/255, green: 10/255, blue: 10/255, alpha: 1.0) // Dark Blood Red
        
        // Rounded corners
        cardView.layer.cornerRadius = 8
        cardView.clipsToBounds = false
        
        // Shadow properties for the card effect
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.2
        cardView.layer.shadowOffset = CGSize(width: 0, height: 4)
        cardView.layer.shadowRadius = 8
        
        cardView.alpha = isConnected ? 1.0 : 0.3
    }

    func updateCard(_ card: HoundCard, hound: Hound) {
        card.ledSwitch.isOn = hound.isOn
        card.ledSlider.value = Float(hound.brightness)
        card.battery.level = hound.battery
        updateCardColor(card.view, isConnected: hound.isConnected)
    }
}

extension ViewController: UITabBarControllerDelegate {
    // Prevent automatic popToRootViewController on double-tap of UITabBarController
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        return viewController != tabBarController.selectedViewController
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
