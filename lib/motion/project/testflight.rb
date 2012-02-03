# TestFlight builtin support for RubyMotion projects.
#
# Usage:
#
#   1. Download the TestFlight SDK into `vendor/TestFlightSDK'.
#
#   2. In your project Rakefile, add the following line:
#        require 'motion/project/testflight'
#
#   3. Still in the Rakefile, add the mandatory configuration settings:
#        app.testflight.sdk = 'vendor/TestFlightSDK'
#        app.testflight.api_token = '<insert your API token here>'
#        app.testflight.team_token = '<insert your team token here>'
#
#   4. (Optional) You can set the distribution lists, if needed:
#        app.testflight.distribution_lists = ['CoolKids']
#
#   5. You can now submit your project to TestFlight, using:
#        rake testflight notes="zomg!"

class TestFlightConfig
  attr_accessor :sdk, :api_token, :team_token, :distribution_lists

  def initialize(config)
    @config = config
  end

  def sdk=(sdk)
    if @sdk != sdk
      @config.unvendor_project(@sdk)
      @sdk = sdk
      @config.vendor_project(sdk, :static)
    end
  end

  def team_token=(team_token)
    @team_token = team_token
    create_launcher
  end

  def inspect
    {:sdk => sdk, :api_token => api_token, :team_token => team_token, :distribution_lists => distribution_lists}.inspect
  end

  private

  def create_launcher
    return unless team_token
    launcher_code = <<EOF
# This file is automatically generated. Do not edit.

if Object.const_defined?('TestFlight') and !UIDevice.currentDevice.model.include?('Simulator')
  NSNotificationCenter.defaultCenter.addObserverForName(UIApplicationDidBecomeActiveNotification, object:nil, queue:nil, usingBlock:lambda do |notification|
  TestFlight.takeOff('#{team_token}')
  end)
end
EOF
    launcher_file = './app/testflight_launcher.rb'
    if !File.exist?(launcher_file) or File.read(launcher_file) != launcher_code
      File.open(launcher_file, 'w') { |io| io.write(launcher_code) }
    end
    files = @config.files
    files << launcher_file unless files.find { |x| File.expand_path(x) == File.expand_path(launcher_file) }
  end
end

module Motion; module Project; class Config
  variable :testflight

  def testflight
    @testflight ||= TestFlightConfig.new(self)
  end
end; end; end

desc "Submit build to TestFlight"
task :testflight => :archive do
  # Retrieve configuration settings.
  prefs = App.config.testflight
  unless prefs.api_token
    App.fail "A value for app.testflight.api_token is mandatory" 
  end
  unless prefs.team_token
    App.fail "A value for app.testflight.team_token is mandatory"
  end
  distribution_lists = (prefs.distribution_lists.join(',') or nil)
  notes = ENV['notes']
  unless notes
    App.fail "Submission notes must be provided via the `notes' environment variable. Example: rake testflight notes='w00t'"
  end

  # An archived version of the .dSYM bundle is needed.
  app_dsym = App.config.app_bundle('iPhoneOS').sub(/\.app$/, '.dSYM')
  app_dsym_zip = app_dsym + '.zip'
  if !File.exist?(app_dsym_zip) or File.mtime(app_dsym) > File.mtime(app_dsym_zip)
    Dir.chdir(File.dirname(app_dsym)) do
      sh "/usr/bin/zip -q -r \"#{File.basename(app_dsym)}.zip\" \"#{File.basename(app_dsym)}\""
    end
  end  

  curl = "/usr/bin/curl http://testflightapp.com/api/builds.json -F file=@\"#{App.config.archive}\" -F dsym=@\"#{app_dsym_zip}\" -F api_token='#{prefs.api_token}' -F team_token='#{prefs.team_token}' -F notes=\"#{notes}\" -F notify=True"
  curl << " -F distribution_lists='#{distribution_lists}'" if distribution_lists
  App.info 'Run', curl
  sh curl
end
