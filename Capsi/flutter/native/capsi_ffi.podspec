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
end
