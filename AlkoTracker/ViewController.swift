//
//  ViewController.swift
//  AlkoTracker
//
//  Created by Olli Warro on 26.6.2018.
//  Copyright © 2018 Olli Warro. All rights reserved.
//

import UIKit
import MapKit
import AudioToolbox
import Alamofire
import SwiftyJSON

class ViewController: UIViewController, CLLocationManagerDelegate {

    let locationManager: CLLocationManager = CLLocationManager()
    var latitude: CLLocationDegrees = 0
    var longitude: CLLocationDegrees = 0
    var nearestPlace: Place? = nil
    var places: [Place] = []
    var hasFetched: Bool = false
    var keys: NSDictionary?
    var API_KEY: String? = ""
    @IBOutlet weak var arrowImageView: UIImageView!
    @IBOutlet weak var targetTextView: UILabel!
    @IBOutlet weak var distanceTextView: UILabel!
    @IBOutlet var backgroundView: UIView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let path = Bundle.main.path(forResource: "Keys", ofType: "plist") {
            keys = NSDictionary(contentsOfFile: path)
        }
        
        if let dict = keys {
            print("1")
            API_KEY = dict["API_KEY"] as? String
        }

        print("2")
        configureLocationManager()
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    func configureLocationManager() {
        switch CLLocationManager.authorizationStatus() {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            break
        case .restricted, .denied:
            return
        case .authorizedWhenInUse, .authorizedAlways:
            break
        }
        
        if !CLLocationManager.locationServicesEnabled() {
            return
        }
        
        locationServicesAvailable()
    }
    
    func locationServicesAvailable() {
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10.0
        locationManager.headingOrientation = .portrait
        // locationManager.headingFilter = kCLHeadingFilterNone
        locationManager.delegate = self
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let latestLocation = locations.last!
        if (latestLocation.horizontalAccuracy > 0) {
            let latitude = latestLocation.coordinate.latitude
            let longitude = latestLocation.coordinate.longitude
    
            self.latitude = latitude
            self.longitude = longitude
            
            if !hasFetched {
                fetchPlaces()
                hasFetched = true
            }
            self.getNearestPlace()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        if nearestPlace == nil {
            return
        }
        
        let angleToPlace = angleFromCoordinate(lat1: latitude, lng1: longitude, lat2: nearestPlace!.latitude, lng2: nearestPlace!.longitude)
        let phoneHeadingInRadians = self.fromDegreesToRadians(degrees: (newHeading.magneticHeading))
        let placeInRadians = self.fromDegreesToRadians(degrees: angleToPlace)
        var diff = newHeading.magneticHeading - angleToPlace
        if diff < 0 {
            diff += 360
        }
        diff = abs(diff - 180) / 180
        var green = 0.0
        var red = 0.0
        var blue = 0.0
        
        if diff >= 0.8 {
            setColors(red: &red, green: &green, blue: &blue, redValue: 127, greenValue: 226, blueValue: 145)
        } else if diff >= 0.5 {
            setColors(red: &red, green: &green, blue: &blue, redValue: 251, greenValue: 246, blueValue: 73)
        } else if diff >= 0.2 {
            self.distanceTextView.textColor = .black
            self.targetTextView.textColor = .black
            setColors(red: &red, green: &green, blue: &blue, redValue: 232, greenValue: 94, blueValue: 85)
            AudioServicesPlaySystemSound(1519)
        } else {
            self.distanceTextView.textColor = .white
            self.targetTextView.textColor = .white
            setColors(red: &red, green: &green, blue: &blue, redValue: 255, greenValue: 0, blueValue: 0)
            AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
        }
        
        let color = UIColor(red: CGFloat(red / 255), green: CGFloat(green / 255), blue: CGFloat(blue / 255), alpha: 1.0)
        UIView.animate(withDuration: 0.5) {
            self.arrowImageView.transform = CGAffineTransform(rotationAngle: CGFloat(placeInRadians - phoneHeadingInRadians))
            self.backgroundView.backgroundColor = color
        }
    }
    
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        return true
    }
    
    func setColors(red: inout Double, green: inout Double, blue: inout Double, redValue: Double, greenValue: Double, blueValue: Double) {
        red = redValue
        green = greenValue
        blue = blueValue
    }
    
    func fetchPlaces() {
        let apiUrl = "https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=\(latitude),\(longitude)&radius=1500&keyword=alko&key=\(API_KEY!)"
        Alamofire.request(apiUrl).responseJSON {
            (response) in
            if let responseJSON = JSON(response.data!)["results"].array {
                for place in responseJSON {
                    let placeLocation = place["geometry"]["location"]
                    let newPlace = Place()
                    newPlace.name = place["name"].string!
                    newPlace.latitude = placeLocation["lat"].double!
                    newPlace.longitude = placeLocation["lng"].double!
                    newPlace.isOpen = place["opening_hours"]["open_now"].bool!
                    self.places.append(newPlace)
                }
                self.getNearestPlace()
            }
        }
    }
    
    func getNearestPlace() {
        var shortestDistance : Double = .infinity
        for place in places {
            let d = calculateDistanceFromUser(lat: place.latitude, lng: place.longitude)
            if d < shortestDistance {
                shortestDistance = d
                nearestPlace = place
            }
        }
        if nearestPlace == nil {
            return
        }
        targetTextView.text = nearestPlace!.name
        distanceTextView.text = "\(Int(round(calculateDistanceFromUser(lat: nearestPlace!.latitude, lng: nearestPlace!.longitude))))m"
    }
    
    func calculateDistanceFromUser(lat: Double, lng: Double) -> Double {
        let R = 6371e3
        let l1 = fromDegreesToRadians(degrees: lat)
        let l2 = fromDegreesToRadians(degrees: latitude)
        let lDiff = fromDegreesToRadians(degrees: (lat - latitude))
        let lonDiff = fromDegreesToRadians(degrees: (lng - longitude))
        let a = sin(lDiff / 2) * sin(lDiff / 2) + cos(l1) * cos(l2) * sin(lonDiff / 2) * sin(lonDiff / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        let d = R * c
        return d
    }
    
    func angleFromCoordinate(lat1: Double, lng1: Double, lat2: Double, lng2: Double) -> Double {
        let l1 = fromDegreesToRadians(degrees: lat1)
        let l2 = fromDegreesToRadians(degrees: lat2)
        let lg1 = fromDegreesToRadians(degrees: lng1)
        let lg2 = fromDegreesToRadians(degrees: lng2)
        let lngDiff = lg2 - lg1
        let x = cos(l2) * sin(lngDiff)
        let y = cos(l1) * sin(l2) - sin(l1) * cos(l2) * cos(lngDiff)
        return radiansToDegrees(radians: atan2(x, y))
    }
    
    func fromDegreesToRadians(degrees: Double) -> Double {
        return degrees * Double.pi / 180
    }
    
    func radiansToDegrees(radians: Double) -> Double {
        return radians * 180 / Double.pi
    }

}
