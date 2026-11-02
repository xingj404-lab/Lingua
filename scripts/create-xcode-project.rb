#!/usr/bin/env ruby
# Reproducible native app project. Requires the xcodeproj gem only when regenerating.
require 'xcodeproj'
root = File.expand_path('..', __dir__)
Dir.chdir(root)
project = Xcodeproj::Project.new('Lingua.xcodeproj')
project.root_object.attributes['LastUpgradeCheck'] = '2700'
project.root_object.known_regions = ['en', 'zh-Hans', 'ja', 'ko', 'Base']
app = project.new_target(:application, 'Lingua', :osx, '14.0', nil, :swift)
core = project.new_target(:framework, 'TranslationCore', :osx, '14.0', nil, :swift)
[app, core].each do |target|
  target.build_configurations.each do |config|
    config.build_settings.merge!('SWIFT_VERSION'=>'6.0', 'MACOSX_DEPLOYMENT_TARGET'=>'14.0',
      'ARCHS'=>'arm64', 'CODE_SIGN_STYLE'=>'Automatic', 'ENABLE_HARDENED_RUNTIME'=>'YES')
  end
end
core.build_configurations.each { |c| c.build_settings.merge!('GENERATE_INFOPLIST_FILE'=>'YES', 'PRODUCT_BUNDLE_IDENTIFIER'=>'app.lingua.mac.core', 'SKIP_INSTALL'=>'YES', 'DEFINES_MODULE'=>'YES') }
app.build_configurations.each do |config|
  config.base_configuration_reference = project.main_group.new_file("Distribution/Config/#{config.name}.xcconfig")
  config.build_settings.merge!('PRODUCT_BUNDLE_IDENTIFIER'=>'app.lingua.mac', 'INFOPLIST_FILE'=>'Distribution/Info.plist',
    'CODE_SIGN_ENTITLEMENTS'=>'Distribution/Lingua.entitlements', 'ASSETCATALOG_COMPILER_APPICON_NAME'=>'AppIcon',
    'ENABLE_APP_SANDBOX'=>'YES', 'ENABLE_USER_SCRIPT_SANDBOXING'=>'NO', 'LD_RUNPATH_SEARCH_PATHS'=>'$(inherited) @executable_path/../Frameworks')
end
sources = project.main_group.new_group('Sources')
[app,core].each do |target|
  folder = target == app ? 'LinguaMac' : 'TranslationCore'
  group = sources.new_group(folder)
  Dir["Sources/#{folder}/*.swift"].sort.each { |path| target.source_build_phase.add_file_reference(group.new_file(path)) }
end
app.add_dependency(core)
app.frameworks_build_phase.add_file_reference(core.product_reference)
embed = app.new_copy_files_build_phase('Embed Frameworks'); embed.dst_subfolder_spec = '10'
f = embed.add_file_reference(core.product_reference); f.settings = {'ATTRIBUTES'=>['CodeSignOnCopy', 'RemoveHeadersOnCopy']}
resources = project.main_group.new_group('Resources')
['Sources/LinguaMac/Resources/AppIcon.png', 'Distribution/Resources/Assets.xcassets', 'Distribution/Resources/PrivacyInfo.xcprivacy', 'Sources/LinguaMac/Resources/Legal', 'Distribution/Resources/BundledModels'].each do |path|
  ref = resources.new_file(path); ref.last_known_file_type = 'folder' if ['Legal','BundledModels'].include?(File.basename(path))
  app.resources_build_phase.add_file_reference(ref)
end
core.resources_build_phase.add_file_reference(resources.new_file('Sources/TranslationCore/Resources/InterfaceStrings.json'))
phase = app.new_shell_script_build_phase('Prepare verified bundled model and licenses')
phase.shell_script = 'set -eu\ncd "$SRCROOT"\n/usr/bin/python3 scripts/bundle-default-model.py Distribution/Resources\n/usr/bin/python3 scripts/collect-licenses.py\n'.gsub('\\n', "\n")
phase.always_out_of_date = '1'
app.build_phases.delete(phase); app.build_phases.unshift(phase)
local_mlx = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
local_mlx.relative_path = 'Vendor/mlx-swift'
project.root_object.package_references << local_mlx
mlx_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
mlx_dep.product_name = 'MLX'
app.package_product_dependencies << mlx_dep
mlx_build = project.new(Xcodeproj::Project::Object::PBXBuildFile)
mlx_build.product_ref = mlx_dep
app.frameworks_build_phase.files << mlx_build
refs = {}
[['https://github.com/ml-explore/mlx-swift-lm','3.32.3'], ['https://github.com/huggingface/swift-huggingface','0.9.0'], ['https://github.com/huggingface/swift-transformers','1.3.0']].each do |url,version|
  ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  ref.repositoryURL = url; ref.requirement = {'kind'=>'exactVersion', 'version'=>version}
  project.root_object.package_references << ref; refs[url.split('/').last] = ref
end
{'mlx-swift-lm'=>['MLXLLM','MLXLMCommon','MLXHuggingFace'], 'swift-huggingface'=>['HuggingFace'], 'swift-transformers'=>['Tokenizers']}.each do |repo,names|
  names.each do |name|
    dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    dep.package = refs[repo]; dep.product_name = name; app.package_product_dependencies << dep
    build = project.new(Xcodeproj::Project::Object::PBXBuildFile); build.product_ref = dep
    app.frameworks_build_phase.files << build
  end
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app); scheme.set_launch_target(app)
scheme.archive_action.build_configuration = 'Release'
scheme.save_as('Lingua.xcodeproj', 'Lingua', true)
