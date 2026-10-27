#
# The pod an app's `pod install` adds for this plugin: `dn pub get` lists the
# plugin in the app's .dn-plugins-dependencies and the Podfile picks it up
# from there. `dn plugin build` reads this file too, so keep s.platform,
# s.frameworks and any s.dependency lines in this plain one-per-line form.
#
Pod::Spec.new do |s|
  s.name             = 'biometric_storage_kit'
  s.version          = '0.1.0'
  s.summary          = 'Biometric-protected secret storage for DartNative using iOS Keychain and Android Keystore.'
  s.description      = <<-DESC
Biometric-protected secret storage for DartNative using iOS Keychain and Android Keystore.
                       DESC
  s.homepage         = 'https://github.com/ManmohanTalwar/biometric_storage_kit'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = 'biometric_storage_kit contributors'
  s.source           = { :path => '.' }

  # Every Swift file under Classes/ is compiled into the app. The @_cdecl
  # functions in them are what lib/src/biometric_storage_kit_bindings.dart looks up.
  s.source_files     = 'Classes/**/*.swift'
  s.swift_version    = '5.9'
  s.platform = :ios, '15.0'
  s.frameworks       = 'Foundation', 'UIKit', 'Security', 'LocalAuthentication'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
