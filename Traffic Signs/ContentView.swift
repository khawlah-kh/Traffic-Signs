//
//  ContentView.swift
//  Traffic Signs
//
//  Created by Khawlah Khalid on 04/08/2024.
//

import SwiftUI
import CoreML
import Vision
//    
//
//class ViewModel: ObservableObject{
//    let model = Traffic_Signs()
//    @Published var classLabel: String = ""
//    func classify(imageName: String){
//        guard let uiImage = UIImage(named: imageName), let buffer =  Utalities.imageToPixelBuffer(uiImage) else {return}
//        do{
//            let  prediction = try model.prediction(image: buffer)
//            self.classLabel = prediction.target
//            //self.classLabel = prediction.classLabel
//            //Just to explore
////            let predictionDic = try model.prediction(image: buffer)
////            let topPredictions = predictionDic.classLabelProbs.sorted { $0.value > $1.value }.prefix(3)
////
////            var result = ""
////            for (label, probability) in topPredictions {
////                print("Predicted class: \(label), Probability: \(probability)")
////                result.append(label+"="+"\(Int(probability*100))%\n")
////            }
////            self.classLabel = result
//        }
//        catch{
//            print("Error")
//        }
//    }
//
//}
