import UIKit

/// Menu thao tác cho một bài hát (phát tiếp, hàng đợi, yêu thích, playlist, tải xuống).
enum SongActions {
    static func present(for song: Song, from vc: UIViewController, sourceView: UIView? = nil,
                        removeTitle: String? = nil, onRemove: (() -> Void)? = nil) {
        let sheet = UIAlertController(title: song.title, message: song.artist, preferredStyle: .actionSheet)
        let player = PlayerEngine.shared
        let library = Library.shared

        sheet.addAction(UIAlertAction(title: "Phát tiếp theo", style: .default) { _ in
            player.playNext(song)
            Toast.show("Sẽ phát tiếp theo")
        })
        sheet.addAction(UIAlertAction(title: "Thêm vào hàng đợi", style: .default) { _ in
            player.addToQueue(song)
            Toast.show("Đã thêm vào hàng đợi")
        })
        let liked = library.isLiked(song)
        sheet.addAction(UIAlertAction(title: liked ? "Bỏ yêu thích" : "Thêm vào Yêu thích", style: .default) { _ in
            let nowLiked = library.toggleLike(song)
            LastFM.shared.love(song, loved: nowLiked)
            Toast.show(nowLiked ? "Đã thêm vào Yêu thích" : "Đã bỏ khỏi Yêu thích")
        })
        if let artistId = song.artistId, !artistId.isEmpty {
            sheet.addAction(UIAlertAction(title: "Xem nghệ sĩ", style: .default) { _ in
                MusicPageViewController.present(artist: song.artist, id: artistId, from: vc)
            })
        }
        sheet.addAction(UIAlertAction(title: "Thêm vào playlist…", style: .default) { _ in
            presentPlaylistPicker(for: song, from: vc, sourceView: sourceView)
        })

        let manager = DownloadManager.shared
        if library.isDownloaded(song) {
            sheet.addAction(UIAlertAction(title: "Xoá bản tải xuống", style: .destructive) { _ in
                library.removeDownload(song)
                Toast.show("Đã xoá bản tải")
            })
        } else if manager.isActive(song.videoId) {
            sheet.addAction(UIAlertAction(title: "Huỷ tải xuống", style: .destructive) { _ in
                manager.cancel(song.videoId)
            })
        } else {
            sheet.addAction(UIAlertAction(title: "Tải xuống để nghe offline", style: .default) { _ in
                manager.start(song)
                Toast.show("Đang tải xuống…")
            })
        }
        if let removeTitle = removeTitle, let onRemove = onRemove {
            sheet.addAction(UIAlertAction(title: removeTitle, style: .destructive) { _ in onRemove() })
        }
        sheet.addAction(UIAlertAction(title: "Đóng", style: .cancel, handler: nil))
        anchor(sheet, in: vc, sourceView: sourceView)
        vc.present(sheet, animated: true, completion: nil)
    }

    static func presentPlaylistPicker(for song: Song, from vc: UIViewController, sourceView: UIView? = nil) {
        let sheet = UIAlertController(title: "Thêm vào playlist", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Playlist mới…", style: .default) { _ in
            promptNewPlaylist(from: vc) { name in
                let list = Library.shared.createPlaylist(name: name, with: song)
                Toast.show("Đã tạo \"\(list.name)\"")
            }
        })
        for list in Library.shared.playlists {
            sheet.addAction(UIAlertAction(title: list.name, style: .default) { _ in
                if Library.shared.add(song, toPlaylist: list.id) {
                    Toast.show("Đã thêm vào \"\(list.name)\"")
                } else {
                    Toast.show("Bài này đã có trong \"\(list.name)\"")
                }
            })
        }
        sheet.addAction(UIAlertAction(title: "Đóng", style: .cancel, handler: nil))
        anchor(sheet, in: vc, sourceView: sourceView)
        vc.present(sheet, animated: true, completion: nil)
    }

    static func promptNewPlaylist(from vc: UIViewController, initial: String = "", title: String = "Playlist mới",
                                  confirm: String = "Tạo", _ done: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: "Đặt tên cho playlist", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Tên playlist"
            field.text = initial
            field.autocapitalizationType = .sentences
        }
        alert.addAction(UIAlertAction(title: "Huỷ", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: confirm, style: .default) { _ in
            done(alert.textFields?.first?.text ?? "")
        })
        vc.present(alert, animated: true, completion: nil)
    }

    private static func anchor(_ sheet: UIAlertController, in vc: UIViewController, sourceView: UIView?) {
        if let popover = sheet.popoverPresentationController {
            let source = sourceView ?? vc.view!
            popover.sourceView = source
            popover.sourceRect = sourceView == nil
                ? CGRect(x: source.bounds.midX, y: source.bounds.midY, width: 1, height: 1)
                : source.bounds
        }
    }
}
