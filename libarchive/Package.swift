// swift-tools-version: 999.0.0

@_spi(ExperimentalTraits) import PackageDescription

// This is a list of traits that can be enabled in libarchive to add extra functionality using the specified trait coming from either a system library or an SDK built-in.
// Dependent packages can enable the traits that they need and/or the `swift build` can enable one or more of them.
let traits: [(name: String, define: String, libName: String, moduleLoc: String, pkgConfig: String, aptProvider: String, sysLibPlatforms: [PackageDescription.Platform])] = [
    (name: "Z", define: "HAVE_LIBZ", libName: "zlib", moduleLoc: "swiftpm/zlib", pkgConfig: "zlib", aptProvider: "zlib1g-dev", sysLibPlatforms: [.linux]), // This library is included in the SDK when on macOS
    (name: "LZMA", define: "HAVE_LIBLZMA", libName: "lzma", moduleLoc: "swiftpm/lzma", pkgConfig: "liblzma", aptProvider: "liblzma-dev", sysLibPlatforms: []),
    (name: "ZStd", define: "HAVE_LIBZSTD", libName: "zstd", moduleLoc: "swiftpm/zstd", pkgConfig: "libzstd", aptProvider: "libzstd-dev", sysLibPlatforms: []),
    (name: "ACL", define: "HAVE_LIBACL", libName: "acl", moduleLoc: "swiftpm/acl", pkgConfig: "libacl", aptProvider: "libacl1-dev", sysLibPlatforms: []),
    (name: "ATTR", define: "HAVE_LIBATTR", libName: "attr", moduleLoc: "swiftpm/attr", pkgConfig: "libattr", aptProvider: "libattr1-dev", sysLibPlatforms: []),
    (name: "BSDXML", define: "HAVE_LIBBSDXML", libName: "bsdxml", moduleLoc: "swiftpm/bsdxml", pkgConfig: "libbsdxml", aptProvider: "libbsdxml-dev", sysLibPlatforms: []),
    (name: "Z2", define: "HAVE_LIBBZ2", libName: "bz2", moduleLoc: "swiftpm/bz2", pkgConfig: "libbz2", aptProvider: "libbz2-dev", sysLibPlatforms: []),
    (name: "B2", define: "HAVE_LIBB2", libName: "b2", moduleLoc: "swiftpm/b2", pkgConfig: "libb2", aptProvider: "libb2-dev", sysLibPlatforms: []),
    (name: "Charset", define: "HAVE_LIBCHARSET", libName: "charset", moduleLoc: "swiftpm/charset", pkgConfig: "libcharset", aptProvider: "libcharset-dev", sysLibPlatforms: []),
    (name: "Crypto", define: "HAVE_LIBCRYPTO", libName: "crypto", moduleLoc: "swiftpm/crypto", pkgConfig: "libcrypto", aptProvider: "libcrypto-dev", sysLibPlatforms: []),
    (name: "Expat", define: "HAVE_LIBEXPAT", libName: "expat", moduleLoc: "swiftpm/expat", pkgConfig: "expat", aptProvider: "libexpat1-dev", sysLibPlatforms: []),
    (name: "LZ4", define: "HAVE_LIBLZ4", libName: "lz4", moduleLoc: "swiftpm/lz4", pkgConfig: "liblz4", aptProvider: "liblz4-dev", sysLibPlatforms: []),
    (name: "LZMADec", define: "HAVE_LIBLZMADEC", libName: "lzmadec", moduleLoc: "swiftpm/lzmadec", pkgConfig: "liblzmadec", aptProvider: "liblzmadec-dev", sysLibPlatforms: []),
    (name: "LZO2", define: "HAVE_LIBLZO2", libName: "lzo2", moduleLoc: "swiftpm/lzo2", pkgConfig: "liblzo2", aptProvider: "liblzo2-dev", sysLibPlatforms: []),
    (name: "MbedCrypto", define: "HAVE_LIBMBEDCRYPTO", libName: "mbedcrypto", moduleLoc: "swiftpm/mbedcrypto", pkgConfig: "libmbedcrypto", aptProvider: "libmbedcrypto7", sysLibPlatforms: []),
    (name: "Nettle", define: "HAVE_LIBNETTLE", libName: "nettle", moduleLoc: "swiftpm/nettle", pkgConfig: "nettle", aptProvider: "nettle-dev", sysLibPlatforms: []),
    // (name: "PCRE", define: "HAVE_LIBPCRE", libName: "pcre", moduleLoc: "swiftpm/pcre", pkgConfig: "libpcre", aptProvider: "libpcre-dev", sysLibPlatforms: []),
    // (name: "PCREPOSIX", define: "HAVE_LIBPCREPOSIX", libName: "pcreposix", moduleLoc: "swiftpm/pcreposix", pkgConfig: "libpcre-posix", aptProvider: "libpcre-dev", sysLibPlatforms: []),
    (name: "PCRE2", define: "HAVE_LIBPCRE2", libName: "pcre2", moduleLoc: "swiftpm/pcre2", pkgConfig: "libpcre2-8", aptProvider: "libpcre2-dev", sysLibPlatforms: []),
    (name: "PCRE2POSIX", define: "HAVE_LIBPCRE2POSIX", libName: "pcre2posix", moduleLoc: "swiftpm/pcre2posix", pkgConfig: "libpcre2-posix", aptProvider: "libpcre2-dev", sysLibPlatforms: []),
    (name: "XML2", define: "HAVE_LIBXML2", libName: "xml2", moduleLoc: "swiftpm/xml2", pkgConfig: "libxml-2.0", aptProvider: "libxml2-dev", sysLibPlatforms: []),
]

let pkgTraits: Set<PackageDescription.Trait> = Set<Trait>(traits.map { .trait(name: $0.name) })

let sysLibs: [PackageDescription.Target] = traits.map { trait in
    .systemLibrary(
        name: trait.libName,
        path: trait.moduleLoc,
        pkgConfig: trait.pkgConfig,
        providers: [.apt([trait.aptProvider])]
    )
}

let sysLibDeps: [PackageDescription.Target.Dependency] = traits.map { trait in
    .target(
        name: trait.libName,
        condition: .when(platforms: trait.sysLibPlatforms, traits: [trait.name])
    )
}

let cSettings: [PackageDescription.CSetting] = traits.map { trait in
    .define(trait.define, to: "1", .when(traits: [trait.name]))
}

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
    traits: pkgTraits,
    targets: [
        .target(
            name: "CArchive",
            dependencies: sysLibDeps,
            path: "libarchive",
            exclude: ["test"],
            publicHeadersPath: ".",
            cSettings: [
                .define("PLATFORM_CONFIG_H", to: "\"config_swiftpm.h\""),
            ] + cSettings
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
    ] + sysLibs
)
