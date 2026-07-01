import Testing
@testable import NTFSAccessCore

@Suite("Filesystem identifier mapping")
struct FilesystemTests {

    @Test("NTFS identifier maps to NTFS kind")
    func ntfsIdentifierMapsToNTFS() {
        #expect(Filesystem.fromIdentifier("ntfs").kind == .ntfs)
        #expect(Filesystem.fromIdentifier("NTFS").kind == .ntfs)
    }

    @Test("Common filesystem identifiers map correctly")
    func commonFilesystemMappings() {
        #expect(Filesystem.fromIdentifier("apfs").kind == .apfs)
        #expect(Filesystem.fromIdentifier("hfs").kind == .hfs)
        #expect(Filesystem.fromIdentifier("exfat").kind == .exfat)
        #expect(Filesystem.fromIdentifier("msdos").kind == .fat32)
        #expect(Filesystem.fromIdentifier("ext4").kind == .ext)
    }

    @Test("Unknown / empty / unrecognized identifiers")
    func unknownAndOther() {
        #expect(Filesystem.fromIdentifier(nil).kind == .unknown)
        #expect(Filesystem.fromIdentifier("").kind == .unknown)
        #expect(Filesystem.fromIdentifier("zfs").kind == .other)
    }

    @Test("Drive.isNTFS reflects filesystem")
    func driveIsNTFSReflectsFilesystem() {
        let d = Drive(bsdName: "disk2s1", filesystem: Filesystem(kind: .ntfs, rawIdentifier: "ntfs"))
        #expect(d.isNTFS)
        let e = Drive(bsdName: "disk2s2", filesystem: Filesystem(kind: .apfs, rawIdentifier: "apfs"))
        #expect(!e.isNTFS)
    }
}
