//
//  ViewController.swift
//  Connect
//
//  Created by Friedrich Weise on 13.11.18.
//  Copyright © 2018 Friedrich Weise. All rights reserved.
//

import Cocoa
import UserNotifications

enum ModalState {
    case ConnectionMode
    case BluetoothMode
    case EmptyDeviceListMode
}


class ViewController: NSViewController {
    
    @IBOutlet var errorView: NSStackView!
    @IBOutlet var tableView: NSTableView!
    @IBOutlet var scrollView: NSScrollView!
    
    let preferenceWindowController = PreferenceWindowController.shared
    
    var bluetooth: Bluetooth = Bluetooth.shared
    var state: ModalState = ModalState.ConnectionMode
    /* initalize view */
    override func viewDidLoad() {
        super.viewDidLoad()
        bluetooth.delegate = self
        tableView.backgroundColor = .clear
        tableView.target = self
        tableView.doubleAction = #selector(tableViewDoubleClick(_:))
    }
    /* modal window gets shown */
    override func viewWillAppear() {
        super.viewWillAppear()
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        tableView.scrollRowToVisible(0)
        reloadTableView()
    }
    
    /* interaction */
    @objc func tableViewDoubleClick(_ sender:AnyObject) {
        toggleConnectionState();
    }
    override func keyDown(with event: NSEvent) {
        //return or enter
        if ((event.keyCode == 36) || (event.keyCode == 76)) {
            toggleConnectionState()
        }
        //escape
        if (event.keyCode == 53) {
            closeModal()
        }
    }
    func toggleConnectionState() {
        guard tableView.selectedRow >= 0 else {
            return
        }
        
        let selectedCell = tableView.view(atColumn: 0, row: tableView.selectedRow, makeIfNecessary: false)
        if (selectedCell as? BluetoothTableCellView) != nil {
            self.bluetooth.setBluetoothPowerState(state: true)
            self.reloadTableView()
        }
        if let deviceCellView = selectedCell as? DeviceTableCellView {
            let device = self.bluetooth.getDevices()[tableView.selectedRow]
            deviceCellView.indicateProgress()
            let finishedHandler = {(success: Bool) -> Void in
                //hides the progress indicator and draws state image
                deviceCellView.indicateState()
                if success {
                    self.perform(#selector(self.closeModal), with: nil, afterDelay: 0)
                }
                self.reloadTableView()
            }
            
            let desiredState = !device.isConnected()
            self.bluetooth.modifyConnection(device: device, desiredState: desiredState, finished: finishedHandler)
        }
    }
    func reloadTableView() {
        //preserve selection state
        var selectedRow = tableView.selectedRow
        
        //refetch device list to incorperate connection changes
        self.bluetooth.refreshDeviceList()
        
        self.errorView.isHidden = true
        self.scrollView.isHidden = false
        
        if self.bluetooth.getBluetoothPowerState() == false {
            self.state = ModalState.BluetoothMode
            selectedRow = 0
        } else if self.bluetooth.getDevices().isEmpty {
            self.state = ModalState.EmptyDeviceListMode
            self.scrollView.isHidden = true
            self.errorView.isHidden = false
        } else {
            self.state = ModalState.ConnectionMode
        }
        
        tableView.reloadData()

        //restore selection state
        tableView.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
    }
    
    @objc func closeModal() {
        if let window = self.view.window {
            window.close()
        }
    }
}

extension ViewController: BluetoothWatcherDelegate {
    func deviceConnected() {
        self.reloadTableView()
    }
    
    func deviceDisconnected() {
        self.reloadTableView()
    }
}

extension ViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return self.bluetooth.getDevices().count
    }
}

extension ViewController: NSTableViewDelegate {
    
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if self.state == ModalState.BluetoothMode && row != 0 {
            return false
        } else {
            return true;
        }
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?{
        
        // create Bluetooth Cell View
        if row == 0 && self.state == ModalState.BluetoothMode {
            return tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "bluetoothRow"), owner: self) as! BluetoothTableCellView
        }
        
        let deviceView:DeviceTableCellView = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "deviceRow"), owner: self) as! DeviceTableCellView
        let bluetoothDevices = self.bluetooth.getDevices()
        
        guard bluetoothDevices.indices.contains(row),
            let name = bluetoothDevices[row].nameOrAddress,
            let recentAccess = bluetoothDevices[row].recentAccessDate() else {
            return nil
        }
        deviceView.nameTextField.stringValue = name
        deviceView.lastUsedTextField.stringValue = timeAgoSince(recentAccess)
        deviceView.setConnectionState(connnected: bluetoothDevices[row].isConnected())
        deviceView.shortcutView.associatedUserDefaultsKey = Config.key + name
        
        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: Config.key + name, toAction: { () -> Void in
            self.connectToDevice(device: bluetoothDevices[row])
        })

        if self.state == ModalState.BluetoothMode {
            deviceView.disabled()
        }
        
        return deviceView
    }
    
    func connectToDevice(device: IOBluetoothDevice) {
        
        let finishedHandler = {(success: Bool) -> Void in
        }
        
        showNotification(device: device)
        
        let desiredState = !device.isConnected()
        self.bluetooth.modifyConnection(device: device, desiredState: desiredState, finished: finishedHandler)
    }
    
    func showNotification(device: IOBluetoothDevice) {
        let content = UNMutableNotificationContent()
        var state = "Connecting"
        if(device.isConnected()) {
            state = "Disconnecting"
        }
        
        content.title = NSString.localizedUserNotificationString(forKey: "Bluetooth Connection", arguments: nil)
        content.body = NSString.localizedUserNotificationString(forKey: "\(state) \(device.nameOrAddress ?? "a bluetooth device")",
                                                                arguments: nil)
        
        let trigger = UNTimeIntervalNotificationTrigger.init(timeInterval: 0.3, repeats: false)
         
        // Create the request object.
        let request = UNNotificationRequest(identifier: "MorningAlarm", content: content, trigger: trigger)
        
        // Schedule the request.
        let center = UNUserNotificationCenter.current()
        center.add(request) { (error : Error?) in
            if let theError = error {
                print(theError.localizedDescription)
            }
        }
    }
}
