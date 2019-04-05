//
//  ViewController.swift
//  VideoMergeTest
//
//  Created by Ivan on 12/11/18.
//  Copyright © 2018 Ivan. All rights reserved.
//

import UIKit

class MainVC: UIViewController {

    @IBOutlet weak var mTableView: UITableView!
    
    // properties
    var videoItemArray = [VideoItem]() {
        didSet {
            self.mTableView.reloadData()
        }
    }
    
    //MARK: - IBAction functions
    @IBAction func onAddBtn(_ sender: Any?) {
        performSegue(withIdentifier: C_AddNewSegueID, sender: nil)
    }
}

//MARK: - Override functions
extension MainVC {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.setVideoItemArray()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == C_PlayVideoItemSegueID {
            let vc = segue.destination as! PlayVC
            vc.selectedVideoItem = sender as? VideoItem
        }
        if segue.identifier == C_AddNewSegueID {
            let vc = segue.destination as! RecordVC
            vc.delegate = self
        }
    }
    
}

//MARK: - Custom functions
extension MainVC {
    
    func setVideoItemArray() {
        let defaults = UserDefaults.standard

        if let encodedObject = defaults.object(forKey: C_LocalVideoItemsKey) {
            let object = NSKeyedUnarchiver.unarchiveObject(with: encodedObject as! Data )
            videoItemArray = object as! [VideoItem]
        }
    }
    
}

//MARK: - RecordVCDelegate
extension MainVC: RecordVCDelegate {
    
    func onDismiss() {
        self.setVideoItemArray()
    }
    
}

//MARK: - Table view data source & delegate
extension MainVC: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return videoItemArray.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: C_VideoItemCellID, for: indexPath) as! VideoItemCell
        
        cell.set(videoItem: videoItemArray[indexPath.row])
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        performSegue(withIdentifier: C_PlayVideoItemSegueID, sender: self.videoItemArray[indexPath.row])
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 100
    }
    
}
