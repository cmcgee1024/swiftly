// swift-tools-version: 999.0.0

@_spi(ExperimentalTraits) import PackageDescription

// This is a list of system libraries that can be enabled in libarchive to add extra functionality using the specified trait.
// Dependent packages can enable the traits that they need and/or the `swift build` can enable one or more of them.
var traits = [
    (name: "ArchiveZ", define: "HAVE_LIBZ", libName: "zlib", moduleLoc: "swiftpm/zlib", pkgConfig: "zlib", aptProvider: "zlib1g-dev", makeSysLibTarget: true),
    (name: "ArchiveLZMA", define: "HAVE_LIBLZMA", libName: "lzma", moduleLoc: "swiftpm/lzma", pkgConfig: "liblzma", aptProvider: "liblzma-dev", makeSysLibTarget: true),
    (name: "ArchiveZSTD", define: "HAVE_LIBZSTD", libName: "zstd", moduleLoc: "swiftpm/zstd", pkgConfig: "libzstd", aptProvider: "libzstd-dev", makeSysLibTarget: true),
    (name: "ArchiveACL", define: "HAVE_LIBACL", libName: "acl", moduleLoc: "swiftpm/acl", pkgConfig: "libacl", aptProvider: "libacl1-dev", makeSysLibTarget: true),
    (name: "ArchiveATTR", define: "HAVE_LIBATTR", libName: "attr", moduleLoc: "swiftpm/attr", pkgConfig: "libattr", aptProvider: "libattr1-dev", makeSysLibTarget: true),
    (name: "ArchiveBSDXML", define: "HAVE_LIBBSDXML", libName: "bsdxml", moduleLoc: "swiftpm/bsdxml", pkgConfig: "libbsdxml", aptProvider: "libbsdxml-dev", makeSysLibTarget: true),
    (name: "ArchiveZ2", define: "HAVE_LIBBZ2", libName: "bz2", moduleLoc: "swiftpm/bz2", pkgConfig: "libbz2", aptProvider: "libbz2-dev", makeSysLibTarget: true),
    (name: "ArchiveB2", define: "HAVE_LIBB2", libName: "b2", moduleLoc: "swiftpm/b2", pkgConfig: "libb2", aptProvider: "libb2-dev", makeSysLibTarget: true),
    (name: "ArchiveCHARSET", define: "HAVE_LIBCHARSET", libName: "charset", moduleLoc: "swiftpm/charset", pkgConfig: "libcharset", aptProvider: "libcharset-dev", makeSysLibTarget: true),
    (name: "ArchiveCRYPTO", define: "HAVE_LIBCRYPTO", libName: "crypto", moduleLoc: "swiftpm/crypto", pkgConfig: "libcrypto", aptProvider: "libcrypto-dev", makeSysLibTarget: true),
    (name: "ArchiveEXPAT", define: "HAVE_LIBEXPAT", libName: "expat", moduleLoc: "swiftpm/expat", pkgConfig: "expat", aptProvider: "libexpat1-dev", makeSysLibTarget: true),
    (name: "ArchiveLZ4", define: "HAVE_LIBLZ4", libName: "lz4", moduleLoc: "swiftpm/lz4", pkgConfig: "liblz4", aptProvider: "liblz4-dev", makeSysLibTarget: true),
    (name: "ArchiveLZMADEC", define: "HAVE_LIBLZMADEC", libName: "lzmadec", moduleLoc: "swiftpm/lzmadec", pkgConfig: "liblzmadec", aptProvider: "liblzmadec-dev", makeSysLibTarget: true),
    (name: "ArchiveLZO2", define: "HAVE_LIBLZO2", libName: "lzo2", moduleLoc: "swiftpm/lzo2", pkgConfig: "liblzo2", aptProvider: "liblzo2-dev", makeSysLibTarget: true),
    (name: "ArchiveMBEDCRYPTO", define: "HAVE_LIBMBEDCRYPTO", libName: "mbedcrypto", moduleLoc: "swiftpm/mbedcrypto", pkgConfig: "libmbedcrypto", aptProvider: "libmbedcrypto7", makeSysLibTarget: true),
    (name: "ArchiveNETTLE", define: "HAVE_LIBNETTLE", libName: "nettle", moduleLoc: "swiftpm/nettle", pkgConfig: "nettle", aptProvider: "nettle-dev", makeSysLibTarget: true),
    // (name: "ArchivePCRE", define: "HAVE_LIBPCRE", libName: "pcre", moduleLoc: "swiftpm/pcre", pkgConfig: "libpcre", aptProvider: "libpcre-dev", makeSysLibTarget: true),
    // (name: "ArchivePCREPOSIX", define: "HAVE_LIBPCREPOSIX", libName: "pcreposix", moduleLoc: "swiftpm/pcreposix", pkgConfig: "libpcre-posix", aptProvider: "libpcre-dev", makeSysLibTarget: true),
    (name: "ArchivePCRE2", define: "HAVE_LIBPCRE2", libName: "pcre2", moduleLoc: "swiftpm/pcre2", pkgConfig: "libpcre2-8", aptProvider: "libpcre2-dev", makeSysLibTarget: true),
    (name: "ArchivePCRE2POSIX", define: "HAVE_LIBPCRE2POSIX", libName: "pcre2posix", moduleLoc: "swiftpm/pcre2posix", pkgConfig: "libpcre2-posix", aptProvider: "libpcre2-dev", makeSysLibTarget: true),
    (name: "ArchiveXML2", define: "HAVE_LIBXML2", libName: "xml2", moduleLoc: "swiftpm/xml2", pkgConfig: "libxml-2.0", aptProvider: "libxml2-dev", makeSysLibTarget: true),
]

