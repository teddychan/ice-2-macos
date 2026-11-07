#!/usr/bin/env ruby
# Idempotently add/refresh the IceTests unit-test target in Ice.xcodeproj.
# Requires the `xcodeproj` gem. Re-run after adding any IceTests/*.swift file.
require 'xcodeproj'

PROJECT = 'Ice.xcodeproj'
project = Xcodeproj::Project.open(PROJECT)

ice = project.targets.find { |t| t.name == 'Ice' }
abort 'Ice target not found' unless ice

test = project.targets.find { |t| t.name == 'IceTests' }
if test.nil?
  test = project.new_target(:unit_test_bundle, 'IceTests', :osx, '26.0')
  test.build_configurations.each do |config|
    s = config.build_settings
    # Explicit PRODUCT_NAME so the test bundle's Swift module name is valid.
    s['PRODUCT_NAME'] = 'IceTests'
    s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.dragonapp.ice.IceTests'
    s['SWIFT_VERSION'] = '5.0'
    s['MACOSX_DEPLOYMENT_TARGET'] = '26.0'
    s['GENERATE_INFOPLIST_FILE'] = 'YES'
    # The Ice app target's product is "Ice 2.app" (PRODUCT_NAME = "Ice 2"),
    # so the host binary lives at "Ice 2.app/Contents/MacOS/Ice 2".
    s['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/Ice 2.app/Contents/MacOS/Ice 2'
    s['BUNDLE_LOADER'] = '$(TEST_HOST)'
    s['DEVELOPMENT_TEAM'] = 'K2ATHQPJDP'
    s['CODE_SIGN_STYLE'] = 'Automatic'
    s['SWIFT_EMIT_LOC_STRINGS'] = 'NO'
  end
  test.add_dependency(ice)

  # Register the target in the shared Ice scheme's Test action.
  scheme_dir = Xcodeproj::XCScheme.shared_data_dir(PROJECT)
  scheme_path = File.join(scheme_dir, 'Ice.xcscheme')
  scheme = Xcodeproj::XCScheme.new(scheme_path)
  ref = Xcodeproj::XCScheme::TestAction::TestableReference.new(test)
  scheme.test_action.add_testable(ref)
  scheme.save_as(PROJECT, 'Ice', true)
end

# Sync every IceTests/*.swift file into the target: add new files, drop deleted ones.
group = project.main_group['IceTests'] || project.main_group.new_group('IceTests', 'IceTests')
already = test.source_build_phase.files_references.map { |r| r.real_path.to_s }
Dir.glob('IceTests/*.swift').sort.each do |path|
  abs = File.expand_path(path)
  next if already.include?(abs)
  file_ref = group.new_file(File.basename(path))
  test.add_file_references([file_ref])
end
test.source_build_phase.files.dup.each do |build_file|
  ref = build_file.file_ref
  next if ref.nil? || File.exist?(ref.real_path.to_s)
  build_file.remove_from_project
  ref.remove_from_project
end

project.save
puts "IceTests synced (#{test.source_build_phase.files.count} source files)"
