//
//  Traffic_Sign_Data.swift
//  Traffic Signs
//
//  Created by Khawlah Khalid on 28/08/2024.
//

import Foundation



import UIKit
import Vision
import AVFoundation

//csv
class TrafficSignManager{
    static var idNameDic:[String:String] = [:]

    static func readCivFile(named fileName: String = "labels") -> [String: Any]? {
        guard let filepath = Bundle.main.path(forResource: fileName, ofType: "csv") else {
            return [:]
        }

        do {
            // Read the file content
            var data = ""
            data = try String(contentsOfFile: filepath)
            var rows = data.components(separatedBy: "\n")
            rows.removeFirst()
            rows.removeLast()
            for row in rows {
                let columns = row.components(separatedBy: ",")
                let id = columns[0]
                let label = columns[1]
                self.idNameDic[id] = label
            }

        } catch {
            print("Error reading or parsing the file: \(error)")
        }
        
        return nil
    }

   static func createIdNameDic(){
       if let civData = readCivFile() as? [String:String] {
            self.idNameDic = civData
            print("Parsed dictionary: \(civData)")
        } else {
            print("Failed to read or parse the .csv file.")
        }
    }

}