#if os(macOS)
// macOS bundles zlib in its SDK, so in this case we don't add the system library, but allow the define to be set from the trait
traits[0] = (name: "ArchiveZ", define: "HAVE_LIBZ", libName: "zlib", moduleLoc: "swiftpm/zlib", pkgConfig: "zlib", aptProvider: "zlib1g-dev", makeSysLibTarget: false)
#endif

#if os(Linux)
let gnuSource: [CSetting] = [.define("_GNU_SOURCE")]
#else
let gnuSource: [CSetting] = []
#endif

let package = Package(
    name: "libarchive",
    products: [
        .library(
            name: "archive",
            type: .static,
            targets: ["CArchive"]
        ),
        .executable(
            name: "bsdcat",
            targets: ["bsdcat"]
        ),
    ],
    traits: Set<Trait>(traits.map { .trait(name: $0.name) }),
    targets: [
        .target(
            name: "CArchive",
            dependencies: traits.filter(\.makeSysLibTarget).map { trait in
                .target(
                    name: trait.libName,
                    condition: .when(traits: [trait.name])
                )
            },
            path: "libarchive",
            exclude: ["test"],
            publicHeadersPath: ".",
            cSettings: [
                .define("PLATFORM_CONFIG_H", to: "\"config_swiftpm.h\""),
            ] + traits.map { trait in
                .define(trait.define, to: "1", .when(traits: [trait.name]))
            }
        ),
        .target(
            name: "CArchiveFE",
            dependencies: ["CArchive"],
            path: "libarchive_fe",
            publicHeadersPath: ".",
            cSettings: [.define("PLATFORM_CONFIG_H", to: "\"config_swiftpm.h\"")]
        ),
        .executableTarget(
            name: "bsdcat",
            dependencies: ["CArchive", "CArchiveFE"],
            path: "cat",
            exclude: ["test"],
            cSettings: [.define("PLATFORM_CONFIG_H", to: "\"config_swiftpm.h\"")]
        ),
    ] + traits.filter(\.makeSysLibTarget).map { trait in
        .systemLibrary(
            name: trait.libName,
            path: trait.moduleLoc,
            pkgConfig: trait.pkgConfig,
            providers: [.apt([trait.aptProvider])]
        )
    }
)
