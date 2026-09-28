Pod::Spec.new do |s|
  s.name = 'capsi_ffi'
  s.version = '1.0.2'
  s.summary = 'Capsi native Rust FFI bridge'
  s.description = 'Static Rust FFI bridge used by the Capsi Flutter client.'
  s.homepage = 'https://capsi.win'
  s.license = { :type => 'MIT' }
  s.author = { 'CAPSICOM' => 'capsi.win' }
  s.source = { :path => '.' }
  s.platform = :ios, '12.0'
  s.vendored_frameworks = 'CapsiFfi.xcframework'
  s.static_framework = true
  # Dart FFI resolves these functions from the iOS process image. Keep the
  # statically linked Rust exports visible in release builds.
  s.user_target_xcconfig = {
    'DEAD_CODE_STRIPPING' => 'NO',
    'STRIP_INSTALLED_PRODUCT' => 'NO',
    'DEPLOYMENT_POSTPROCESSING' => 'NO',
    'GCC_SYMBOLS_PRIVATE_EXTERN' => 'NO',
    'STRIP_STYLE' => 'non-global',
    'COPY_PHASE_STRIP' => 'NO'
  }
end
