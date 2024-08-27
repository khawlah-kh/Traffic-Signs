//
//  ContentView.swift
//  Traffic Signs
//
//  Created by Khawlah Khalid on 04/08/2024.
//

import SwiftUI

struct ContentView: View {
    @StateObject var vm: ViewModel = .init()

    var body: some View {
       
        VStack {
            Text(vm.classLabel)
            ScrollView{
                ForEach(vm.images, id: \.self){ image in
                    Image(image)
                        .resizable()
                        .scaledToFit()
                        .onTapGesture {
                            vm.classify(imageName: image)
                        }
                }
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
import CoreML
import Vision
    
//class TrafficSignDetector : ObservableObject{
//    let model: Traffic_Signs
//    init(model: Traffic_Signs) {
//        self.model = model
//    }
//
//    func detectAndClassifySign(from image: CIImage) -> (CGRect, String)? {
//            guard let model = try? VNCoreMLModel(for: model.model) else {
//                return nil
//            }
//
//            let request = VNCoreMLRequest(model: model) { request, error in
//                guard let results = request.results as? [VNCoreMLFeatureValueObservation],
//                      let topResult = results.first else {
//                    return
//                }
//
//                DispatchQueue.main.async {
//                    let className = topResult.featureValue.stringValue ?? "Unknown"
////                    let boundingBox = topResult.boundingBox
////                    print("Detected sign: \(className) at \(boundingBox)")
//                }
//            }
//
//        let handler = VNImageRequestHandler(cvPixelBuffer: image.pixelBuffer!)
//            DispatchQueue.global(qos: .userInitiated).async {
//                do {
//                    try handler.perform([request])
//                    if let result = request.results?.first as? VNCoreMLFeatureValueObservation {
//                        return (result.boundingBox, result.featureValue.stringValue ?? "Unknown")
//                    }
//                } catch {
//                    print("Error: \(error)")
//                }
//            }
//
//            return nil
//        }
//}

class ViewModel: ObservableObject{
    let model = Traffic_Signs()
    @Published var images: [String] = ["020_1_0001","004_1_0006","045_1_0004","002_0001_j", "011_1_0002_1_j"]
    @Published var classLabel: String = ""
    func classify(imageName: String){
        guard let uiImage = UIImage(named: imageName), let buffer =  Utalities.imageToPixelBuffer(uiImage) else {return}
        do{
            let  prediction = try model.prediction(image: buffer)
            self.classLabel = prediction.target
            //self.classLabel = prediction.classLabel
            //Just to explore
//            let predictionDic = try model.prediction(image: buffer)
//            let topPredictions = predictionDic.classLabelProbs.sorted { $0.value > $1.value }.prefix(3)
//
//            var result = ""
//            for (label, probability) in topPredictions {
//                print("Predicted class: \(label), Probability: \(probability)")
//                result.append(label+"="+"\(Int(probability*100))%\n")
//            }
//            self.classLabel = result
        }
        catch{
            print("Error")
        }
    }

}
