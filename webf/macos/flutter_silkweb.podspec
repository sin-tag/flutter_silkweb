#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_silkweb.podspec' to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_silkweb'
  s.version          = '1.0.0'
  s.summary          = 'Embed React/Vue/Tailwind apps inside Flutter at native speed.'
  s.description      = <<-DESC
flutter_silkweb is an optimized fork of openwebf/webf with layout-read cache, smooth animations and a typed reactive bridge.
                       DESC
  s.homepage         = 'https://github.com/sin-tag/flutter_silkweb'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'sin-tag' => 'hoangtuyensk@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'FlutterMacOS'
  s.vendored_libraries = 'libwebf.dylib', 'libquickjs.dylib'
  s.prepare_command = 'bash prepare.sh'

  s.platform = :osx, '10.14'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
