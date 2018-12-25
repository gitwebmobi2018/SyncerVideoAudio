//
//  ManageAppURLService.swift
//  VideoMergeTest
//
//  Created by Ivan on 12/11/18.
//  Copyright © 2018 Ivan. All rights reserved.
//

import Foundation

protocol ManageAppURLServiceProtocol {
    
    //create a new video file name
    func newVideoFileName() -> String
    //get video file full path
    func getVideoFileFullPath(of fileName: String) -> String
    // get file name from the path
    func getFileName(from url: URL) -> String
}

extension ManageAppURLServiceProtocol {
    
}

class ManageAppURLService: ManageAppURLServiceProtocol {
    var appDir: String
    
    init() {
        appDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
    }
    
    func newVideoFileName() -> String {
        let newFileName = Date().timeIntervalSince1970 * 1000
        return "\(newFileName).mov"
    }
    
    func getVideoFileFullPath(of fileName: String) -> String {
        return appDir + "/\(fileName)"
    }
    
    func getFileName(from url: URL) -> String {
        let pathComponents = url.path.split(separator: "/")
        return String(pathComponents.last!)
    }
}
