#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_silkweb'
  s.version          = '1.0.0'
  s.summary          = 'Embed React/Vue/Tailwind apps inside Flutter at native speed.'
  s.description      = <<-DESC
  flutter_silkweb is a W3C-compliant web rendering engine for Flutter, optimized fork of openwebf/webf with layout-read cache, smooth animations, full Tailwind support and a typed reactive bridge.
                       DESC
  s.homepage         = 'https://github.com/sin-tag/flutter_silkweb'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'sin-tag' => 'hoangtuyensk@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.libraries = 'c++'
  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'GCC_ENABLE_CPP_EXCEPTIONS' => 'NO',
    'GCC_ENABLE_CPP_RTTI' => 'YES',
    'OTHER_CPLUSPLUSFLAGS' => '-DNDEBUG -std=c++20 -fno-exceptions -fvisibility=hidden -fdata-sections -ffunction-sections', # Add specific C++ flags
    "OTHER_CFLAGS" => '-DNDEBUG',
    'LLVM_LTO' => 'YES', # Enable Link Time Optimization for release builds
    'GCC_OPTIMIZATION_LEVEL' => 's', # Enable optimization for size
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) ' +
      'APP_REV=\\"3090db6cb\\" ' +
      'APP_VERSION=\\"0.24.27\\" ' +
      'CONFIG_VERSION=\\"2025-04-26\\" ' +
      'WEBF_QUICK_JS_ENGINE=1 ' +
      'FLUTTER_BACKEND=1 ' +
      'IS_IOS=1 ' +
      'ENABLE_PROFILE=0 ',
    'HEADER_SEARCH_PATHS' => '$(inherited) ' +
      ' "${PODS_TARGET_SRCROOT}/../src/third_party/quickjs/include" '  +
      ' "${PODS_TARGET_SRCROOT}/../src/third_party/gumbo-parser/src" ' +
      ' "${PODS_TARGET_SRCROOT}/../src/third_party/modp_b64/include" ' +
      ' "${PODS_TARGET_SRCROOT}/../src/third_party/double_conversion" ' +
      ' "${PODS_TARGET_SRCROOT}/../src/third_party/dart" ' +
      ' "${PODS_TARGET_SRCROOT}/../src/foundation" ' +
      ' "${PODS_TARGET_SRCROOT}/../src/code_gen" ' +
      ' "${PODS_TARGET_SRCROOT}/../src" ' +
      ' "${PODS_TARGET_SRCROOT}/../src/include" ' +
      ' "${PODS_TARGET_SRCROOT}/../src/core_rs/include" ' +
      ' "${PODS_TARGET_SRCROOT}/../src/third_party" ' +
      ' "${PODS_TARGET_SRCROOT}/../src/core" ' +
      ' "${PODS_TARGET_SRCROOT}/../src/bindings" '
  }
  s.swift_version = '5.0'
end
