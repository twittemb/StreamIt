//
//  AppDelegate.swift
//  StreamIt
//
//  Created by Thibault Wittemberg on 14/04/2016.
//  Copyright © 2016 Thibault Wittemberg. All rights reserved.
//

import UIKit
import CocoaAsyncSocket

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, GCDAsyncSocketDelegate {

    var window: UIWindow?
    let ip = IPChecker.getIP()
    let serverQueue = dispatch_queue_create("ServerQueue", DISPATCH_QUEUE_SERIAL)
    var clientSocket: GCDAsyncSocket?

    // Methodes du Delegate
    
    func socket(sock: GCDAsyncSocket!, didConnectToHost host: String!, port: UInt16) {
        print ("Connected to \(host)")
        
        // enregistrement dans le broker MQTT
        let json = ["ip": "\(self.ip)",
                    "port": 10001,
                    "name": "\(UIDevice.currentDevice().name)",
                    "model": "\(UIDevice.currentDevice().model)",
                    "serial": "\(UIDevice.currentDevice().identifierForVendor!.description)",
                    "url": ["mjpeg":"/"],
                    "available": false,
                    "found": true
        ]
        
        if NSJSONSerialization.isValidJSONObject(json) { // True
            do {
                let rawData = try NSJSONSerialization.dataWithJSONObject(json, options: .PrettyPrinted)
                let readable = NSString(data: rawData, encoding: NSUTF8StringEncoding)
                let goodReadable = readable?.stringByReplacingOccurrencesOfString("\\/", withString: "/")
                sock.writeData(goodReadable!.dataUsingEncoding(NSUTF8StringEncoding), withTimeout: -1, tag: 0)
            } catch {
                print ("Failed contacting hmi.armonic ...")
            }
        }
        
    }
    
    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        // Override point for customization after application launch.
        return true
    }

    func applicationWillResignActive(application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        // desenregistrement dans le broker MQTT
        do {
            self.clientSocket = GCDAsyncSocket(delegate: self, delegateQueue: self.serverQueue)
            try self.clientSocket!.connectToHost("hmi.armonic", onPort: 43210, withTimeout: -1)
        } catch {
            print ("Failed contacting hmi.armonic ...")
        }
    }


}

