"""Generate the checked-in Xcode project using only Python's standard library."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "ClockWork.xcodeproj"

def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def quote(value):
    return json.dumps(str(value), ensure_ascii=False)

def run():
    app_files = sorted(str(p.relative_to(ROOT)).replace("\\", "/") for p in (ROOT / "ClockWork").rglob("*.swift"))
    test_files = sorted(str(p.relative_to(ROOT)).replace("\\", "/") for p in (ROOT / "Tests").rglob("*.swift"))
    resources = ["ClockWork/Resources/PrivacyInfo.xcprivacy", "ClockWork/Resources/Assets.xcassets"]
    extras = ["ClockWork/Resources/Info.plist", "README.md"]
    objects = []
    def add(key, body): objects.append(f"\t\t{uid(key)} = {{ {body} }};")
    def refs(values): return "(" + ", ".join(uid(v) for v in values) + ("," if values else "") + ")"
    for file in app_files + test_files + resources + extras:
        filetype = "sourcecode.swift" if file.endswith(".swift") else "folder.assetcatalog" if file.endswith(".xcassets") else "text.plist.xml" if file.endswith((".plist", ".xcprivacy")) else "net.daringfireball.markdown"
        add("ref:" + file, f"isa = PBXFileReference; lastKnownFileType = {quote(filetype)}; path = {quote(file)}; sourceTree = SOURCE_ROOT;")
    for file in app_files + test_files + resources:
        add("build:" + file, f"isa = PBXBuildFile; fileRef = {uid('ref:' + file)};")
    add("app-product", 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = ClockWork.app; sourceTree = BUILT_PRODUCTS_DIR;')
    add("test-product", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = ClockWorkTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
    add("root-group", f"isa = PBXGroup; children = {refs(['app-group', 'test-group', 'resources-group', 'ref:README.md', 'products-group'])}; sourceTree = \"<group>\";")
    add("app-group", f"isa = PBXGroup; name = ClockWork; children = {refs(['ref:' + f for f in app_files])}; sourceTree = \"<group>\";")
    add("test-group", f"isa = PBXGroup; name = Tests; children = {refs(['ref:' + f for f in test_files])}; sourceTree = \"<group>\";")
    add("resources-group", f"isa = PBXGroup; name = Resources; children = {refs(['ref:' + f for f in resources + extras[:1]])}; sourceTree = \"<group>\";")
    add("products-group", f"isa = PBXGroup; name = Products; children = {refs(['app-product', 'test-product'])}; sourceTree = \"<group>\";")
    for target, files in [("app", app_files), ("test", test_files)]:
        add(target + "-sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(['build:' + f for f in files])}; runOnlyForDeploymentPostprocessing = 0;")
        add(target + "-frameworks", "isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;")
        add(target + "-resources", f"isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {refs(['build:' + f for f in resources] if target == 'app' else [])}; runOnlyForDeploymentPostprocessing = 0;")
    add("proxy", f"isa = PBXContainerItemProxy; containerPortal = {uid('project')}; proxyType = 1; remoteGlobalIDString = {uid('app-target')}; remoteInfo = ClockWork;")
    add("dependency", f"isa = PBXTargetDependency; target = {uid('app-target')}; targetProxy = {uid('proxy')};")
    for target, name, producttype in [("app", "ClockWork", "application"), ("test", "ClockWorkTests", "bundle.unit-test")]:
        add(target + "-target", f"isa = PBXNativeTarget; buildConfigurationList = {uid(target + '-configs')}; buildPhases = {refs([target + '-sources', target + '-frameworks', target + '-resources'])}; buildRules = (); dependencies = {refs(['dependency'] if target == 'test' else [])}; name = {name}; productName = {name}; productReference = {uid(target + '-product')}; productType = {quote('com.apple.product-type.' + producttype)};")
    project_settings = {
        "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SDKROOT": "iphoneos", "SWIFT_VERSION": "5.0",
        "SWIFT_STRICT_CONCURRENCY": "targeted", "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES", "GCC_WARN_UNUSED_FUNCTION": "YES",
    }
    app_settings = {
        "PRODUCT_BUNDLE_IDENTIFIER": "com.personal.ClockWork", "PRODUCT_NAME": "$(TARGET_NAME)",
        "INFOPLIST_FILE": "ClockWork/Resources/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
        "CODE_SIGN_STYLE": "Automatic", "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "1.0",
        "TARGETED_DEVICE_FAMILY": "1", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
        "SUPPORTS_MACCATALYST": "NO", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "SWIFT_EMIT_LOC_STRINGS": "YES",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
    }
    test_settings = {
        "PRODUCT_BUNDLE_IDENTIFIER": "com.personal.ClockWorkTests", "PRODUCT_NAME": "$(TARGET_NAME)",
        "GENERATE_INFOPLIST_FILE": "YES", "CODE_SIGN_STYLE": "Automatic", "TARGETED_DEVICE_FAMILY": "1",
        "BUNDLE_LOADER": "$(TEST_HOST)", "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/ClockWork.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/ClockWork",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @loader_path/Frameworks",
    }
    for scope, base in [("project", project_settings), ("app", app_settings), ("test", test_settings)]:
        for name in ["Debug", "Release"]:
            settings = dict(base)
            if scope == "project":
                settings.update({"DEBUG_INFORMATION_FORMAT": "dwarf" if name == "Debug" else "dwarf-with-dsym", "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if name == "Debug" else "-O"})
                if name == "Debug": settings.update({"ENABLE_TESTABILITY": "YES", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)", "ONLY_ACTIVE_ARCH": "YES"})
            body = " ".join(f"{key} = {quote(value)};" for key, value in settings.items())
            add(scope + "-" + name, f"isa = XCBuildConfiguration; buildSettings = {{ {body} }}; name = {name};")
        add(scope + "-configs", f"isa = XCConfigurationList; buildConfigurations = {refs([scope + '-Debug', scope + '-Release'])}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
    add("project", f"isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastSwiftUpdateCheck = 1600; LastUpgradeCheck = 1600; TargetAttributes = {{ {uid('app-target')} = {{ CreatedOnToolsVersion = 16.0; }}; {uid('test-target')} = {{ CreatedOnToolsVersion = 16.0; TestTargetID = {uid('app-target')}; }}; }}; }}; buildConfigurationList = {uid('project-configs')}; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = fr; hasScannedForEncodings = 0; knownRegions = (fr, en, Base); mainGroup = {uid('root-group')}; productRefGroup = {uid('products-group')}; projectDirPath = \"\"; projectRoot = \"\"; targets = {refs(['app-target', 'test-target'])};")
    PROJECT.mkdir(exist_ok=True)
    (PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n" + "\n".join(objects) + f"\n\t}};\n\trootObject = {uid('project')};\n}}\n", encoding="utf-8")
    schemes = PROJECT / "xcshareddata" / "xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    app_ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("app-target")}" BuildableName="ClockWork.app" BlueprintName="ClockWork" ReferencedContainer="container:ClockWork.xcodeproj"/>'
    test_ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("test-target")}" BuildableName="ClockWorkTests.xctest" BlueprintName="ClockWorkTests" ReferencedContainer="container:ClockWork.xcodeproj"/>'
    (schemes / "ClockWork.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_ref}</TestableReference></Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''', encoding="utf-8")
    workspace = PROJECT / "project.xcworkspace"
    workspace.mkdir(exist_ok=True)
    (workspace / "contents.xcworkspacedata").write_text('<?xml version="1.0" encoding="UTF-8"?><Workspace version="1.0"><FileRef location="self:"></FileRef></Workspace>\n', encoding="utf-8")
    print(f"Generated Xcode project: {len(app_files)} app files, {len(test_files)} test files.")

if __name__ == "__main__": run()
